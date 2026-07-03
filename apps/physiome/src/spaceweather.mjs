// Parse NOAA SWPC products (array-of-arrays with a header row) into typed series.
// Pure (no I/O) so it's unit-testable; the poller bin does the fetching.

// Handles BOTH NOAA SWPC shapes: array-of-objects ({time_tag, <value>}) and
// array-of-arrays with a header row (["time_tag", ...], [...]).
function seriesByHeader(json, valueNames) {
  if (!Array.isArray(json) || json.length < 1) return [];
  const want = valueNames.map((s) => s.toLowerCase());

  // array-of-objects
  if (json[0] && !Array.isArray(json[0]) && typeof json[0] === "object") {
    const keys = Object.keys(json[0]);
    const tsKey = keys.find((k) => k.toLowerCase() === "time_tag");
    const valKey = keys.find((k) => want.includes(k.toLowerCase()));
    if (!tsKey || !valKey) return [];
    const out = [];
    for (const o of json) {
      const v = Number(o[valKey]);
      if (o[tsKey] && Number.isFinite(v)) out.push({ ts: isoUtc(o[tsKey]), value: v });
    }
    return out;
  }

  // array-of-arrays with header row
  if (json.length < 2) return [];
  const header = json[0].map((h) => String(h).toLowerCase());
  const tsIdx = header.indexOf("time_tag");
  let valIdx = -1;
  for (const name of want) {
    valIdx = header.indexOf(name);
    if (valIdx >= 0) break;
  }
  if (tsIdx < 0 || valIdx < 0) return [];
  const out = [];
  for (let i = 1; i < json.length; i++) {
    const row = json[i];
    const v = Number(row[valIdx]);
    if (!row[tsIdx] || !Number.isFinite(v)) continue;
    out.push({ ts: isoUtc(row[tsIdx]), value: v });
  }
  return out;
}

function isoUtc(t) {
  // SWPC uses "YYYY-MM-DD HH:MM:SS" (UTC). Normalize to ISO.
  const s = String(t).trim().replace(" ", "T");
  return s.endsWith("Z") || /[+-]\d\d:?\d\d$/.test(s) ? s : s + "Z";
}

export function parseKp(json) {
  return seriesByHeader(json, ["kp", "kp_index", "estimated_kp"]).map((r) => ({ ts: r.ts, kp: r.value }));
}

export function parseF107(json) {
  return seriesByHeader(json, ["flux", "f10.7", "f107", "observed_flux"]).map((r) => ({ ts: r.ts, f107: r.value }));
}

export function parseDst(json) {
  return seriesByHeader(json, ["dst", "dst_index"]).map((r) => ({ ts: r.ts, dst: r.value }));
}

// NOAA retired /products/solar-wind/plasma-1-day.json + mag-1-day.json (both 404 as of
// 2026-07). The live sources are the /products/summary/ single-latest products, whose speed
// field is "proton_speed" (not "speed"/"bulk_speed") — and the real-time /json/rtsw/ feeds,
// which are ordered NEWEST-FIRST (so the ascending-order latest() would pick the oldest row).
// Accept all of those value names; the poller now points at the summary products.
export function parseSolarWind(plasmaJson, magJson) {
  return {
    speed: seriesByHeader(plasmaJson, ["speed", "bulk_speed", "proton_speed"]),
    bz: seriesByHeader(magJson, ["bz_gsm", "bz"]),
  };
}

function latest(arr, key) {
  for (let i = arr.length - 1; i >= 0; i--) {
    const v = key ? arr[i][key] : arr[i].value;
    if (Number.isFinite(v)) return { v, ts: arr[i].ts };
  }
  return { v: null, ts: null };
}

// Parse a GFZ Hp30/Hp60 nowcast ASCII file. Whitespace-separated columns:
//   YYY MM DD hh.h hh._m days days_m Hp ap D
// where hh.h is the decimal UTC hour of the interval START, and Hp/ap are -1 for
// intervals not yet observed (the nowcast file is pre-filled to end-of-day). Returns
// observed rows only, as [{ ts, hp, ap }]. Same layout for Hp30 and Hp60 files.
export function parseHpAscii(text) {
  const out = [];
  if (typeof text !== "string") return out;
  for (const line of text.split("\n")) {
    if (!line || line[0] === "#") continue;
    const f = line.trim().split(/\s+/);
    if (f.length < 9) continue;
    const hp = Number(f[7]);
    const ap = Number(f[8]);
    if (!Number.isFinite(hp) || hp < 0) continue; // -1 = not yet observed
    const hStart = Number(f[3]);
    if (!Number.isFinite(hStart)) continue;
    const hh = Math.floor(hStart);
    const mm = Math.round((hStart - hh) * 60);
    const p2 = (n) => String(n).padStart(2, "0");
    const ts = `${f[0]}-${p2(f[1])}-${p2(f[2])}T${p2(hh)}:${p2(mm)}:00Z`;
    out.push({ ts, hp, ap: Number.isFinite(ap) && ap >= 0 ? ap : null });
  }
  return out;
}

// Parse NMDB NEST ascii (semicolon-delimited): comment/blank lines, then a header,
// then rows "YYYY-MM-DD HH:MM:SS;<count>". Returns [{ ts, count }]. Fail-soft: an
// empty/HTML body (NMDB sometimes rate-limits or blocks) yields []. count is the
// efficiency-corrected neutron rate; the poller keeps the most recent finite row.
export function parseNmdbAscii(text) {
  const out = [];
  if (typeof text !== "string") return out;
  for (const line of text.split("\n")) {
    const s = line.trim();
    if (!s || s[0] === "#") continue;
    const parts = s.split(";");
    if (parts.length < 2) continue;
    const d = parts[0].trim();
    const v = Number(parts[1]);
    if (!/^\d{4}-\d\d-\d\d/.test(d) || !Number.isFinite(v)) continue;
    out.push({ ts: d.replace(" ", "T") + (/[Zz]|[+-]\d\d:?\d\d$/.test(d) ? "" : "Z"), count: v });
  }
  return out;
}

// Parse NOAA SWPC GOES X-ray flux (array-of-objects: {time_tag, satellite, flux, energy}).
// The feed interleaves TWO energy channels — short (0.05-0.4nm) and long (0.1-0.8nm). The
// LONG channel drives flare classification (C >=1e-6, M >=1e-5, X >=1e-4 W/m²), so we keep
// only energy === "0.1-0.8nm". Returns [{ ts, xray_flux }]. Fail-soft: non-array → [].
export function parseXrayFlux(json) {
  if (!Array.isArray(json)) return [];
  const out = [];
  for (const o of json) {
    if (!o || typeof o !== "object" || String(o.energy) !== "0.1-0.8nm") continue;
    const v = Number(o.flux);
    if (o.time_tag && Number.isFinite(v)) out.push({ ts: isoUtc(o.time_tag), xray_flux: v });
  }
  return out;
}

// Parse NOAA SWPC GOES integral proton flux (array-of-objects: {time_tag, satellite, flux,
// energy}). The feed carries many energy channels; the radiation-storm S-scale is defined
// on the >=10 MeV channel (S1 10, S2 100, S3 1e3, S4 1e4, S5 1e5 protons/cm²/s), so we keep
// only energy === ">=10 MeV". Returns [{ ts, proton_flux }]. Fail-soft: non-array → [].
export function parseProtonFlux(json) {
  if (!Array.isArray(json)) return [];
  const out = [];
  for (const o of json) {
    if (!o || typeof o !== "object" || String(o.energy) !== ">=10 MeV") continue;
    const v = Number(o.flux);
    if (o.time_tag && Number.isFinite(v)) out.push({ ts: isoUtc(o.time_tag), proton_flux: v });
  }
  return out;
}

// Parse NOAA SWPC OVATION aurora nowcast: ONE object with a `coordinates` array of
// [lon, lat, aurora] triples (aurora 0..~22, arbitrary units, 1° global grid). We collapse
// the grid to a single hemispheric-power proxy = SUM of the aurora column (an integrated
// power measure), timestamped at "Observation Time". Returns [{ ts, aurora_power }] (0 or 1
// row). Fail-soft: missing/blank coordinates → [].
export function parseOvation(json) {
  if (!json || typeof json !== "object" || !Array.isArray(json.coordinates)) return [];
  let sum = 0, n = 0;
  for (const c of json.coordinates) {
    if (!Array.isArray(c) || c.length < 3) continue;
    const a = Number(c[2]);
    if (Number.isFinite(a)) { sum += a; n++; }
  }
  if (n === 0) return [];
  const t = json["Observation Time"] || json["Forecast Time"];
  const ts = t ? isoUtc(t) : new Date().toISOString();
  return [{ ts, aurora_power: sum }];
}

// Parse NASA CDAWeb HAPI OMNI_HRO_1MIN CSV. The /hapi/data rows are HEADERLESS and column
// order is fixed by the request's parameters=AE_INDEX,AL_INDEX,AU_INDEX,SYM_H, so each row
// is: Time,AE,AL,AU,SYM_H. Fill value 99999 → dropped (null). Returns { ae:[{ts,ae}],
// symH:[{ts,sym_h}] }. RETROSPECTIVE ONLY: OMNI currently has ~40-day latency, so the live
// poller snapshot for sym_h/ae_index is USUALLY NULL — this feed backfills historical rows
// (older than ~30d) via ON CONFLICT. Same fail-soft contract as every other channel.
export function parseOmniCsv(text) {
  const ae = [], symH = [];
  if (typeof text !== "string") return { ae, symH };
  const FILL = 99999;
  for (const line of text.split("\n")) {
    const s = line.trim();
    if (!s || s[0] === "#") continue;
    const f = s.split(",");
    if (f.length < 5 || !/^\d{4}-\d\d-\d\d/.test(f[0])) continue; // skip any header row
    const ts = isoUtc(f[0]);
    const aeV = Number(f[1]), symV = Number(f[4]);
    if (Number.isFinite(aeV) && aeV !== FILL) ae.push({ ts, ae: aeV });
    if (Number.isFinite(symV) && symV !== FILL) symH.push({ ts, sym_h: symV });
  }
  return { ae, symH };
}

// Collapse the latest reading of each series into one snapshot row for `space_weather`.
// New (2026-07) high-cadence + heliophysics channels: hp30/hp60/ap30 (GFZ, 30/60-min
// geomagnetic — finer than 3-hourly Kp) and cosmicRay (NMDB neutron rate, for Forbush
// context). Also NOAA GOES xrayFlux (long-channel W/m², flare context) + protonFlux (>=10
// MeV, S-scale) + OVATION aurora hemispheric power, and OMNI symH/ae (RETROSPECTIVE backfill
// — live snapshot usually null). All fail-soft: a missing feed leaves that column null,
// never crashes the run.
export function mergeSpaceWeather({
  kp = [], dst = [], f107 = [], speed = [], bz = [], hp30 = [], hp60 = [], cosmicRay = [],
  xrayFlux = [], protonFlux = [], aurora = [], symH = [], ae = [],
}) {
  const lk = latest(kp, "kp"), ld = latest(dst, "dst"), lf = latest(f107, "f107");
  const ls = latest(speed), lb = latest(bz);
  const lh30 = latest(hp30, "hp"), lap30 = latest(hp30, "ap"), lh60 = latest(hp60, "hp");
  const lcr = latest(cosmicRay, "count");
  const lxr = latest(xrayFlux, "xray_flux"), lpr = latest(protonFlux, "proton_flux");
  const lau = latest(aurora, "aurora_power");
  const lsy = latest(symH, "sym_h"), lae = latest(ae, "ae");
  // Snapshot ts = the FRESHEST observation among the present metrics, NOT Kp's coarse 3-hourly
  // stamp. Keying to Kp pinned every poll within a 3h window onto ONE row, so the fast metrics
  // (solar wind, X-ray — native ~1-min) were flattened to 3-hourly in the history/chart and the
  // reported "as of" was misleading. Freshest-ts makes each poll a distinct row at its real time,
  // giving per-poll granularity for the fast channels and an honest timestamp. sym_h/ae from the
  // OMNI backfill are ~40d old so they never win the max; the live channels do.
  const tsCandidates = [lk, ld, lf, ls, lb, lh30, lh60, lcr, lxr, lpr, lau]
    .map((x) => x.ts)
    .filter(Boolean);
  const ts = tsCandidates.length
    ? tsCandidates.reduce((a, b) => (new Date(b) > new Date(a) ? b : a))
    : lsy.ts || lae.ts || new Date().toISOString();
  return {
    ts, kp: lk.v, dst: ld.v, f107: lf.v, solar_wind_speed: ls.v, bz: lb.v,
    hp30: lh30.v, ap30: lap30.v, hp60: lh60.v, cosmic_ray_oulu: lcr.v,
    xray_flux: lxr.v, proton_flux: lpr.v, aurora_power: lau.v,
    sym_h: lsy.v, ae_index: lae.v,
    source: "noaa-swpc+gfz+nmdb+omni",
  };
}
