#!/usr/bin/env node
// bin/ab-eval.mjs — Phase 3, Task 3.3: A/B the read cutover on real queries.
//
// Runs a held-out set of REAL queries against BOTH retrieval paths:
//   legacy = memory-engine /v1/query (ColBERT multivector)
//   new    = memory-pg /query        (dense+BM25+RRF → cross-encoder rerank)
// and reports recall@k against a gold set, snippet agreement, latency, and a
// verdict (is the new path at least as good?). This is the evidence gate before
// flipping BEAGLE_RETRIEVAL_VIA_MEMORY_PG default-on.
//
// Queries file: JSON array of { "query": "...", "scope"?: "...", "gold"?: ["frag", ...] }.
// `gold` = fragments you know SHOULD be retrieved for that query (from the real
// answers you actually got). Queries without gold still contribute overlap+latency.
//
// Env:
//   BEAGLE_MEMORY_ENGINE_URL  legacy base (default the beagle-memory-lab svc)
//   MEMORY_PG_QUERY_URL       memory-pg serve base (default memory-pg-serve svc)
//   MEMORY_PG_QUERY_TOKEN     bearer for memory-pg /query (optional)
//
// Usage:
//   node bin/ab-eval.mjs --queries held_out.json --k 100 [--out report.json]

import { readFile, writeFile } from "node:fs/promises";
import { evaluateAb } from "../src/ab-eval.mjs";

function arg(name, def = undefined) {
  const i = process.argv.indexOf(name);
  if (i === -1) return def;
  const v = process.argv[i + 1];
  return v && !v.startsWith("--") ? v : true;
}

const LEGACY_BASE = (
  process.env.BEAGLE_MEMORY_ENGINE_URL ||
  "http://beagle-memory-engine.beagle-memory-lab.svc.cluster.local:8090"
).replace(/\/+$/, "");
const MEMPG_BASE = (
  process.env.MEMORY_PG_QUERY_URL || "http://memory-pg-serve.beagle.svc.cluster.local"
).replace(/\/+$/, "");
const QUERY_TOKEN = process.env.MEMORY_PG_QUERY_TOKEN || "";

async function legacyFn(query, scope, k) {
  const res = await fetch(`${LEGACY_BASE}/v1/query`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query, scope, max_items: k }),
  });
  if (!res.ok) throw new Error(`legacy ${res.status}`);
  const j = await res.json();
  return (j.semantic_results || []).map((r) => r.text_preview || r.text || "");
}

async function newFn(query, k) {
  const headers = { "content-type": "application/json" };
  if (QUERY_TOKEN) headers.authorization = `Bearer ${QUERY_TOKEN}`;
  const res = await fetch(`${MEMPG_BASE}/query`, {
    method: "POST",
    headers,
    body: JSON.stringify({ query, k }),
  });
  if (!res.ok) throw new Error(`memory-pg ${res.status}`);
  const j = await res.json();
  return (j.results || []).map((r) => r.text || "");
}

function pct(x) {
  return (x * 100).toFixed(1) + "%";
}

async function main() {
  const queriesFile = arg("--queries");
  if (!queriesFile) throw new Error("provide --queries <file.json>");
  const k = Number(arg("--k", 100));
  const queries = JSON.parse(await readFile(queriesFile, "utf8"));
  if (!Array.isArray(queries)) throw new Error("queries file must be a JSON array");

  console.log(`[ab-eval] ${queries.length} queries, k=${k}`);
  console.log(`[ab-eval] legacy=${LEGACY_BASE}/v1/query  new=${MEMPG_BASE}/query`);

  const { rows, summary } = await evaluateAb(queries, { legacyFn, newFn, k });

  console.log("\n=== per-query ===");
  for (const r of rows) {
    const rec = r.gold
      ? `recall legacy=${pct(r.legacyRecall)} new=${pct(r.newRecall)}`
      : "(no gold)";
    console.log(
      `  ${rec}  overlap=${pct(r.overlap)}  ms legacy=${r.legacyMs} new=${r.newMs}  ` +
        `n legacy=${r.legacyCount} new=${r.newCount}  | ${r.query.slice(0, 50)}`,
    );
  }

  console.log("\n=== summary ===");
  console.log(`queries=${summary.queries} measured(gold)=${summary.measured}`);
  console.log(`mean recall@${k}: legacy=${pct(summary.legacy.meanRecall)} new=${pct(summary.new.meanRecall)} (Δ=${pct(summary.verdict.recallDelta)})`);
  console.log(`per-query wins: new=${summary.wins.new} tie=${summary.wins.tie} legacy=${summary.wins.legacy}`);
  console.log(`mean snippet overlap: ${pct(summary.meanOverlap)}`);
  console.log(`mean latency ms: legacy=${summary.legacy.meanMs.toFixed(0)} new=${summary.new.meanMs.toFixed(0)}`);
  console.log(
    `VERDICT: new path is ${summary.verdict.newAtLeastAsGood ? "AT LEAST AS GOOD" : "WORSE"} on recall — ` +
      `${summary.verdict.newAtLeastAsGood ? "safe to default the cutover on" : "do NOT flip yet"}`,
  );

  const outFile = arg("--out");
  if (outFile) {
    await writeFile(outFile, JSON.stringify({ k, rows, summary }, null, 2));
    console.log(`\n[ab-eval] report written: ${outFile}`);
  }

  process.exit(summary.verdict.newAtLeastAsGood ? 0 : 1);
}

main().catch((err) => {
  console.error(`[ab-eval] fatal: ${err.stack || err.message}`);
  process.exit(2);
});
