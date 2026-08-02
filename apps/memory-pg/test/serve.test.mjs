// serve.test.mjs — Phase 2, Task 2.3: the retrieval HTTP API.
//
// No cluster: createApp() takes injectable deps (pool, embedFn, retrieveFn,
// rerankFn) so the embed -> retrieve -> rerank pipeline is exercised end-to-end
// against stubs. We assert: /healthz; /query returns reranked results in order;
// auth gate (401 without token when a token is set, 200 when unset).

import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../bin/serve.mjs";

// Stub captureFn: records the capture-ready records it was handed and reports
// each as newly created. Lets us assert /capture's extraction+routing without a DB.
function makeCaptureStub() {
  const seen = [];
  const captureFn = async (recs) => {
    seen.push(...recs);
    return recs.map((_, i) => ({ id: `id-${seen.length - recs.length + i}`, created: true }));
  };
  return { captureFn, seen };
}

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

test("POST /capture extracts a raw atom record and routes it to captureFn", async () => {
  const s = makeStubs();
  const cap = makeCaptureStub();
  const app = createApp({ pool: {}, ...s, captureFn: cap.captureFn });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/capture", {
      kind: "MemoryAtom",
      record: { id: "at1", text: "an atom of meaning", content_hash: "h-at1", privacy_class: "sensitive" },
    });
    assert.equal(r.status, 200);
    const j = await r.json();
    assert.equal(j.ok, true);
    assert.equal(j.total, 1);
    assert.equal(j.created, 1);
    // the record handed to captureFn is the capture-ready shape (kind -> source_type, text -> content)
    assert.equal(cap.seen.length, 1);
    assert.equal(cap.seen[0].source_type, "MemoryAtom");
    assert.equal(cap.seen[0].content, "an atom of meaning");
    assert.equal(cap.seen[0].metadata.canonical_id, "at1");
  });
});

test("POST /capture expands a passage into one record per non-empty turn", async () => {
  const s = makeStubs();
  const cap = makeCaptureStub();
  const app = createApp({ pool: {}, ...s, captureFn: cap.captureFn });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/capture", {
      kind: "ConversationPassage",
      record: {
        id: "pa1", privacy_class: "sensitive", occurred_at: "2026-02-02",
        turns: [{ content: "hello world this is a turn long enough" }, { content: "" }, { content: "second real turn here" }],
      },
    });
    assert.equal(r.status, 200);
    const j = await r.json();
    assert.equal(j.total, 2, "two non-empty turns -> two records");
    assert.deepEqual(cap.seen.map((x) => x.metadata.canonical_id), ["passage:pa1:0", "passage:pa1:2"]);
  });
});

test("POST /capture skips a restricted record (0 captured), still 200", async () => {
  const s = makeStubs();
  const cap = makeCaptureStub();
  const app = createApp({ pool: {}, ...s, captureFn: cap.captureFn });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/capture", {
      kind: "MemoryAtom",
      record: { id: "x", normalized_text: "secret", privacy_class: "restricted" },
    });
    assert.equal(r.status, 200);
    const j = await r.json();
    assert.equal(j.total, 0);
    assert.equal(cap.seen.length, 0, "restricted never reaches captureFn");
  });
});

test("POST /capture rejects missing kind/record with 400", async () => {
  const s = makeStubs();
  const cap = makeCaptureStub();
  const app = createApp({ pool: {}, ...s, captureFn: cap.captureFn });
  await withServer(app, async (base) => {
    assert.equal((await jpost(base, "/capture", { record: {} })).status, 400);
    assert.equal((await jpost(base, "/capture", { kind: "MemoryAtom" })).status, 400);
  });
});

test("POST /capture 401 without token when ingestToken set", async () => {
  const s = makeStubs();
  const cap = makeCaptureStub();
  const app = createApp({ pool: {}, ...s, captureFn: cap.captureFn, ingestToken: "ings3cret" });
  await withServer(app, async (base) => {
    const body = { kind: "MemoryAtom", record: { id: "a", text: "hi there friend", privacy_class: "sensitive" } };
    assert.equal((await jpost(base, "/capture", body)).status, 401);
    assert.equal(
      (await jpost(base, "/capture", body, { authorization: "Bearer ings3cret" })).status,
      200,
    );
  });
});

test("POST /query fuses graph facts into candidates when graphEnabled", async () => {
  const s = makeStubs();
  // graph returns a fact whose statement contains the query term → rerank floats it up.
  const graphRetrieveFn = async () => [
    { fact_id: "f1", statement: "quantum tunneling underlies the effect", source_record_id: "rg" },
  ];
  const app = createApp({ pool: {}, ...s, graphEnabled: true, graphRetrieveFn });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/query", { query: "quantum", k: 5 });
    assert.equal(r.status, 200);
    const j = await r.json();
    const fact = j.results.find((x) => x.source === "graph");
    assert.ok(fact, "a graph-sourced result is present");
    assert.equal(fact.chunk_id, "fact:f1");
    assert.match(fact.text, /quantum tunneling/);
  });
});

test("POST /query graph fusion is fail-soft (graph error → chunks still returned)", async () => {
  const s = makeStubs();
  const graphRetrieveFn = async () => {
    throw new Error("graph down");
  };
  const app = createApp({ pool: {}, ...s, graphEnabled: true, graphRetrieveFn });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/query", { query: "quantum", k: 5 });
    assert.equal(r.status, 200, "graph failure does not break /query");
    const j = await r.json();
    assert.ok(j.results.length > 0, "chunk results still returned");
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

// --- resilience + warmth (added 2026-08-02 after the silent-recall outage) ---

test("POST /query survives a dead reranker: blunter memory, never no memory", async () => {
  // The real failure: reranker-gpu sat scaled to 0, rerank threw ECONNREFUSED, and
  // /query answered 500 to every recall — so the companion ran with no grounding
  // at all and nothing alerted. First-stage RRF order is a fine fallback.
  const s = makeStubs();
  const app = createApp({
    pool: {},
    ...s,
    rerankFn: async () => {
      throw new Error("fetch failed: ECONNREFUSED 10.96.4.234:80");
    },
  });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/query", { query: "quantum", k: 3 });
    assert.equal(r.status, 200, "a dead reranker must not 500 the whole recall");
    const j = await r.json();
    assert.equal(j.ok, true);
    assert.equal(j.reranked, false, "the caller is told the ranking is degraded");
    assert.equal(j.results.length, 3, "first-stage candidates are served as-is");
    assert.equal(j.results[0].record_id, "r1", "first-stage RRF order preserved");
  });
});

test("POST /query expands surviving hits into episodes", async () => {
  const s = makeStubs();
  const expandCalls = [];
  const app = createApp({
    pool: {},
    ...s,
    expandFn: async (_pool, hits, opts) => {
      expandCalls.push({ hits, opts });
      return hits.map((h) => ({ ...h, text: `<<${h.text}>>`, hit_text: h.text, expanded: true }));
    },
  });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/query", { query: "quantum", k: 3 });
    const j = await r.json();
    assert.equal(j.results[0].text, "<<quantum entanglement basics>>", "the scene, not the shard");
    assert.equal(j.results[0].hit_text, "quantum entanglement basics");
    assert.equal(expandCalls.length, 1, "expansion runs once, on the final list");
    assert.ok(expandCalls[0].hits.length <= 3, "never on the full first-stage pool");
  });
});

test("POST /query keeps the shards when expansion fails", async () => {
  const s = makeStubs();
  const app = createApp({
    pool: {},
    ...s,
    expandFn: async () => {
      throw new Error("chunks table unavailable");
    },
  });
  await withServer(app, async (base) => {
    const r = await jpost(base, "/query", { query: "quantum", k: 3 });
    assert.equal(r.status, 200, "expansion is a bonus; its failure must not blank recall");
    const j = await r.json();
    assert.equal(j.results[0].text, "quantum entanglement basics");
  });
});
