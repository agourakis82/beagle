// aggregate.mjs — Phase C: daily aggregates + the companion grounding digest.
//
// Rolls the per-turn cognitive_telemetry up to per-DAY summaries (which also
// mitigates the within-session autocorrelation before correlation) and produces a
// compact recent digest for the companion (coherence trend, dissociation proximity,
// rupture episodes) — injected alongside the biography + physiome digests.

function mean(xs) { return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null; }
function r3(v) { return v == null ? null : Math.round(v * 1000) / 1000; }

/**
 * Group per-turn telemetry rows into per-day aggregates.
 * @param {Array<{occurred_at:(string|Date|null), coherence:number, lr:number, zd:number, rupture:boolean}>} rows
 * @returns {Array<{date:string, coherenceMean:number, coherenceMax:number, zdMin:number, zdMean:number, lrMean:number, ruptures:number, turns:number}>}
 */
export function dailyAggregate(rows) {
  const byDay = new Map();
  for (const r of rows) {
    const d = r.occurred_at ? new Date(r.occurred_at).toISOString().slice(0, 10) : "undated";
    if (!byDay.has(d)) byDay.set(d, []);
    byDay.get(d).push(r);
  }
  const out = [];
  for (const [date, rs] of byDay) {
    const coh = rs.map((r) => r.coherence);
    const zd = rs.map((r) => r.zd);
    out.push({
      date,
      coherenceMean: r3(mean(coh)),
      coherenceMax: r3(Math.max(...coh)),
      zdMin: r3(Math.min(...zd)),
      zdMean: r3(mean(zd)),
      lrMean: r3(mean(rs.map((r) => r.lr))),
      ruptures: rs.filter((r) => r.rupture).length,
      turns: rs.length,
    });
  }
  out.sort((a, b) => (a.date < b.date ? -1 : 1));
  return out;
}

/**
 * Compact recent digest for companion grounding. Compares the latest `windowDays`
 * against the prior window for the coherence trend.
 * @param {Array} rows  cognitive_telemetry rows (newest-inclusive)
 * @param {{windowDays?:number}} [opts]
 * @returns {{summary:string, coherenceMean:(number|null), coherenceTrend:string, zdMin:(number|null), ruptures:number, days:number}}
 */
export function cognitiveTelemetryDigest(rows, opts = {}) {
  const w = opts.windowDays ?? 7;
  const days = dailyAggregate(rows);
  if (days.length === 0) {
    return { summary: "Sem telemetria cognitiva recente.", coherenceMean: null, coherenceTrend: "n/a", zdMin: null, ruptures: 0, days: 0 };
  }
  const recent = days.slice(-w);
  const prior = days.slice(-2 * w, -w);
  const rc = mean(recent.map((d) => d.coherenceMean).filter((x) => x != null));
  const pc = mean(prior.map((d) => d.coherenceMean).filter((x) => x != null));
  let trend = "estável";
  if (rc != null && pc != null) {
    if (rc > pc * 1.15) trend = "subindo";
    else if (rc < pc * 0.85) trend = "caindo";
  }
  const zdMin = Math.min(...recent.map((d) => d.zdMin).filter((x) => x != null));
  const ruptures = recent.reduce((a, d) => a + d.ruptures, 0);
  const turns = recent.reduce((a, d) => a + d.turns, 0);

  const parts = [`Telemetria cognitiva (${recent.length}d, ${turns} turnos):`];
  parts.push(`coerência ${trend} (média ${r3(rc) ?? "—"})`);
  if (Number.isFinite(zdMin)) {
    parts.push(zdMin < 0.2 ? `proximidade de dissociação ALTA (zd mín ${r3(zdMin)})` : `dissociação baixa (zd mín ${r3(zdMin)})`);
  }
  if (ruptures > 0) parts.push(`${ruptures} episódio(s) de ruptura`);
  return {
    summary: parts.join("; ") + ".",
    coherenceMean: r3(rc),
    coherenceTrend: trend,
    zdMin: Number.isFinite(zdMin) ? r3(zdMin) : null,
    ruptures,
    days: days.length,
  };
}

export default cognitiveTelemetryDigest;
