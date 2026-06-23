// capture.test.mjs — Phase 1, Task 1.2.
//
// TDD for the transactional outbox (`captureRecord`). Runs against the live
// dedicated `memory-pg` Postgres (DSN from MEMORY_PG_TEST_DSN, normally a
// port-forward). Each test is isolated by a beforeEach TRUNCATE — the instance
// is dedicated with no real data, so this is safe and makes runs idempotent.
//
// The concurrent-capture case is the ACID-vs-JSONL-corruption proof: two
// different contents captured in parallel must yield exactly 2 records, 2 queue
// rows, and zero partial/orphan rows.

import { test, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool } from "../src/db.mjs";
import { captureRecord } from "../src/capture.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) {
  throw new Error("MEMORY_PG_TEST_DSN must be set (port-forwarded memory-pg DSN)");
}

const pool = makePool(DSN);

beforeEach(async () => {
  await pool.query(
    "TRUNCATE records, chunks, embeddings, pending_embeddings, failed_embeddings CASCADE",
  );
});

after(async () => {
  await pool.end();
});

async function counts() {
  const [recs, chs, pend] = await Promise.all([
    pool.query("SELECT count(*)::int AS n FROM records"),
    pool.query("SELECT count(*)::int AS n FROM chunks"),
    pool.query("SELECT count(*)::int AS n FROM pending_embeddings"),
  ]);
  return { records: recs.rows[0].n, chunks: chs.rows[0].n, pending: pend.rows[0].n };
}

test("capture once → 1 record, chunks, exactly 1 queue row; created=true", async () => {
  const res = await captureRecord(pool, {
    source_type: "test",
    content: "Hello from the memory pipeline. This is a single captured record.",
  });

  assert.equal(res.created, true);
  assert.ok(res.id, "returns an id");
  assert.ok(res.chunk_count > 0, "chunk_count > 0");

  const c = await counts();
  assert.equal(c.records, 1, "exactly 1 record");
  assert.equal(c.chunks, res.chunk_count, "chunk rows match returned chunk_count");
  assert.ok(c.chunks > 0, "at least one chunk row");
  assert.equal(c.pending, 1, "exactly 1 pending_embeddings row");
});

test("capture same content twice → no dupes; second created=false", async () => {
  const content = "Idempotency proof: this exact content is captured twice.";
  const first = await captureRecord(pool, { source_type: "test", content });
  const second = await captureRecord(pool, { source_type: "test", content });

  assert.equal(first.created, true);
  assert.equal(second.created, false, "second capture is a no-op");
  assert.equal(second.id, first.id, "duplicate returns the existing id");

  const c = await counts();
  assert.equal(c.records, 1, "still exactly 1 record");
  assert.equal(c.chunks, first.chunk_count, "still 1 set of chunks");
  assert.equal(c.pending, 1, "still 1 queue row");
});

test("concurrent capture of 2 different contents → 2 records, 2 queue rows, no corruption (ACID proof)", async () => {
  const a = "Concurrent capture A: the first distinct content blob.";
  const b = "Concurrent capture B: the second distinct content blob.";

  const [ra, rb] = await Promise.all([
    captureRecord(pool, { source_type: "test", content: a }),
    captureRecord(pool, { source_type: "test", content: b }),
  ]);

  assert.equal(ra.created, true);
  assert.equal(rb.created, true);
  assert.notEqual(ra.id, rb.id, "two distinct record ids");

  const c = await counts();
  assert.equal(c.records, 2, "exactly 2 records");
  assert.equal(c.pending, 2, "exactly 2 queue rows");
  assert.equal(c.chunks, ra.chunk_count + rb.chunk_count, "chunk rows == sum, no partials");

  // No orphan chunks (every chunk references a live record) and every record
  // has exactly one queue row — i.e. no partial/corrupt transactions.
  const orphans = await pool.query(
    "SELECT count(*)::int AS n FROM chunks c LEFT JOIN records r ON r.id = c.record_id WHERE r.id IS NULL",
  );
  assert.equal(orphans.rows[0].n, 0, "no orphan chunks");
  const queuePerRecord = await pool.query(
    "SELECT count(*)::int AS n FROM records r WHERE (SELECT count(*) FROM pending_embeddings p WHERE p.record_id = r.id) <> 1",
  );
  assert.equal(queuePerRecord.rows[0].n, 0, "every record has exactly one queue row");
});
