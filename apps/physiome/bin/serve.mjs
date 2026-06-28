import express from "express";
import { makePool, ensureSchema, upsertHealthSamples, upsertWeather } from "../src/db.mjs";
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

// Latest space weather snapshot — Kp, F10.7, solar wind, IMF Bz. The /noaa-swpc
// poller (run-poller.mjs) writes this every 2h; this is the read side so the
// iOS companion can render the aurora presence with real-time geomagnetic state.
// Read-only; same auth gate as ingest.
app.get("/api/physiome/space-weather/latest", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  try {
    const { rows } = await pool.query(
      `SELECT ts, kp, f107, solar_wind_speed, bz, source
         FROM space_weather ORDER BY ts DESC LIMIT 1`
    );
    if (!rows.length) return res.json({ ok: true, latest: null });
    res.json({ ok: true, latest: rows[0] });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

app.listen(PORT, () => console.log(`[physiome] ingest listening on :${PORT}`));
