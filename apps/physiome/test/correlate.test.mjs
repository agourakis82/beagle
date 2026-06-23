import { test } from "node:test";
import assert from "node:assert/strict";
import {
  pearson,
  spearman,
  studentTwoTailedP,
  alignPair,
  correlatePhysiome,
  summarizeCorrelations,
} from "../src/correlate.mjs";

test("pearson: perfect positive / negative / none", () => {
  assert.equal(pearson([1, 2, 3, 4], [2, 4, 6, 8]), 1);
  assert.equal(pearson([1, 2, 3, 4], [8, 6, 4, 2]), -1);
  // constant series → undefined correlation → null (no variance)
  assert.equal(pearson([1, 1, 1], [1, 2, 3]), null);
});

test("spearman: monotonic-but-nonlinear is 1, robust to scale", () => {
  // y = x^3 is monotonic → Spearman rho = 1 even though Pearson < 1
  const xs = [1, 2, 3, 4, 5];
  const ys = xs.map((x) => x ** 3);
  assert.equal(spearman(xs, ys), 1);
  assert.ok(pearson(xs, ys) < 1);
});

test("spearman handles tied ranks (average rank)", () => {
  const rho = spearman([1, 2, 2, 3], [1, 2, 2, 3]);
  assert.equal(rho, 1);
});

test("studentTwoTailedP: strong correlation → small p; df monotonic", () => {
  // t large → p small
  const pBig = studentTwoTailedP(8, 10);
  const pSmall = studentTwoTailedP(0.1, 10);
  assert.ok(pBig < 0.01, `expected tiny p, got ${pBig}`);
  assert.ok(pSmall > 0.5, `expected large p, got ${pSmall}`);
  // p is in [0,1]
  assert.ok(pBig >= 0 && pBig <= 1);
});

test("alignPair: aligns by date, applies lag (driver leads), drops nulls", () => {
  const series = [
    { date: "2026-06-01", kpMax: 1, hrvMs: 50 },
    { date: "2026-06-02", kpMax: 5, hrvMs: 40 },
    { date: "2026-06-03", kpMax: 2, hrvMs: 55 },
    { date: "2026-06-04", kpMax: null, hrvMs: 60 },
  ];
  // lag 0: pairs (kp,hrv) on same day, dropping the null kp day
  const a0 = alignPair(series, "kpMax", "hrvMs", 0);
  assert.deepEqual(a0.xs, [1, 5, 2]);
  assert.deepEqual(a0.ys, [50, 40, 55]);
  // lag 1: driver day d → outcome day d+1. kp on 06-01/02/03 → hrv on 06-02/03/04.
  const a1 = alignPair(series, "kpMax", "hrvMs", 1);
  assert.deepEqual(a1.xs, [1, 5, 2]);
  assert.deepEqual(a1.ys, [40, 55, 60]);
});

test("correlatePhysiome: surfaces a driver→outcome relationship with the right lag", () => {
  // Build aggregates where kpMax on day d strongly DROPS hrv on day d+1 (lag 1).
  const days = ["01", "02", "03", "04", "05", "06", "07", "08"];
  const kp = [1, 5, 2, 6, 1, 4, 3, 5];
  const aggs = days.map((d, i) => ({
    date: `2026-06-${d}`,
    health: { hrvMs: i === 0 ? 60 : 70 - kp[i - 1] * 5, restingHr: null, sleepHours: null, steps: null },
    weather: { pressureTrendHpa: null, uvMax: null, aqi: null, tempMaxC: null },
    space: { kpMax: kp[i], solarWindSpeed: null, f107: null },
  }));
  const res = correlatePhysiome(aggs, { lags: [0, 1, 2], minN: 5 });
  const top = res.correlations.find((c) => c.driver === "kpMax" && c.outcome === "hrvMs");
  assert.ok(top, "expected a kpMax→hrvMs correlation");
  assert.equal(top.lag, 1, `expected best lag 1, got ${top.lag}`);
  assert.ok(top.rho < -0.8, `expected strong negative rho, got ${top.rho}`);
  assert.ok(top.n >= 5);
});

test("correlatePhysiome: drops pairs below minN, never throws on sparse data", () => {
  const aggs = [
    { date: "2026-06-01", health: { hrvMs: 50 }, weather: {}, space: { kpMax: 1 } },
    { date: "2026-06-02", health: { hrvMs: 40 }, weather: {}, space: { kpMax: 5 } },
  ];
  const res = correlatePhysiome(aggs, { minN: 5 });
  assert.equal(res.correlations.length, 0);
  assert.ok(Array.isArray(res.skipped));
});

test("summarizeCorrelations: deterministic pt-BR, mentions the top pair", () => {
  const res = {
    correlations: [
      { driver: "kpMax", outcome: "hrvMs", lag: 1, rho: -0.86, n: 7, p: 0.012, notable: true },
    ],
    skipped: [],
  };
  const s = summarizeCorrelations(res);
  assert.match(s, /Kp/);
  assert.match(s, /HRV/);
  assert.match(s, /-0\.86|0,86|86/);
});
