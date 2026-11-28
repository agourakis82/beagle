import { test } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

test("fact_supports table + trust_tier columns exist with the tier CHECK", async () => {
  await ensureSchema(pool);
  const fs = await pool.query(
    "SELECT to_regclass('public.fact_supports') AS t");
  assert.equal(fs.rows[0].t, "fact_supports");
  const cols = await pool.query(
    `SELECT table_name, column_name FROM information_schema.columns
      WHERE column_name = 'trust_tier' AND table_name IN ('facts','records')`);
  const tabs = cols.rows.map((r) => r.table_name).sort();
  assert.deepEqual(tabs, ["facts", "records"]);
  // tier CHECK rejects a bad value. Use an INSERT (always writes a row → always fires
  // the CHECK); an UPDATE on an empty table touches zero rows and never validates.
  await assert.rejects(
    pool.query(
      `INSERT INTO records (source_type, content, content_sha256, trust_tier)
       VALUES ('T', 'x', 'sha-' || gen_random_uuid()::text, 'famous')`),
    /records_trust_tier_chk|check constraint/i,
  );
});

test.after(async () => { await pool.end(); });
