#!/usr/bin/env node
// bin/graph-backfill.mjs — Phase 4, Task 4.5: tiered historical graph backfill.
//
// Extracts a knowledge graph from the existing corpus with qwen2.5-14b (the fast
// "bulk" tier) at high concurrency, leaving r1-distill-70b for the going-forward
// trickle (bin/graph-worker.mjs). Thin MemoryEpisode pointers (just an
// "omnimemory:<uuid>" source_ref, no extractable graph) are SKIPPED.
//
// Mechanism: enqueue the target records into pending_graph (idempotent), then run
// N concurrent runGraphOnce drain loops (SKIP-LOCKED → disjoint rows, safe
// parallelism). Resumable: re-running skips status='done' rows. Facts dedup on
// content_sha256, so even a re-extraction is idempotent.
//
// Env: MEMORY_PG_DSN, GRAPH_LLM_URL, BEAGLE_TEI_EMBED_URL.
// Usage:
//   node bin/graph-backfill.mjs --concurrency 12 --model qwen2.5-14b
//   node bin/graph-backfill.mjs --kinds MemoryAtom,ConversationPassage

import { makePool } from "../src/db.mjs";
import { makeTeiEmbedFn } from "../src/embed-worker.mjs";
import { makeRouterLlmFn } from "../src/graph-extract.mjs";
import { runGraphOnce } from "../src/graph-worker.mjs";

function arg(name, def) {
  const i = process.argv.indexOf(name);
  if (i === -1) return def;
  const v = process.argv[i + 1];
  return v && !v.startsWith("--") ? v : true;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const dsn = process.env.MEMORY_PG_DSN;
  if (!dsn) throw new Error("MEMORY_PG_DSN is required");
  const embedUrl = process.env.BEAGLE_TEI_EMBED_URL;
  if (!embedUrl) throw new Error("BEAGLE_TEI_EMBED_URL is required");
  const llmBase = process.env.GRAPH_LLM_URL || "http://router.llm-router.svc.cluster.local:4000";
  const model = arg("--model", "qwen2.5-14b");
  const concurrency = Number(arg("--concurrency", 12));
  const kinds = String(arg("--kinds", "MemoryAtom,ConversationPassage")).split(",");

  const pool = makePool(dsn);
  const llmFn = makeRouterLlmFn(llmBase, { model, timeoutMs: 120000 });
  const embedFn = makeTeiEmbedFn(embedUrl);

  // 1. Enqueue target records not already queued (idempotent). Skips thin episodes.
  const enq = await pool.query(
    `INSERT INTO pending_graph (record_id)
       SELECT r.id FROM records r
        WHERE r.source_type = ANY($1)
          AND length(r.content) >= 80
          AND NOT EXISTS (SELECT 1 FROM pending_graph p WHERE p.record_id = r.id)
          AND NOT EXISTS (SELECT 1 FROM failed_graph g WHERE g.record_id = r.id)`,
    [kinds],
  );
  console.log(`[graph-backfill] enqueued ${enq.rowCount} records (model=${model}, conc=${concurrency})`);

  const pending = async () =>
    (await pool.query("SELECT count(*)::int n FROM pending_graph WHERE status<>'done'")).rows[0].n;

  // 2. N concurrent SKIP-LOCKED drain loops.
  let running = true;
  const t0 = Date.now();
  const totals = { processed: 0, facts: 0, entities: 0, failed: 0 };
  const loop = async () => {
    while (running) {
      const res = await runGraphOnce(pool, { llmFn, embedFn, batch: 2, maxRetries: 2 });
      if (res.claimed === 0) return;
      totals.processed += res.processed;
      totals.facts += res.facts;
      totals.entities += res.entities;
      totals.failed += res.failed;
    }
  };
  const workers = Array.from({ length: concurrency }, () => loop());

  // 3. progress ticker
  const ticker = (async () => {
    let last = await pending();
    while (running && last > 0) {
      await sleep(20000);
      const now = await pending();
      const rate = ((last - now) / 20).toFixed(2);
      console.log(
        `[graph-backfill] pending=${now} processed=${totals.processed} facts=${totals.facts} (~${rate}/s)`,
      );
      last = now;
    }
  })();

  await Promise.all(workers);
  running = false;
  await ticker;
  console.log(
    `[graph-backfill] DONE in ${((Date.now() - t0) / 60000).toFixed(1)}min ${JSON.stringify(totals)}`,
  );
  await pool.end();
}

main().catch((err) => {
  console.error(`[graph-backfill] fatal: ${err.stack || err.message}`);
  process.exit(1);
});
