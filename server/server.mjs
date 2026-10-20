#!/usr/bin/env node
// Server webhook + bắn push cuộc gọi — MỘT tiến trình, không cần webhook.site:
//
//   ANY  /<uuid>                    Webhook "Cuộc gọi App SDK" của web Zenify trỏ tới đây (như URL
//                                   webhook.site). Nhận event → bắn push NGAY → lưu lại để xem.
//   GET  /view/<uuid>               Trang xem các request đã nhận + kết quả bắn push (tự làm mới)
//   GET  /token/<uuid>/requests     Cùng API với webhook.site (JSON) — dùng được với webhook.mjs
//   POST /push                      Bắn push trực tiếp với body
//                                   { "token", "os": "ios"|"android", "is_apn_prod", "payload" }
//   GET  /health
//
// uuid hợp lệ khai trong WEBHOOK_TOKENS (cách nhau dấu phẩy) — uuid là "mật khẩu" của URL,
// không khai thì /<uuid> trả 404. Tạo: node -e "console.log(crypto.randomUUID())"
//  · os=ios     → APNs VoIP, `payload` gửi nguyên vẹn; is_apn_prod chọn production / sandbox
//  · os=android → FCM data message ưu tiên cao
// Thêm "channel": "fcm" khi os=ios để gửi push im lặng qua FCM (CALL_CANCEL).
import crypto from 'node:crypto';
import http from 'node:http';
import { alreadyFired, forgetFired, handlePush, short } from './lib.mjs';

const PORT = Number(process.env.PORT || 3000);
// Mặc định chỉ nghe trên máy này: server cầm key APNs, không mở ra mạng ngoài
const HOST = process.env.HOST || '127.0.0.1';
// "Authen Key" của webhook trên web Zenify. Đặt thì request thiếu / sai key bị 401.
// Header chứa key: WEBHOOK_AUTH_HEADER (mặc định authorization); nhận cả "<key>" lẫn "Bearer <key>".
const AUTH_KEY = process.env.WEBHOOK_AUTH_KEY || '';
const AUTH_HEADER = (process.env.WEBHOOK_AUTH_HEADER || 'authorization').toLowerCase();
const TOKENS = new Set(
  (process.env.WEBHOOK_TOKENS || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean),
);
// Số request giữ lại cho mỗi uuid (trong bộ nhớ — khởi động lại là mất, như bản xem nhanh)
const KEEP = Number(process.env.WEBHOOK_KEEP || 200);

const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
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

function onView(res, uuid) {
  if (!TOKENS.has(uuid)) return reply(res, 404, { error: 'webhook không tồn tại' });
  const rows = (store.get(uuid) ?? [])
    .map((r) => {
      let b = {};
      try {
        b = JSON.parse(r.content);
      } catch {}
      const p = b?.payload ?? {};
      const ok = r.result?.ok;
      const res = r.result
        ? `${ok ? '✅' : r.result.skipped ? '⏭' : '❌'} ${esc(r.result.via ?? r.result.skipped ?? r.result.error ?? '')} ${esc(
            r.result.apns_status ?? r.result.fcm_status ?? '',
          )} ${esc(r.result.apns_reason ?? '')}`
        : '…';
      return `<details><summary><b>${esc(r.created_at)}Z</b> ${esc(r.method)} · ${esc(b.os ?? '?')} · ${esc(
        p.type ?? '(không type)',
      )} · call=${esc(p.call_id ?? '?')} · token=${esc(b.token ? short(b.token) : '?')} · ${res}</summary><pre>${esc(
        JSON.stringify({ headers: r.headers, body: b && Object.keys(b).length ? b : r.content, result: r.result }, null, 2),
      )}</pre></details>`;
    })
    .join('');
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
  res.end(`<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="3"><title>Webhook ${esc(uuid.slice(0, 8))}</title>
<style>body{font:14px system-ui,sans-serif;margin:16px;color:#111}details{border:1px solid #ddd;border-radius:8px;
margin:6px 0;padding:8px}summary{cursor:pointer}pre{overflow:auto;background:#f6f6f6;padding:8px;border-radius:6px}
code{background:#f0f0f0;padding:2px 4px;border-radius:4px}</style></head><body>
<h3>Webhook <code>${esc(uuid)}</code></h3>
<p>Giờ UTC · tự làm mới mỗi 3 giây · giữ ${KEEP} request gần nhất (khởi động lại server là mất).</p>
${rows || '<p>Chưa nhận request nào.</p>'}</body></html>`);
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
      if ((m = RE_HOOK.exec(path))) return await onHook(req, res, m[1].toLowerCase());
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
    if (TOKENS.size === 0) {
      console.log('webhook: chưa khai WEBHOOK_TOKENS → /<uuid> trả 404 (tạo uuid: node -e "console.log(crypto.randomUUID())")');
    }
    for (const t of TOKENS) {
      console.log(`webhook: http://${HOST}:${PORT}/${t}   (xem: /view/${t})`);
    }
  });
