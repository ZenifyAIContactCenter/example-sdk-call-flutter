#!/usr/bin/env node
// CLI bắn push cuộc gọi thử (APNs VoIP + FCM) đúng payload server Zenify. Xem README.md.
import crypto from 'node:crypto';
import { parseArgs } from 'node:util';
import { apnsDefaultProduction, payloadWarning, sendApnsVoip, sendFcm, short } from './lib.mjs';

const { values: opt, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    token: { type: 'string', short: 't' },
    type: { type: 'string', default: 'CALL_IN' },
    'call-id': { type: 'string' },
    number: { type: 'string', default: '0900000000' },
    name: { type: 'string', default: 'Push Tester' },
    platform: { type: 'string', default: 'android' }, // fcm: android | ios
    sandbox: { type: 'boolean', default: false }, // apns: dùng máy chủ sandbox
    'cancel-after': { type: 'string' }, // giây: gửi CALL_CANCEL cùng call_id sau N giây
  },
});

const cmd = positionals[0];
if (!['apns', 'fcm'].includes(cmd) || !opt.token) {
  console.log(`Cách dùng:
  node push.mjs apns --token <voip_push_token> [--type CALL_IN|CALL_CANCEL] [--sandbox]
  node push.mjs fcm  --token <fcm_token> [--platform android|ios] [--type CALL_IN|CALL_CANCEL]
Tuỳ chọn chung: --call-id <id> --number <sđt> --name <tên> --cancel-after <giây>
Server HTTP (POST /push): node server.mjs`);
  process.exit(1);
}

const callId = opt['call-id'] ?? `test-${Date.now()}`;

/** Payload giống server Zenify (docs/PRODUCTION_REFERENCE.md "Payload push"). */
const payload = (type) => ({
  type,
  call_id: callId,
  phone_number: opt.number,
  callerName: opt.name,
  uuid: crypto.randomUUID(), // server sinh uuid MỚI cho mỗi push
});

async function send(type) {
  const p = payload(type);
  const warn = payloadWarning(p);
  if (warn) console.warn(`⚠ ${warn}`);
  if (cmd === 'apns') {
    const production = opt.sandbox ? false : apnsDefaultProduction();
    console.log(`→ APNs ${production ? 'PRODUCTION' : 'SANDBOX'} voip ${type} call=${callId} token=${short(opt.token)}`);
    const r = await sendApnsVoip({ token: opt.token, payload: p, production });
    console.log(`← HTTP ${r.status} apns-id=${r.apnsId} ${r.body || '(OK)'}`);
  } else {
    console.log(`→ FCM ${opt.platform} ${type} call=${callId} token=${short(opt.token)}`);
    const r = await sendFcm({ token: opt.token, payload: p, platform: opt.platform });
    console.log(`← HTTP ${r.status} project=${r.project} ${r.body}`);
  }
}

try {
  await send(opt.type);
  const after = Number(opt['cancel-after']);
  if (opt.type === 'CALL_IN' && after > 0) {
    console.log(`… chờ ${after}s rồi gửi CALL_CANCEL`);
    await new Promise((r) => setTimeout(r, after * 1000));
    await send('CALL_CANCEL');
  }
} catch (e) {
  console.error(`LỖI: ${e.message}`);
  process.exit(1);
}
