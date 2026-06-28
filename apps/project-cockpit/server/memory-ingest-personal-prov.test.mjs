import { test } from "node:test";
import assert from "node:assert/strict";
import { ingestPersonalTurn } from "./memory-ingest.mjs";

test("ingestPersonalTurn writes provenance: user_stated, model_generated, model_distilled+derived_from", async () => {
  const captures = [];
  const deps = {
    fetchImpl: async () => ({ ok: true, json: async () => ({}) }),
    tokenFn: async () => "tok",
    memoryPgUrl: "http://memory-pg",
    distillFn: async () => ["Demetrios runs marathons."],
    captureFn: async (rec) => {
      captures.push(rec);
      if (rec.prov_actor === "user_stated") return { id: "user-rec-1", created: true };
      return { id: `rec-${captures.length}`, created: true };
    },
  };
  await ingestPersonalTurn(
    { sessionId: "home:companion", userText: "I run marathons", assistantText: "Nice!", clientTime: null, timezone: null },
    deps,
  );

  const byActor = (a) => captures.filter((c) => c.prov_actor === a);
  assert.equal(byActor("user_stated").length, 1);
  assert.equal(byActor("user_stated")[0].content, "I run marathons");
  assert.equal(byActor("model_generated").length, 1);
  const atoms = byActor("model_distilled");
  assert.equal(atoms.length, 1);
  assert.equal(atoms[0].content, "Demetrios runs marathons.");
  assert.deepEqual(atoms[0].prov_derived_from, ["user-rec-1"]);
});

test("ingestPersonalTurn is fail-soft: a capture error never throws", async () => {
  await ingestPersonalTurn(
    { sessionId: "s", userText: "hi", assistantText: "ok" },
    {
      fetchImpl: async () => ({ ok: true, json: async () => ({}) }),
      tokenFn: async () => "t",
      memoryPgUrl: "http://memory-pg",
      distillFn: async () => [],
      captureFn: async () => { throw new Error("capture down"); },
    },
  );
  assert.ok(true);
});
