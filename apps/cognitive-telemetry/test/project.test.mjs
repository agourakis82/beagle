import { test } from "node:test";
import assert from "node:assert/strict";
import { project, PROJECTION_SEED, signColumn } from "../src/project.mjs";

function norm(v) { return Math.sqrt(v.reduce((s, x) => s + x * x, 0)); }

test("project: deterministic, 8-dim, finite", () => {
  const v = Array.from({ length: 1024 }, (_, i) => Math.sin(i * 0.1));
  const a = project(v);
  const b = project(v);
  assert.equal(a.length, 8);
  assert.deepEqual(a, b, "same embedding -> identical content (reproducible)");
  assert.ok(a.every(Number.isFinite));
});

test("project: zeros -> zeros, distinct inputs -> distinct outputs", () => {
  assert.deepEqual(project(new Array(1024).fill(0)), new Array(8).fill(0));
  const v1 = Array.from({ length: 1024 }, (_, i) => (i % 3 === 0 ? 1 : 0));
  const v2 = Array.from({ length: 1024 }, (_, i) => (i % 5 === 0 ? 1 : 0));
  assert.notDeepEqual(project(v1), project(v2));
});

test("project: a one-hot e_j yields (1/sqrt(8)) * the j-th sign column", () => {
  // P e_j = (1/sqrt(8)) * column j of the ±1 matrix → each coord is ±1/sqrt(8).
  const e5 = new Array(1024).fill(0); e5[5] = 1;
  const out = project(e5);
  const s = 1 / Math.sqrt(8);
  const col = signColumn(5, 1024); // the 8 signs for input index 5
  for (let k = 0; k < 8; k++) assert.ok(Math.abs(out[k] - s * col[k]) < 1e-12);
});

test("project: approx norm preservation for an L2-normalized embedding (JL, loose at d=8)", () => {
  // bge-m3 is unit-norm; the d=8 sketch preserves norm only roughly — assert it's
  // the right order of magnitude, not degenerate.
  const raw = Array.from({ length: 1024 }, (_, i) => Math.cos(i * 0.37) + 0.2 * Math.sin(i));
  const n = norm(raw);
  const unit = raw.map((x) => x / n);
  const c = norm(project(unit));
  assert.ok(c > 0.2 && c < 5.0, `content norm ${c} is a sane sketch of a unit vector`);
});

test("PROJECTION_SEED is a fixed documented constant", () => {
  assert.equal(typeof PROJECTION_SEED, "number");
});
