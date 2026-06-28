#!/usr/bin/env node
// bin/backfill.mjs — Phase 3, Task 3.1: run the migration backfill for real.
//
// Orchestrates the build-after-bulk-load sequence:
//   [--drop-index]  drop HNSW so the embed-worker's inserts don't pay index
//                   maintenance during a large import
//   load            from a local --export file, or --fetch <limit> straight
//                   from beagle-core's /api/exocortex/v1/memory/export
//   backfill        captureRecord every candidate (idempotent; restricted excluded)
//   [--wait-drain]  poll pending_embeddings until the worker has embedded the
//                   backlog, then --rebuild-index recreates HNSW
//
// The canonical JSONL/beagle-core store is only READ (export is read-only);
// nothing in the old stack is mutated. Re-running is safe (idempotent).
//
// Env:
//   MEMORY_PG_DSN     postgres connection string (required)
//   BEAGLE_CORE_URL   beagle-core base URL (required for --fetch)
//   BEAGLE_CORE_TOKEN bearer token for the export endpoint (optional)
//
// Usage:
//   node bin/backfill.mjs --export /path/to/export.json --drop-index --wait-drain --rebuild-index
//   node bin/backfill.mjs --fetch 200            # bounded real smoke from live core
//   node bin/backfill.mjs --fetch 200000 --drop-index --wait-drain --rebuild-index

import { writeFile, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { makePool } from "../src/db.mjs";
import { backfill, dropEmbeddingIndex, rebuildEmbeddingIndex } from "../src/backfill.mjs";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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
    body: JSON.stringify({
      limit: Number(limit),
      include_worlds: true,
      include_candidates: false,
      purpose: "memory-pg-backfill",
    }),
  });
  if (!res.ok) throw new Error(`export fetch failed: ${res.status} ${await res.text()}`);
  const doc = await res.json();
  const file = join(tmpdir(), `memory-pg-export-${limit}.json`);
  await writeFile(file, JSON.stringify(doc));
  return { file, counts: {
    episodes: (doc.episodes || []).length,
    atoms: (doc.atoms || []).length,
    worlds: (doc.worlds || []).length,
    passages: (doc.passages || []).length,
  } };
}

async function pendingCount(pool) {
  const r = await pool.query(
    "SELECT count(*)::int AS n FROM pending_embeddings WHERE status <> 'done'",
  );
  return r.rows[0].n;
}

async function main() {
  const dsn = process.env.MEMORY_PG_DSN;
  if (!dsn) throw new Error("MEMORY_PG_DSN is required");
  const pool = makePool(dsn);

  let exportFile = arg("--export");
  let cleanup = null;
  const fetchLimit = arg("--fetch");
  if (!exportFile && fetchLimit) {
    console.log(`[backfill] fetching export from beagle-core (limit=${fetchLimit})`);
    const { file, counts } = await fetchExport(fetchLimit);
    console.log(`[backfill] export saved: ${file} counts=${JSON.stringify(counts)}`);
    exportFile = file;
    cleanup = file;
  }
  if (!exportFile) throw new Error("provide --export <file> or --fetch <limit>");

  if (arg("--drop-index")) {
    console.log("[backfill] dropping HNSW index (build-after-bulk-load)");
    await dropEmbeddingIndex(pool);
  }

  console.log(`[backfill] importing ${exportFile}`);
  const t0 = Date.now();
  const stats = await backfill(pool, exportFile, {
    onProgress: (s) =>
      console.log(`[backfill] progress created=${s.created} dup=${s.duplicate}/${s.seen}`),
  });
  console.log(
    `[backfill] done in ${((Date.now() - t0) / 1000).toFixed(1)}s ${JSON.stringify(stats)}`,
  );

  if (arg("--wait-drain")) {
    console.log("[backfill] waiting for embed-worker to drain the queue…");
    let n = await pendingCount(pool);
    while (n > 0) {
      console.log(`[backfill] pending=${n}`);
      await sleep(5000);
      n = await pendingCount(pool);
    }
    console.log("[backfill] queue drained");
  }

  if (arg("--rebuild-index")) {
    console.log("[backfill] rebuilding HNSW index");
    const t1 = Date.now();
    await rebuildEmbeddingIndex(pool);
    console.log(`[backfill] index rebuilt in ${((Date.now() - t1) / 1000).toFixed(1)}s`);
  }

  if (cleanup) await unlink(cleanup).catch(() => {});
  await pool.end();
}

main().catch((err) => {
  console.error(`[backfill] fatal: ${err.stack || err.message}`);
  process.exit(1);
});
