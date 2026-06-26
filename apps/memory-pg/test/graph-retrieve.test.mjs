// graph-retrieve.test.mjs — Phase 4, Task 4.4: graph retrieval channel + fusion.
//
// graphRetrieve finds relevant facts by vector similarity AND by multi-hop
// traversal — the value the plan calls out: "a multi-hop question answerable via
// graph that vector-only misses". fuseChannels is the pure RRF merge of the
// dense ⊕ BM25 ⊕ graph ranked lists. Graph tests only touch entities/facts.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { resolveEntity, graphRetrieve, fuseChannels } from "../src/graph.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

function vec(axis, axis2 = null, w = 0) {
  const a = new Array(1024).fill(0);
  a[axis] = 1;
  if (axis2 != null) a[axis2] = w;
  const norm = Math.sqrt(a.reduce((s, x) => s + x * x, 0)) || 1;
  return "[" + a.map((x) => x / norm).join(",") + "]";
}

async function ent(name, type, axis) {
  return (await resolveEntity(pool, { name, type, embedding: axis == null ? null : vec(axis) })).id;
}
async function fact(subjId, predicate, objId, statement, embAxis) {
  const crypto = await import("node:crypto");
  const sha = crypto.createHash("sha256").update(statement).digest("hex");
  await pool.query(
    `INSERT INTO facts (subject_id, predicate, object_id, statement, embedding, content_sha256)
     VALUES ($1,$2,$3,$4,$5::halfvec,$6)`,
    [subjId, predicate, objId, statement, embAxis == null ? null : vec(embAxis), sha],
  );
}

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE entities, facts, pending_graph CASCADE"); });
after(async () => { await pool.end(); });

test("graphRetrieve finds the vector-similar fact", async () => {
  const a = await ent("Sounio", "project", 1);
  const b = await ent("Rust", "lang", 2);
  await fact(a, "written_in", b, "Sounio is written in Rust", 10); // embedding axis 10
  await fact(a, "has_feature", null, "Sounio has effects", 700);    // far axis
  const out = await graphRetrieve(pool, { queryEmbedding: vec(10), k: 5, hops: 0 });
  assert.ok(out.length >= 1);
  assert.match(out[0].statement, /written in Rust/, "vector-nearest fact ranks first");
});

test("multi-hop surfaces a fact vector-only would miss", async () => {
  // Query is similar to fact1 (about Demetrios). The ANSWER fact2 (Beagle->cluster)
  // has an orthogonal embedding, so vector-only (hops=0) misses it; but it's 1 hop
  // away via the shared entity Beagle, so hops>=1 surfaces it.
  const dem = await ent("Demetrios", "person", 1);
  const beagle = await ent("Beagle", "project", 2);
  const cluster = await ent("t560-cluster", "system", 3);
  await fact(dem, "built", beagle, "Demetrios built Beagle", 10);          // query-similar
  await fact(beagle, "runs_on", cluster, "Beagle runs on the t560 cluster", 800); // far embedding

  const q = vec(10);
  const noHop = await graphRetrieve(pool, { queryEmbedding: q, k: 5, hops: 0 });
  assert.ok(!noHop.some((f) => /runs on the t560/.test(f.statement)), "vector-only misses the 1-hop fact");

  const hop1 = await graphRetrieve(pool, { queryEmbedding: q, k: 10, hops: 1 });
  assert.ok(hop1.some((f) => /runs on the t560/.test(f.statement)), "1-hop traversal surfaces it");
});

test("graphRetrieve ignores invalidated facts", async () => {
  const a = await ent("X", "thing", 1);
  const b = await ent("Y", "thing", 2);
  const crypto = await import("node:crypto");
  const sha = crypto.createHash("sha256").update("X located_in Y old").digest("hex");
  await pool.query(
    `INSERT INTO facts (subject_id, predicate, object_id, statement, embedding, content_sha256, valid_to)
     VALUES ($1,'located_in',$2,'X located_in Y old',$3::halfvec,$4, now())`,
    [a, b, vec(10), sha],
  );
  const out = await graphRetrieve(pool, { queryEmbedding: vec(10), k: 5, hops: 0 });
  assert.equal(out.length, 0, "invalidated (valid_to set) facts are excluded");
});

test("fuseChannels RRF-merges dense/bm25/graph ranked lists", () => {
  // chunk c1 tops dense; chunk c2 tops bm25; fact f1 tops graph.
  const dense = [{ key: "c1" }, { key: "c2" }];
  const bm25 = [{ key: "c2" }, { key: "c3" }];
  const graph = [{ key: "f1", statement: "a fact" }];
  const fused = fuseChannels([
    { items: dense, keyOf: (x) => x.key },
    { items: bm25, keyOf: (x) => x.key },
    { items: graph, keyOf: (x) => x.key },
  ], { k: 60 });
  // c2 appears in dense(#2)+bm25(#1) → highest combined RRF; everything present once.
  assert.equal(fused[0].key, "c2");
  const keys = fused.map((x) => x.key).sort();
  assert.deepEqual(keys, ["c1", "c2", "c3", "f1"]);
  // each fused item carries its rrf score
  assert.ok(fused.every((x) => typeof x.rrf === "number"));
});
