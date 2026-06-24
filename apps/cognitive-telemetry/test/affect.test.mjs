import { test } from "node:test";
import assert from "node:assert/strict";
import { affectUncertainty, AFFECT_CHANNELS } from "../src/affect.mjs";

test("affectUncertainty: deterministic, 8-dim, non-negative", () => {
  const t = "I think maybe this is, possibly, not quite what I meant?";
  const a = affectUncertainty(t);
  const b = affectUncertainty(t);
  assert.equal(a.length, 8);
  assert.deepEqual(a, b);
  assert.ok(a.every((x) => x >= 0 && Number.isFinite(x)));
  assert.equal(AFFECT_CHANNELS.length, 8);
});

test("affectUncertainty: empty/whitespace -> zeros (no throw)", () => {
  assert.deepEqual(affectUncertainty(""), new Array(8).fill(0));
  assert.deepEqual(affectUncertainty("   \n  "), new Array(8).fill(0));
});

test("affectUncertainty: hedging text scores higher on the hedging channel", () => {
  const hedged = affectUncertainty("maybe perhaps i think it might possibly be");
  const flat = affectUncertainty("the report is finished and shipped");
  const h = AFFECT_CHANNELS.indexOf("hedging");
  assert.ok(hedged[h] > flat[h], "hedging density discriminates");
});

test("affectUncertainty: question-heavy text scores higher on the interrogative channel", () => {
  const q = affectUncertainty("why? how? what do you mean? is it real?");
  const s = affectUncertainty("it is done. it works. shipped.");
  const i = AFFECT_CHANNELS.indexOf("interrogative");
  assert.ok(q[i] > s[i]);
});

test("affectUncertainty: absolutist terms score on the rigidity channel", () => {
  const abs = affectUncertainty("i always fail, never succeed, everything is completely ruined");
  const mod = affectUncertainty("some parts went well, others need work");
  const r = AFFECT_CHANNELS.indexOf("rigidity");
  assert.ok(abs[r] > mod[r], "absolutist density (a known clinical marker) discriminates");
});
