import { test } from "node:test";
import assert from "node:assert/strict";
import { dailyAggregate, cognitiveTelemetryDigest } from "../src/aggregate.mjs";
import { blockBootstrapCI, joinByDate, correlateCognitivePhysiome } from "../src/correlate-cog.mjs";

function row(date, coherence, lr, zd, rupture) {
  return { occurred_at: date + "T12:00:00Z", coherence, lr, fano: 2, zd, rupture };
}

test("dailyAggregate rolls turns up to per-day summaries", () => {
  const d = dailyAggregate([
    row("2026-06-01", 0.2, 1.0, 0.9, false),
    row("2026-06-01", 0.8, 1.2, 0.1, true),
    row("2026-06-02", 0.4, 0.5, 0.5, false),
  ]);
  assert.equal(d.length, 2);
  assert.equal(d[0].date, "2026-06-01");
  assert.equal(d[0].turns, 2);
  assert.equal(d[0].ruptures, 1);
  assert.equal(d[0].zdMin, 0.1);
  assert.equal(d[0].coherenceMax, 0.8);
});

test("digest reports coherence trend + dissociation + ruptures", () => {
  const rows = [];
  for (let i = 0; i < 7; i++) rows.push(row(`2026-05-${10 + i}`, 0.2, 1.0, 0.9, false)); // prior week low
  for (let i = 0; i < 7; i++) rows.push(row(`2026-05-${20 + i}`, 0.8, 1.0, 0.15, i === 0)); // recent high coh + a rupture
  const dg = cognitiveTelemetryDigest(rows, { windowDays: 7 });
  assert.equal(dg.coherenceTrend, "subindo");
  assert.equal(dg.ruptures, 1);
  assert.match(dg.summary, /coerência subindo/);
});

test("blockBootstrapCI: correlated series -> CI excludes 0; noise -> CI spans 0", () => {
  const n = 40;
  const xs = Array.from({ length: n }, (_, i) => Math.sin(i * 0.3));
  const ysCorr = xs.map((x, i) => x + 0.05 * Math.sin(i)); // strongly monotone-related
  const ci = blockBootstrapCI(xs, ysCorr, { iters: 1000 });
  assert.ok(ci.lo > 0, `correlated CI [${ci.lo},${ci.hi}] should exclude 0`);

  const ysNoise = Array.from({ length: n }, (_, i) => ((i * 2654435761) % 1000) / 1000);
  const ciN = blockBootstrapCI(xs, ysNoise, { iters: 1000 });
  assert.ok(ciN.lo <= 0 && ciN.hi >= 0, `noise CI [${ciN.lo},${ciN.hi}] should span 0`);
});

test("correlateCognitivePhysiome joins by date + flags robust significance", () => {
  // 12 days: HRV tracks coherence (positive), zdMin anti-tracks (negative).
  const cog = [], phys = [];
  for (let i = 0; i < 12; i++) {
    const date = `2026-06-${(i + 1).toString().padStart(2, "0")}`;
    const c = 0.2 + 0.05 * i;
    cog.push({ date, coherenceMean: c, coherenceMax: c + 0.1, zdMin: 1 - 0.05 * i, zdMean: 0.5, lrMean: 1.0, ruptures: 0, turns: 5 });
    phys.push({ date, hrvMs: 40 + 3 * i, sleepHours: 7, restingHr: 60, kpMax: 2, mood: null });
  }
  const { correlations, days } = correlateCognitivePhysiome(cog, phys, { iters: 800, minN: 8 });
  assert.equal(days, 12);
  const hit = correlations.find((c) => c.cognitive === "coherenceMean" && c.physiome === "hrvMs");
  assert.ok(hit, "coherence×HRV pair present");
  assert.ok(hit.rho > 0.8 && hit.robustSignificant, "monotone coherence↑HRV↑ is robustly significant");
});
