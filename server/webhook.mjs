#!/usr/bin/env node
// Nhận event cuộc gọi server Zenify gửi tới webhook.site (hoặc bản tự host cùng API) rồi bắn push
// (APNs VoIP / FCM). Server Zenify POST lên URL webhook → script này đọc request MỚI qua API
// (poll, không cần mở cổng ra Internet) → body giống POST /push → handlePush.
//   WEBHOOK_URL=https://webhook.site/<uuid>   (hoặc --url; host khác cùng API cũng được)
//   WEBHOOK_API_KEY=…                          (chỉ khi token webhook cần Api-Key)
//   WEBHOOK_MAX_AGE=60                         (giây; event cũ hơn thì bỏ, 0 = không giới hạn)
// Event thiếu "type" → coi là CALL_IN (app chỉ đổ chuông khi có type).
// Event cũ KHÔNG bắn lại (bắn lại = máy đổ chuông lại cho mọi cuộc gọi đã qua):
//  · request tạo TRƯỚC lúc chạy script — so `created_at`, không phụ thuộc lần đọc đầu thành công
//  · request quá WEBHOOK_MAX_AGE (vd mạng lỗi một lúc rồi đọc bù)
//  · event lặp: cùng call_id + token và cùng type với lần bắn trước (vòng quay số mới vẫn bắn —
//    xem alreadyFired)
// --dry-run: chỉ in event sẽ bắn, không gửi push.
import { parseArgs } from 'node:util';
import { alreadyFired, forgetFired, handlePush } from './lib.mjs';

const { values: opt } = parseArgs({
  options: {
    url: { type: 'string', default: process.env.WEBHOOK_URL },
    interval: { type: 'string', default: '2' }, // giây giữa 2 lần đọc
    'max-age': { type: 'string', default: process.env.WEBHOOK_MAX_AGE || '60' },
    replay: { type: 'boolean', default: false }, // bắn lại cả request đã có (bỏ qua max-age)
    'dry-run': { type: 'boolean', default: false },
  },
});

const id = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i.exec(opt.url ?? '')?.[1];
const origin = (() => {
  try {
    return new URL(opt.url).origin;
  } catch {
    return '';
  }
})();
if (!id || !origin) {
  console.log('Thiếu WEBHOOK_URL (vd https://webhook.site/<uuid>) — điền vào .env hoặc --url');
  process.exit(1);
}
// API đọc request của webhook.site — cùng host với URL nhận (webhook.site hoặc bản tự host)
const api = `${origin}/token/${id}/requests?sorting=newest&per_page=50`;
const headers = { accept: 'application/json', ...(process.env.WEBHOOK_API_KEY && { 'api-key': process.env.WEBHOOK_API_KEY }) };
const maxAgeMs = opt.replay ? 0 : Number(opt['max-age']) * 1000;
const startedAt = Date.now();
// đồng hồ máy này có thể lệch server webhook vài giây → nới 5s
const SKEW_MS = 5000;
const seen = new Set();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const now = () => new Date().toTimeString().slice(0, 8);

async function fetchRequests() {
  const r = await fetch(api, { headers });
  if (!r.ok) throw new Error(`webhook HTTP ${r.status}`);
  const data = (await r.json())?.data;
  // không phải danh sách → coi là lỗi; KHÔNG coi là rỗng (lần sau sẽ tưởng mọi request là mới)
  if (!Array.isArray(data)) throw new Error('webhook trả dữ liệu không phải danh sách request');
  return data;
}

/** `created_at` của webhook: "2026-10-15 09:08:14", giờ UTC. */
const ageMs = (req) => Date.now() - Date.parse(`${String(req.created_at).replace(' ', 'T')}Z`);

function markSeen(uuid) {
  seen.add(uuid);
  // chỉ cần nhớ quanh 50 request mới nhất mà API trả về
  if (seen.size > 500) seen.delete(seen.values().next().value);
}

async function handle(req) {
  const age = ageMs(req);
  if (!opt.replay && !(Date.now() - age >= startedAt - SKEW_MS)) {
    return console.log(`[${now()}] bỏ qua ${req.uuid.slice(0, 8)}: event ${req.created_at} có trước lúc chạy`);
  }
  if (maxAgeMs > 0 && age > maxAgeMs) {
    return console.log(`[${now()}] bỏ qua ${req.uuid.slice(0, 8)}: event cũ ${Math.round(age / 1000)}s (> ${opt['max-age']}s)`);
  }
  let body;
  try {
    body = JSON.parse(req.content);
  } catch {
    return console.log(`[${now()}] bỏ qua ${req.method} ${req.uuid.slice(0, 8)}: body không phải JSON`);
  }
  if (!body?.token || !body?.payload) {
    return console.log(`[${now()}] bỏ qua ${req.uuid.slice(0, 8)}: thiếu token / payload`);
  }
  if (body.payload.type == null) body.payload = { type: 'CALL_IN', ...body.payload };
  if (opt['dry-run']) {
    return console.log(`[${now()}] (dry-run) sẽ bắn ${body.os} ${body.payload.type} call=${body.payload.call_id} — event ${req.created_at}`);
  }
  if (alreadyFired(body)) {
    return console.log(`[${now()}] bỏ qua ${req.uuid.slice(0, 8)}: đã bắn ${body.payload.type} call=${body.payload.call_id}`);
  }
  const [status, out] = await handlePush(body).catch((e) => {
    forgetFired(body);
    throw e;
  });
  if (status !== 200) forgetFired(body);
  console.log(`[${now()}] event ${req.created_at} → ${JSON.stringify(out)}`);
}

// Lần đầu: đánh dấu request cũ là đã xem (trừ --replay) → chỉ bắn event tới SAU khi chạy.
// Mạng lỗi lúc mở thì đọc lại, KHÔNG coi danh sách rỗng (sẽ bắn lại toàn bộ request cũ).
for (;;) {
  try {
    for (const req of await fetchRequests()) if (!opt.replay) markSeen(req.uuid);
    break;
  } catch (e) {
    console.error(`[${now()}] đọc webhook lỗi: ${e.message} — thử lại`);
    await sleep(Number(opt.interval) * 1000);
  }
}
console.log(
  `Đang nghe ${opt.url} (mỗi ${opt.interval}s) — bỏ qua ${seen.size} request cũ` +
    `${maxAgeMs > 0 ? `, event cũ hơn ${opt['max-age']}s` : ''}${opt['dry-run'] ? ' (dry-run: không gửi push)' : ''}. Ctrl+C để dừng.`,
);

for (;;) {
  try {
    // cũ trước, mới sau → bắn đúng thứ tự (CALL_IN rồi CALL_CANCEL)
    for (const req of (await fetchRequests()).reverse()) {
      if (seen.has(req.uuid)) continue;
      markSeen(req.uuid);
      await handle(req).catch((e) => console.error(`[${now()}] LỖI: ${e.message}`));
    }
  } catch (e) {
    console.error(`[${now()}] đọc webhook lỗi: ${e.message}`);
  }
  await sleep(Number(opt.interval) * 1000);
}
