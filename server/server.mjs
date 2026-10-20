#!/usr/bin/env node
// Server webhook + bắn push cuộc gọi — MỘT tiến trình, không cần webhook.site:
//
//   ANY  /<uuid>                    Webhook "Cuộc gọi App SDK" của web Zenify trỏ tới đây (như URL
//                                   webhook.site). Nhận event → bắn push NGAY → lưu lại để xem.
//   GET  /view/<uuid>               Giao diện xem request đã nhận + kết quả bắn push (như webhook.site);
//                                   mở /<uuid> bằng trình duyệt cũng tự chuyển sang đây
//   GET  /token/<uuid>/requests     Cùng API với webhook.site (JSON) — dùng được với webhook.mjs
//   POST /push                      Bắn push trực tiếp với body
//                                   { "token", "os": "ios"|"android", "is_apn_prod", "payload" }
//   GET  /health
//
// uuid hợp lệ khai trong WEBHOOK_TOKENS (cách nhau dấu phẩy) — uuid là "mật khẩu" của URL.
// Để trống → lần chạy đầu TỰ TẠO một uuid và lưu vào data/webhook-tokens (WEBHOOK_TOKEN_FILE);
// các lần sau đọc lại đúng uuid đó, URL đã điền trên web Zenify không đổi.
//  · os=ios     → APNs VoIP, `payload` gửi nguyên vẹn; is_apn_prod chọn production / sandbox
//  · os=android → FCM data message ưu tiên cao
// Thêm "channel": "fcm" khi os=ios để gửi push im lặng qua FCM (CALL_CANCEL).
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { alreadyFired, checkKeyFiles, describeKeys, forgetFired, handlePush, short } from './lib.mjs';

const PORT = Number(process.env.PORT || 3000);
// Mặc định chỉ nghe trên máy này: server cầm key APNs, không mở ra mạng ngoài
const HOST = process.env.HOST || '127.0.0.1';
// "Authen Key" của webhook trên web Zenify. Đặt thì request thiếu / sai key bị 401.
// Header chứa key: WEBHOOK_AUTH_HEADER (mặc định authorization); nhận cả "<key>" lẫn "Bearer <key>".
const AUTH_KEY = process.env.WEBHOOK_AUTH_KEY || '';
const AUTH_HEADER = (process.env.WEBHOOK_AUTH_HEADER || 'authorization').toLowerCase();
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const parseTokens = (raw) =>
  String(raw ?? '')
    .split(/[,\s]+/)
    .map((s) => s.trim().toLowerCase())
    .filter((s) => new RegExp(`^${UUID}$`).test(s));

// File lưu uuid tự tạo. Docker: volume `data` (docker-compose.yml) để tạo lại container không mất.
const TOKEN_FILE =
  process.env.WEBHOOK_TOKEN_FILE || path.join(path.dirname(new URL(import.meta.url).pathname), 'data', 'webhook-tokens');

/** WEBHOOK_TOKENS > file đã lưu > tạo mới + lưu. Trả [danh sách uuid, nguồn]. */
function loadTokens() {
  const fromEnv = parseTokens(process.env.WEBHOOK_TOKENS);
  if (fromEnv.length) return [fromEnv, 'WEBHOOK_TOKENS'];
  try {
    const saved = parseTokens(fs.readFileSync(TOKEN_FILE, 'utf8'));
    if (saved.length) return [saved, TOKEN_FILE];
  } catch {}
  const created = crypto.randomUUID();
  try {
    fs.mkdirSync(path.dirname(TOKEN_FILE), { recursive: true });
    fs.writeFileSync(TOKEN_FILE, created + '\n', { mode: 0o600 });
    return [[created], `tạo mới, đã lưu ${TOKEN_FILE}`];
  } catch (e) {
    // không ghi được (ổ chỉ đọc…) → vẫn chạy, nhưng khởi động lại sẽ ra uuid KHÁC
    return [[created], `tạo mới, KHÔNG lưu được (${e.message}) — khởi động lại sẽ đổi uuid, nên đặt WEBHOOK_TOKENS`];
  }
}
const [tokenList, tokenSource] = loadTokens();
const TOKENS = new Set(tokenList);
// Số request giữ lại cho mỗi uuid (trong bộ nhớ — khởi động lại là mất, như bản xem nhanh)
const KEEP = Number(process.env.WEBHOOK_KEEP || 200);

const RE_HOOK = new RegExp(`^/(${UUID})(?:/.*)?$`, 'i');
const RE_VIEW = new RegExp(`^/view/(${UUID})/?$`, 'i');
const RE_API = new RegExp(`^/token/(${UUID})/requests/?$`, 'i');

/** uuid → request đã nhận (mới nhất ở đầu) */
const store = new Map();

function authorized(req) {
  if (!AUTH_KEY) return true;
  const got = String(req.headers[AUTH_HEADER] ?? '').replace(/^Bearer\s+/i, '');
  const a = Buffer.from(got);
  const b = Buffer.from(AUTH_KEY);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function reply(res, status, obj) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj, null, 2));
}

async function readBody(req) {
  let raw = '';
  for await (const c of req) {
    raw += c;
    if (raw.length > 64 * 1024) throw new Error('body quá lớn');
  }
  return raw;
}

/** "2026-10-15 09:08:14" giờ UTC — cùng định dạng `created_at` của webhook.site */
const utcNow = () => new Date().toISOString().slice(0, 19).replace('T', ' ');

/** Header lưu lại để xem — bỏ khoá xác thực */
function safeHeaders(h) {
  const out = { ...h };
  delete out[AUTH_HEADER];
  delete out.authorization;
  delete out.cookie;
  return out;
}

function remember(uuid, entry) {
  const list = store.get(uuid) ?? [];
  list.unshift(entry);
  if (list.length > KEEP) list.length = KEEP;
  store.set(uuid, list);
}

/** Event webhook → bắn push. Trả [HTTP status, kết quả] — kết quả cũng được lưu để xem. */
async function processEvent(content) {
  let body;
  try {
    body = JSON.parse(content);
  } catch {
    return [200, { ok: false, skipped: 'body không phải JSON' }];
  }
  if (!body?.token || !body?.payload) return [200, { ok: false, skipped: 'thiếu token / payload' }];
  // Event thiếu "type" → coi là CALL_IN (app chỉ đổ chuông khi có type)
  if (body.payload.type == null) body.payload = { type: 'CALL_IN', ...body.payload };
  if (alreadyFired(body)) {
    console.log(`bỏ qua event trùng: ${body.payload.type} call=${body.payload.call_id}`);
    return [200, { ok: true, skipped: 'duplicate' }];
  }
  try {
    const [status, out] = await handlePush(body);
    if (status !== 200) forgetFired(body);
    return [status, out];
  } catch (e) {
    forgetFired(body);
    throw e;
  }
}

async function onHook(req, res, uuid) {
  if (!TOKENS.has(uuid)) return reply(res, 404, { error: 'webhook không tồn tại' });
  if (!authorized(req)) return reply(res, 401, { error: 'sai Authen Key' });
  const content = await readBody(req);
  const entry = {
    uuid: crypto.randomUUID(),
    token_id: uuid,
    created_at: utcNow(),
    method: req.method,
    ip: req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket.remoteAddress,
    url: req.url,
    headers: safeHeaders(req.headers),
    content,
    result: null,
  };
  remember(uuid, entry);
  let status = 200;
  let out;
  try {
    [status, out] = await processEvent(content);
  } catch (e) {
    console.error('LỖI:', e.message);
    [status, out] = [500, { ok: false, error: e.message }];
  }
  entry.result = { status, ...out };
  reply(res, status, out);
}

function onApi(req, res, uuid, url) {
  if (!TOKENS.has(uuid)) return reply(res, 404, { error: 'webhook không tồn tại' });
  const all = store.get(uuid) ?? [];
  const perPage = Math.min(Math.max(Number(url.searchParams.get('per_page')) || 50, 1), KEEP);
  const list = url.searchParams.get('sorting') === 'oldest' ? [...all].reverse() : all;
  reply(res, 200, {
    data: list.slice(0, perPage),
    total: all.length,
    per_page: perPage,
    current_page: 1,
    is_last_page: all.length <= perPage,
  });
}

const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

/**
 * Giao diện xem request (giống webhook.site): cột trái danh sách, cột phải chi tiết. Tự đọc lại
 * `/token/<uuid>/requests` mỗi 2 giây bằng fetch — KHÔNG tải lại trang, nên đang xem request nào
 * vẫn giữ nguyên. Không dùng thư viện ngoài.
 */
function onView(res, uuid) {
  if (!TOKENS.has(uuid)) return reply(res, 404, { error: 'webhook không tồn tại' });
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
  res.end(`<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Webhook ${esc(uuid.slice(0, 8))}</title>
<style>
:root{--bg:#f7f7f8;--card:#fff;--line:#e3e3e6;--text:#16161a;--muted:#6b6b76;--ok:#0a7d33;--bad:#c62828;--skip:#8a6d00;--sel:#e8f0fe}
@media (prefers-color-scheme:dark){:root{--bg:#141417;--card:#1d1d22;--line:#2e2e35;--text:#ececf1;--muted:#9a9aa6;--ok:#4cc574;--bad:#ff6b6b;--skip:#e0b84a;--sel:#26324a}}
*{box-sizing:border-box}body{margin:0;font:14px system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--text)}
header{padding:12px 16px;border-bottom:1px solid var(--line);background:var(--card);display:flex;gap:8px;align-items:center;flex-wrap:wrap}
header b{font-size:15px}code{font:12px ui-monospace,Menlo,monospace}
.url{flex:1;min-width:220px;display:flex;gap:6px}.url input{flex:1;min-width:0;padding:6px 8px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--text);font:12px ui-monospace,Menlo,monospace}
button{padding:6px 10px;border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--text);cursor:pointer}
main{display:grid;grid-template-columns:minmax(260px,380px) 1fr;height:calc(100vh - 57px)}
#list{border-right:1px solid var(--line);overflow:auto;background:var(--card)}
.item{padding:10px 12px;border-bottom:1px solid var(--line);cursor:pointer}.item:hover{background:var(--bg)}.item.sel{background:var(--sel)}
.row{display:flex;justify-content:space-between;gap:8px}.muted{color:var(--muted);font-size:12px}
.ok{color:var(--ok)}.bad{color:var(--bad)}.skip{color:var(--skip)}
#detail{overflow:auto;padding:16px}pre{white-space:pre-wrap;word-break:break-all;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px;font:12px ui-monospace,Menlo,monospace}
h4{margin:16px 0 6px}.empty{padding:24px;color:var(--muted)}
@media (max-width:720px){main{grid-template-columns:1fr;height:auto}#list{max-height:45vh;border-right:0;border-bottom:1px solid var(--line)}}
</style></head><body>
<header><b>Webhook</b><span class="muted" id="count"></span>
<div class="url"><input id="url" readonly><button id="copy">Copy URL</button></div>
<span class="muted">giờ máy bạn · tự cập nhật 2s · giữ ${KEEP} request (mất khi khởi động lại server)</span></header>
<main><div id="list"><div class="empty">Đang tải…</div></div><div id="detail"><div class="empty">Chọn một request để xem chi tiết.</div></div></main>
<script>
const UUID=${JSON.stringify(uuid)};
const hookUrl=location.origin+'/'+UUID;
document.getElementById('url').value=hookUrl;
document.getElementById('copy').onclick=()=>navigator.clipboard?.writeText(hookUrl);
let rows=[],sel=null;
const e=(s)=>String(s??'').replace(/[&<>"']/g,(c)=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]);
const body=(r)=>{try{return JSON.parse(r.content)}catch{return null}};
const time=(r)=>new Date(r.created_at.replace(' ','T')+'Z').toLocaleString();
const shortTok=(t)=>t&&t.length>16?t.slice(0,8)+'…'+t.slice(-6):(t||'?');
function status(r){const x=r.result;if(!x)return['…',''];
 if(x.ok)return['✅ '+(x.via||'đã gửi'),'ok'];
 if(x.skipped)return['⏭ '+x.skipped,'skip'];
 return['❌ '+(x.apns_reason||x.error||x.via||'lỗi')+(x.apns_status||x.fcm_status?' ('+(x.apns_status||x.fcm_status)+')':''),'bad'];}
function renderList(){const L=document.getElementById('list');
 document.getElementById('count').textContent=rows.length+' request';
 if(!rows.length){L.innerHTML='<div class="empty">Chưa nhận request nào. Trỏ webhook "Cuộc gọi App SDK" trên web Zenify tới URL ở trên.</div>';return;}
 L.innerHTML=rows.map((r)=>{const b=body(r)||{},p=b.payload||{},[st,cls]=status(r);
  return '<div class="item'+(r.uuid===sel?' sel':'')+'" data-id="'+e(r.uuid)+'"><div class="row"><b>'+e(r.method)+' · '+e(b.os||'?')+' · '+e(p.type||'(không type)')+'</b><span class="muted">'+e(time(r))+'</span></div>'
  +'<div class="row"><span class="muted">call '+e(p.call_id||'?')+' · token '+e(shortTok(b.token))+'</span></div><div class="'+cls+'">'+e(st)+'</div></div>';}).join('');
 L.querySelectorAll('.item').forEach((n)=>n.onclick=()=>{sel=n.dataset.id;renderList();renderDetail();});}
function renderDetail(){const D=document.getElementById('detail'),r=rows.find((x)=>x.uuid===sel);
 if(!r){D.innerHTML='<div class="empty">Chọn một request để xem chi tiết.</div>';return;}
 const b=body(r);
 D.innerHTML='<div class="row"><b>'+e(r.method)+' '+e(r.url)+'</b><span class="muted">'+e(time(r))+' · IP '+e(r.ip)+'</span></div>'
  +'<h4>Kết quả bắn push</h4><pre>'+e(JSON.stringify(r.result,null,2))+'</pre>'
  +'<h4>Body</h4><pre>'+e(b?JSON.stringify(b,null,2):r.content)+'</pre>'
  +'<h4>Header</h4><pre>'+e(JSON.stringify(r.headers,null,2))+'</pre>';}
async function load(){try{const res=await fetch('/token/'+UUID+'/requests?per_page=${KEEP}',{cache:'no-store'});
 const j=await res.json();const next=j.data||[];
 const changed=next.length!==rows.length||next[0]?.uuid!==rows[0]?.uuid||JSON.stringify(next.map(x=>x.result))!==JSON.stringify(rows.map(x=>x.result));
 rows=next;if(!sel&&rows[0])sel=rows[0].uuid;if(changed){renderList();renderDetail();}}catch{}}
load();setInterval(load,2000);
</script></body></html>`);
}

http
  .createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const path = url.pathname;
      if (req.method === 'GET' && path === '/health') return reply(res, 200, { ok: true });
      let m;
      if (req.method === 'GET' && (m = RE_VIEW.exec(path))) return onView(res, m[1].toLowerCase());
      if (req.method === 'GET' && (m = RE_API.exec(path))) return onApi(req, res, m[1].toLowerCase(), url);
      if ((m = RE_HOOK.exec(path))) {
        const id = m[1].toLowerCase();
        // Mở URL webhook trên trình duyệt (GET, Accept text/html) → sang trang xem, không coi là event
        if (req.method === 'GET' && String(req.headers.accept ?? '').includes('text/html') && TOKENS.has(id)) {
          res.writeHead(302, { location: `/view/${id}` });
          return res.end();
        }
        return await onHook(req, res, id);
      }
      if (req.method !== 'POST' || path !== '/push') return reply(res, 404, { error: 'không có đường dẫn này' });
      if (!authorized(req)) return reply(res, 401, { error: 'sai Authen Key' });
      const body = JSON.parse((await readBody(req)) || '{}');
      if (alreadyFired(body)) {
        console.log(`bỏ qua event trùng: ${body.payload.type ?? 'CALL_IN'} call=${body.payload.call_id}`);
        return reply(res, 200, { ok: true, skipped: 'duplicate' });
      }
      const [status, out] = await handlePush(body).catch((e) => {
        forgetFired(body);
        throw e;
      });
      if (status !== 200) forgetFired(body);
      reply(res, status, out);
    } catch (e) {
      console.error('LỖI:', e.message);
      reply(res, 500, { ok: false, error: e.message });
    }
  })
  .listen(PORT, HOST, () => {
    console.log(`push server: http://${HOST}:${PORT}/push${AUTH_KEY ? ` (kiểm tra Authen Key ở header ${AUTH_HEADER})` : ''}`);
    console.log(describeKeys());
    for (const w of checkKeyFiles()) console.warn(`⚠ ${w}`);
    console.log(`webhook uuid (${tokenSource}):`);
    for (const t of TOKENS) {
      console.log(`webhook: http://${HOST}:${PORT}/${t}   (xem: /view/${t})`);
    }
  });
