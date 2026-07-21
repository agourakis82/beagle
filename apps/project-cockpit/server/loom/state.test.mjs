import { test } from "node:test";
import assert from "node:assert/strict";
import { classify } from "./state.mjs";

test("classify maps signals to the fixed state vocabulary", () => {
  const now = 1_000_000;
  assert.equal(classify({ alive: false, now }), "exited");
  assert.equal(classify({ alive: true, awaitingInput: true, now }), "waiting");
  assert.equal(classify({ alive: true, atPrompt: true, lastOutputAt: now - 10, now }), "idle");
  assert.equal(classify({ alive: true, lastOutputAt: now - 100, now }), "running");
  assert.equal(classify({ alive: true, atPrompt: false, lastOutputAt: now - 999999, now, stuckAfterMs: 120000 }), "stuck");
});
