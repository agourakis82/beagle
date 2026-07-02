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
