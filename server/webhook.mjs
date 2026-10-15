#!/usr/bin/env node
// Nhận event cuộc gọi server Zenify gửi tới webhook.site rồi bắn push (APNs VoIP / FCM).
// Server Zenify POST lên URL webhook.site → script này đọc request MỚI qua API webhook.site
// (poll, không cần mở cổng ra Internet) → body giống POST /push → handlePush.
//   WEBHOOK_URL=https://webhook.site/<uuid>   (hoặc --url)
//   WEBHOOK_API_KEY=…                          (chỉ khi token webhook.site cần Api-Key)
// Event thiếu "type" → coi là CALL_IN (app chỉ đổ chuông khi có type).
import { parseArgs } from 'node:util';
import { handlePush } from './lib.mjs';

const { values: opt } = parseArgs({
  options: {
    url: { type: 'string', default: process.env.WEBHOOK_URL },
    interval: { type: 'string', default: '2' }, // giây giữa 2 lần đọc
    replay: { type: 'boolean', default: false }, // bắn lại cả request đã có trước khi chạy
  },
});

const id = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i.exec(opt.url ?? '')?.[1];
if (!id) {
  console.log('Thiếu WEBHOOK_URL (vd https://webhook.site/<uuid>) — điền vào .env hoặc --url');
  process.exit(1);
}
const api = `https://webhook.site/token/${id}/requests?sorting=newest&per_page=50`;
const headers = { accept: 'application/json', ...(process.env.WEBHOOK_API_KEY && { 'api-key': process.env.WEBHOOK_API_KEY }) };
const seen = new Set();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const now = () => new Date().toTimeString().slice(0, 8);

async function fetchRequests() {
  const r = await fetch(api, { headers });
  if (!r.ok) throw new Error(`webhook.site HTTP ${r.status}`);
  return (await r.json()).data ?? [];
}

async function handle(req) {
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
  const [, out] = await handlePush(body);
  console.log(`[${now()}] event ${req.created_at} → ${JSON.stringify(out)}`);
}

// Lần đầu: đánh dấu request cũ là đã xem (trừ --replay) → chỉ bắn event tới SAU khi chạy
for (const req of await fetchRequests()) if (!opt.replay) seen.add(req.uuid);
console.log(`Đang nghe ${opt.url} (mỗi ${opt.interval}s) — bỏ qua ${seen.size} request cũ. Ctrl+C để dừng.`);

for (;;) {
  try {
    // cũ trước, mới sau → bắn đúng thứ tự (CALL_IN rồi CALL_CANCEL)
    for (const req of (await fetchRequests()).reverse()) {
      if (seen.has(req.uuid)) continue;
      seen.add(req.uuid);
      await handle(req).catch((e) => console.error(`[${now()}] LỖI: ${e.message}`));
    }
  } catch (e) {
    console.error(`[${now()}] đọc webhook lỗi: ${e.message}`);
  }
  await sleep(Number(opt.interval) * 1000);
}
