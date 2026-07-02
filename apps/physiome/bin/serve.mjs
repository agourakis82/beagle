import express from "express";
import {
  makePool, ensureSchema, upsertHealthSamples, upsertWeather,
  getSpaceWeatherHistory, getWeatherHistory, getHealthHistory
} from "../src/db.mjs";
import { validateBatch } from "../src/validate.mjs";
import { aggregateRange } from "../src/digest.mjs";
import { correlatePhysiome, summarizeCorrelations } from "../src/correlate.mjs";

const PORT = Number(process.env.PORT || 8090);
const INGEST_TOKEN = process.env.PHYSIOME_INGEST_TOKEN || "";

const pool = makePool();
await ensureSchema(pool);

const app = express();
app.use(express.json({ limit: "16mb" }));

app.get("/healthz", (_req, res) => res.json({ ok: true }));

function authed(req) {
  if (!INGEST_TOKEN) return true; // unset = open (dev); set in prod
  const auth = req.get("authorization") || "";
  return auth === `Bearer ${INGEST_TOKEN}`;
}

app.post("/api/physiome/ingest", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  try {
    const { health_samples, weather_obs, received, rejected } = validateBatch(req.body || {});
    const health = await upsertHealthSamples(pool, health_samples);
    const weather = await upsertWeather(pool, weather_obs);
    if (rejected.health || rejected.weather) {
      console.warn(`[physiome] ingest dropped invalid samples: health=${rejected.health}/${received.health} weather=${rejected.weather}/${received.weather}`);
    }
    res.json({ ok: true, ingested: { health, weather }, received, rejected });
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
         (SELECT ts FROM space_weather ORDER BY ts DESC LIMIT 1) AS ts,
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
         (SELECT source FROM space_weather ORDER BY ts DESC LIMIT 1) AS source`
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
    let w;
    try { w = await fetchOpenMeteo(lat, lon); }
    catch (e1) {
      try { w = await fetchOWM(lat, lon); }
      catch (e2) { return res.status(502).json({ error: `both weather providers failed: ${e1.message}; ${e2.message}` }); }
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

app.listen(PORT, () => console.log(`[physiome] ingest listening on :${PORT}`));
