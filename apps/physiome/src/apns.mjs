// Apple Push Notification service (APNs) — token-based (JWT/ES256) provider auth.
//
// This is the delivery mechanism for:
//   - HKStateOfMind EMA prompts, triggered server-side by a place-change event
//     (the N-of-1 companion experiment).
//   - space-weather alerts (Kp/Dst threshold crossings).
//
// Token-based auth (NOT a per-connection TLS client cert): we sign a short-lived
// ES256 JWT with the APNs Auth Key (.p8) and send it as a bearer token on every
// HTTP/2 request. One key works for every app + both environments, and Apple
// recommends the token be reused for ~20min-1h (do not regenerate per-request —
// APNs rate-limits token generation). See:
//   https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns
//
// Env (never written to disk/git — mounted from the cluster Secret 'apple-auth-key'):
//   APNS_P8        - the AuthKey .p8 file contents (PEM, EC PRIVATE KEY)
//   APNS_KEY_ID     - key_id, e.g. M74D39F98L (JWT `kid`)
//   APNS_TEAM_ID    - team_id, e.g. S9DPGW22A8 (JWT `iss`)
//   APNS_TOPIC      - apns-topic / bundle id, default "dev.sounio.cockpit"
//   APNS_ENV        - "sandbox" | "production", default "sandbox" (dev builds use
//                     sandbox; TestFlight/App Store builds use production — the
//                     device tells us which via the device-token registration).
//
// Node has native HTTP/2 (node:http2) and native ES256 signing (node:crypto) — no
// dependency needed (jsonwebtoken/node-apn etc. are NOT added to package.json).

import http2 from "node:http2";
import crypto from "node:crypto";

const PROD_HOST = "api.push.apple.com";
const SANDBOX_HOST = "api.sandbox.push.apple.com";
const APNS_PORT = 443;

// JWT is valid up to 60min per Apple's docs; we refresh at 50min to stay well
// inside that window even under clock skew, while easily respecting the
// "don't regenerate more than once every 20min" guidance.
const TOKEN_TTL_MS = 50 * 60 * 1000;

function base64url(buf) {
  return Buffer.from(buf)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

// One cached signer+token per (keyId,teamId) pair — in practice there is exactly
// one APNs key for this app, but keying by kid+iss avoids cross-contamination if
// that ever changes (e.g. key rotation with an overlap window).
const tokenCache = new Map();

function loadKeyMaterial() {
  const p8 = process.env.APNS_P8;
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  if (!p8 || !keyId || !teamId) return null;
  return { p8, keyId, teamId };
}

// Sign (or reuse a cached) ES256 provider JWT. Returns null if key material is
// not configured (fail-soft — callers turn this into {ok:false}).
export function getProviderJwt(now = Date.now()) {
  const km = loadKeyMaterial();
  if (!km) return null;
  const cacheKey = `${km.keyId}:${km.teamId}`;
  const cached = tokenCache.get(cacheKey);
  if (cached && now - cached.signedAt < TOKEN_TTL_MS) return cached.jwt;

  const header = { alg: "ES256", kid: km.keyId };
  const claims = { iss: km.teamId, iat: Math.floor(now / 1000) };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;

  let privateKey;
  try {
    privateKey = crypto.createPrivateKey({ key: km.p8, format: "pem" });
  } catch (e) {
    throw new Error(`APNS_P8 is not a valid PEM private key: ${e.message}`);
  }

  // JOSE (JWS) ES256 requires the raw R||S signature (64 bytes for P-256), NOT
  // the DER encoding Node's default 'crypto.sign' produces — `dsaEncoding:
  // 'ieee-p1363'` is exactly that raw fixed-width format.
  const signature = crypto.sign("sha256", Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });

  const jwt = `${signingInput}.${base64url(signature)}`;
  tokenCache.set(cacheKey, { jwt, signedAt: now });
  return jwt;
}

// Force a re-sign next call (e.g. after a 403 InvalidProviderToken, or in tests).
export function resetProviderJwtCache() {
  tokenCache.clear();
}

export function apnsHost(env = process.env.APNS_ENV || "sandbox") {
  return env === "production" ? PROD_HOST : SANDBOX_HOST;
}

// POST one push via HTTP/2 to APNs. Fail-soft: never throws — always resolves
// {ok, status, reason}. `status` is the APNs HTTP status (0 if the request never
// got a response, e.g. connection error). `reason` is APNs' JSON {reason: "..."}
// on failure (e.g. "BadDeviceToken", "TopicDisallowed"), or a local error string.
export function sendPush({ deviceToken, title, body, payload = {}, env, priority, pushType } = {}) {
  return new Promise((resolve) => {
    if (!deviceToken) {
      resolve({ ok: false, status: 0, reason: "missing deviceToken" });
      return;
    }
    let jwt;
    try {
      jwt = getProviderJwt();
    } catch (e) {
      resolve({ ok: false, status: 0, reason: `jwt sign failed: ${e.message}` });
      return;
    }
    if (!jwt) {
      resolve({ ok: false, status: 0, reason: "APNS_P8/APNS_KEY_ID/APNS_TEAM_ID not configured" });
      return;
    }

    const topic = process.env.APNS_TOPIC || "dev.sounio.cockpit";
    const host = apnsHost(env);
    const isBackground = payload["content-available"] === 1 && title == null && body == null;
    const apsAlert = title != null || body != null ? { title, body } : undefined;
    const aps = {
      ...(apsAlert ? { alert: Object.fromEntries(Object.entries(apsAlert).filter(([, v]) => v != null)) } : {}),
      ...(apsAlert ? { sound: "default" } : {}),
    };
    const body_ = JSON.stringify({ ...payload, aps: { ...aps, ...(payload.aps || {}) } });

    let session;
    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      try { session?.close(); } catch { /* already closing */ }
      resolve(result);
    };

    try {
      session = http2.connect(`https://${host}:${APNS_PORT}`);
    } catch (e) {
      finish({ ok: false, status: 0, reason: `connect failed: ${e.message}` });
      return;
    }

    session.on("error", (e) => finish({ ok: false, status: 0, reason: `session error: ${e.message}` }));

    const timeout = setTimeout(() => finish({ ok: false, status: 0, reason: "timeout" }), 15000);

    const req = session.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": pushType || (isBackground ? "background" : "alert"),
      "apns-priority": String(priority ?? (isBackground ? 5 : 10)),
      "content-type": "application/json",
    });

    let respStatus = 0;
    let chunks = [];
    req.on("response", (headers) => {
      respStatus = Number(headers[":status"] || 0);
    });
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      clearTimeout(timeout);
      const ok = respStatus >= 200 && respStatus < 300;
      let reason;
      if (!ok) {
        try {
          const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
          reason = parsed.reason || `HTTP ${respStatus}`;
        } catch {
          reason = `HTTP ${respStatus}`;
        }
      }
      finish({ ok, status: respStatus, reason });
    });
    req.on("error", (e) => {
      clearTimeout(timeout);
      finish({ ok: false, status: respStatus, reason: `request error: ${e.message}` });
    });

    req.end(body_);
  });
}
