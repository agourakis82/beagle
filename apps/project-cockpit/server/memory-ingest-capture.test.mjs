import { test } from "node:test";
import assert from "node:assert/strict";
import { captureProvenanced } from "./memory-ingest.mjs";

test("captureProvenanced POSTs the record to /capture_turn and returns {id, created}", async () => {
  let seenUrl, seenBody;
  const fetchImpl = async (url, opts) => {
    seenUrl = url; seenBody = JSON.parse(opts.body);
    return { ok: true, json: async () => ({ id: "rec-9", created: true }) };
  };
  const out = await captureProvenanced(
    { source_type: "MemoryAtom", content: "x", prov_actor: "model_distilled", prov_derived_from: ["u1"] },
    { memoryPgUrl: "http://memory-pg", fetchImpl },
  );
  assert.equal(seenUrl, "http://memory-pg/capture_turn");
  assert.equal(seenBody.prov_actor, "model_distilled");
  assert.deepEqual(seenBody.prov_derived_from, ["u1"]);
  assert.deepEqual(out, { id: "rec-9", created: true });
});

test("captureProvenanced is best-effort: returns null on !ok and never throws", async () => {
  const bad = await captureProvenanced({ source_type: "X", content: "y" }, {
    memoryPgUrl: "http://memory-pg", fetchImpl: async () => ({ ok: false, json: async () => ({}) }),
  });
  assert.equal(bad, null);
  const threw = await captureProvenanced({ source_type: "X", content: "y" }, {
    memoryPgUrl: "http://memory-pg", fetchImpl: async () => { throw new Error("down"); },
  });
  assert.equal(threw, null);
});
