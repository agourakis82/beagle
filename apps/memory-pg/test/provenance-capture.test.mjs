// captureRecord persists provenance; defaults to model_generated; validates the actor.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { captureRecord } from "../src/capture.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
// Safety: these tests mutate/TRUNCATE records — refuse to touch a non-scratch DB.
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records CASCADE"); });
after(async () => { await pool.end(); });

test("user_stated provenance is persisted", async () => {
  const { id } = await captureRecord(pool, {
    source_type: "TestPassage",
    content: "I run every morning before work.",
    prov_actor: "user_stated",
    prov_surface: "companion-ios",
    prov_confidence: 1.0,
  });
  const row = (await pool.query(
    "SELECT prov_actor, prov_surface, prov_confidence FROM records WHERE id = $1", [id],
  )).rows[0];
  assert.equal(row.prov_actor, "user_stated");
  assert.equal(row.prov_surface, "companion-ios");
  assert.equal(row.prov_confidence, 1);
});

test("absent provenance defaults to model_generated", async () => {
  const { id } = await captureRecord(pool, { source_type: "TestPassage", content: "untagged content" });
  const row = (await pool.query("SELECT prov_actor FROM records WHERE id = $1", [id])).rows[0];
  assert.equal(row.prov_actor, "model_generated");
});

test("an invalid actor is rejected before any write", async () => {
  await assert.rejects(
    captureRecord(pool, { source_type: "TestPassage", content: "x", prov_actor: "rumor" }),
    /invalid prov_actor/,
  );
  const n = (await pool.query("SELECT count(*) FROM records")).rows[0].count;
  assert.equal(n, "0");
});
