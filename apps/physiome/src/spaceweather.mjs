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

export function parseSolarWind(plasmaJson, magJson) {
  return {
    speed: seriesByHeader(plasmaJson, ["speed", "bulk_speed"]),
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

// Collapse the latest reading of each series into one snapshot row for `space_weather`.
// New (2026-07) high-cadence + heliophysics channels: hp30/hp60/ap30 (GFZ, 30/60-min
// geomagnetic — finer than 3-hourly Kp) and cosmicRay (NMDB neutron rate, for Forbush
// context). All fail-soft: a missing feed leaves that column null, never crashes the run.
export function mergeSpaceWeather({
  kp = [], dst = [], f107 = [], speed = [], bz = [], hp30 = [], hp60 = [], cosmicRay = [],
}) {
  const lk = latest(kp, "kp"), ld = latest(dst, "dst"), lf = latest(f107, "f107");
  const ls = latest(speed), lb = latest(bz);
  const lh30 = latest(hp30, "hp"), lap30 = latest(hp30, "ap"), lh60 = latest(hp60, "hp");
  const lcr = latest(cosmicRay, "count");
  const ts =
    lk.ts || ld.ts || lf.ts || ls.ts || lb.ts || lh30.ts || lh60.ts || lcr.ts ||
    new Date().toISOString();
  return {
    ts, kp: lk.v, dst: ld.v, f107: lf.v, solar_wind_speed: ls.v, bz: lb.v,
    hp30: lh30.v, ap30: lap30.v, hp60: lh60.v, cosmic_ray_oulu: lcr.v,
    source: "noaa-swpc+gfz+nmdb",
  };
}
