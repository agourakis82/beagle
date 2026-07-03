// Poll NOAA SWPC space-weather products → parse → upsert a latest snapshot into space_weather.
// Fail-soft per source: a missing/down feed yields null for that metric, never crashes the run.
import { makePool, ensureSchema, upsertSpaceWeather, upsertHiresSeries } from "../src/db.mjs";
import {
  parseKp, parseDst, parseF107, parseSolarWind, parseHpAscii, parseNmdbAscii,
  parseXrayFlux, parseProtonFlux, parseOvation, parseOmniCsv, parseRtswSeries, mergeSpaceWeather,
} from "../src/spaceweather.mjs";

const SWPC = "https://services.swpc.noaa.gov/products";
// NOAA SWPC JSON products (separate host from /products): GOES X-ray (0.1-0.8nm long channel,
// flare context), GOES integral protons (>=10 MeV, radiation-storm S-scale), OVATION aurora
// nowcast (hemispheric power). All array-/object-JSON, fail-soft via getJson → null.
const SWPC_JSON = "https://services.swpc.noaa.gov/json";
// NASA CDAWeb HAPI OMNI_HRO_1MIN → SYM-H + AE (nT). RETROSPECTIVE ONLY: OMNI runs ~40-day
// latency, so the live snapshot for sym_h/ae_index is almost always null; this feed only
// backfills historical rows (ON CONFLICT). Request a wide trailing window so we catch
// whatever has been published. Returns headerless CSV text → parseOmniCsv.
function omniUrl() {
  const end = new Date();
  const start = new Date(end.getTime() - 45 * 24 * 3600 * 1000); // trailing 45 days
  const iso = (d) => d.toISOString().slice(0, 19) + "Z";
  return (
    "https://cdaweb.gsfc.nasa.gov/hapi/data?id=OMNI_HRO_1MIN" +
    `&time.min=${iso(start)}&time.max=${iso(end)}` +
    "&parameters=AE_INDEX,AL_INDEX,AU_INDEX,SYM_H&format=csv"
  );
}
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
  // NOAA retired /products/solar-wind/plasma-1-day.json + mag-1-day.json (404 as of 2026-07).
  // Use the /products/summary/ single-latest products — speed via proton_speed, IMF via
  // bz_gsm — which are what SpaceWeatherLive shows and are always the newest reading.
  plasma: `${SWPC}/summary/solar-wind-speed.json`,
  mag: `${SWPC}/summary/solar-wind-mag-field.json`,
  hp30: `${GFZ}/Hp30_ap30_nowcast.txt`,
  hp60: `${GFZ}/Hp60_ap60_nowcast.txt`,
  nmdb: nmdbUrl(),
  xray: `${SWPC_JSON}/goes/primary/xrays-1-day.json`,
  proton: `${SWPC_JSON}/goes/primary/integral-protons-1-day.json`,
  ovation: `${SWPC_JSON}/ovation_aurora_latest.json`,
  omni: omniUrl(),
  // Native ~1-minute real-time solar wind (DSCOVR/ACE) → space_weather_hires, for intraday
  // scientific correlation. Newest-first, multi-source; parseRtswSeries keeps active===true.
  rtswWind: `${SWPC_JSON}/rtsw/rtsw_wind_1m.json`,
  rtswMag: `${SWPC_JSON}/rtsw/rtsw_mag_1m.json`,
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

const [kpJ, dstJ, f107J, plasmaJ, magJ, hp30T, hp60T, nmdbT, xrayJ, protonJ, ovationJ, omniT, rtswWindJ, rtswMagJ] =
  await Promise.all([
    getJson(URLS.kp), getJson(URLS.dst), getJson(URLS.f107), getJson(URLS.plasma), getJson(URLS.mag),
    getText(URLS.hp30), getText(URLS.hp60), getText(URLS.nmdb),
    getJson(URLS.xray), getJson(URLS.proton), getJson(URLS.ovation), getText(URLS.omni),
    getJson(URLS.rtswWind), getJson(URLS.rtswMag),
  ]);
const sw = parseSolarWind(plasmaJ || [], magJ || []);
const omni = parseOmniCsv(omniT || ""); // { ae, symH } — RETROSPECTIVE backfill, usually null live
const row = mergeSpaceWeather({
  kp: parseKp(kpJ || []),
  dst: parseDst(dstJ || []),
  f107: parseF107(f107J || []),
  speed: sw.speed,
  bz: sw.bz,
  hp30: parseHpAscii(hp30T || ""),
  hp60: parseHpAscii(hp60T || ""),
  cosmicRay: parseNmdbAscii(nmdbT || ""),
  xrayFlux: parseXrayFlux(xrayJ || []),
  protonFlux: parseProtonFlux(protonJ || []),
  aurora: parseOvation(ovationJ || null),
  symH: omni.symH,
  ae: omni.ae,
});

// Native 1-minute solar wind → hires store. Bound to a trailing ~40-min window (covers the
// 30-min poll gap + margin) so each run upserts only recent points, not the whole ~1-day feed.
// Idempotent (ON CONFLICT), so overlap across runs is harmless.
const HIRES_WINDOW_MS = 40 * 60 * 1000;
const hiresCutoff = Date.now() - HIRES_WINDOW_MS;
const inWindow = (p) => { const t = new Date(p.ts).getTime(); return Number.isFinite(t) && t >= hiresCutoff; };
const hiresRows = [
  ...parseRtswSeries(rtswWindJ || [], "proton_speed").filter(inWindow)
    .map((p) => ({ ts: p.ts, metric: "solar_wind_speed", value: p.value, source: "noaa-rtsw" })),
  ...parseRtswSeries(rtswMagJ || [], "bz_gsm").filter(inWindow)
    .map((p) => ({ ts: p.ts, metric: "bz", value: p.value, source: "noaa-rtsw" })),
];

const pool = makePool();
await ensureSchema(pool);
const n = await upsertSpaceWeather(pool, row);
const hiresN = await upsertHiresSeries(pool, hiresRows);
await pool.end();
console.log("[poller]", JSON.stringify({ upserted: n, hires: hiresN, ...row }));
