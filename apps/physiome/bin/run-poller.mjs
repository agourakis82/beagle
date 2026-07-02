// Poll NOAA SWPC space-weather products → parse → upsert a latest snapshot into space_weather.
// Fail-soft per source: a missing/down feed yields null for that metric, never crashes the run.
import { makePool, ensureSchema, upsertSpaceWeather } from "../src/db.mjs";
import {
  parseKp, parseDst, parseF107, parseSolarWind, parseHpAscii, parseNmdbAscii, mergeSpaceWeather,
} from "../src/spaceweather.mjs";

const SWPC = "https://services.swpc.noaa.gov/products";
// GFZ Hp30/Hp60 nowcast (30/60-min geomagnetic, ASCII). Use kp.gfz.de — the www.gfz.de
// path 404s. NMDB neutron rate (galactic cosmic ray / Forbush context): the NEST ascii
// GET, fail-soft (NMDB rate-limits/blocks some IPs → empty body → null column).
const GFZ = "https://kp.gfz.de/app/files";
function nmdbUrl() {
  const end = new Date();
  const start = new Date(end.getTime() - 2 * 24 * 3600 * 1000); // trailing 2 days
  const p = (d) => ({ y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate() });
  const s = p(start), e = p(end);
  return (
    "https://www.nmdb.eu/nest/draw_graph.php?formchk=1&stations[]=OULU&output=ascii" +
    "&tabchoice=revori&dtype=corr_for_efficiency&date_choice=bydate&yunits=0&tresolution=60" +
    `&start_year=${s.y}&start_month=${s.m}&start_day=${s.d}&start_hour=0&start_min=0` +
    `&end_year=${e.y}&end_month=${e.m}&end_day=${e.d}&end_hour=23&end_min=0`
  );
}
const URLS = {
  kp: `${SWPC}/noaa-planetary-k-index.json`,
  dst: `${SWPC}/kyoto-dst.json`,
  f107: `${SWPC}/10cm-flux-30-day.json`,
  plasma: `${SWPC}/solar-wind/plasma-1-day.json`,
  mag: `${SWPC}/solar-wind/mag-1-day.json`,
  hp30: `${GFZ}/Hp30_ap30_nowcast.txt`,
  hp60: `${GFZ}/Hp60_ap60_nowcast.txt`,
  nmdb: nmdbUrl(),
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

async function getText(url) {
  try {
    const r = await fetch(url, {
      signal: AbortSignal.timeout(25000),
      headers: { "User-Agent": "beagle-physiome-poller/1 (research; contact via github.com/agourakis82/beagle)" },
    });
    if (!r.ok) throw new Error(`${r.status}`);
    return await r.text();
  } catch (e) {
    console.error(`[poller] ${url} failed: ${e.message}`);
    return null;
  }
}

const [kpJ, dstJ, f107J, plasmaJ, magJ, hp30T, hp60T, nmdbT] = await Promise.all([
  getJson(URLS.kp), getJson(URLS.dst), getJson(URLS.f107), getJson(URLS.plasma), getJson(URLS.mag),
  getText(URLS.hp30), getText(URLS.hp60), getText(URLS.nmdb),
]);
const sw = parseSolarWind(plasmaJ || [], magJ || []);
const row = mergeSpaceWeather({
  kp: parseKp(kpJ || []),
  dst: parseDst(dstJ || []),
  f107: parseF107(f107J || []),
  speed: sw.speed,
  bz: sw.bz,
  hp30: parseHpAscii(hp30T || ""),
  hp60: parseHpAscii(hp60T || ""),
  cosmicRay: parseNmdbAscii(nmdbT || ""),
});

const pool = makePool();
await ensureSchema(pool);
const n = await upsertSpaceWeather(pool, row);
await pool.end();
console.log("[poller]", JSON.stringify({ upserted: n, ...row }));
