import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { promoteFacts, promoteRecords } from "../src/promote.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, entities, facts, fact_supports CASCADE"); });
after(async () => { await pool.end(); });

async function rec({ actor = "user_stated", session = "s1", day = "2026-06-01", content }) {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, prov_actor, created_at, metadata)
     VALUES ('T', $1, 'sha-' || gen_random_uuid()::text, $2, $3::timestamptz,
             jsonb_build_object('session_id', $4::text))
     RETURNING id`,
    [content, actor, `${day}T12:00:00Z`, session],
  );
  return r.rows[0].id;
}
async function fact(predicate = "likes", literal = "green") {
  const e = await pool.query(
    `INSERT INTO entities (name, norm_name, type, content_sha256)
     VALUES ('Demetrios','demetrios','person','e-'||gen_random_uuid()::text) RETURNING id`);
  const f = await pool.query(
    `INSERT INTO facts (subject_id, predicate, object_literal, statement, content_sha256)
     VALUES ($1, $2, $3, $2 || ' ' || $3, 'f-'||gen_random_uuid()::text) RETURNING id`,
    [e.rows[0].id, predicate, literal]);
  return f.rows[0].id;
}
async function support(factId, recordId) {
  await pool.query("INSERT INTO fact_supports (fact_id, source_record_id) VALUES ($1,$2)", [factId, recordId]);
}
async function tierOf(factId) {
  return (await pool.query("SELECT trust_tier, independent_user_sources FROM facts WHERE id=$1", [factId])).rows[0];
}

test("10 user_stated supports from ONE session+day count as 1 → claimed (kills amplification)", async () => {
  const f = await fact();
  for (let i = 0; i < 10; i++) {
    await support(f, await rec({ session: "sX", day: "2026-06-01", content: `c${i}` }));
  }
  await promoteFacts(pool);
  const t = await tierOf(f);
  assert.equal(t.independent_user_sources, 1);
  assert.equal(t.trust_tier, "claimed");
});

test("2 distinct sessions on 2 days within a week → corroborated", async () => {
  const f = await fact();
  await support(f, await rec({ session: "comp", day: "2026-06-01", content: "a" }));
  await support(f, await rec({ session: "cd",   day: "2026-06-03", content: "b" }));
  await promoteFacts(pool);
  const t = await tierOf(f);
  assert.equal(t.independent_user_sources, 2);
  assert.equal(t.trust_tier, "corroborated");
});

test("2 independent sources spanning ≥7 days → known", async () => {
  const f = await fact();
  await support(f, await rec({ session: "comp", day: "2026-06-01", content: "a" }));
  await support(f, await rec({ session: "cd",   day: "2026-06-10", content: "b" }));
  await promoteFacts(pool);
  assert.equal((await tierOf(f)).trust_tier, "known");
});

test("a fact with only non-user_stated supports stays unverified", async () => {
  const f = await fact();
  await support(f, await rec({ actor: "model_generated", content: "x" }));
  await support(f, await rec({ actor: "model_distilled", content: "y" }));
  await promoteFacts(pool);
  const t = await tierOf(f);
  assert.equal(t.independent_user_sources, 0);
  assert.equal(t.trust_tier, "unverified");
});

test("promoteRecords sets a base tier from actor/orphan", async () => {
  const u = await rec({ actor: "user_stated", content: "u" });
  const g = await rec({ actor: "model_generated", content: "g" });
  const o = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, prov_actor, prov_orphan)
     VALUES ('T','orf','sha-'||gen_random_uuid()::text,'model_distilled',true) RETURNING id`);
  await promoteRecords(pool);
  const tier = async (id) => (await pool.query("SELECT trust_tier FROM records WHERE id=$1",[id])).rows[0].trust_tier;
  assert.equal(await tier(u), "claimed");
  assert.equal(await tier(g), "unverified");
  assert.equal(await tier(o.rows[0].id), "unverified"); // orphaned distilled
});
