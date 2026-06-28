import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { backfillFactSupports } from "../src/trust-backfill.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, entities, facts, fact_supports CASCADE"); });
after(async () => { await pool.end(); });

test("backfill seeds one support per existing fact from its source_record_id, idempotently", async () => {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, prov_actor)
     VALUES ('T','x','sha-'||gen_random_uuid()::text,'user_stated') RETURNING id`);
  const e = await pool.query(
    `INSERT INTO entities (name, norm_name, type, content_sha256)
     VALUES ('D','d','person','e-'||gen_random_uuid()::text) RETURNING id`);
  await pool.query(
    `INSERT INTO facts (subject_id, predicate, object_literal, statement, source_record_id, content_sha256)
     VALUES ($1,'likes','green','D likes green',$2,'f-'||gen_random_uuid()::text)`,
    [e.rows[0].id, r.rows[0].id]);
  // a fact with NULL source_record_id must be skipped (no record to attribute it to)
  await pool.query(
    `INSERT INTO facts (subject_id, predicate, object_literal, statement, content_sha256)
     VALUES ($1,'knows','nobody','D knows nobody','f-'||gen_random_uuid()::text)`, [e.rows[0].id]);

  const first = await backfillFactSupports(pool);
  const second = await backfillFactSupports(pool);
  assert.equal(first.inserted, 1);   // only the fact with a source
  assert.equal(second.inserted, 0);  // idempotent
  assert.equal((await pool.query("SELECT count(*) FROM fact_supports")).rows[0].count, "1");
});
