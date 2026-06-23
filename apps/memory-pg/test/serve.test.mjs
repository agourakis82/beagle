// serve.test.mjs — Phase 2, Task 2.3: the retrieval HTTP API.
//
// No cluster: createApp() takes injectable deps (pool, embedFn, retrieveFn,
// rerankFn) so the embed -> retrieve -> rerank pipeline is exercised end-to-end
// against stubs. We assert: /healthz; /query returns reranked results in order;
// auth gate (401 without token when a token is set, 200 when unset).

import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../bin/serve.mjs";

// Minimal HTTP helper: start the express app on an ephemeral port, fetch, stop.
async function withServer(app, fn) {
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;
  try {
    return await fn(base);
  } finally {
    await new Promise((r) => server.close(r));
  }
}

function jpost(base, path, body, headers = {}) {
  return fetch(base + path, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

// Stub deps: the embedFn returns one 1024-dim vector; retrieveFn returns a fixed
// candidate set (out of relevance order); rerankFn re-scores so the candidate
// whose text contains the query word floats to the top.
function makeStubs() {
  const embedCalls = [];
  const embedFn = async (texts) => {
    embedCalls.push(texts);
    return texts.map(() => new Array(1024).fill(0.01));
  };

  const candidates = [
    { chunk_id: "c1", record_id: "r1", text: "the cat sat on the mat", occurred_at: "2026-01-01T00:00:00Z" },
    { chunk_id: "c2", record_id: "r2", text: "quantum entanglement basics", occurred_at: "2026-02-01T00:00:00Z" },
    { chunk_id: "c3", record_id: "r3", text: "a dog barked at the moon", occurred_at: "2026-03-01T00:00:00Z" },
  ];
  const retrieveCalls = [];
  const retrieveFn = async (pool, opts) => {
    retrieveCalls.push(opts);
    return candidates;
  };

  // rerankFn: score = does the text contain the query string? higher = better.
  const rerankCalls = [];
  const rerankFn = async (query, texts) => {
    rerankCalls.push({ query, texts });
    return texts.map((t, index) => ({
      index,
      score: t.includes(query) ? 1.0 : 0.0 - index * 0.001,
    }));
  };

  return { embedFn, retrieveFn, rerankFn, embedCalls, retrieveCalls, rerankCalls };
}

test("GET /healthz returns ok", async () => {
  const s = makeStubs();
  const app = createApp({ pool: {}, ...s });
  await withServer(app, async (base) => {
    const r = await fetch(base + "/healthz");
    assert.equal(r.status, 200);
    const j = await r.json();
    assert.deepEqual(j, { ok: true });
  });
});

test("POST /query embeds -> retrieves -> reranks, top result first", async () => {
  const s = makeStubs();
  const app = createApp({ pool: {}, ...s });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/query", { query: "quantum", k: 3 });
    assert.equal(r.status, 200);
    const j = await r.json();
    assert.equal(j.ok, true);
    assert.ok(Array.isArray(j.results));
    // The "quantum entanglement basics" candidate must be reranked to the top.
    assert.equal(j.results[0].record_id, "r2");
    assert.equal(j.results[0].text, "quantum entanglement basics");
    assert.equal(j.results[0].rerank_score, 1.0);
    // Shape: each result carries the contracted fields.
    for (const res of j.results) {
      assert.ok("text" in res && "record_id" in res && "chunk_id" in res);
      assert.ok("rerank_score" in res && "occurred_at" in res);
    }
    // The query was embedded exactly once, as a single text.
    assert.equal(s.embedCalls.length, 1);
    assert.equal(s.embedCalls[0].length, 1);
    assert.equal(s.embedCalls[0][0], "quantum");
    // retrieve got the embedding + query text + a k of 50 (first-stage recall).
    assert.equal(s.retrieveCalls.length, 1);
    assert.equal(s.retrieveCalls[0].queryText, "quantum");
    assert.ok(Array.isArray(s.retrieveCalls[0].queryEmbedding));
    assert.equal(s.retrieveCalls[0].queryEmbedding.length, 1024);
  });
});

test("POST /query rejects missing query with 400", async () => {
  const s = makeStubs();
  const app = createApp({ pool: {}, ...s });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/query", {});
    assert.equal(r.status, 400);
  });
});

test("POST /query 401 without token when queryToken set", async () => {
  const s = makeStubs();
  const app = createApp({ pool: {}, queryToken: "s3cret", ...s });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/query", { query: "quantum" });
    assert.equal(r.status, 401);
    // With the correct token it passes.
    const r2 = await jpost(base, "/query", { query: "quantum" }, { authorization: "Bearer s3cret" });
    assert.equal(r2.status, 200);
  });
});

test("POST /query 200 without token when queryToken unset (dev/open)", async () => {
  const s = makeStubs();
  const app = createApp({ pool: {}, queryToken: "", ...s });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/query", { query: "quantum" });
    assert.equal(r.status, 200);
  });
});

test("POST /query never crashes the server on a failing dep (500)", async () => {
  const s = makeStubs();
  const boom = createApp({
    pool: {},
    embedFn: s.embedFn,
    retrieveFn: async () => {
      throw new Error("db down");
    },
    rerankFn: s.rerankFn,
  });
  await withServer(boom, async (base) => {
    const r = await jpost(base, "/query", { query: "quantum" });
    assert.equal(r.status, 500);
    const j = await r.json();
    assert.ok(j.error);
    // Server still alive: a second request also gets a response.
    const r2 = await jpost(base, "/query", { query: "quantum" });
    assert.equal(r2.status, 500);
  });
});
