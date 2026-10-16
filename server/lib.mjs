// Gửi push APNs (VoIP) + FCM HTTP v1 — dùng chung cho CLI (push.mjs) và server (server.mjs).
// Cấu hình qua biến môi trường / file .env (KHÔNG commit). Không cần thư viện ngoài.
import crypto from 'node:crypto';
import fs from 'node:fs';
import http2 from 'node:http2';
import path from 'node:path';

const DIR = path.dirname(new URL(import.meta.url).pathname);
const ENV_FILE = path.join(DIR, '.env');
if (fs.existsSync(ENV_FILE)) process.loadEnvFile(ENV_FILE); // biến đã có sẵn trong shell được ưu tiên

const env = (k, def) => process.env[k] || def;
const b64url = (buf) => Buffer.from(buf).toString('base64url');
export const short = (t) => `${String(t).slice(0, 8)}…${String(t).slice(-6)}`;

export function missingEnv(...keys) {
  return keys.filter((k) => !process.env[k]);
}

function requireEnv(...keys) {
  const miss = missingEnv(...keys);
  if (miss.length) throw new Error(`Thiếu biến môi trường: ${miss.join(', ')} (điền vào .env — xem .env.example)`);
}

/** Mặc định gửi production trừ khi APN_PRODUCTION=false. */
export const apnsDefaultProduction = () => env('APN_PRODUCTION', 'true') !== 'false';

// ---------------- APNs (VoIP, PushKit) ----------------

// JWT APNs dùng lại tối đa 50 phút (Apple từ chối nếu làm mới quá dày: TooManyProviderTokenUpdates)
let apnsJwtCache = { token: '', at: 0 };
function apnsJwt() {
  const now = Math.floor(Date.now() / 1000);
  if (apnsJwtCache.token && now - apnsJwtCache.at < 3000) return apnsJwtCache.token;
  const key = fs.readFileSync(env('APN_KEY_FILE'), 'utf8');
  const head = b64url(JSON.stringify({ alg: 'ES256', kid: env('APN_KEY_ID') }));
  const body = b64url(JSON.stringify({ iss: env('APN_TEAM_ID'), iat: now }));
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key, dsaEncoding: 'ieee-p1363' });
  apnsJwtCache = { token: `${head}.${body}.${b64url(sig)}`, at: now };
  return apnsJwtCache.token;
}

/**
 * VoIP push: `payload` gửi NGUYÊN VẸN làm body APNs (app đọc các trường ở cấp gốc).
 * @returns {{status:number, apnsId:string, body:string, host:string}}
 */
export function sendApnsVoip({ token, payload, production = apnsDefaultProduction() }) {
  requireEnv('APN_KEY_FILE', 'APN_KEY_ID', 'APN_TEAM_ID');
  const host = production ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
  const topic = `${env('APN_BUNDLE_ID', 'com.example.sdk.zenify')}.voip`;
  return new Promise((resolve, reject) => {
    const client = http2.connect(host);
    client.on('error', reject);
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      authorization: `bearer ${apnsJwt()}`,
      'apns-topic': topic,
      'apns-push-type': 'voip',
      'apns-priority': '10',
      'apns-expiration': '0',
      'content-type': 'application/json',
    });
    const res = { status: 0, apnsId: '', body: '', host };
    req.on('response', (h) => {
      res.status = h[':status'];
      res.apnsId = h['apns-id'] ?? '';
    });
    req.setEncoding('utf8');
    req.on('data', (c) => (res.body += c));
    req.on('end', () => {
      client.close();
      resolve(res);
    });
    req.on('error', reject);
    req.end(JSON.stringify(payload));
  });
}

// ---------------- FCM HTTP v1 ----------------

let fcmCache = { token: '', exp: 0, sa: null };
async function fcmAuth() {
  requireEnv('FCM_SERVICE_ACCOUNT_FILE');
  const now = Math.floor(Date.now() / 1000);
  if (fcmCache.token && now < fcmCache.exp - 60) return fcmCache;
  const sa = JSON.parse(fs.readFileSync(env('FCM_SERVICE_ACCOUNT_FILE'), 'utf8'));
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: sa.token_uri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const sig = crypto.sign('RSA-SHA256', Buffer.from(`${head}.${claim}`), sa.private_key);
  const r = await fetch(sa.token_uri, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${head}.${claim}.${b64url(sig)}`,
    }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error(`Lấy OAuth token FCM lỗi: ${JSON.stringify(j)}`);
  fcmCache = { token: j.access_token, exp: now + (j.expires_in ?? 3600), sa };
  return fcmCache;
}

/**
 * FCM data message. `platform`:
 *  · `android` — ưu tiên cao, FirebaseMessagingService chạy cả khi app đã tắt.
 *  · `ios` — push IM LẶNG (content-available) → didReceiveRemoteNotification (CALL_CANCEL).
 * @returns {{status:number, body:string, project:string}}
 */
export async function sendFcm({ token, payload, platform = 'android' }) {
  const { token: access, sa } = await fcmAuth();
  // FCM: mọi giá trị trong `data` phải là chuỗi
  const data = Object.fromEntries(Object.entries(payload).map(([k, v]) => [k, String(v)]));
  const message = { token, data };
  if (platform === 'ios') {
    message.apns = {
      headers: { 'apns-push-type': 'background', 'apns-priority': '5' },
      payload: { aps: { 'content-available': 1 } },
    };
  } else {
    message.android = { priority: 'HIGH', ttl: '30s' };
  }
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: { authorization: `Bearer ${access}`, 'content-type': 'application/json' },
    body: JSON.stringify({ message }),
  });
  return { status: r.status, body: await r.text(), project: sa.project_id };
}

/** App (SDK) chỉ xử lý `type` = CALL_IN / CALL_CANCEL — thiếu thì báo cuộc ma, không đổ chuông. */
export function payloadWarning(payload) {
  const t = payload?.type;
  if (t === 'CALL_IN' || t === 'CALL_CANCEL') return null;
  return t == null
    ? 'payload THIẾU "type" → app báo cuộc ma, KHÔNG đổ chuông (cần "type": "CALL_IN")'
    : `type "${t}" app không xử lý → không đổ chuông (chỉ CALL_IN / CALL_CANCEL)`;
}

// ---------------- Body POST /push / event webhook ----------------

// Event đã bắn gần nhất của mỗi `call_id:token` → { type, at }. Server Zenify quay số nhiều vòng
// với CÙNG call_id: CALL_IN → CALL_CANCEL → CALL_IN (vòng 2) → CALL_CANCEL… → mỗi lần ĐỔI type là
// một bước mới, phải bắn. Chỉ bỏ event LẶP (cùng type với lần bắn trước của cuộc đó — Zenify gửi
// lại / relay chạy trùng), để máy không nhận push thừa.
const DEDUPE_MS = Number(env('DEDUPE_SECONDS', '600')) * 1000;
const fired = new Map();
const keyOf = (body) => `${body?.payload?.call_id}:${body?.token}`;
const typeOf = (body) => body?.payload?.type ?? 'CALL_IN';

/** `true` nếu cuộc này (call_id + token) vừa bắn đúng type này rồi (trong DEDUPE_SECONDS, mặc định 600). */
export function alreadyFired(body) {
  if (!body?.payload?.call_id || !body.token || !(DEDUPE_MS > 0)) return false;
  const now = Date.now();
  for (const [k, v] of fired) if (now - v.at > DEDUPE_MS) fired.delete(k);
  const key = keyOf(body);
  const last = fired.get(key);
  if (last?.type === typeOf(body)) return true;
  fired.set(key, { type: typeOf(body), at: now, prev: last });
  return false;
}

/** Bắn lỗi → trả về trạng thái trước, để lần gửi lại (Zenify retry) vẫn được bắn. */
export function forgetFired(body) {
  const key = keyOf(body);
  const cur = fired.get(key);
  if (cur?.type !== typeOf(body)) return;
  if (cur.prev) fired.set(key, cur.prev);
  else fired.delete(key);
}

/**
 * Body `{ token, os: ios|android, is_apn_prod?, payload, channel?: 'fcm' }` (giống event server
 * Zenify) → APNs VoIP (ios) / FCM (android). Dùng chung cho server.mjs và webhook.mjs.
 * @returns {Promise<[number, object]>} [HTTP status, kết quả]
 */
export async function handlePush(body) {
  const { token, os, payload } = body;
  if (!token || typeof token !== 'string') return [400, { error: 'thiếu "token"' }];
  if (os !== 'ios' && os !== 'android') return [400, { error: '"os" phải là "ios" hoặc "android"' }];
  if (!payload || typeof payload !== 'object') return [400, { error: 'thiếu "payload" (object)' }];

  const warning = payloadWarning(payload);
  const tag = `${os} ${payload.type ?? '(không type)'} call=${payload.call_id ?? '?'} token=${short(token)}`;

  if (os === 'ios' && body.channel !== 'fcm') {
    const production = typeof body.is_apn_prod === 'boolean' ? body.is_apn_prod : apnsDefaultProduction();
    const r = await sendApnsVoip({ token, payload, production });
    console.log(`APNs ${production ? 'prod' : 'sandbox'} ${tag} → ${r.status} ${r.body}`);
    return [
      r.status === 200 ? 200 : 502,
      {
        ok: r.status === 200,
        via: 'apns-voip',
        environment: production ? 'production' : 'sandbox',
        apns_status: r.status,
        apns_id: r.apnsId,
        apns_reason: r.body ? (JSON.parse(r.body).reason ?? r.body) : null,
        warning,
      },
    ];
  }
  const r = await sendFcm({ token, payload, platform: os });
  console.log(`FCM ${tag} → ${r.status} ${r.body}`);
  return [r.status === 200 ? 200 : 502, { ok: r.status === 200, via: `fcm-${os}`, fcm_status: r.status, fcm_response: r.body, warning }];
}
