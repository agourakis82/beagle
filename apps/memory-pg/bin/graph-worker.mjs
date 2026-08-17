#!/usr/bin/env node
// bin/graph-worker.mjs — Phase 4, Task 4.3: the going-forward graph trickle worker.
//
// Drains pending_graph (rows enqueued by captureRecord when MEMORY_PG_GRAPH_ENABLED)
// via the sovereign LLM. Low volume (new memories), high quality → defaults to
// r1-distill-70b. The historical bulk is handled separately by bin/graph-backfill.mjs
// (qwen2.5-14b, parallel) — different driver, so the two tiers never contend.
//
// Env:
//   MEMORY_PG_DSN          postgres DSN (required)
//   GRAPH_LLM_URL          LiteLLM router base (default router.llm-router.svc:4000)
//   GRAPH_MODEL            sovereign model (default r1-distill-70b)
//   BEAGLE_TEI_EMBED_URL   Spark/TEI embed endpoint (required for fact embeddings)
//   GRAPH_BATCH            rows claimed per iteration (default 4)
//   GRAPH_MAX_RETRIES      retries before failed_graph DLQ (default 3)
//   GRAPH_IDLE_SLEEP_MS    sleep when the queue is empty (default 5000)
//   GRAPH_LLM_TIMEOUT_MS   per-call LLM timeout (default 240000 — 70B is slow)

import { makePool } from "../src/db.mjs";
import { makeTeiEmbedFn } from "../src/embed-worker.mjs";
import { makeRouterLlmFn } from "../src/graph-extract.mjs";
import { runGraphOnce } from "../src/graph-worker.mjs";

const intEnv = (n, d) => {
  const v = process.env[n];
  const x = v == null || v === "" ? d : Number(v);
  return Number.isFinite(x) ? x : d;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const dsn = process.env.MEMORY_PG_DSN;
  if (!dsn) throw new Error("MEMORY_PG_DSN is required");
  const embedUrl = process.env.BEAGLE_TEI_EMBED_URL;
  if (!embedUrl) throw new Error("BEAGLE_TEI_EMBED_URL is required");
  const llmBase = process.env.GRAPH_LLM_URL || "http://router.llm-router.svc.cluster.local:4000";
  const model = process.env.GRAPH_MODEL || "r1-distill-70b";

  const pool = makePool(dsn);
  const llmFn = makeRouterLlmFn(llmBase, { model, timeoutMs: intEnv("GRAPH_LLM_TIMEOUT_MS", 240000) });
  const embedFn = makeTeiEmbedFn(embedUrl);
  const batch = intEnv("GRAPH_BATCH", 4);
  const maxRetries = intEnv("GRAPH_MAX_RETRIES", 3);
  const idle = intEnv("GRAPH_IDLE_SLEEP_MS", 5000);

  let stopping = false;
  const stop = () => (stopping = true);
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  console.log(`[graph-worker] started model=${model} batch=${batch}`);

  while (!stopping) {
    let res;
    try {
      res = await runGraphOnce(pool, { llmFn, embedFn, batch, maxRetries, model });
    } catch (err) {
      console.error(`[graph-worker] runGraphOnce error: ${err.message}`);
      await sleep(idle);
      continue;
    }
    if (res.claimed > 0) {
      console.log(
        `[graph-worker] claimed=${res.claimed} processed=${res.processed} entities=${res.entities} facts=${res.facts} failed=${res.failed}`,
      );
    } else {
      await sleep(idle);
    }
  }
  console.log("[graph-worker] draining, closing pool");
  await pool.end();
}

main().catch((err) => {
  console.error(`[graph-worker] fatal: ${err.stack || err.message}`);
  process.exit(1);
});
