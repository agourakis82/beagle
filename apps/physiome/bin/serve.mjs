import express from "express";
import {
  makePool, ensureSchema, upsertHealthSamples, upsertWeather,
  getSpaceWeatherHistory, getWeatherHistory, getHealthHistory
} from "../src/db.mjs";
import { ensurePlacesSchema, upsertPlaces, getPlaces, matchPlace } from "../src/places.mjs";
import { validateBatch } from "../src/validate.mjs";
import { aggregateRange } from "../src/digest.mjs";
import { correlatePhysiome, summarizeCorrelations } from "../src/correlate.mjs";
import { ensureDeviceTokensSchema, upsertDeviceToken, getLatestDeviceToken } from "../src/devicetokens.mjs";
import { ensureEmaSchema, maybePromptEMA, fire, saveEmaResponse } from "../src/ema.mjs";
import { sendPush } from "../src/apns.mjs";

const PORT = Number(process.env.PORT || 8090);
const INGEST_TOKEN = process.env.PHYSIOME_INGEST_TOKEN || "";

const pool = makePool();
await ensureSchema(pool);
await ensurePlacesSchema(pool);
await ensureDeviceTokensSchema(pool);
await ensureEmaSchema(pool);

const app = express();

// ── INSTRUMENTAÇÃO DO INGEST ────────────────────────────────────────────────
// Existe para responder uma pergunta concreta: vale trocar JSON por Apache Arrow
// no transporte? A fila do relógio pode ter milhões de amostras, e cada linha
// JSON custa ~175 bytes (o uuid sozinho são 36 caracteres, e type/unit repetem a
// mesma string milhão de vezes).
//
// Arrow só compensa se o gargalo for CPU de serialização. Se for tamanho de fio,
// gzip resolve com uma linha e nenhuma dependência nova. Isto mede qual dos dois.
//
// O parse acontece DENTRO do express.json, antes do handler — por isso os
// carimbos ficam em volta do middleware, não dentro dele.
const marco = () => Number(process.hrtime.bigint() / 1000n) / 1000; // ms

app.use((req, _res, next) => { req._t0 = marco(); next(); });
app.use(express.json({
  limit: "16mb",
  verify: (req, _res, buf) => { req._bytes = buf.length; req._tLido = marco(); },
}));

/// Resumo rolante em memória. Sem série temporal, sem dependência: só o suficiente
/// para decidir. Zera quando o pod reinicia, e tudo bem — isto é uma investigação,
/// não observabilidade permanente.
const perfil = {
  desde: new Date().toISOString(),
  requisicoes: 0, linhas: 0, bytes: 0,
  ms: { leitura: 0, parse: 0, validacao: 0, banco: 0, total: 0 },
  picos: { bytes: 0, linhas: 0, total_ms: 0 },
  cliente: { encode_ms: 0, amostras: 0 },  // vem do header X-Beagle-Client-Timing
};

function anotar(req, medidas, linhas) {
  perfil.requisicoes += 1;
  perfil.linhas += linhas;
  perfil.bytes += req._bytes || 0;
  for (const k of Object.keys(perfil.ms)) perfil.ms[k] += medidas[k] || 0;
  perfil.picos.bytes = Math.max(perfil.picos.bytes, req._bytes || 0);
  perfil.picos.linhas = Math.max(perfil.picos.linhas, linhas);
  perfil.picos.total_ms = Math.max(perfil.picos.total_ms, medidas.total || 0);

  // O telefone manda o que só ele sabe: quanto gastou codificando.
  const t = req.get("x-beagle-client-timing") || "";
  const enc = /encode_ms=([\d.]+)/.exec(t);
  if (enc) { perfil.cliente.encode_ms += Number(enc[1]); perfil.cliente.amostras += 1; }

  const porLinha = linhas ? ((req._bytes || 0) / linhas).toFixed(1) : "0";
  console.log(
    `[physiome] ingest linhas=${linhas} bytes=${req._bytes || 0} bytes_por_linha=${porLinha} ` +
    `leitura=${medidas.leitura.toFixed(1)}ms parse=${medidas.parse.toFixed(1)}ms ` +
    `validacao=${medidas.validacao.toFixed(1)}ms banco=${medidas.banco.toFixed(1)}ms ` +
    `total=${medidas.total.toFixed(1)}ms${t ? ` cliente[${t}]` : ""} ` +
    `encoding=${req.get("content-encoding") || "nenhum"}`
  );
}

/// Onde eu leio o veredito. Media por requisicao e por linha — que e o numero que
/// decide entre Arrow, gzip, ou nada.
app.get("/api/physiome/ingest/perfil", (_req, res) => {
  const n = perfil.requisicoes || 1;
  res.json({
    ...perfil,
    media_por_requisicao: Object.fromEntries(
      Object.entries(perfil.ms).map(([k, v]) => [k, +(v / n).toFixed(2)])
    ),
    bytes_por_linha: perfil.linhas ? +(perfil.bytes / perfil.linhas).toFixed(1) : 0,
    linhas_por_segundo: perfil.ms.total ? +(perfil.linhas / (perfil.ms.total / 1000)).toFixed(0) : 0,
    cliente_encode_ms_medio: perfil.cliente.amostras
      ? +(perfil.cliente.encode_ms / perfil.cliente.amostras).toFixed(2) : null,
  });
});

app.get("/healthz", (_req, res) => res.json({ ok: true }));

function authed(req) {
  if (!INGEST_TOKEN) return true; // unset = open (dev); set in prod
  const auth = req.get("authorization") || "";
  return auth === `Bearer ${INGEST_TOKEN}`;
}

app.post("/api/physiome/ingest", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  const tEntrada = marco();
  try {
    const { health_samples, weather_obs, received, rejected } = validateBatch(req.body || {});
    // O marco de "validado" fica AQUI, logo depois do `validateBatch` e antes do place-match:
    // o place-match consulta o banco, e contá-lo como validação inflaria justamente o número
    // que a instrumentação existe para comparar contra o custo de parse.
    const tValidado = marco();
    // OPTIONAL: override the geocoded street-address `place` with the user's own label,
    // if the coordinate falls inside a synced labeled_places radius. Fail-soft — a places
    // lookup error must never block health/weather ingest.
    if (weather_obs.length) {
      try {
        const places = await getPlaces(pool);
        if (places.length) {
          for (const w of weather_obs) {
            const m = matchPlace(places, w.lat, w.lon);
            if (m) { w.place = m.name; w._labeled = true; }
          }
        }
      } catch (e) {
        console.warn(`[physiome] place-match skipped: ${String(e.message || e)}`);
      }
    }
    const health = await upsertHealthSamples(pool, health_samples);
    const weather = await upsertWeather(pool, weather_obs);
    const tGravado = marco();

    // leitura = ler o corpo do socket; parse = JSON.parse dentro do express.json.
    // Separo os dois porque só o parse é o que Arrow eliminaria.
    //
    // `banco` engloba o place-match junto dos upserts, de propósito: os dois são ida ao
    // Postgres, e foi essa fatia que respondeu a pergunta do Arrow (banco ~99,5%, parse ~0,2%).
    anotar(req, {
      leitura:   (req._tLido || tEntrada) - (req._t0 || tEntrada),
      parse:     tEntrada - (req._tLido || tEntrada),
      validacao: tValidado - tEntrada,
      banco:     tGravado - tValidado,
      total:     tGravado - (req._t0 || tEntrada),
    }, (health_samples?.length || 0) + (weather_obs?.length || 0));

    // EMA place-change trigger (gated off by default; fail-soft — never blocks ingest).
    // Depois do `anotar` porque é gatilho opcional e não faz parte do custo de ingerir: incluí-lo
    // no tempo medido misturaria uma feature desligável na medida que decide o transporte.
    try {
      if (weather_obs.length) {
        let newest = null;
        for (const w of weather_obs) if (w.place && (!newest || String(w.ts) > String(newest.ts))) newest = w;
        if (newest) await maybePromptEMA(pool, { place: newest.place, ts: newest.ts, labeled: newest._labeled === true });
      }
    } catch (e) { console.warn(`[physiome] ema trigger skipped: ${String(e.message || e)}`); }
    if (rejected.health || rejected.weather) {
      console.warn(`[physiome] ingest dropped invalid samples: health=${rejected.health}/${received.health} weather=${rejected.weather}/${received.weather}`);
    }
    res.json({ ok: true, ingested: { health, weather }, received, rejected });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

// Device→server sync of the user's own named places (Sources/BeagleCore/AgoraHistory.swift
// PlaceLabelStore). Full-list upsert keyed by client-generated UUID; same auth gate as ingest.
app.post("/api/physiome/places", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  try {
    const places = Array.isArray(req.body?.places) ? req.body.places : [];
    const n = await upsertPlaces(pool, places);
    res.json({ ok: true, upserted: n });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

app.get("/api/physiome/places", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  try {
    res.json({ ok: true, places: await getPlaces(pool) });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

// Correlation insights: body (HRV/sleep/mood/HR) × environment+space (pressure/Kp/solar wind),
// over a rolling window with lag scan. Read-only; same auth gate as ingest.
app.get("/api/physiome/correlations", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  try {
    const days = Math.min(Math.max(Number(req.query.days) || 30, 7), 365);
    const minN = Math.max(Number(req.query.minN) || 7, 3);
    const aggs = await aggregateRange(pool, days);
    const result = correlatePhysiome(aggs, { minN });
    res.json({ ok: true, window_days: days, ...result, summary: summarizeCorrelations(result) });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

// Latest space weather snapshot — Kp, Dst, F10.7, solar wind, IMF Bz. The /noaa-swpc
// poller (run-poller.mjs) writes this every 2h; this is the read side so the
// iOS companion can render the aurora presence with real-time geomagnetic state.
// PUBLIC by design (no auth gate): this is global NOAA SWPC data (no user data), and
// it must be reachable without the ingest token — the cockpit reads it as a chat
// fallback and the phone reaches it via the cockpit (/api/mobile/v1/space-weather).
app.get("/api/physiome/space-weather/latest", async (_req, res) => {
  try {
    // Coalesce the newer high-cadence channels from recent rows: the poller (NOAA/GFZ) and
    // the schumann CronJob write on different grids, so the single newest row may miss some.
    // Pull the most recent non-null of each over the last ~3h so "latest" is complete.
    const { rows } = await pool.query(
      `SELECT
         -- ts/source come from the freshest row carrying actual NOAA/GFZ space weather, NOT the
         -- newest row overall — the schumann CronJob (source 'tomsk-sos-image') writes rows with
         -- every geomagnetic/solar column null, so the plain "newest row" mislabeled the whole
         -- snapshot as tomsk with a Schumann-grid timestamp even though the values are NOAA's.
         (SELECT ts FROM space_weather
            WHERE kp IS NOT NULL OR solar_wind_speed IS NOT NULL OR dst IS NOT NULL
               OR hp30 IS NOT NULL OR xray_flux IS NOT NULL OR aurora_power IS NOT NULL
            ORDER BY ts DESC LIMIT 1) AS ts,
         (SELECT kp FROM space_weather WHERE kp IS NOT NULL ORDER BY ts DESC LIMIT 1) AS kp,
         (SELECT dst FROM space_weather WHERE dst IS NOT NULL ORDER BY ts DESC LIMIT 1) AS dst,
         (SELECT f107 FROM space_weather WHERE f107 IS NOT NULL ORDER BY ts DESC LIMIT 1) AS f107,
         (SELECT solar_wind_speed FROM space_weather WHERE solar_wind_speed IS NOT NULL ORDER BY ts DESC LIMIT 1) AS solar_wind_speed,
         (SELECT bz FROM space_weather WHERE bz IS NOT NULL ORDER BY ts DESC LIMIT 1) AS bz,
         (SELECT hp30 FROM space_weather WHERE hp30 IS NOT NULL ORDER BY ts DESC LIMIT 1) AS hp30,
         (SELECT ap30 FROM space_weather WHERE ap30 IS NOT NULL ORDER BY ts DESC LIMIT 1) AS ap30,
         (SELECT hp60 FROM space_weather WHERE hp60 IS NOT NULL ORDER BY ts DESC LIMIT 1) AS hp60,
         (SELECT cosmic_ray_oulu FROM space_weather WHERE cosmic_ray_oulu IS NOT NULL ORDER BY ts DESC LIMIT 1) AS cosmic_ray_oulu,
         (SELECT schumann_f1 FROM space_weather WHERE schumann_f1 IS NOT NULL ORDER BY ts DESC LIMIT 1) AS schumann_f1,
         (SELECT schumann_f2 FROM space_weather WHERE schumann_f2 IS NOT NULL ORDER BY ts DESC LIMIT 1) AS schumann_f2,
         (SELECT schumann_f3 FROM space_weather WHERE schumann_f3 IS NOT NULL ORDER BY ts DESC LIMIT 1) AS schumann_f3,
         (SELECT source FROM space_weather
            WHERE kp IS NOT NULL OR solar_wind_speed IS NOT NULL OR dst IS NOT NULL
               OR hp30 IS NOT NULL OR xray_flux IS NOT NULL OR aurora_power IS NOT NULL
            ORDER BY ts DESC LIMIT 1) AS source`
    );
    if (!rows.length || rows[0].ts == null) return res.json({ ok: true, latest: null });
    res.json({ ok: true, latest: rows[0] });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

// Weather proxy for the app's "tempo" (ambiente) — REPLACES on-device WeatherKit, which
// fails with a runtime JWT error (Code=2) that no code change can fix (it's an Apple
// account/activation issue). The device sends its lat/lon; the server fetches from
// Open-Meteo (primary — free, no key, includes UV) and falls back to OpenWeatherMap (key
// held ONLY in the physiome-secrets cluster secret, never in the app binary or git).
// Returns the shape the iOS PhysioWeatherObservation expects.
import { fetchWeatherKit } from "../src/weatherkit.mjs";

const OWM_KEY = process.env.OWM_API_KEY || "";
async function fetchOpenMeteo(lat, lon) {
  const url =
    `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
    `&current=temperature_2m,relative_humidity_2m,surface_pressure,uv_index,precipitation`;
  const r = await fetch(url, { signal: AbortSignal.timeout(12000) });
  if (!r.ok) throw new Error(`open-meteo ${r.status}`);
  const c = (await r.json()).current || {};
  return {
    temp_c: num(c.temperature_2m), humidity: num(c.relative_humidity_2m),
    pressure_hpa: num(c.surface_pressure), uv_index: num(c.uv_index),
    precip: num(c.precipitation), source: "open-meteo",
  };
}
async function fetchOWM(lat, lon) {
  if (!OWM_KEY) throw new Error("no OWM key");
  const url = `https://api.openweathermap.org/data/2.5/weather?lat=${lat}&lon=${lon}&appid=${OWM_KEY}&units=metric`;
  const r = await fetch(url, { signal: AbortSignal.timeout(12000) });
  if (!r.ok) throw new Error(`owm ${r.status}`);
  const d = await r.json(), m = d.main || {};
  // OWM 2.5 has no UV (that needs One Call 3.0); leave uv null on this fallback path.
  return {
    temp_c: num(m.temp), humidity: num(m.humidity), pressure_hpa: num(m.pressure),
    uv_index: null, precip: num(d.rain?.["1h"]), source: "openweathermap",
  };
}
function num(v) { const n = Number(v); return Number.isFinite(n) ? n : null; }
// Air quality (Open-Meteo AQ API, keyless): US AQI (0-500, the standard scale) + the key
// pollutants. Best-effort — returns nulls if the AQ API is down, never blocks the weather.
async function fetchOpenMeteoAQ(lat, lon) {
  try {
    const url =
      `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${lat}&longitude=${lon}` +
      `&current=us_aqi,pm2_5,pm10,ozone,nitrogen_dioxide`;
    const r = await fetch(url, { signal: AbortSignal.timeout(12000) });
    if (!r.ok) return {};
    const c = (await r.json()).current || {};
    return {
      aqi: num(c.us_aqi), pm2_5: num(c.pm2_5), pm10: num(c.pm10),
      ozone: num(c.ozone), no2: num(c.nitrogen_dioxide),
    };
  } catch { return {}; }
}
app.get("/api/physiome/weather", async (req, res) => {
  const lat = Number(req.query.lat), lon = Number(req.query.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return res.status(400).json({ error: "lat and lon (numbers) required" });
  }
  try {
    // Prefer Apple WeatherKit REST (first-party for the iOS app's own account) when the
    // server is provisioned for it; it fails soft to null on any missing config, network
    // error, or non-2xx (e.g. NOT_ENABLED — see apps/physiome/src/weatherkit.mjs), so the
    // existing Open-Meteo -> OWM chain below is the always-on fallback path.
    let w = await fetchWeatherKit(lat, lon);
    if (!w) {
      try { w = await fetchOpenMeteo(lat, lon); }
      catch (e1) {
        try { w = await fetchOWM(lat, lon); }
        catch (e2) { return res.status(502).json({ error: `both weather providers failed: ${e1.message}; ${e2.message}` }); }
      }
    }
    const aq = await fetchOpenMeteoAQ(lat, lon); // best-effort, keyless
    res.json({ ok: true, ts: new Date().toISOString(), lat, lon, ...w, ...aq });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

// Forecast for the Agora charts' forward half (past = uploaded history, future = this).
// Open-Meteo hourly temp/UV + AQ hourly us_aqi (keyless), and the NOAA SWPC 3-day planetary
// Kp forecast (each point tagged observed|predicted, so the chart can draw the future dashed).
// Best-effort per source: a failing feed yields an empty array, never a 500.
async function omHourly(base, params, keys) {
  try {
    const r = await fetch(`${base}&${params}&forecast_days=3`, { signal: AbortSignal.timeout(12000) });
    if (!r.ok) return [];
    const h = (await r.json()).hourly || {};
    const t = h.time || [];
    return t.map((ts, i) => {
      const row = { ts: ts.endsWith("Z") ? ts : ts + ":00Z" };
      for (const [out, src] of keys) row[out] = num(h[src]?.[i]);
      return row;
    });
  } catch { return []; }
}
function zulu(t) {
  const s = String(t || "").trim().replace(" ", "T");
  if (!s) return null;
  return s.endsWith("Z") || /[+-]\d\d:?\d\d$/.test(s) ? s : s + "Z";
}
async function kpForecast() {
  try {
    const r = await fetch("https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json",
      { signal: AbortSignal.timeout(12000) });
    if (!r.ok) return [];
    const rows = await r.json();
    // array-of-arrays has a string header row to drop; array-of-objects does not.
    const arr = Array.isArray(rows[0]) ? rows.slice(1) : rows;
    return arr
      .map((x) => (Array.isArray(x)
        ? { ts: zulu(x[0]), kp: num(x[1]), predicted: String(x[2]) !== "observed" }
        : { ts: zulu(x.time_tag), kp: num(x.kp), predicted: String(x.observed) !== "observed" }))
      .filter((p) => p.ts && p.kp != null);
  } catch { return []; }
}
app.get("/api/physiome/forecast", async (req, res) => {
  try {
    // lat/lon optional: default to the device's most recently uploaded weather location, so
    // the Agora screen can fetch the forecast without plumbing location through the UI.
    let lat = Number(req.query.lat), lon = Number(req.query.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      const { rows } = await pool.query(
        "SELECT lat, lon FROM weather_obs WHERE lat IS NOT NULL AND lon IS NOT NULL ORDER BY ts DESC LIMIT 1"
      );
      if (!rows.length) return res.json({ ok: true, weather: [], sky_kp: [], note: "no known location yet" });
      lat = Number(rows[0].lat); lon = Number(rows[0].lon);
    }
    const wxBase = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}`;
    const aqBase = `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${lat}&longitude=${lon}`;
    const [wx, aq, kp] = await Promise.all([
      omHourly(wxBase, "hourly=temperature_2m,uv_index", [["temp_c", "temperature_2m"], ["uv_index", "uv_index"]]),
      omHourly(aqBase, "hourly=us_aqi", [["aqi", "us_aqi"]]),
      kpForecast(),
    ]);
    // merge aqi into the weather hourly grid by ts
    const aqBy = new Map(aq.map((r) => [r.ts, r.aqi]));
    const weather = wx.map((r) => ({ ...r, aqi: aqBy.get(r.ts) ?? null }));
    // Do NOT echo lat/lon: this endpoint is public and can default to the user's last
    // uploaded location, so returning coordinates would disclose the user's location to an
    // unauthenticated caller. The app only needs the series.
    res.json({ ok: true, ts: new Date().toISOString(), weather, sky_kp: kp });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

// History series for the "Agora" detail screen (weather-app-style trends): sky (Kp/Dst/
// solar wind/Bz), ambient (temp/pressure/humidity/UV), and body (HRV). PUBLIC like the
// latest endpoint — only the user's own uploaded series + global NOAA data; best-effort.
const HRV_TYPE = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN";
const AUDIO_DB_TYPE = "HKQuantityTypeIdentifierEnvironmentalAudioExposure";
app.get("/api/physiome/agora-history", async (req, res) => {
  const hours = Math.min(Math.max(Number(req.query.hours) || 48, 6), 168);
  try {
    const [sky, weather, hrv, audioDb] = await Promise.all([
      getSpaceWeatherHistory(pool, hours),
      getWeatherHistory(pool, hours),
      getHealthHistory(pool, HRV_TYPE, hours),
      getHealthHistory(pool, AUDIO_DB_TYPE, hours),
    ]);
    res.json({ ok: true, hours, sky, weather, hrv, audioDb });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

// APNs device-token registration + a test-push endpoint (both authed). The sender
// (apps/physiome/src/apns.mjs) fails soft when APNS_* env is unset, so these are inert
// until the key + Push capability are live — proven working: sandbox returns BadDeviceToken.
app.post("/api/physiome/device-token", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  const { token, apns_env, bundle } = req.body || {};
  if (!token) return res.status(400).json({ error: "missing token" });
  try {
    await upsertDeviceToken(pool, { token, apnsEnv: apns_env || "sandbox", bundle: bundle || "dev.sounio.cockpit" });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

app.post("/api/physiome/ema", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  try { const id = await saveEmaResponse(pool, req.body || {}); res.json({ ok: true, id }); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Force an EMA prompt regardless of the gate/cooldown/hours — for testing the push+deep-link
// path without moving or enabling the live trigger. Does NOT change ema_state.last_prompt cooldown gate.
app.post("/api/physiome/ema-trigger-test", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  try {
    const place = (req.body && req.body.place) || "Casa";
    const r = await fire(pool, { place, fromPlace: (req.body && req.body.from_place) || null, trigger: "test",
                                 protocol: process.env.EMA_PROTOCOL_VERSION || "v0-draft", force: true });
    res.json(r);
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

app.post("/api/physiome/push-test", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  try {
    const row = await getLatestDeviceToken(pool);
    if (!row) return res.status(404).json({ error: "no device token registered" });
    const result = await sendPush({
      deviceToken: row.token,
      title: "Beagle",
      body: "Test push from physiome-ingest.",
      env: row.apns_env,
    });
    res.status(result.ok ? 200 : 502).json(result);
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

app.listen(PORT, () => console.log(`[physiome] ingest listening on :${PORT}`));
