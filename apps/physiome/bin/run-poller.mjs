// Poll NOAA SWPC space-weather products → parse → upsert a latest snapshot into space_weather.
// Fail-soft per source: a missing/down feed yields null for that metric, never crashes the run.
import { makePool, ensureSchema, upsertSpaceWeather } from "../src/db.mjs";
import { parseKp, parseDst, parseF107, parseSolarWind, mergeSpaceWeather } from "../src/spaceweather.mjs";

const SWPC = "https://services.swpc.noaa.gov/products";
const URLS = {
  kp: `${SWPC}/noaa-planetary-k-index.json`,
  dst: `${SWPC}/kyoto-dst.json`,
  f107: `${SWPC}/10cm-flux-30-day.json`,
  plasma: `${SWPC}/solar-wind/plasma-1-day.json`,
  mag: `${SWPC}/solar-wind/mag-1-day.json`,
};

async function getJson(url) {
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(20000) });
    if (!r.ok) throw new Error(`${r.status}`);
    return await r.json();
  } catch (e) {
    console.error(`[poller] ${url} failed: ${e.message}`);
    return null;
  }
}

const [kpJ, dstJ, f107J, plasmaJ, magJ] = await Promise.all(
  [URLS.kp, URLS.dst, URLS.f107, URLS.plasma, URLS.mag].map(getJson)
);
const sw = parseSolarWind(plasmaJ || [], magJ || []);
const row = mergeSpaceWeather({
  kp: parseKp(kpJ || []),
  dst: parseDst(dstJ || []),
  f107: parseF107(f107J || []),
  speed: sw.speed,
  bz: sw.bz,
});

const pool = makePool();
await ensureSchema(pool);
const n = await upsertSpaceWeather(pool, row);
await pool.end();
console.log("[poller]", JSON.stringify({ upserted: n, ...row }));
