import { test } from "node:test";
import assert from "node:assert/strict";
import { parseTelemetry } from "../src/parse.mjs";
import { genDriverSio } from "../src/siogen.mjs";

test("parseTelemetry reads TELEM blocks into objects", () => {
  const out = parseTelemetry(
    ["TELEM", "1", "0", "0.900109", "1.951403", "2", "0.326912", "0",
     "TELEM", "2", "1", "0.000000", "1.885734", "4", "0.267949", "1"].join("\n"),
  );
  assert.equal(out.length, 2);
  assert.equal(out[0].idx, 1);
  assert.equal(out[0].fano, 2);
  assert.ok(Math.abs(out[0].coherence - 0.900109) < 1e-6);
  assert.equal(out[0].rupture, false);
  assert.equal(out[1].rupture, true);
});

test("genDriverSio emits valid f64 literals + one emit_turn per turn", () => {
  const traj = [
    { speaker: 0, content: [0, 1, 0, 0, 0, 0, 0, 0], uncertainty: [0, 0, 0, 0, 0, 0, 0, 1] },
    { speaker: 1, content: [0, 0, 1, 0, 0, 0, 0, 0], uncertainty: [0, 1, 0, 0, 0, 0, 0, 0] },
  ];
  const sio = genDriverSio(traj);
  assert.match(sio, /use cybernetic::dialogue_tapestry::\{emit_turn\}/);
  assert.equal((sio.match(/emit_turn\(/g) || []).length, 2);
  // every numeric is a decimal literal (no bare ints, no exponentials)
  assert.ok(!/\[\s*0\s*,/.test(sio), "integers are written as f64 decimals");
  assert.match(sio, /1\.000000000/);
  // endpoints reuse cur for the missing neighbour, interior has both
  assert.match(sio, /emit_turn\(0, 0, c0, c0, c1, u0, false, true/);
  assert.match(sio, /emit_turn\(1, 1, c0, c1, c1, u1, true, false/);
});
