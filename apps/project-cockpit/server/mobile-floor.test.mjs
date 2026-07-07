// The FLOOR — presence + state that holds when the voice can't be reached.
// Guards the promise made after the 2026-07-06 outage: the intimate companion must
// never return the void (unconnecting dots) to someone who reached out hurting.
import { test } from "node:test";
import assert from "node:assert/strict";
import { buildPersonalFloor } from "./mobile-routes.mjs";

test("floor always carries a warm, non-empty presence in `response`", () => {
  const f = buildPersonalFloor({ reason: "connect ECONNREFUSED 100.103.228.8:9500" });
  assert.ok(f.response && f.response.trim().length > 0, "response must never be empty");
  assert.equal(f.response, f.presence, "old apps read `response`; it must equal the presence line");
  assert.match(f.response, /Estou aqui/, "presence must open with being here");
  assert.equal(f.degraded, true);
  assert.equal(f.model, "floor");
  assert.equal(f.source, "floor");
});

test("floor surfaces the state block it already has (agora)", () => {
  const agora = "## Agora\nTEMPO: 18h\nCORPO: pronto (coração 72 bpm)";
  const f = buildPersonalFloor({ agoraState: agora });
  assert.equal(f.state, agora, "the live state must ride on the floor");
  assert.equal(f.grounded, true, "grounded when state present");
});

test("floor echoes State of Mind label the app sent — never invents affect", () => {
  const f = buildPersonalFloor({ body: { stateOfMindLabel: "sobrecarregado" } });
  assert.match(f.response, /sobrecarregado/, "must reflect his own logged state");
  assert.match(f.response, /você mesmo se registrou/, "must attribute it to him, not claim to know");
});

test("floor falls back to heart rate when no mood label", () => {
  const f = buildPersonalFloor({ body: { heartRate: 99 } });
  assert.match(f.response, /99 bpm/);
});

test("floor with no state at all is still present and safe", () => {
  const f = buildPersonalFloor({});
  assert.ok(f.response.trim().length > 0);
  assert.equal(f.state, "");
  assert.equal(f.grounded, false);
  assert.equal(f.degradedReason, "voice unreachable");
});

test("floor never leaks a raw error object into the reason", () => {
  const f = buildPersonalFloor({ reason: "  timeout after 150000ms  " });
  assert.equal(f.degradedReason, "timeout after 150000ms");
});
