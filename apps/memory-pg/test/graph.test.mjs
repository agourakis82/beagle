// graph.test.mjs — Phase 4, Task 4.2: entity resolution over the bi-temporal graph.
//
// resolveEntity dedups entities two ways: an exact normalized-name match, and a
// near-duplicate match by embedding cosine similarity (different surface forms of
// the same entity — "Demetrios" vs "Demetrios Agourakis"). Runs against the live
// memory-pg, but only TRUNCATEs the NEW graph tables (entities/facts/pending_graph)
// — never records/chunks/embeddings — so it is safe during/after the migration.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { resolveEntity, normalizeEntityName } from "../src/graph.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (port-forwarded memory-pg DSN)");
const pool = makePool(DSN);

// unit halfvec literal mostly on `axis`, with optional `w` weight on `axis2`.
function vec(axis, axis2 = null, w = 0) {
  const a = new Array(1024).fill(0);
  a[axis] = 1;
  if (axis2 != null) a[axis2] = w;
  const norm = Math.sqrt(a.reduce((s, x) => s + x * x, 0)) || 1;
  return "[" + a.map((x) => x / norm).join(",") + "]";
}

before(async () => {
  await ensureSchema(pool); // creates entities/facts/pending_graph if absent
});

beforeEach(async () => {
  await pool.query("TRUNCATE entities, facts, pending_graph CASCADE");
});

after(async () => {
  await pool.end();
});

test("normalizeEntityName lowercases + collapses whitespace", () => {
  assert.equal(normalizeEntityName("  Demetrios   Agourakis "), "demetrios agourakis");
});

test("resolving the same entity twice yields one node", async () => {
  const a = await resolveEntity(pool, { name: "Sounio", type: "project", embedding: vec(1) });
  const b = await resolveEntity(pool, { name: "Sounio", type: "project", embedding: vec(1) });
  assert.equal(a.created, true);
  assert.equal(b.created, false, "second resolve reuses the node");
  assert.equal(b.id, a.id);
  const n = await pool.query("SELECT count(*)::int n FROM entities");
  assert.equal(n.rows[0].n, 1, "exactly one entity node");
});

test("exact normalized-name match merges different casing/spacing", async () => {
  const a = await resolveEntity(pool, { name: "Beagle Platform", type: "project" });
  const b = await resolveEntity(pool, { name: "  beagle   platform ", type: "project" });
  assert.equal(b.id, a.id, "normalized name dedups");
  assert.equal((await pool.query("SELECT count(*)::int n FROM entities")).rows[0].n, 1);
});

test("near-duplicate name + similar embedding is merged by cosine threshold", async () => {
  // "Demetrios" at axis 0; "Demetrios Agourakis" embedding ~0.96 cosine to it.
  const a = await resolveEntity(pool, { name: "Demetrios", type: "person", embedding: vec(0) });
  const b = await resolveEntity(pool, {
    name: "Demetrios Agourakis",
    type: "person",
    embedding: vec(0, 5, 0.3), // cosine to vec(0) ≈ 0.958 > threshold
  });
  assert.equal(b.created, false, "near-duplicate merged, not a new node");
  assert.equal(b.id, a.id);
  assert.equal((await pool.query("SELECT count(*)::int n FROM entities")).rows[0].n, 1);
});

test("a genuinely different entity gets its own node", async () => {
  const a = await resolveEntity(pool, { name: "Demetrios", type: "person", embedding: vec(0) });
  const b = await resolveEntity(pool, { name: "OrangeFS", type: "system", embedding: vec(500) });
  assert.notEqual(b.id, a.id);
  assert.equal(b.created, true);
  assert.equal((await pool.query("SELECT count(*)::int n FROM entities")).rows[0].n, 2);
});

test("dissimilar embedding with a different name is NOT merged (no false positive)", async () => {
  // same type, different name, orthogonal embedding → must stay distinct.
  await resolveEntity(pool, { name: "Ceph", type: "system", embedding: vec(10) });
  const b = await resolveEntity(pool, { name: "Slurm", type: "system", embedding: vec(900) });
  assert.equal(b.created, true, "orthogonal embedding is a new entity");
  assert.equal((await pool.query("SELECT count(*)::int n FROM entities")).rows[0].n, 2);
});
