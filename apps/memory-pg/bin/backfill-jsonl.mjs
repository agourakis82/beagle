#!/usr/bin/env node
// bin/backfill-jsonl.mjs — Phase 3 full backfill by streaming canonical JSONL files.
//
// Streams the three canonical exocortex logs (episodes, atoms, conversation
// passages) straight into memory-pg via captureRecord. Constant memory,
// idempotent (re-runnable), zero load on beagle-core. Embeddings are NOT done
// here — captureRecord enqueues the outbox and the live embed-worker drains it.
//
// HNSW: NOT dropped by default. In a throttled live drain the per-insert index
// maintenance is spread thin, and the index is shared with a live system — so we
// keep it. Pass --drop-index to drop before load + rebuild after (only sensible
// in a dedicated window with cutover off and no concurrent queries).
//
// Env:
//   MEMORY_PG_DSN   postgres connection string (required)
//
// Usage:
//   node bin/backfill-jsonl.mjs --dir /path/to/exocortex
//   node bin/backfill-jsonl.mjs --episodes a.jsonl --atoms b.jsonl --passages c.jsonl
//   node bin/backfill-jsonl.mjs --dir ./exo --concurrency 12

import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { join } from "node:path";
import { makePool } from "../src/db.mjs";
import { captureRecord } from "../src/capture.mjs";
import { backfillJsonlStream } from "../src/backfill-jsonl.mjs";
import { dropEmbeddingIndex, rebuildEmbeddingIndex } from "../src/backfill.mjs";

function arg(name, def = undefined) {
  const i = process.argv.indexOf(name);
  if (i === -1) return def;
  const v = process.argv[i + 1];
  return v && !v.startsWith("--") ? v : true;
}

const FILES = [
  ["memory_episodes.jsonl", "MemoryEpisode", "--episodes"],
  ["memory_atoms.jsonl", "MemoryAtom", "--atoms"],
  ["conversation_passages.jsonl", "ConversationPassage", "--passages"],
];

async function exists(p) {
  try {
    await stat(p);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const dsn = process.env.MEMORY_PG_DSN;
  if (!dsn) throw new Error("MEMORY_PG_DSN is required");
  const dir = arg("--dir");
  const concurrency = Number(arg("--concurrency", 8));
  const pool = makePool(dsn);
  const capture = (rec) => captureRecord(pool, rec);

  if (arg("--drop-index")) {
    console.log("[backfill-jsonl] dropping HNSW index");
    await dropEmbeddingIndex(pool);
  }

  const total = { lines: 0, badLines: 0, candidates: 0, created: 0, duplicate: 0, errors: 0 };
  const t0 = Date.now();
  for (const [fname, kind, flag] of FILES) {
    const path = arg(flag) || (dir ? join(dir, fname) : null);
    if (!path || !(await exists(path))) {
      console.log(`[backfill-jsonl] SKIP ${kind}: no file (${path || flag})`);
      continue;
    }
    console.log(`[backfill-jsonl] streaming ${kind} from ${path}`);
    const st = await backfillJsonlStream(createReadStream(path, "utf8"), kind, {
      capture,
      concurrency,
      onProgress: (s) =>
        console.log(
          `[backfill-jsonl]   ${kind} progress created=${s.created} dup=${s.duplicate} bad=${s.badLines} err=${s.errors}`,
        ),
    });
    console.log(`[backfill-jsonl] ${kind} done: ${JSON.stringify(st)}`);
    for (const k of Object.keys(total)) total[k] += st[k];
  }

  console.log(
    `[backfill-jsonl] ALL done in ${((Date.now() - t0) / 1000).toFixed(1)}s ${JSON.stringify(total)}`,
  );

  if (arg("--rebuild-index")) {
    console.log("[backfill-jsonl] rebuilding HNSW index");
    await rebuildEmbeddingIndex(pool);
  }

  const pend = await pool.query(
    "SELECT count(*)::int n FROM pending_embeddings WHERE status <> 'done'",
  );
  console.log(`[backfill-jsonl] pending_embeddings to drain (via embed-worker): ${pend.rows[0].n}`);
  await pool.end();
}

main().catch((err) => {
  console.error(`[backfill-jsonl] fatal: ${err.stack || err.message}`);
  process.exit(1);
});
