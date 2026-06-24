// correlate-cog.mjs — Phase C: cluster-robust cognitive × physiome correlation.
//
// The post-construction novelty verdict (2026-06-24 deep-research) makes this
// MANDATORY: cognitive telemetry is strongly autocorrelated (ρ up to 0.928), so a
// naive per-day Pearson/Spearman p-value is presumptively spurious. We use a
// MOVING-BLOCK BOOTSTRAP — resample contiguous day-blocks (block length ≈ √n) so
// the resampled series preserves the temporal dependence — and report a 95% CI on
// ρ. "Robustly significant" = the CI excludes 0. Daily aggregation already absorbs
// the within-session autocorrelation; the block bootstrap handles day-to-day.

import { spearman, pearson } from "../../physiome/src/correlate.mjs";

const COG_KEYS = ["coherenceMean", "coherenceMax", "zdMin", "zdMean", "lrMean", "ruptures"];
const PHYS_KEYS = ["hrvMs", "sleepHours", "restingHr", "kpMax", "mood"];

function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Join the cognitive daily aggregates with a flat physiome series by date. */
export function joinByDate(cogDaily, physFlat) {
  const phys = new Map(physFlat.map((p) => [p.date, p]));
  const merged = [];
  for (const c of cogDaily) {
    const p = phys.get(c.date);
    if (p) merged.push({ ...p, ...c });
  }
  merged.sort((a, b) => (a.date < b.date ? -1 : 1));
  return merged;
}

/**
 * Moving-block bootstrap CI for Spearman ρ (cluster-robust to autocorrelation).
 * @returns {{rho:number, lo:number, hi:number, n:number, blockLen:number}|null}
 */
export function blockBootstrapCI(xs, ys, opts = {}) {
  const n = xs.length;
  if (n < 4) return null;
  const rho = spearman(xs, ys);
  if (rho == null) return null;
  const L = opts.blockLen || Math.max(2, Math.round(Math.sqrt(n)));
  const iters = opts.iters ?? 2000;
  const rng = mulberry32(opts.seed ?? 0x5eed1234);
  const rhos = [];
  for (let it = 0; it < iters; it++) {
    const rx = [], ry = [];
    while (rx.length < n) {
      const start = Math.floor(rng() * (n - L + 1));
      for (let j = 0; j < L && rx.length < n; j++) {
        rx.push(xs[start + j]);
        ry.push(ys[start + j]);
      }
    }
    const r = spearman(rx, ry);
    if (r != null) rhos.push(r);
  }
  if (rhos.length < 20) return { rho, lo: null, hi: null, n, blockLen: L };
  rhos.sort((a, b) => a - b);
  const q = (p) => rhos[Math.min(rhos.length - 1, Math.floor(p * rhos.length))];
  return { rho: round(rho, 3), lo: round(q(0.025), 3), hi: round(q(0.975), 3), n, blockLen: L };
}

/**
 * Correlate every cognitive key against every physiome key with a cluster-robust CI.
 * @param {Array} cogDaily   from dailyAggregate()
 * @param {Array} physFlat   from physiome flattenAggregates()
 * @param {{minN?:number, iters?:number}} [opts]
 */
export function correlateCognitivePhysiome(cogDaily, physFlat, opts = {}) {
  const minN = opts.minN ?? 8; // need enough days for a block bootstrap to mean anything
  const merged = joinByDate(cogDaily, physFlat);
  const correlations = [];
  for (const ck of COG_KEYS) {
    for (const pk of PHYS_KEYS) {
      const pairs = merged
        .map((m) => [m[ck], m[pk]])
        .filter(([a, b]) => Number.isFinite(a) && Number.isFinite(b));
      if (pairs.length < minN) continue;
      const xs = pairs.map((p) => p[0]);
      const ys = pairs.map((p) => p[1]);
      const ci = blockBootstrapCI(xs, ys, { iters: opts.iters });
      if (!ci) continue;
      const robustSignificant = ci.lo != null && ci.hi != null && (ci.lo > 0 || ci.hi < 0);
      correlations.push({
        cognitive: ck, physiome: pk, n: ci.n,
        rho: ci.rho, ciLo: ci.lo, ciHi: ci.hi,
        robustSignificant,
        r: round(pearson(xs, ys), 3),
      });
    }
  }
  correlations.sort((a, b) => Math.abs(b.rho ?? 0) - Math.abs(a.rho ?? 0));
  return { correlations, days: merged.length, minN, note: "cluster-robust (moving-block bootstrap); CI excludes 0 = robustly significant" };
}

function round(v, d) {
  if (v == null || !Number.isFinite(v)) return null;
  const f = 10 ** d;
  return Math.round(v * f) / f;
}

export default correlateCognitivePhysiome;
