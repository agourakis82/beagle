// Content-free pointer records must never reach retrieval.
//
// Measured in production 2026-08-02: 16,723 records whose ENTIRE content is a
// dangling reference of the form `omnimemory:<uuid>` — 47-49 chars, no prose, and
// the UUIDs resolve to nothing (0 of 5 sampled found a matching record). They carry
// embeddings (17,020 of them), so they compete in the dense channel, and they are
// 17,046 of 215,991 chunks — 7.9% of the entire retrieval pool.
//
// The trust filter already hides them from the companion's authoritative grounding
// (they are model_generated), but broadRecall is deliberately unfiltered and feeds
// them straight into the prompt. Either way they burn first-stage slots that a real
// memory could have used.
//
// We drop them at retrieval rather than deleting the rows: the data is someone
// else's to purge, and a WHERE clause is reversible in a way DELETE is not.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { retrieve } from "../src/retrieve.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

function oneHot(axis) {
  const v = new Array(1024).fill(0);
  v[axis] = 1;
  return "[" + v.join(",") + "]";
}

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, embeddings CASCADE"); });
after(async () => { await pool.end(); });

async function seed({ axis, text, tier = "claimed" }) {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, trust_tier)
     VALUES ('T', $1, 'sha-'||gen_random_uuid()::text, $2) RETURNING id`,
    [text, tier],
  );
  const c = await pool.query(
    `INSERT INTO chunks (record_id, chunk_index, text, content_sha256)
     VALUES ($1, 0, $2, 'cs-'||gen_random_uuid()::text) RETURNING id`,
    [r.rows[0].id, text],
  );
  await pool.query(
    `INSERT INTO embeddings (chunk_id, embedding, model_version)
     VALUES ($1, $2::halfvec, 'bge-m3')`,
    [c.rows[0].id, oneHot(axis)],
  );
  return c.rows[0].id;
}

test("a dangling omnimemory pointer never surfaces, even as the nearest vector", async () => {
  // Same axis: the pointer is an EXACT vector match, the real memory is not seeded
  // on that axis at all. Without the drop, the pointer wins outright.
  await seed({ axis: 3, text: "omnimemory:136393b4-f28f-4751-b8e4-1321024c8cb9" });

  const hits = await retrieve(pool, { queryEmbedding: oneHot(3), queryText: "omnimemory", k: 10 });
  assert.equal(hits.length, 0, "a content-free pointer must not be retrievable at all");
});

test("the pointer loses its slot to a real memory", async () => {
  await seed({ axis: 5, text: "omnimemory:cd32d0c7-4e81-4685-9668-c73332b0e140" });
  await seed({ axis: 5, text: "Hoje passei o dia me sentindo angustiado, com vontade de chorar." });

  const hits = await retrieve(pool, { queryEmbedding: oneHot(5), queryText: "sentindo", k: 10 });
  assert.equal(hits.length, 1, "only the real memory survives");
  assert.match(hits[0].text, /angustiado/);
});

test("prose that merely mentions omnimemory is NOT dropped", async () => {
  // The rule keys on "the whole content IS a bare pointer", not on the substring.
  // A real memory discussing the system must survive.
  const text = "Expliquei pra ele que o omnimemory:136393b4 era só um ponteiro quebrado, não memória.";
  await seed({ axis: 9, text });

  const hits = await retrieve(pool, { queryEmbedding: oneHot(9), queryText: "ponteiro", k: 10 });
  assert.equal(hits.length, 1, "prose about pointers is still a real memory");
  assert.equal(hits[0].text, text);
});

test("the drop applies to the lexical channel too, not just the dense one", async () => {
  // BM25 rarely matches a bare uuid for natural language, but a query containing the
  // literal token would — the pointer must be unreachable from BOTH channels.
  await seed({ axis: 11, text: "omnimemory:75442e16-1fe2-4f76-8553-1a90810966f4" });

  const hits = await retrieve(pool, {
    queryEmbedding: oneHot(700), // deliberately far away: only BM25 could surface it
    queryText: "omnimemory 75442e16",
    k: 10,
  });
  assert.equal(hits.length, 0, "unreachable from the lexical channel as well");
});
