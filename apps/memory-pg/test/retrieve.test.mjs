// retrieve.test.mjs — Phase 2, Task 2.1.
//
// TDD for hybrid dense+BM25 retrieval with RRF fusion + recency prior.
// Runs against the live dedicated `memory-pg` Postgres (DSN from
// MEMORY_PG_TEST_DSN, normally a port-forward). Each test is isolated by a
// beforeEach TRUNCATE — the instance is dedicated with no real data.
//
// Embeddings are inserted DIRECTLY as hand-chosen 1024-dim one-hot halfvecs so
// cosine distances are fully deterministic (no TEI needed). With one-hot
// vectors, cosine distance is 0 to the same axis and 1 to any other axis, so
// the dense channel's ordering is exactly controllable by axis choice.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { retrieve } from "../src/retrieve.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) {
  throw new Error("MEMORY_PG_TEST_DSN must be set (port-forwarded memory-pg DSN)");
}

const pool = makePool(DSN);
const DIM = 1024;

// A 1024-dim one-hot unit halfvec literal with a 1 at `axis`.
function oneHot(axis) {
  const v = new Array(DIM).fill(0);
  v[axis] = 1;
  return "[" + v.join(",") + "]";
}

// Seed one record + one chunk + one current embedding; return the chunk id.
async function seedDoc({ text, axis, occurred_at = null, sha }) {
  const rec = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, occurred_at, decay_class)
     VALUES ('test', $1, $2, $3, 'tasks') RETURNING id`,
    [text, "rec-" + sha, occurred_at],
  );
  const rid = rec.rows[0].id;
  const chk = await pool.query(
    `INSERT INTO chunks (record_id, chunk_index, text, content_sha256)
     VALUES ($1, 0, $2, $3) RETURNING id`,
    [rid, text, "chk-" + sha],
  );
  const cid = chk.rows[0].id;
  await pool.query(
    `INSERT INTO embeddings (chunk_id, embedding, model_version)
     VALUES ($1, $2::halfvec, 'bge-m3')`,
    [cid, oneHot(axis)],
  );
  return { record_id: rid, chunk_id: cid };
}

before(async () => {
  await ensureSchema(pool);
});

beforeEach(async () => {
  await pool.query(
    "TRUNCATE records, chunks, embeddings, pending_embeddings, failed_embeddings CASCADE",
  );
});

after(async () => {
  await pool.end();
});

test("lexical-only match surfaces via BM25 even with a far embedding", async () => {
  // Query embedding lives on axis 0. Query text contains the rare proper noun.
  const queryEmbedding = oneHot(0);
  const queryText = "Zanzibar";

  // Doc X: contains "Zanzibar" but its embedding is on a FAR axis (500) → dense
  // distance ~1, so it would never surface via dense alone. BM25 must find it.
  const x = await seedDoc({
    text: "Zanzibar elephant migration along the eastern coast",
    axis: 500,
    sha: "x",
  });
  // Noise docs: no "Zanzibar", embeddings on other far axes.
  await seedDoc({ text: "ordinary notes about cats and dogs", axis: 600, sha: "n1" });
  await seedDoc({ text: "weather report for the afternoon", axis: 700, sha: "n2" });

  const out = await retrieve(pool, { queryEmbedding, queryText, k: 10 });
  const ids = out.map((r) => r.chunk_id);
  assert.ok(ids.includes(x.chunk_id), "lexical match X surfaces");
  const xr = out.find((r) => r.chunk_id === x.chunk_id);
  assert.ok(Number.isFinite(xr.bm25_rank), "X has a bm25_rank");
});

test("semantic match surfaces via dense even with no lexical overlap", async () => {
  // Query embedding on axis 42. Query text shares NO tokens with doc Y.
  const queryEmbedding = oneHot(42);
  const queryText = "xylophonics quasar";

  // Doc Y: embedding exactly on axis 42 (cosine distance 0) but text has none
  // of the query tokens → must surface via the dense channel.
  const y = await seedDoc({
    text: "completely unrelated prose about gardening tools",
    axis: 42,
    sha: "y",
  });
  await seedDoc({ text: "another irrelevant note about taxes", axis: 800, sha: "n1" });

  const out = await retrieve(pool, { queryEmbedding, queryText, k: 10 });
  const yr = out.find((r) => r.chunk_id === y.chunk_id);
  assert.ok(yr, "semantic match Y surfaces");
  assert.ok(Number.isFinite(yr.dense_rank), "Y has a dense_rank");
});

test("RRF reinforcement: a doc matching BOTH channels outranks single-channel hits", async () => {
  const queryEmbedding = oneHot(7);
  const queryText = "Zanzibar";

  // Z: matches BM25 ("Zanzibar") AND is the dense nearest (axis 7).
  const z = await seedDoc({
    text: "Zanzibar spice trade routes and harbor logistics",
    axis: 7,
    sha: "z",
  });
  // X: lexical-only (has "Zanzibar", far embedding axis 500).
  const x = await seedDoc({
    text: "Zanzibar is also known for its beaches",
    axis: 500,
    sha: "x",
  });
  // Y: dense-only (no "Zanzibar", but second-closest axis 8).
  const y = await seedDoc({
    text: "harbor logistics primer with no proper nouns",
    axis: 8,
    sha: "y",
  });

  const out = await retrieve(pool, { queryEmbedding, queryText, k: 10 });
  const pos = (cid) => out.findIndex((r) => r.chunk_id === cid);
  assert.ok(pos(z.chunk_id) >= 0, "Z present");
  assert.ok(pos(z.chunk_id) < pos(x.chunk_id), "Z (both) ranks above X (lexical-only)");
  assert.ok(pos(z.chunk_id) < pos(y.chunk_id), "Z (both) ranks above Y (dense-only)");
});

test("recency prior: among ties, the more recent doc ranks higher; alpha tunes it", async () => {
  // Two docs identical in BOTH channels (same text → same BM25 rank tier; same
  // embedding axis → same dense distance), differing ONLY in occurred_at.
  const queryEmbedding = oneHot(0);
  const queryText = "Zanzibar harbor";
  const sameText = "Zanzibar harbor logistics report";

  const older = await seedDoc({
    text: sameText,
    axis: 0,
    occurred_at: "2020-01-01T00:00:00Z",
    sha: "old",
  });
  // distinct content_sha256 handled via sha param; same text/embedding axis.
  const newer = await seedDoc({
    text: sameText + " ",
    axis: 0,
    occurred_at: "2026-06-01T00:00:00Z",
    sha: "new",
  });

  // High alpha (0.95): RRF dominates, recency barely matters — but with the two
  // RRF contributions essentially tied, the recency tiebreak still favors newer.
  const out = await retrieve(pool, {
    queryEmbedding,
    queryText,
    k: 10,
    alpha: 0.7,
  });
  const posNewer = out.findIndex((r) => r.chunk_id === newer.chunk_id);
  const posOlder = out.findIndex((r) => r.chunk_id === older.chunk_id);
  assert.ok(posNewer >= 0 && posOlder >= 0, "both present");
  assert.ok(posNewer < posOlder, "more recent ranks higher at alpha=0.7");

  // Sanity: alpha is tunable and changes the blend. With alpha=1.0 (pure RRF,
  // no recency), the two tied docs get equal recency contribution removed; the
  // newer must still not rank BELOW older purely by recency since recency is
  // gone — order may flip to insertion/score order. We assert the recency
  // weight actually moves scores: newer's score gap shrinks as alpha rises.
  const scoreGap = (rows) => {
    const n = rows.find((r) => r.chunk_id === newer.chunk_id).score;
    const o = rows.find((r) => r.chunk_id === older.chunk_id).score;
    return n - o;
  };
  const gapLowAlpha = scoreGap(
    await retrieve(pool, { queryEmbedding, queryText, k: 10, alpha: 0.3 }),
  );
  const gapHighAlpha = scoreGap(
    await retrieve(pool, { queryEmbedding, queryText, k: 10, alpha: 0.95 }),
  );
  assert.ok(
    gapLowAlpha > gapHighAlpha,
    `lower alpha weights recency more (gap ${gapLowAlpha} should exceed ${gapHighAlpha})`,
  );
});
