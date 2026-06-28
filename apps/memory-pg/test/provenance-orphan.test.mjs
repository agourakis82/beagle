// A model_distilled record is flagged prov_orphan unless an ancestor is user_stated/external_import.
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

async function orphanOf(id) {
  return (await pool.query("SELECT prov_orphan FROM records WHERE id = $1", [id])).rows[0].prov_orphan;
}

test("distilled atom with a user_stated ancestor is NOT an orphan", async () => {
  const src = await captureRecord(pool, {
    source_type: "TestPassage", content: "I have run marathons since 2015.", prov_actor: "user_stated",
  });
  const atom = await captureRecord(pool, {
    source_type: "TestAtom", content: "Demetrios is a long-distance runner.",
    prov_actor: "model_distilled", prov_derived_from: [src.id],
  });
  assert.equal(await orphanOf(atom.id), false);
});

test("distilled atom with NO user-stated ancestor IS an orphan (the Teobaldo class)", async () => {
  const asst = await captureRecord(pool, {
    source_type: "TestPassage", content: "The assistant invented a detail here.", prov_actor: "model_generated",
  });
  const atom = await captureRecord(pool, {
    source_type: "TestAtom", content: "Fabricated intimate fact.",
    prov_actor: "model_distilled", prov_derived_from: [asst.id],
  });
  assert.equal(await orphanOf(atom.id), true);
});

test("distilled atom with empty derived_from IS an orphan", async () => {
  const atom = await captureRecord(pool, {
    source_type: "TestAtom", content: "Floating claim, no source.", prov_actor: "model_distilled",
  });
  assert.equal(await orphanOf(atom.id), true);
});

test("non-distilled actors are never orphaned", async () => {
  const r = await captureRecord(pool, {
    source_type: "TestPassage", content: "A plain user statement.", prov_actor: "user_stated",
  });
  assert.equal(await orphanOf(r.id), false);
});
