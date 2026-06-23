// Parse NOAA SWPC products (array-of-arrays with a header row) into typed series.
// Pure (no I/O) so it's unit-testable; the poller bin does the fetching.

function seriesByHeader(json, valueNames) {
  if (!Array.isArray(json) || json.length < 2) return [];
  const header = json[0].map((h) => String(h).toLowerCase());
  const tsIdx = header.indexOf("time_tag");
  let valIdx = -1;
  for (const name of valueNames) {
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

// Collapse the latest reading of each series into one snapshot row for `space_weather`.
export function mergeSpaceWeather({ kp = [], f107 = [], speed = [], bz = [] }) {
  const lk = latest(kp, "kp"), lf = latest(f107, "f107"), ls = latest(speed), lb = latest(bz);
  const ts = lk.ts || lf.ts || ls.ts || lb.ts || new Date().toISOString();
  return { ts, kp: lk.v, f107: lf.v, solar_wind_speed: ls.v, bz: lb.v, source: "noaa-swpc" };
}
