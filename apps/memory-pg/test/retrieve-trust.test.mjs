// retrieve() returns each hit's trust_tier (added in P3). One-hot halfvecs, like retrieve.test.mjs.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { retrieve } from "../src/retrieve.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

function oneHot(axis) {
  const v = new Array(1024).fill(0);
  v[axis] = 1;
  return "[" + v.join(",") + "]";
}

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, embeddings CASCADE"); });
after(async () => { await pool.end(); });

async function seed({ axis, text, tier }) {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, trust_tier)
     VALUES ('T', $1, 'sha-'||gen_random_uuid()::text, $2) RETURNING id`, [text, tier]);
  const c = await pool.query(
    `INSERT INTO chunks (record_id, chunk_index, text, content_sha256)
     VALUES ($1, 0, $2, 'cs-'||gen_random_uuid()::text) RETURNING id`, [r.rows[0].id, text]);
  await pool.query(
    `INSERT INTO embeddings (chunk_id, embedding, model_version)
     VALUES ($1, $2::halfvec, 'bge-m3')`, [c.rows[0].id, oneHot(axis)]);
  return c.rows[0].id;
}

test("each hit carries its record's trust_tier", async () => {
  await seed({ axis: 0, text: "the user runs marathons", tier: "claimed" });
  const hits = await retrieve(pool, { queryEmbedding: oneHot(0), queryText: "marathons", k: 5 });
  assert.ok(hits.length >= 1, "expected at least one hit");
  assert.equal(hits[0].trust_tier, "claimed");
});

test("trustedOnly restricts retrieval to non-unverified records (his authoritative words)", async () => {
  await seed({ axis: 7, text: "his own words about sailing weekends", tier: "claimed" });
  await seed({ axis: 7, text: "a model reply about sailing weekends", tier: "unverified" });

  const all = await retrieve(pool, { queryEmbedding: oneHot(7), queryText: "sailing", k: 5 });
  assert.equal(all.length, 2, "both records returned without the filter");

  const trusted = await retrieve(pool, {
    queryEmbedding: oneHot(7), queryText: "sailing", k: 5, trustedOnly: true,
  });
  assert.equal(trusted.length, 1, "only the trusted record survives trustedOnly");
  assert.equal(trusted[0].trust_tier, "claimed");
});
