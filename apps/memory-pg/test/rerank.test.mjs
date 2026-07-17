// rerank.test.mjs — Phase 2, Task 2.2.
//
// TDD for the cross-encoder rerank stage. NO cluster needed: rerankFn is stubbed
// so the test is pure and deterministic. The stub scores each candidate by a
// crude substring overlap with the query (more query words present -> higher
// score), which is enough to assert that rerank() reorders by the score the
// rerankFn returns, truncates to topN, is stable on ties, and handles empty.

import { test } from "node:test";
import assert from "node:assert/strict";
import { rerank, makeTeiRerankFn, cleanResults } from "../src/rerank.mjs";

// Stub rerankFn: returns scores ALIGNED to input order. Scores by the number of
// query tokens that appear in the text (substring match), normalized lightly.
function substringRerankFn(query, texts) {
  const qTokens = query.toLowerCase().split(/\s+/).filter(Boolean);
  return texts.map((t) => {
    const lt = t.toLowerCase();
    let hits = 0;
    for (const q of qTokens) if (lt.includes(q)) hits += 1;
    return hits;
  });
}

function cand(chunk_id, text) {
  return { chunk_id, record_id: "r-" + chunk_id, text };
}

// ---- cleanResults: post-rerank sharpening (empty-drop + floor + dedup) ----

test("cleanResults drops empty / whitespace-only text (kills blank graph facts)", () => {
  const out = cleanResults(
    [
      { chunk_id: "a", text: "real content", rerank_score: 0.9 },
      { chunk_id: "b", text: "   ", rerank_score: 0.8 },
      { chunk_id: "c", text: "", rerank_score: 0.7 },
      { chunk_id: "d", text: null, rerank_score: 0.6 },
    ],
    { floor: 0 },
  );
  assert.deepEqual(out.map((r) => r.chunk_id), ["a"]);
});

test("cleanResults applies the relevance floor (junk below floor is dropped, not padded)", () => {
  const out = cleanResults(
    [
      { chunk_id: "good", text: "on topic", rerank_score: 0.9 },
      { chunk_id: "junk", text: "zombie process log", rerank_score: 0.126 },
    ],
    { floor: 0.2 },
  );
  assert.deepEqual(out.map((r) => r.chunk_id), ["good"]);
});

test("cleanResults floor is an inclusive lower bound; missing score is kept", () => {
  const out = cleanResults(
    [
      { chunk_id: "at", text: "x", rerank_score: 0.2 }, // == floor → kept
      { chunk_id: "below", text: "y", rerank_score: 0.199 }, // < floor → dropped
      { chunk_id: "noscore", text: "z" }, // no score → kept
    ],
    { floor: 0.2 },
  );
  assert.deepEqual(out.map((r) => r.chunk_id), ["at", "noscore"]);
});

test("cleanResults dedups by normalized text, keeping the first (highest-ranked)", () => {
  const out = cleanResults(
    [
      { chunk_id: "a", text: "Redes semânticas em depressão", rerank_score: 0.9 },
      { chunk_id: "b", text: "  redes   SEMÂNTICAS  em depressão ", rerank_score: 0.8 },
      { chunk_id: "c", text: "distinct", rerank_score: 0.5 },
    ],
    { floor: 0 },
  );
  assert.deepEqual(out.map((r) => r.chunk_id), ["a", "c"]);
});

test("rerank puts the best cross-encoder match first", async () => {
  const candidates = [
    cand("a", "bananas are yellow and ripe"),
    cand("b", "paris is the capital of france"),
    cand("c", "the weather is cold today"),
  ];
  const out = await rerank("what is the capital of france", candidates, {
    rerankFn: substringRerankFn,
  });
  assert.equal(out[0].chunk_id, "b", "the paris doc ranks first");
  assert.ok(out[0].rerank_score > out[1].rerank_score, "scores are descending");
  // every returned candidate carries a rerank_score
  for (const r of out) assert.equal(typeof r.rerank_score, "number");
});

test("topN truncates to the requested count", async () => {
  const candidates = [
    cand("a", "the capital of france is paris"),
    cand("b", "france france capital"),
    cand("c", "capital city"),
    cand("d", "totally unrelated text"),
  ];
  const out = await rerank("capital france paris", candidates, {
    rerankFn: substringRerankFn,
    topN: 2,
  });
  assert.equal(out.length, 2, "only topN returned");
  // The two highest scorers are kept (a has 3 hits, b has 2 hits).
  assert.deepEqual(out.map((r) => r.chunk_id), ["a", "b"]);
});

test("ties preserve input order (stable sort)", async () => {
  // All three texts contain the single query token exactly once -> equal scores.
  const candidates = [
    cand("x", "alpha token here"),
    cand("y", "another token line"),
    cand("z", "final token entry"),
  ];
  const out = await rerank("token", candidates, {
    rerankFn: substringRerankFn,
  });
  assert.deepEqual(
    out.map((r) => r.chunk_id),
    ["x", "y", "z"],
    "tied candidates keep their original relative order",
  );
});

test("empty candidates -> empty array (rerankFn not called)", async () => {
  let called = false;
  const out = await rerank(
    "anything",
    [],
    {
      rerankFn: () => {
        called = true;
        return [];
      },
    },
  );
  assert.deepEqual(out, []);
  assert.equal(called, false, "rerankFn skipped for empty candidates");
});

test("topN larger than candidate count returns all", async () => {
  const candidates = [cand("a", "paris france"), cand("b", "berlin germany")];
  const out = await rerank("france", candidates, {
    rerankFn: substringRerankFn,
    topN: 100,
  });
  assert.equal(out.length, 2);
});

test("rerankFn returning {index,score} pairs is supported", async () => {
  // Some rerankers (TEI) return [{index, score}] in arbitrary order. rerank()
  // must realign by index, not assume positional alignment.
  const candidates = [cand("a", "first"), cand("b", "second"), cand("c", "third")];
  const pairFn = () => [
    { index: 2, score: 9 },
    { index: 0, score: 5 },
    { index: 1, score: 1 },
  ];
  const out = await rerank("q", candidates, { rerankFn: pairFn });
  assert.deepEqual(out.map((r) => r.chunk_id), ["c", "a", "b"]);
  assert.equal(out[0].rerank_score, 9);
});

test("makeTeiRerankFn POSTs {query,texts} and returns index-aligned scores", async () => {
  // Stub global fetch to assert the request shape and return a TEI-style body.
  const calls = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init });
    const body = JSON.parse(init.body);
    // TEI returns [{index, score}] possibly unsorted.
    const out = body.texts.map((t, i) => ({
      index: i,
      score: t.includes("paris") ? 0.99 : 0.01,
    }));
    // shuffle to prove realignment
    out.reverse();
    return { ok: true, json: async () => out };
  };
  try {
    const fn = makeTeiRerankFn("http://memory-pg-reranker.beagle.svc.cluster.local:80");
    const scores = await fn("capital of france", [
      "bananas are yellow",
      "paris is the capital of france",
    ]);
    // scores aligned to INPUT order: index 0 (bananas) low, index 1 (paris) high
    assert.equal(scores.length, 2);
    assert.ok(scores[1] > scores[0], "paris (input idx 1) scores higher");
    const sent = JSON.parse(calls[0].init.body);
    assert.equal(calls[0].url, "http://memory-pg-reranker.beagle.svc.cluster.local:80/rerank");
    assert.equal(sent.query, "capital of france");
    assert.deepEqual(sent.texts, ["bananas are yellow", "paris is the capital of france"]);
    assert.equal(calls[0].init.method, "POST");
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("makeTeiRerankFn splits >maxBatch texts into sub-batches (TEI caps batch at 32)", async () => {
  // The TEI reranker rejects batches > 32 (HTTP 422). A first-stage retrieve can
  // return up to 50 candidates, so the rerank fn must sub-batch and merge scores
  // index-aligned to the FULL input, not send all 50 at once.
  const calls = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    const body = JSON.parse(init.body);
    assert.ok(body.texts.length <= 32, `sub-batch ${body.texts.length} must be <= 32`);
    calls.push(body.texts.length);
    return { ok: true, json: async () => body.texts.map((t, i) => ({ index: i, score: Number(t.split("#")[1]) })) };
  };
  try {
    const fn = makeTeiRerankFn("http://reranker", { maxBatch: 32 });
    const texts = Array.from({ length: 50 }, (_, i) => `doc#${i}`);
    const scores = await fn("q", texts);
    assert.equal(scores.length, 50, "score per input across sub-batches");
    // global alignment: each doc's score equals its global index.
    for (let i = 0; i < 50; i++) assert.equal(scores[i], i, `score[${i}] aligned`);
    assert.deepEqual(calls, [32, 18], "two sub-batches: 32 then 18");
  } finally {
    globalThis.fetch = realFetch;
  }
});
