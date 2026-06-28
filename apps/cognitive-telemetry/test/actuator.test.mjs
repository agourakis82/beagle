import { test } from "node:test";
import assert from "node:assert/strict";
import { inferRegister, extractSignals, defaultWeights } from "../src/actuator/register.mjs";
import { applyCorrection } from "../src/actuator/learn.mjs";
import { steerDirective } from "../src/actuator/steer.mjs";

test("inferRegister: low zd (near dissociation variety) → friend + high license", () => {
  const d = inferRegister({ telemetry: { zd: 0.1, coherence: 0.2 }, space: "personal", hour: 2 });
  assert.equal(d.register, "friend");
  assert.ok(d.license > 0.7, `vulnerability raises license, got ${d.license}`);
});

test("inferRegister: technical query → researcher; ops query → operator", () => {
  assert.equal(inferRegister({ query: "prove the octonion associator theorem for the functor" }).register, "researcher");
  assert.equal(inferRegister({ query: "rollout the gpu pod and check the slurm cluster" }).register, "operator");
});

test("inferRegister: work context lowers license even with some personal signal", () => {
  const work = inferRegister({ query: "i think we should deploy", space: "work", telemetry: { zd: 1.0 } });
  const pers = inferRegister({ query: "i think we should deploy", space: "personal", telemetry: { zd: 1.0 } });
  assert.ok(pers.license > work.license, "personal space carries more license than work");
});

test("ANTI-DRIFT: repeated 'be warmer' corrections never decrease license (no caution drift)", () => {
  const ctx = { telemetry: { zd: 0.25 }, query: "i feel a bit lost today", space: "personal", hour: 1 };
  const sig = extractSignals(ctx);
  let w = defaultWeights();
  let prev = inferRegister(ctx, w).license;
  for (let i = 0; i < 8; i++) {
    w = applyCorrection(w, sig, { licenseDelta: +1 });
    const lic = inferRegister(ctx, w).license;
    assert.ok(lic >= prev - 1e-9, `license must not drop on a warmth correction (${prev} -> ${lic})`);
    prev = lic;
  }
  assert.ok(prev >= inferRegister(ctx, defaultWeights()).license, "warmth corrections raised license overall");
});

test("learning: a register correction makes the target win next time for that context", () => {
  const ctx = { query: "help me think through this", telemetry: { zd: 0.9 } }; // ambiguous -> not researcher
  const before = inferRegister(ctx);
  const w = applyCorrection(defaultWeights(), extractSignals(ctx), { register: "friend" }, { lr: 0.3 });
  const after = inferRegister(ctx, w);
  assert.equal(after.register, "friend");
  assert.ok(after.scores.friend >= before.scores.friend);
});

test("steerDirective: friend+high license → warm persona, intimacy vector, higher temp", () => {
  const dir = steerDirective({ register: "friend", license: 0.9 });
  assert.match(dir.persona, /amigo/);
  assert.ok(dir.temperature > 0.7);
  const intimacy = dir.emotionVectors.find((v) => v.name === "intimacy");
  assert.ok(intimacy.weight > 0.7, "high license → high intimacy steering");
  const rigor = steerDirective({ register: "researcher", license: 0.2 }).emotionVectors.find((v) => v.name === "rigor");
  assert.ok(rigor.weight > 0.6, "researcher anchors rigor");
});
