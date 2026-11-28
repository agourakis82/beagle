// Asserts the provenance migration adds the prov_* columns + actor CHECK to records.
// Runs against a live memory-pg (DSN via MEMORY_PG_TEST_DSN).
import { test } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
// Safety: these tests mutate/TRUNCATE records — refuse to touch a non-scratch DB.
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

test("records has the prov_* columns with correct types/defaults", async () => {
  await ensureSchema(pool);
  const cols = await pool.query(
    `SELECT column_name, data_type, column_default, is_nullable
       FROM information_schema.columns
      WHERE table_name = 'records' AND column_name LIKE 'prov_%'
      ORDER BY column_name`,
  );
  const byName = Object.fromEntries(cols.rows.map((r) => [r.column_name, r]));
  assert.equal(byName.prov_actor.is_nullable, "NO");
  assert.match(byName.prov_actor.column_default, /model_generated/);
  assert.equal(byName.prov_derived_from.data_type, "ARRAY");
  assert.equal(byName.prov_orphan.data_type, "boolean");
  assert.ok(byName.prov_confidence, "prov_confidence column exists");
  assert.ok(byName.prov_surface, "prov_surface column exists");
  assert.ok(byName.prov_asserted_at, "prov_asserted_at column exists");
});

test("records_prov_actor_chk rejects an actor outside the taxonomy", async () => {
  await ensureSchema(pool);
  await assert.rejects(
    pool.query(
      `INSERT INTO records (source_type, content, content_sha256, prov_actor)
       VALUES ('TestPassage', 'x', 'sha-bad-actor-' || gen_random_uuid()::text, 'gossip')`,
    ),
    /records_prov_actor_chk|check constraint/i,
  );
});

test.after(async () => { await pool.end(); });
