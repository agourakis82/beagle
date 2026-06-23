// Physiome daily digest: a compact, deterministic pt-BR summary of the day's body+environment,
// for the Personal companion's grounding. buildPhysiomeSummary is pure (testable);
// generateDigest (added with DB wiring) aggregates Postgres + stores into the exocortex.

function n(v, suffix = "") {
  return v == null || Number.isNaN(v) ? "—" : `${v}${suffix}`;
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
