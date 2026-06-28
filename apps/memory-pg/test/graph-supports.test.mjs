import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { applyExtraction } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, entities, facts, fact_supports CASCADE"); });
after(async () => { await pool.end(); });

async function mkRecord(content) {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, prov_actor)
     VALUES ('T', $1, 'sha-'||gen_random_uuid()::text, 'user_stated') RETURNING id`, [content]);
  return r.rows[0].id;
}

const extraction = {
  entities: [{ name: "Demetrios", type: "person" }],
  facts: [{ subject: "Demetrios", predicate: "likes", object: "moss green",
            statement: "Demetrios likes moss green" }],
};

test("two records asserting the SAME fact yield ONE fact but TWO supports", async () => {
  const r1 = await mkRecord("first mention");
  const r2 = await mkRecord("second mention");
  await applyExtraction(pool, extraction, { recordId: r1 });
  await applyExtraction(pool, extraction, { recordId: r2 });

  const nFacts = (await pool.query("SELECT count(*) FROM facts")).rows[0].count;
  const nSupports = (await pool.query("SELECT count(*) FROM fact_supports")).rows[0].count;
  assert.equal(nFacts, "1");    // deduped on the claim hash
  assert.equal(nSupports, "2"); // but BOTH sources are recorded
});
