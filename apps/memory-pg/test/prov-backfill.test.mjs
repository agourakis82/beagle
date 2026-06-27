import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { captureRecord } from "../src/capture.mjs";
import { backfillProvenance } from "../src/prov-backfill.mjs";

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

async function actorOf(id) {
  return (await pool.query("SELECT prov_actor FROM records WHERE id = $1", [id])).rows[0].prov_actor;
}

test("MemoryAtom → model_distilled, MemoryEpisode → external_import, Passage stays default", async () => {
  const atom = await captureRecord(pool, { source_type: "MemoryAtom", content: "atom one" });
  const epi = await captureRecord(pool, { source_type: "MemoryEpisode", content: "episode one" });
  const pass = await captureRecord(pool, { source_type: "ConversationPassage", content: "passage one" });

  const res = await backfillProvenance(pool);

  assert.equal(await actorOf(atom.id), "model_distilled");
  assert.equal(await actorOf(epi.id), "external_import");
  assert.equal(await actorOf(pass.id), "model_generated");
  assert.equal(res.distilled, 1);
  assert.equal(res.imported, 1);
});

test("backfill never overwrites a forward-path user_stated tag and is idempotent", async () => {
  const u = await captureRecord(pool, {
    source_type: "MemoryAtom", content: "already tagged", prov_actor: "user_stated",
  });
  const first = await backfillProvenance(pool);
  const second = await backfillProvenance(pool);
  assert.equal(await actorOf(u.id), "user_stated"); // untouched (not at default)
  assert.equal(second.distilled, 0); // nothing left at default to change
  assert.equal(second.imported, 0);
  assert.equal(typeof first.distilled, "number");
});
