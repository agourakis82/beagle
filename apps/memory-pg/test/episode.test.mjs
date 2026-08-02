// expandEpisodes() — the warmth fix.
//
// Recall returns shards: measured in production, the median atom reaching the
// companion's prompt was 53 characters ("minha casa", "meu bem-estar pessoal").
// You cannot be warm about a 53-char fragment — it is the label of a memory, not
// the memory. expandEpisodes() widens each surviving hit back into the scene it
// came from: the neighbouring chunks of the same record, in order.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { expandEpisodes } from "../src/episode.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, embeddings CASCADE"); });
after(async () => { await pool.end(); });

// Seed one record whose text is split across `texts` as ordered chunks.
async function seedRecord(texts, { tier = "claimed" } = {}) {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, trust_tier)
     VALUES ('T', $1, 'sha-'||gen_random_uuid()::text, $2) RETURNING id`,
    [texts.join(" "), tier],
  );
  const recordId = r.rows[0].id;
  const chunkIds = [];
  for (let i = 0; i < texts.length; i++) {
    const c = await pool.query(
      `INSERT INTO chunks (record_id, chunk_index, text, content_sha256)
       VALUES ($1, $2, $3, 'cs-'||gen_random_uuid()::text) RETURNING id`,
      [recordId, i, texts[i]],
    );
    chunkIds.push(c.rows[0].id);
  }
  return { recordId, chunkIds };
}

test("a mid-record shard is expanded into its surrounding scene, in order", async () => {
  const { recordId, chunkIds } = await seedRecord([
    "Hoje passei o dia me sentindo",
    "angustiado, com vontade de chorar,",
    "e mesmo assim fui trabalhar no compilador.",
  ]);

  const [hit] = await expandEpisodes(pool, [
    { chunk_id: chunkIds[1], record_id: recordId, text: "angustiado, com vontade de chorar," },
  ], { radius: 1 });

  assert.equal(
    hit.text,
    "Hoje passei o dia me sentindo angustiado, com vontade de chorar, e mesmo assim fui trabalhar no compilador.",
    "the neighbours must be stitched back in reading order",
  );
  assert.equal(hit.hit_text, "angustiado, com vontade de chorar,", "the matched shard stays available");
  assert.equal(hit.expanded, true);
});

test("overlapping windows from the same record collapse into ONE episode", async () => {
  // Two hits two chunks apart: naively expanding each would repeat the shared
  // middle chunk in the prompt, spending the companion's scarce context on an echo.
  const { recordId, chunkIds } = await seedRecord(["um", "dois", "tres", "quatro", "cinco"]);

  const out = await expandEpisodes(pool, [
    { chunk_id: chunkIds[1], record_id: recordId, text: "dois" },
    { chunk_id: chunkIds[3], record_id: recordId, text: "quatro" },
  ], { radius: 1 });

  assert.equal(out.length, 1, "the two overlapping windows merge");
  assert.equal(out[0].text, "um dois tres quatro cinco");
});

test("non-overlapping hits in the same record stay as separate scenes", async () => {
  const { recordId, chunkIds } = await seedRecord(["a", "b", "c", "d", "e", "f", "g", "h", "i"]);

  const out = await expandEpisodes(pool, [
    { chunk_id: chunkIds[0], record_id: recordId, text: "a" },
    { chunk_id: chunkIds[8], record_id: recordId, text: "i" },
  ], { radius: 1 });

  assert.equal(out.length, 2, "distant windows are distinct memories, not one blob");
  assert.deepEqual(out.map((h) => h.text), ["a b", "h i"]);
});

test("expansion is capped so one long record cannot eat the whole prompt", async () => {
  const long = "x".repeat(900);
  const { recordId, chunkIds } = await seedRecord([long, "meio", long]);

  const [hit] = await expandEpisodes(pool, [
    { chunk_id: chunkIds[1], record_id: recordId, text: "meio" },
  ], { radius: 1, maxChars: 400 });

  assert.ok(hit.text.length <= 400, `expected <=400 chars, got ${hit.text.length}`);
  assert.ok(hit.text.includes("meio"), "the matched shard must survive truncation");
});

test("a single-chunk record passes through untouched", async () => {
  const { recordId, chunkIds } = await seedRecord(["Estou construindo algo extraordinário"]);

  const [hit] = await expandEpisodes(pool, [
    { chunk_id: chunkIds[0], record_id: recordId, text: "Estou construindo algo extraordinário" },
  ], { radius: 1 });

  assert.equal(hit.text, "Estou construindo algo extraordinário");
  assert.equal(hit.expanded, false, "nothing was added, so it is not an expansion");
});

test("graph facts and record-less hits survive untouched (never dropped)", async () => {
  // Graph facts carry chunk_id "fact:<uuid>" and no record row. A hit we cannot
  // expand must pass through — losing it would trade warmth for amnesia.
  const out = await expandEpisodes(pool, [
    { chunk_id: "fact:abc", record_id: null, text: "ele mora em São Paulo", source: "graph" },
  ], { radius: 1 });

  assert.equal(out.length, 1);
  assert.equal(out[0].text, "ele mora em São Paulo");
  assert.equal(out[0].expanded, false);
});

test("metadata of the highest-ranked hit wins for a merged episode", async () => {
  const { recordId, chunkIds } = await seedRecord(["um", "dois", "tres"]);

  const out = await expandEpisodes(pool, [
    { chunk_id: chunkIds[0], record_id: recordId, text: "um", rerank_score: 0.9, trust_tier: "claimed" },
    { chunk_id: chunkIds[2], record_id: recordId, text: "tres", rerank_score: 0.2, trust_tier: "claimed" },
  ], { radius: 1 });

  assert.equal(out.length, 1, "windows [0..1] and [1..2] overlap at chunk 1");
  assert.equal(out[0].rerank_score, 0.9, "the merged scene keeps the best hit's score");
});
