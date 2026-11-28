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

async function rowOf(id) {
  return (await pool.query("SELECT prov_actor, prov_orphan FROM records WHERE id = $1", [id])).rows[0];
}

test("MemoryAtom → model_distilled + orphan; Episode/Passage stay conservative (no trust granted)", async () => {
  const atom = await captureRecord(pool, { source_type: "MemoryAtom", content: "atom one" });
  const epi = await captureRecord(pool, { source_type: "MemoryEpisode", content: "episode one" });
  const pass = await captureRecord(pool, { source_type: "ConversationPassage", content: "passage one" });

  const res = await backfillProvenance(pool);

  const atomRow = await rowOf(atom.id);
  assert.equal(atomRow.prov_actor, "model_distilled");
  assert.equal(atomRow.prov_orphan, true); // untraced historical atom → orphan (untrusted)
  // No blind trust elevation: imports/passages stay at the conservative default.
  assert.equal((await rowOf(epi.id)).prov_actor, "model_generated");
  assert.equal((await rowOf(pass.id)).prov_actor, "model_generated");
  assert.equal(res.distilled, 1);
});

test("the backfill NEVER grants a trusted actor (user_stated/external_import) to bulk", async () => {
  await captureRecord(pool, { source_type: "MemoryAtom", content: "a" });
  await captureRecord(pool, { source_type: "MemoryEpisode", content: "b" });
  await captureRecord(pool, { source_type: "ConversationPassage", content: "c" });
  await backfillProvenance(pool);
  const trusted = (await pool.query(
    "SELECT count(*) FROM records WHERE prov_actor IN ('user_stated', 'external_import')",
  )).rows[0].count;
  assert.equal(trusted, "0");
});

test("backfill never overwrites a forward-path user_stated tag and is idempotent", async () => {
  const u = await captureRecord(pool, {
    source_type: "MemoryAtom", content: "already tagged", prov_actor: "user_stated",
  });
  const first = await backfillProvenance(pool);
  const second = await backfillProvenance(pool);
  assert.equal((await rowOf(u.id)).prov_actor, "user_stated"); // untouched (not at default)
  assert.equal(second.distilled, 0); // nothing left at default to change
  assert.equal(typeof first.distilled, "number");
});
