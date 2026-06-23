// embed-worker.test.mjs — Phase 1, Task 1.3.
//
// Tests the SKIP-LOCKED embed worker against the LIVE memory-pg Postgres
// (dedicated instance, safe to TRUNCATE). Set MEMORY_PG_TEST_DSN to run.
//
//   DSN: postgresql://memory:<PW>@127.0.0.1:15432/memory  (via port-forward)
//
// The TEI embedder is STUBBED here (no real TEI in tests). The stub returns a
// unit vector (1,0,0,...,0) so l2_norm(embedding) > 0 passes the CHECK.

import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { captureRecord } from "../src/capture.mjs";
import { runOnce } from "../src/embed-worker.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;

// One pool shared across the suite (each test TRUNCATEs first).
const pool = makePool(DSN);

// Stub embedder: one 1024-dim unit vector per input text (passes l2_norm>0).
const unitVec = () => {
  const v = new Array(1024).fill(0);
  v[0] = 1;
  return v;
};
const okEmbedFn = (texts) => texts.map(() => unitVec());

beforeEach(async () => {
  await ensureSchema(pool);
  await pool.query(
    "TRUNCATE failed_embeddings, pending_embeddings, embeddings, chunks, records RESTART IDENTITY CASCADE",
  );
});

async function count(table) {
  const r = await pool.query(`SELECT count(*)::int AS n FROM ${table}`);
  return r.rows[0].n;
}

async function enqueueRecord(content, source = "test") {
  return captureRecord(pool, { source_type: source, content });
}

test("runOnce embeds a captured record and drains the queue", async () => {
  const { id, chunk_count } = await enqueueRecord(
    "The quick brown fox jumps over the lazy dog.\n\nA second paragraph for good measure with enough text.",
  );
  assert.ok(chunk_count >= 1);

  const res = await runOnce(pool, { embedFn: okEmbedFn });

  assert.equal(res.claimed, 1, "claimed one queue row");
  assert.ok(res.embedded > 0, "embedded > 0");
  assert.equal(res.failed, 0, "no failures");

  const embCount = await count("embeddings");
  const chCount = await count("chunks");
  assert.equal(embCount, chCount, "one embedding per chunk");
  assert.equal(await count("pending_embeddings"), 0, "queue drained");

  // Embeddings are tied to this record's chunks.
  const owned = await pool.query(
    `SELECT count(*)::int AS n FROM embeddings e
       JOIN chunks c ON c.id = e.chunk_id WHERE c.record_id = $1`,
    [id],
  );
  assert.equal(owned.rows[0].n, chCount);
});

test("idempotent: re-enqueue + runOnce again produces no duplicate embeddings", async () => {
  const { id } = await enqueueRecord(
    "Idempotency check.\n\nSecond chunk text here that is long enough to matter for sure.",
  );
  await runOnce(pool, { embedFn: okEmbedFn });
  const first = await count("embeddings");
  assert.ok(first > 0);

  // Re-enqueue the SAME record (capture is idempotent on content, so insert a
  // fresh queue row directly to simulate a re-process request).
  await pool.query("INSERT INTO pending_embeddings (record_id) VALUES ($1)", [
    id,
  ]);

  const res = await runOnce(pool, { embedFn: okEmbedFn });
  assert.equal(res.claimed, 1);
  assert.equal(res.failed, 0);

  // ON CONFLICT (chunk_id, model_version) DO UPDATE → count unchanged.
  assert.equal(await count("embeddings"), first, "no duplicate embeddings");
  assert.equal(await count("pending_embeddings"), 0);
});

test("failing embedFn returns the row to pending with incremented retry_count (not lost)", async () => {
  await enqueueRecord("This embed will fail once and must survive in the queue.");
  const throwingFn = () => {
    throw new Error("TEI down");
  };

  const res = await runOnce(pool, { embedFn: throwingFn });
  assert.equal(res.claimed, 1);
  assert.equal(res.embedded, 0);
  assert.equal(res.failed, 1);

  // Row is back in pending, retry_count incremented, NOT in DLQ.
  assert.equal(await count("pending_embeddings"), 1, "row preserved");
  assert.equal(await count("failed_embeddings"), 0, "not in DLQ yet");
  const r = await pool.query(
    "SELECT status, retry_count, locked_until FROM pending_embeddings",
  );
  assert.equal(r.rows[0].status, "pending");
  assert.equal(r.rows[0].retry_count, 1);
  assert.equal(r.rows[0].locked_until, null);
});

test("after maxRetries exceeded the row moves to failed_embeddings (DLQ)", async () => {
  await enqueueRecord("Persistently failing record headed for the DLQ.");
  const throwingFn = () => {
    throw new Error("TEI permanently down");
  };

  // maxRetries = 1: first failure -> retry_count 1 (<=1, stays); second -> 2 (>1, DLQ).
  let res = await runOnce(pool, { embedFn: throwingFn, maxRetries: 1 });
  assert.equal(res.failed, 1);
  assert.equal(await count("pending_embeddings"), 1);
  assert.equal(await count("failed_embeddings"), 0);

  res = await runOnce(pool, { embedFn: throwingFn, maxRetries: 1 });
  assert.equal(res.failed, 1);
  assert.equal(await count("pending_embeddings"), 0, "removed from pending");
  assert.equal(await count("failed_embeddings"), 1, "landed in DLQ");

  const dlq = await pool.query(
    "SELECT status, retry_count FROM failed_embeddings",
  );
  assert.ok(dlq.rows[0].retry_count > 1);
});

test("concurrency: two runOnce in parallel claim disjoint rows (SKIP LOCKED), each chunk embedded once", async () => {
  // Enqueue several distinct records.
  const N = 8;
  let totalChunks = 0;
  for (let i = 0; i < N; i++) {
    const { chunk_count } = await enqueueRecord(
      `Record number ${i}.\n\nA distinct second paragraph #${i} long enough to be its own chunk for testing.`,
    );
    totalChunks += chunk_count;
  }
  assert.equal(await count("pending_embeddings"), N);

  // Two workers run concurrently; SKIP LOCKED must partition the rows.
  const [a, b] = await Promise.all([
    runOnce(pool, { embedFn: okEmbedFn }),
    runOnce(pool, { embedFn: okEmbedFn }),
  ]);

  assert.equal(a.failed, 0);
  assert.equal(b.failed, 0);
  assert.equal(a.claimed + b.claimed, N, "every row claimed exactly once total");
  assert.equal(await count("pending_embeddings"), 0, "queue fully drained");
  assert.equal(
    await count("embeddings"),
    totalChunks,
    "exactly one embedding per chunk, no double-embed",
  );
});

test.after(async () => {
  await pool.end();
});
