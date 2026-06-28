// graph-extract.test.mjs — Phase 4, Task 4.3: sovereign-LLM graph extraction +
// bi-temporal apply. The LLM is STUBBED (no cluster, deterministic): it returns
// known entities + temporally-scoped facts. We assert the parse, entity
// resolution, fact insertion, idempotency, and — the heart of the bi-temporal
// model — that a contradicting fact INVALIDATES the prior one (valid_to set)
// rather than deleting it, so history is preserved.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { extractGraph, applyExtraction } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE entities, facts, pending_graph CASCADE"); });
after(async () => { await pool.end(); });

// stub llmFn: returns whatever JSON the test wired, ignoring the prompt.
function stubLlm(json) {
  return async () => (typeof json === "string" ? json : JSON.stringify(json));
}

test("extractGraph parses entities + facts from the LLM JSON", async () => {
  const llmFn = stubLlm({
    entities: [{ name: "Demetrios", type: "person" }, { name: "Lisbon", type: "place" }],
    facts: [
      { subject: "Demetrios", predicate: "located_in", object: "Lisbon",
        statement: "Demetrios is located in Lisbon", occurred_at: "2026-06-01", confidence: 0.9 },
    ],
  });
  const out = await extractGraph({ content: "Demetrios moved to Lisbon." }, { llmFn });
  assert.equal(out.entities.length, 2);
  assert.equal(out.facts.length, 1);
  assert.equal(out.facts[0].predicate, "located_in");
});

test("extractGraph tolerates LLM prose around the JSON + bad output", async () => {
  const wrapped = "Sure! Here is the graph:\n```json\n" +
    JSON.stringify({ entities: [{ name: "Sounio", type: "project" }], facts: [] }) + "\n```\nDone.";
  const out = await extractGraph({ content: "x" }, { llmFn: stubLlm(wrapped) });
  assert.equal(out.entities[0].name, "Sounio");
  // unparseable → empty extraction, never throws
  const bad = await extractGraph({ content: "x" }, { llmFn: stubLlm("not json at all") });
  assert.deepEqual(bad, { entities: [], facts: [] });
});

test("applyExtraction resolves entities + inserts facts (idempotent)", async () => {
  const extraction = {
    entities: [{ name: "Demetrios", type: "person" }, { name: "Beagle", type: "project" }],
    facts: [{ subject: "Demetrios", predicate: "built", object: "Beagle",
              statement: "Demetrios built Beagle", confidence: 1.0 }],
  };
  const r1 = await applyExtraction(pool, extraction, { recordId: null });
  assert.equal(r1.entitiesResolved, 2);
  assert.equal(r1.factsInserted, 1);
  // re-apply: same content_sha256 → no new facts, entities reused
  const r2 = await applyExtraction(pool, extraction, { recordId: null });
  assert.equal(r2.factsInserted, 0, "idempotent on re-apply");
  assert.equal((await pool.query("SELECT count(*)::int n FROM facts")).rows[0].n, 1);
  assert.equal((await pool.query("SELECT count(*)::int n FROM entities")).rows[0].n, 2);
});

test("a contradicting fact INVALIDATES the prior one (valid_to set, not deleted)", async () => {
  // (Demetrios, located_in, São Paulo) then later (Demetrios, located_in, Lisbon).
  await applyExtraction(pool, {
    entities: [{ name: "Demetrios", type: "person" }, { name: "São Paulo", type: "place" }],
    facts: [{ subject: "Demetrios", predicate: "located_in", object: "São Paulo",
              statement: "Demetrios is located in São Paulo", valid_from: "2025-01-01" }],
  }, { recordId: null });

  const second = await applyExtraction(pool, {
    entities: [{ name: "Demetrios", type: "person" }, { name: "Lisbon", type: "place" }],
    facts: [{ subject: "Demetrios", predicate: "located_in", object: "Lisbon",
              statement: "Demetrios is located in Lisbon", valid_from: "2026-06-01" }],
  }, { recordId: null });
  assert.equal(second.factsInvalidated, 1, "the São Paulo fact was invalidated");

  // both rows still exist — history preserved
  assert.equal((await pool.query("SELECT count(*)::int n FROM facts")).rows[0].n, 2);
  // exactly one CURRENT fact for (Demetrios, located_in), and it's Lisbon
  const cur = await pool.query(
    `SELECT f.statement FROM facts f WHERE f.predicate='located_in' AND f.valid_to IS NULL`);
  assert.equal(cur.rowCount, 1);
  assert.match(cur.rows[0].statement, /Lisbon/);
  // the invalidated one has valid_to set to the new fact's valid_from
  const inv = await pool.query(
    `SELECT valid_to FROM facts WHERE statement LIKE '%São Paulo%'`);
  assert.ok(inv.rows[0].valid_to != null, "prior fact has valid_to set (invalidated, not deleted)");
});

test("multi-valued predicate to a DIFFERENT object is not a contradiction", async () => {
  // "knows" can have many objects → adding a second must NOT invalidate the first.
  await applyExtraction(pool, {
    entities: [{ name: "A", type: "person" }, { name: "B", type: "person" }],
    facts: [{ subject: "A", predicate: "knows", object: "B", statement: "A knows B" }],
  }, { recordId: null });
  const r = await applyExtraction(pool, {
    entities: [{ name: "A", type: "person" }, { name: "C", type: "person" }],
    facts: [{ subject: "A", predicate: "knows", object: "C", statement: "A knows C",
              multi_valued: true }],
  }, { recordId: null });
  assert.equal(r.factsInvalidated, 0, "multi-valued predicate keeps both");
  assert.equal((await pool.query("SELECT count(*)::int n FROM facts WHERE valid_to IS NULL")).rows[0].n, 2);
});
