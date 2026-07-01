// Physiome daily digest: a compact, deterministic pt-BR summary of the day's body+environment,
// for the Personal companion's grounding. buildPhysiomeSummary is pure (testable);
// generateDigest (added with DB wiring) aggregates Postgres + stores into the exocortex.

import { correlatePhysiome, summarizeCorrelations } from "./correlate.mjs";

function n(v, suffix = "") {
  return v == null || Number.isNaN(v) ? "—" : `${v}${suffix}`;
}

// Aggregate one UTC day from the raw store. Returns the shape buildPhysiomeSummary consumes.
export async function aggregateDay(pool, date) {
  const win = [date]; // 'YYYY-MM-DD'
  const range = "ts >= $1::date AND ts < ($1::date + interval '1 day')";
  const h = (await pool.query(
    `SELECT
       COALESCE(SUM(EXTRACT(EPOCH FROM (end_ts - ts))) FILTER (WHERE type='HKCategoryTypeIdentifierSleepAnalysis')/3600.0, 0) AS sleep_hours,
       AVG(value) FILTER (WHERE type='HKQuantityTypeIdentifierHeartRateVariabilitySDNN') AS hrv_ms,
       AVG(value) FILTER (WHERE type='HKQuantityTypeIdentifierRestingHeartRate') AS resting_hr,
       SUM(value) FILTER (WHERE type='HKQuantityTypeIdentifierStepCount') AS steps,
       SUM(value) FILTER (WHERE type='HKQuantityTypeIdentifierActiveEnergyBurned') AS active_kcal,
       AVG(value) FILTER (WHERE type='HKStateOfMindType') AS mood
     FROM health_samples WHERE ${range}`, win)).rows[0];
  const w = (await pool.query(
    `SELECT MIN(temp_c) tmin, MAX(temp_c) tmax, MAX(uv_index) uvmax, AVG(aqi) aqi,
       (SELECT pressure_hpa FROM weather_obs WHERE ${range} ORDER BY ts DESC LIMIT 1) -
       (SELECT pressure_hpa FROM weather_obs WHERE ${range} ORDER BY ts ASC LIMIT 1) AS press_trend
     FROM weather_obs WHERE ${range}`, win)).rows[0];
  const s = (await pool.query(
    `SELECT MAX(kp) kpmax, (ARRAY_AGG(f107 ORDER BY ts DESC))[1] f107, AVG(solar_wind_speed) sws
     FROM space_weather WHERE ${range}`, win)).rows[0];
  const r1 = (x) => (x == null ? null : Math.round(Number(x) * 10) / 10);
  const r0 = (x) => (x == null ? null : Math.round(Number(x)));
  return {
    date,
    health: { sleepHours: r1(h.sleep_hours), hrvMs: r0(h.hrv_ms), restingHr: r0(h.resting_hr), steps: r0(h.steps), activeKcal: r0(h.active_kcal), mood: r1(h.mood) },
    weather: { tempMinC: r1(w.tmin), tempMaxC: r1(w.tmax), pressureTrendHpa: r1(w.press_trend), uvMax: r0(w.uvmax), aqi: r0(w.aqi) },
    space: { kpMax: r1(s.kpmax), f107: r0(s.f107), solarWindSpeed: r0(s.sws) },
  };
}

// Aggregate the last `days` UTC days (inclusive of endDate, default today) into the per-day series
// the correlation engine consumes. Thin glue over aggregateDay.
export async function aggregateRange(pool, days = 30, endDate = null) {
  const end = endDate ? new Date(`${endDate}T00:00:00Z`) : new Date();
  const out = [];
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(end);
    d.setUTCDate(d.getUTCDate() - i);
    out.push(await aggregateDay(pool, d.toISOString().slice(0, 10)));
  }
  return out;
}

// Aggregate the day → deterministic summary → store as a pinned, sovereign exocortex doc.
// Best-effort: also fold trailing-window correlation insights into the stored digest so the
// companion's grounding (which already fetches the physiome-digest tag) becomes correlation-aware
// with no cockpit change. A correlation failure must never block the daily digest.
export async function generateDigest(pool, date, { assistedImport, correlationDays = 30 } = {}) {
  const agg = await aggregateDay(pool, date);
  let summary = buildPhysiomeSummary(agg);
  let correlations = null;
  try {
    const aggs = await aggregateRange(pool, correlationDays, date);
    const res = correlatePhysiome(aggs, {});
    if (res.correlations.some((c) => c.notable)) {
      summary = `${summary}\n\n${summarizeCorrelations(res)}`;
      correlations = res.correlations.filter((c) => c.notable);
    }
  } catch {
    // ignore — store the plain daily digest
  }
  await assistedImport({
    title: `Físio+ambiente — ${date}`,
    sessionId: `physiome-digest:${date}`,
    sourcePlatform: "physiome",
    sourceSurface: "physiome-digest",
    importScope: "physiome_digest",
    confidenceScore: 0.95,
    privacyClass: "sensitive",
    turns: [{ role: "user", content: summary, timestamp: new Date().toISOString(), metadata: { kind: "physiome-digest", date } }],
    tags: ["physiome-digest", "pinned", `date:${date}`],
    metadata: { kind: "physiome-digest", date, agg, correlations },
  });
  return { summary, agg, correlations };
}

export function buildPhysiomeSummary(agg) {
  const h = agg?.health || {};
  const w = agg?.weather || {};
  const s = agg?.space || {};
  const parts = [
    `## Físio+ambiente de ${agg?.date || "hoje"} (Demetrios)`,
    `Corpo: sono ${n(h.sleepHours, "h")}, HRV ${n(h.hrvMs, "ms")}, FC repouso ${n(h.restingHr)}, ` +
      `${n(h.steps)} passos, ${n(h.activeKcal, " kcal")} ativos.`,
    `Clima: ${n(w.tempMinC, "°")}–${n(w.tempMaxC, "°C")}, pressão Δ ${n(w.pressureTrendHpa, " hPa")}, ` +
      `UV ${n(w.uvMax)}, AQI ${n(w.aqi)}.`,
    `Espacial: Kp máx ${n(s.kpMax)}, F10.7 ${n(s.f107)}, vento solar ${n(s.solarWindSpeed, " km/s")}.`,
  ];
  return parts.join("\n").slice(0, 1100);
}
