// apps/physiome/src/weatherkit.mjs
//
// Apple WeatherKit REST client.
//
// Signs a short-lived ES256 JWT per Apple's WeatherKit REST API auth scheme
// (https://developer.apple.com/documentation/weatherkitrestapi) and fetches
// currentWeather for a lat/lon. Fails soft (returns null) on any error so
// callers can fall back to Open-Meteo/OWM.
//
// Required env:
//   WEATHERKIT_P8       - PEM contents of the ES256 private key (AuthKey.p8),
//                          e.g. mounted from the 'apple-auth-key' k8s Secret.
//   WEATHERKIT_KEY_ID    - 10-char Key ID for that key (Apple Developer > Keys).
//   WEATHERKIT_TEAM_ID   - 10-char Team ID.
//   WEATHERKIT_SERVICE_ID (optional) - the Services ID / App ID registered
//                          for WeatherKit and associated with the key above.
//                          Defaults to 'dev.sounio.beagle'.
//
// GOTCHA (see track report): the 'sub' claim (and the 'id' JWT header,
// which is "<teamId>.<serviceId>") MUST be an identifier that has the
// WeatherKit capability enabled in the Apple Developer portal AND is
// associated with the signing key. A wrong-but-plausible identifier
// (e.g. the iOS app's bundle id) fails with 401 {"reason":"NOT_ENABLED"}.
// Even the correct identifier was observed to intermittently return
// 401 NOT_ENABLED during verification here — treat that as a real
// provisioning-propagation risk, not just a coding bug.

import crypto from 'node:crypto';

const WEATHERKIT_BASE = 'https://weatherkit.apple.com/api/v1';
const JWT_TTL_SECONDS = 1800; // 30 min; Apple allows up to ~1h, keep short-lived
const DEFAULT_SERVICE_ID = 'dev.sounio.beagle';

function b64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

let _cachedJwt = null; // { token, exp }

function signWeatherKitJwt() {
  const p8 = process.env.WEATHERKIT_P8;
  const keyId = process.env.WEATHERKIT_KEY_ID;
  const teamId = process.env.WEATHERKIT_TEAM_ID;
  const serviceId = process.env.WEATHERKIT_SERVICE_ID || DEFAULT_SERVICE_ID;

  if (!p8 || !keyId || !teamId) {
    return null; // not configured
  }

  const now = Math.floor(Date.now() / 1000);

  // Reuse a still-valid cached token (avoid re-signing on every request).
  if (_cachedJwt && _cachedJwt.exp - 60 > now) {
    return _cachedJwt.token;
  }

  try {
    const header = { alg: 'ES256', kid: keyId, id: `${teamId}.${serviceId}` };
    const exp = now + JWT_TTL_SECONDS;
    const payload = { iss: teamId, iat: now, exp, sub: serviceId };

    const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
    const privateKey = crypto.createPrivateKey(p8);
    // WeatherKit (like other Apple JWT auth) expects the raw IEEE P1363
    // r||s signature encoding, not ASN.1 DER.
    const sig = crypto.sign(null, Buffer.from(signingInput), {
      key: privateKey,
      dsaEncoding: 'ieee-p1363',
    });
    const token = `${signingInput}.${b64url(sig)}`;

    _cachedJwt = { token, exp };
    return token;
  } catch (err) {
    console.error('[weatherkit] failed to sign JWT:', err.message);
    return null;
  }
}

function mapCondition(conditionCode) {
  // Apple's conditionCode is a CamelCase enum (e.g. "MostlyClear",
  // "Rain", "Haze"). Keep it as-is; callers can map further if needed.
  return conditionCode || null;
}

/**
 * Fetch current weather conditions from Apple WeatherKit REST for a
 * given lat/lon. Fails soft: returns null on any missing config,
 * network error, or non-2xx response.
 *
 * @param {number} lat
 * @param {number} lon
 * @returns {Promise<{temp_c:number, pressure_hpa:number|null, humidity:number|null, uv_index:number|null, condition:string|null, source:'apple-weatherkit'} | null>}
 */
export async function fetchWeatherKit(lat, lon) {
  if (typeof lat !== 'number' || typeof lon !== 'number' || Number.isNaN(lat) || Number.isNaN(lon)) {
    return null;
  }

  const jwt = signWeatherKitJwt();
  if (!jwt) return null;

  const url = `${WEATHERKIT_BASE}/weather/en/${lat}/${lon}?dataSets=currentWeather`;

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    let res;
    try {
      res = await fetch(url, {
        headers: { Authorization: `Bearer ${jwt}` },
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }

    if (!res.ok) {
      // Don't leak the token; just log status + reason.
      let reason = '';
      try {
        const errBody = await res.text();
        reason = errBody.slice(0, 200);
      } catch {
        /* ignore */
      }
      console.error(`[weatherkit] HTTP ${res.status} for ${lat},${lon}: ${reason}`);
      return null;
    }

    const body = await res.json();
    const cw = body?.currentWeather;
    if (!cw) return null;

    return {
      temp_c: typeof cw.temperature === 'number' ? cw.temperature : null,
      pressure_hpa: typeof cw.pressure === 'number' ? cw.pressure : null,
      humidity: typeof cw.humidity === 'number' ? cw.humidity : null,
      uv_index: typeof cw.uvIndex === 'number' ? cw.uvIndex : null,
      condition: mapCondition(cw.conditionCode),
      source: 'apple-weatherkit',
    };
  } catch (err) {
    console.error('[weatherkit] fetch failed:', err.message);
    return null;
  }
}
