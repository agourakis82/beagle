// ab-eval.test.mjs — Phase 3, Task 3.3: A/B harness for the read cutover.
//
// The legacy memory-engine (ColBERT) path and the new memory-pg (dense+BM25+RRF
// → rerank) path share no record IDs, so the honest comparison is recall@k
// against a GOLD set of known-relevant fragments from real queries, plus snippet
// agreement and latency. All metrics are pure and unit-tested here; evaluateAb
// is exercised with stub retrievers (no cluster).

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  normalizeText,
  recallAtK,
  overlapAtK,
  summarize,
  evaluateAb,
} from "../src/ab-eval.mjs";

test("normalizeText lowercases and collapses whitespace", () => {
  assert.equal(normalizeText("  The   QUICK\tBrown\nFox "), "the quick brown fox");
});

test("recallAtK: fraction of gold fragments present in top-k snippets", () => {
  const snippets = [
    "Paris is the capital of France and a major city",
    "bananas are yellow when ripe",
    "the Eiffel tower is in Paris",
  ];
  // both gold fragments appear within top-3
  assert.equal(recallAtK(["capital of france", "eiffel tower"], snippets, 3), 1);
  // one of two present -> 0.5
  assert.equal(recallAtK(["capital of france", "great wall of china"], snippets, 3), 0.5);
  // the eiffel fragment is only in result #3; with k=2 it's out of window
  assert.equal(recallAtK(["eiffel tower"], snippets, 2), 0);
  // empty gold -> not measurable
  assert.equal(recallAtK([], snippets, 3), null);
});

test("overlapAtK: Jaccard of normalized top-k snippet sets", () => {
  const a = ["alpha beta", "gamma delta", "epsilon"];
  const b = ["ALPHA  beta", "zeta eta", "epsilon"];
  // top-3 each: {alpha beta, gamma delta, epsilon} vs {alpha beta, zeta eta, epsilon}
  // intersection = {alpha beta, epsilon} = 2; union = 4 -> 0.5
  assert.equal(overlapAtK(a, b, 3), 0.5);
  assert.equal(overlapAtK(a, a, 3), 1);
  assert.equal(overlapAtK(["x y"], ["p q"], 1), 0);
});

test("summarize aggregates recall, overlap, wins and a verdict", () => {
  const rows = [
    { gold: true, legacyRecall: 0.5, newRecall: 1.0, overlap: 0.4, legacyMs: 120, newMs: 80 },
    { gold: true, legacyRecall: 1.0, newRecall: 1.0, overlap: 0.6, legacyMs: 100, newMs: 90 },
    { gold: false, legacyRecall: null, newRecall: null, overlap: 0.2, legacyMs: 110, newMs: 70 },
  ];
  const s = summarize(rows);
  assert.equal(s.measured, 2, "only gold-bearing rows count for recall");
  assert.equal(s.legacy.meanRecall, 0.75);
  assert.equal(s.new.meanRecall, 1.0);
  assert.equal(s.wins.new, 1);
  assert.equal(s.wins.tie, 1);
  assert.equal(s.wins.legacy, 0);
  assert.ok(Math.abs(s.meanOverlap - 0.4) < 1e-9, "(0.4+0.6+0.2)/3 ≈ 0.4");
  assert.equal(s.new.meanMs, 80);
  assert.equal(s.verdict.newAtLeastAsGood, true, "new recall >= legacy recall");
});

test("evaluateAb runs both retrievers per query and scores them", async () => {
  const queries = [
    { query: "capital of france", gold: ["paris is the capital"] },
    { query: "tallest tower", gold: ["eiffel tower"] },
  ];
  // legacy misses q2; new gets both -> new should win overall.
  const legacyFn = async (q) =>
    q.includes("capital") ? ["Paris is the capital of France here"] : ["unrelated text about cats"];
  const newFn = async (q) =>
    q.includes("capital")
      ? ["Paris is the capital of France here"]
      : ["the Eiffel tower is the tallest in the city"];

  const { rows, summary } = await evaluateAb(queries, { legacyFn, newFn, k: 5 });
  assert.equal(rows.length, 2);
  assert.equal(rows[0].legacyRecall, 1);
  assert.equal(rows[1].legacyRecall, 0, "legacy misses q2 gold");
  assert.equal(rows[1].newRecall, 1, "new finds q2 gold");
  assert.equal(summary.new.meanRecall, 1);
  assert.equal(summary.legacy.meanRecall, 0.5);
  assert.equal(summary.verdict.newAtLeastAsGood, true);
});

test("evaluateAb is fail-soft: a retriever throwing yields empty results, not a crash", async () => {
  const queries = [{ query: "x", gold: ["something"] }];
  const legacyFn = async () => {
    throw new Error("legacy down");
  };
  const newFn = async () => ["something relevant and long enough to match the gold"];
  const { rows } = await evaluateAb(queries, { legacyFn, newFn, k: 5 });
  assert.equal(rows[0].legacyRecall, 0, "legacy error -> 0 recall, not a throw");
  assert.equal(rows[0].newRecall, 1);
});
