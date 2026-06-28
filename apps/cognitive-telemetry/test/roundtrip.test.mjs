// roundtrip.test.mjs — the full Node→souc→parse bridge over a real trajectory.
// Requires the souc binary + Sounio stdlib (SOUNIO_REPO, default /home/devsounio/sounio).

import { test } from "node:test";
import assert from "node:assert/strict";
import { runTapestry } from "../src/runner.mjs";

test("runTapestry executes F via souc and returns per-turn telemetry", async () => {
  const traj = [
    { speaker: 0, content: [0, 0.9, 0.1, 0, 0.2, 0, 0, 0], uncertainty: [0, 0.1, 0, 0.3, 0, 0, 0.5, 0] },
    { speaker: 1, content: [0, 0.1, 0.8, 0.2, 0, 0.1, 0, 0], uncertainty: [0, 0, 0.2, 0, 0.6, 0, 0, 0.1] },
    { speaker: 0, content: [0, 0, 0.1, 0.9, 0.1, 0, 0.2, 0], uncertainty: [0, 0.4, 0, 0, 0, 0.3, 0, 0.2] },
  ];
  const tel = await runTapestry(traj, { ruptureThresh: 0.15 });
  assert.equal(tel.length, 3, "one telemetry record per turn");

  // endpoints: no coherence triple (turn 0 has no prev, turn 2 has no next)
  assert.equal(tel[0].coherence, 0);
  assert.equal(tel[2].coherence, 0);
  // turn 0 has no prior exchange → lr 0, fano 0
  assert.equal(tel[0].lr, 0);
  assert.equal(tel[0].fano, 0);

  // interior turn: a real coherence event + speaker asymmetry + an active mode
  assert.ok(tel[1].coherence > 0, "interior coherence is a measured event");
  assert.ok(tel[1].lr > 0, "interior speaker asymmetry");
  assert.ok(tel[1].fano >= 1 && tel[1].fano <= 7, "active Fano subalgebra in [1,7]");
  // zero-divisor proximity is finite for every turn
  for (const t of tel) assert.ok(Number.isFinite(t.zd));
});
