import express from "express";
import { makePool, ensureSchema, upsertHealthSamples, upsertWeather } from "../src/db.mjs";
import { validateBatch } from "../src/validate.mjs";

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
    const { health_samples, weather_obs } = validateBatch(req.body || {});
    const health = await upsertHealthSamples(pool, health_samples);
    const weather = await upsertWeather(pool, weather_obs);
    res.json({ ok: true, ingested: { health, weather } });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

app.listen(PORT, () => console.log(`[physiome] ingest listening on :${PORT}`));
