import { test } from "node:test";
import assert from "node:assert/strict";
import { gatherSynthesisMaterial } from "./synthesize.mjs";

function deps(overrides = {}) {
  return {
    fetchRecentMemories: async (q, opts) => { deps._mem = { q, opts }; return [{ text: "minha palavra" }]; },
    fetchExocortexContext: async (q, opts) => { deps._exo = { q, opts }; return "fundo"; },
    fetchRecentTrusted: async (opts) => { deps._recent = opts; return [{ text: "pensamento recente" }]; },
    ...overrides,
  };
}

test("topic mode: pulls his words with trustedOnly + background, returns topic shape", async () => {
  const d = deps();
  const m = await gatherSynthesisMaterial({ topic: "HSN", windowDays: 7 }, d);
  assert.equal(m.mode, "topic");
  assert.equal(m.topic, "HSN");
  assert.equal(deps._mem.opts.trustedOnly, true);
  assert.deepEqual(m.trustedWords, [{ text: "minha palavra" }]);
  assert.equal(m.background, "fundo");
});

test("no-topic mode: pulls recent trusted by window, no semantic recall", async () => {
  let memCalled = false;
  const d = deps({ fetchRecentMemories: async () => { memCalled = true; return []; } });
  const m = await gatherSynthesisMaterial({ windowDays: 5 }, d);
  assert.equal(m.mode, "recent");
  assert.equal(m.windowDays, 5);
  assert.equal(memCalled, false);
  assert.deepEqual(m.trustedWords, [{ text: "pensamento recente" }]);
});
