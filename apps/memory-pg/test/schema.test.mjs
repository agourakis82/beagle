// schema.test.mjs — Phase 0, Task 0.2 Step 1.
// Asserts ensureSchema creates the core tables + the HNSW index on embeddings.
// Runs against a live memory-pg (DSN via MEMORY_PG_TEST_DSN, e.g. a port-forward).

import { test } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";

test("schema creates tables + hnsw index", async () => {
  const pool = makePool(process.env.MEMORY_PG_TEST_DSN);
  await ensureSchema(pool);

  const t = await pool.query(
    "select table_name from information_schema.tables where table_schema='public'",
  );
  const names = t.rows.map((r) => r.table_name);
  for (const n of [
    "records",
    "chunks",
    "embeddings",
    "pending_embeddings",
    "failed_embeddings",
  ]) {
    assert.ok(names.includes(n), `missing table: ${n}`);
  }

  const idx = await pool.query(
    "select indexname from pg_indexes where tablename='embeddings'",
  );
  assert.ok(
    idx.rows.some((r) => /hnsw/i.test(r.indexname)),
    "missing hnsw index on embeddings",
  );

  await pool.end();
});
