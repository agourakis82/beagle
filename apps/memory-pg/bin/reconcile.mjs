#!/usr/bin/env node
// bin/reconcile.mjs — Phase 3, Task 3.2: dual-write reconciliation.
//
// Proves no writes are lost between the canonical beagle-core store and the
// memory-pg pipeline. Takes the same export beagle-core produces (file or
// --fetch), derives the records that SHOULD exist in memory-pg via the exact
// same extraction the backfill + /capture use, recomputes each record's
// content_sha256 (the dedup key) and checks presence in memory-pg.
//
// Output: per-kind expected counts, present/missing totals, and a sample of
// missing canonical_ids. A clean run (missing=0 over a dual-write period) is the
// evidence that the dual-write hook is not dropping records.
//
// Env:
//   MEMORY_PG_DSN     postgres connection string (required)
//   BEAGLE_CORE_URL   beagle-core base URL (required for --fetch)
//   BEAGLE_CORE_TOKEN bearer token for the export endpoint (operator-token)
//
// Usage:
//   node bin/reconcile.mjs --export /path/to/export.json [--sample 20]
//   node bin/reconcile.mjs --fetch 200000 [--sample 20]

import { readFile } from "node:fs/promises";
import { makePool } from "../src/db.mjs";
import { extractCandidates } from "../src/backfill.mjs";
import { contentSha256 } from "../src/capture.mjs";

function arg(name, def = undefined) {
  const i = process.argv.indexOf(name);
  if (i === -1) return def;
  const v = process.argv[i + 1];
  return v && !v.startsWith("--") ? v : true;
}

async function fetchExport(limit) {
  const base = process.env.BEAGLE_CORE_URL;
  if (!base) throw new Error("--fetch requires BEAGLE_CORE_URL");
  const headers = { "content-type": "application/json" };
  if (process.env.BEAGLE_CORE_TOKEN) headers.authorization = `Bearer ${process.env.BEAGLE_CORE_TOKEN}`;
  const res = await fetch(`${base.replace(/\/$/, "")}/api/exocortex/v1/memory/export`, {
    method: "POST",
    headers,
    body: JSON.stringify({ limit: Number(limit), include_worlds: true, include_candidates: false, purpose: "memory-pg-reconcile" }),
  });
  if (!res.ok) throw new Error(`export fetch failed: ${res.status} ${await res.text()}`);
  return res.json();
}

async function main() {
  const dsn = process.env.MEMORY_PG_DSN;
  if (!dsn) throw new Error("MEMORY_PG_DSN is required");
  const pool = makePool(dsn);

  const exportFile = arg("--export");
  const fetchLimit = arg("--fetch");
  const sampleN = Number(arg("--sample", 20));

  const exp = exportFile ? JSON.parse(await readFile(exportFile, "utf8")) : await fetchExport(fetchLimit);
  const cands = extractCandidates(exp);

  // Per-kind expected counts.
  const byKind = {};
  for (const c of cands) byKind[c.kind] = (byKind[c.kind] || 0) + 1;

  // Presence check by content_sha256 (the dedup key). Query in chunks.
  const expected = cands.map((c) => ({ canonical_id: c.canonical_id, kind: c.kind, sha: contentSha256(c.content) }));
  const present = new Set();
  const CHUNK = 1000;
  for (let i = 0; i < expected.length; i += CHUNK) {
    const slice = expected.slice(i, i + CHUNK).map((e) => e.sha);
    const r = await pool.query("SELECT content_sha256 FROM records WHERE content_sha256 = ANY($1)", [slice]);
    for (const row of r.rows) present.add(row.content_sha256);
  }

  const missing = expected.filter((e) => !present.has(e.sha));
  const total = await pool.query("SELECT count(*)::int AS n FROM records");

  console.log("=== memory-pg dual-write reconciliation ===");
  console.log(`export candidates (expected in memory-pg): ${expected.length}`);
  console.log(`  by kind: ${JSON.stringify(byKind)}`);
  console.log(`memory-pg records total: ${total.rows[0].n}`);
  console.log(`present: ${expected.length - missing.length}  missing: ${missing.length}`);
  if (missing.length) {
    console.log(`sample missing (up to ${sampleN}):`);
    for (const m of missing.slice(0, sampleN)) console.log(`  - [${m.kind}] ${m.canonical_id}`);
  } else {
    console.log("OK — every exported record is present in memory-pg.");
  }

  await pool.end();
  process.exit(missing.length ? 1 : 0);
}

main().catch((err) => {
  console.error(`[reconcile] fatal: ${err.stack || err.message}`);
  process.exit(2);
});
