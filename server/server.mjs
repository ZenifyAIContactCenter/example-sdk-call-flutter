#!/usr/bin/env node
// Server HTTP bắn push cuộc gọi: POST /push với body
//   { "token": "...", "os": "ios"|"android", "is_apn_prod": true, "payload": { ... } }
//  · os=ios     → APNs VoIP, `payload` gửi nguyên vẹn; is_apn_prod chọn production / sandbox
//  · os=android → FCM data message ưu tiên cao
// Thêm "channel": "fcm" khi os=ios để gửi push im lặng qua FCM (CALL_CANCEL).
import crypto from 'node:crypto';
import http from 'node:http';
import { alreadyFired, forgetFired, handlePush } from './lib.mjs';

const PORT = Number(process.env.PORT || 3000);
// Mặc định chỉ nghe trên máy này: server cầm key APNs, không mở ra mạng ngoài
const HOST = process.env.HOST || '127.0.0.1';
// "Authen Key" của webhook trên web Zenify. Đặt thì request thiếu / sai key bị 401.
// Header chứa key: WEBHOOK_AUTH_HEADER (mặc định authorization); nhận cả "<key>" lẫn "Bearer <key>".
const AUTH_KEY = process.env.WEBHOOK_AUTH_KEY || '';
const AUTH_HEADER = (process.env.WEBHOOK_AUTH_HEADER || 'authorization').toLowerCase();

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

async function readJson(req) {
  let raw = '';
  for await (const c of req) {
    raw += c;
    if (raw.length > 64 * 1024) throw new Error('body quá lớn');
  }
  return JSON.parse(raw || '{}');
}

http
  .createServer(async (req, res) => {
    try {
      if (req.method === 'GET' && req.url === '/health') return reply(res, 200, { ok: true });
      if (req.method !== 'POST' || req.url !== '/push') return reply(res, 404, { error: 'chỉ có POST /push' });
      if (!authorized(req)) return reply(res, 401, { error: 'sai Authen Key' });
      const body = await readJson(req);
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
  .listen(PORT, HOST, () =>
    console.log(`push server: http://${HOST}:${PORT}/push${AUTH_KEY ? ` (kiểm tra Authen Key ở header ${AUTH_HEADER})` : ''}`),
  );
