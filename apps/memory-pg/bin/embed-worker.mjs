#!/usr/bin/env node
// bin/embed-worker.mjs — Phase 1, Task 1.3: the long-running embed worker loop.
//
// Drives src/embed-worker.mjs `runOnce` in a loop against the live memory-pg
// instance, embedding chunks via the cluster TEI service (bge-m3). Sleeps when
// the queue is empty; throttles TEI calls with a simple token-bucket so a
// backfill burst can't saturate the embedding service. The reaper is inherent:
// `runOnce`'s claim query re-picks rows whose locked_until < now(), so a crashed
// worker's in-flight rows are reclaimed automatically after the lease expires.
//
// Env:
//   MEMORY_PG_DSN          postgres connection string (required)
//   BEAGLE_TEI_EMBED_URL   full POST URL of the TEI bge-m3 embed endpoint (required)
//   EMBED_BATCH            queue rows claimed per iteration (default 50)
//   EMBED_MODEL_VERSION    model_version tag stored on embeddings (default bge-m3)
//   EMBED_MAX_RETRIES      retries before a row is sent to the DLQ (default 3)
//   EMBED_IDLE_SLEEP_MS    sleep when the queue is empty (default 2000)
//   EMBED_TEI_RATE         max TEI requests/sec (token-bucket; default 8)
//   EMBED_TEI_TIMEOUT_MS   per-request TEI timeout (default 30000)
//   EMBED_TEI_BATCH        max texts per TEI request (default 32)

import { makePool } from "../src/db.mjs";
import { runOnce, makeTeiEmbedFn } from "../src/embed-worker.mjs";

function intEnv(name, def) {
  const v = process.env[name];
  if (v === undefined || v === "") return def;
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Minimal token-bucket rate limiter: `acquire()` resolves once a token is free.
 */
function makeTokenBucket(ratePerSec, capacity = ratePerSec) {
  let tokens = capacity;
  let last = Date.now();
  return async function acquire() {
    for (;;) {
      const now = Date.now();
      tokens = Math.min(capacity, tokens + ((now - last) / 1000) * ratePerSec);
      last = now;
      if (tokens >= 1) {
        tokens -= 1;
        return;
      }
      await sleep(Math.ceil((1 - tokens) / ratePerSec * 1000));
    }
  };
}

/**
 * Build the worker's TEI embedFn from BEAGLE_TEI_EMBED_URL, wrapping the shared
 * `makeTeiEmbedFn` (src/embed-worker.mjs) with a token-bucket throttle so a
 * backfill burst can't saturate the embedding service.
 *
 * @returns {(texts: string[]) => Promise<number[][]>}
 */
function makeWorkerEmbedFn() {
  const url = process.env.BEAGLE_TEI_EMBED_URL;
  if (!url) throw new Error("BEAGLE_TEI_EMBED_URL is required");
  return makeTeiEmbedFn(url, {
    timeoutMs: intEnv("EMBED_TEI_TIMEOUT_MS", 30000),
    teiBatch: intEnv("EMBED_TEI_BATCH", 32),
    acquire: makeTokenBucket(intEnv("EMBED_TEI_RATE", 8)),
  });
}

async function main() {
  const dsn = process.env.MEMORY_PG_DSN;
  if (!dsn) throw new Error("MEMORY_PG_DSN is required");

  const pool = makePool(dsn);
  const embedFn = makeWorkerEmbedFn();
  const batch = intEnv("EMBED_BATCH", 50);
  const modelVersion = process.env.EMBED_MODEL_VERSION || "bge-m3";
  const maxRetries = intEnv("EMBED_MAX_RETRIES", 3);
  const idleSleep = intEnv("EMBED_IDLE_SLEEP_MS", 2000);

  let stopping = false;
  const stop = () => {
    stopping = true;
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);

  console.log(
    `[embed-worker] started batch=${batch} model=${modelVersion} maxRetries=${maxRetries}`,
  );

  while (!stopping) {
    let res;
    try {
      res = await runOnce(pool, { embedFn, batch, modelVersion, maxRetries });
    } catch (err) {
      console.error(`[embed-worker] runOnce error: ${err.message}`);
      await sleep(idleSleep);
      continue;
    }
    if (res.claimed > 0) {
      console.log(
        `[embed-worker] claimed=${res.claimed} embedded=${res.embedded} failed=${res.failed}`,
      );
    }
    if (res.claimed === 0) {
      await sleep(idleSleep);
    }
  }

  console.log("[embed-worker] draining, closing pool");
  await pool.end();
}

main().catch((err) => {
  console.error(`[embed-worker] fatal: ${err.stack || err.message}`);
  process.exit(1);
});
