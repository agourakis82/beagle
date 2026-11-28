// /capture_turn persists ONE provenance-tagged record. DI'd: a stub captureFn records
// the records handed to it, so we assert provenance pass-through without a database.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../bin/serve.mjs";

function mkStubs() {
  const seen = [];
  const captureFn = async (recs) => {
    seen.push(...recs);
    return recs.map((_, i) => ({ id: `rec-${i}`, created: true, chunk_count: 1 }));
  };
  return {
    seen,
    deps: {
      pool: {},
      embedFn: async () => [[0.1]],
      rerankFn: async () => [],
      captureFn,
    },
  };
}

function listen(app) {
  return new Promise((resolve) => { const s = app.listen(0, () => resolve(s)); });
}
async function jpost(base, path, body) {
  return fetch(base + path, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
  });
}

test("POST /capture_turn passes provenance through to captureRecord and returns the id", async () => {
  const { seen, deps } = mkStubs();
  const app = createApp(deps);
  const s = await listen(app);
  const base = `http://127.0.0.1:${s.address().port}`;
  try {
    const r = await jpost(base, "/capture_turn", {
      source_type: "MemoryAtom",
      content: "Demetrios runs marathons.",
      prov_actor: "model_distilled",
      prov_surface: "companion-ios",
      prov_derived_from: ["11111111-1111-1111-1111-111111111111"],
      prov_confidence: 0.7,
      metadata: { space: "personal" },
    });
    assert.equal(r.status, 200);
    const body = await r.json();
    assert.equal(body.id, "rec-0");
    assert.equal(body.created, true);
    assert.equal(seen.length, 1);
    assert.equal(seen[0].source_type, "MemoryAtom");
    assert.equal(seen[0].prov_actor, "model_distilled");
    assert.deepEqual(seen[0].prov_derived_from, ["11111111-1111-1111-1111-111111111111"]);
    assert.equal(seen[0].prov_confidence, 0.7);
  } finally { s.close(); }
});

test("POST /capture_turn defaults actor to model_generated and derived_from to []", async () => {
  const { seen, deps } = mkStubs();
  const app = createApp(deps);
  const s = await listen(app);
  const base = `http://127.0.0.1:${s.address().port}`;
  try {
    await jpost(base, "/capture_turn", { source_type: "ConversationPassage", content: "hi" });
    assert.equal(seen[0].prov_actor, "model_generated");
    assert.deepEqual(seen[0].prov_derived_from, []);
  } finally { s.close(); }
});

test("POST /capture_turn rejects a missing source_type/content with 400", async () => {
  const { deps } = mkStubs();
  const app = createApp(deps);
  const s = await listen(app);
  const base = `http://127.0.0.1:${s.address().port}`;
  try {
    const r = await jpost(base, "/capture_turn", { content: "no source_type" });
    assert.equal(r.status, 400);
  } finally { s.close(); }
});
