// backfill.test.mjs — Phase 3, Task 3.1.
//
// TDD for the migration backfill importer. The legacy beagle-core export is a
// single JSON document with episodes/atoms/worlds/passages arrays; the dead
// LanceDB worker flattened it via iter_candidates (privacy filter, kind→text
// selection, passage expansion). The importer reproduces the *invariants* of
// that flattening — exclude `restricted`, text-bearing rows only, idempotent —
// and feeds each row through the same ACID `captureRecord` the live pipeline
// uses, so a re-run is a no-op and HNSW is rebuilt only after the bulk load.
//
// The pure extraction is tested without a DB; backfill()/index helpers run
// against the live dedicated memory-pg (DSN from MEMORY_PG_TEST_DSN), isolated
// by a beforeEach TRUNCATE exactly like capture.test.mjs.

import { test, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { makePool } from "../src/db.mjs";
import {
  extractCandidates,
  candidateToRecord,
  backfill,
  dropEmbeddingIndex,
  rebuildEmbeddingIndex,
} from "../src/backfill.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE = join(__dirname, "fixtures", "export_small.json");

// ---- pure extraction (no DB) ----

test("extractCandidates: privacy filter + kind selection + passage-per-turn", () => {
  const exp = {
    episodes: [
      { id: "ep1", summary: "first episode summary", privacy_class: "sensitive", occurred_at: "2026-01-01" },
    ],
    atoms: [
      { id: "at1", text: "an atom of meaning", content_hash: "h-at1", privacy_class: "sensitive" },
      { id: "at2", normalized_text: "restricted atom", privacy_class: "restricted" },
    ],
    worlds: [
      { id: "w1", label: "World One", summary: "a world", project_slug: "p", merkle_root: "m", privacy_class: "sensitive" },
    ],
    passages: [
      {
        id: "pa1", privacy_class: "sensitive", occurred_at: "2026-02-02",
        session_id: "s1", source_platform: "claude",
        turns: [{ content: "hello world this is a turn long enough to chunk" }, { content: "" }],
      },
    ],
  };

  const cands = extractCandidates(exp);
  const ids = cands.map((c) => c.canonical_id);

  // episode, atom at1, world, one passage record for the non-empty turn 0.
  assert.deepEqual(ids.sort(), ["at1", "ep1", "passage:pa1:0", "w1"]);
  // restricted at2 excluded.
  assert.ok(!ids.includes("at2"), "restricted record excluded");
  // every candidate is text-bearing.
  assert.ok(cands.every((c) => c.content.trim().length > 0), "all text-bearing");
  // kinds carried through as source_type.
  const byId = Object.fromEntries(cands.map((c) => [c.canonical_id, c]));
  assert.equal(byId["ep1"].kind, "MemoryEpisode");
  assert.equal(byId["at1"].kind, "MemoryAtom");
  assert.equal(byId["w1"].kind, "MemoryWorld");
  assert.equal(byId["passage:pa1:0"].kind, "ConversationPassage");
  // occurred_at carried from the parent passage to the turn record.
  assert.equal(byId["passage:pa1:0"].occurred_at, "2026-02-02");
});

test("extractCandidates: empty / whitespace-only records produce nothing", () => {
  const cands = extractCandidates({
    episodes: [{ id: "e", summary: "   ", privacy_class: "sensitive" }],
    atoms: [{ id: "a", text: "", privacy_class: "sensitive" }],
    worlds: [],
    passages: [{ id: "p", privacy_class: "sensitive", turns: [{ content: "  " }] }],
  });
  assert.equal(cands.length, 0);
});

test("candidateToRecord: maps kind→source_type, empty occurred_at→null, carries provenance metadata", () => {
  const [cand] = extractCandidates({
    episodes: [], worlds: [], passages: [],
    atoms: [{ id: "at1", text: "an atom of meaning", content_hash: "h-at1", privacy_class: "sensitive", provenance: { src: "x" } }],
  });
  const rec = candidateToRecord(cand);
  assert.equal(rec.source_type, "MemoryAtom");
  assert.equal(rec.content, "an atom of meaning");
  assert.equal(rec.privacy_class, "sensitive");
  assert.equal(rec.occurred_at, null, "empty occurred_at coerced to null");
  assert.equal(rec.metadata.canonical_id, "at1");
  assert.equal(rec.metadata.content_hash, "h-at1");
  assert.deepEqual(rec.metadata.provenance, { src: "x" });
});

// ---- DB-backed: backfill + index helpers ----

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) {
  throw new Error("MEMORY_PG_TEST_DSN must be set (port-forwarded memory-pg DSN)");
}
const pool = makePool(DSN);

beforeEach(async () => {
  await pool.query(
    "TRUNCATE records, chunks, embeddings, pending_embeddings, failed_embeddings CASCADE",
  );
});

after(async () => {
  await pool.end();
});

test("backfill: imports the fixture, idempotent on re-run", async () => {
  const first = await backfill(pool, FIXTURE);
  assert.equal(first.seen, 4, "4 candidates seen");
  assert.equal(first.created, 4, "4 records created");
  assert.equal(first.duplicate, 0);
  assert.equal(first.restricted_excluded, 1, "restricted at2 counted");

  const recs = await pool.query("SELECT count(*)::int AS n FROM records");
  const pend = await pool.query("SELECT count(*)::int AS n FROM pending_embeddings");
  assert.equal(recs.rows[0].n, 4, "4 records persisted");
  assert.equal(pend.rows[0].n, 4, "4 embed-queue rows enqueued");

  // Re-run is a pure no-op: same corpus, zero new records.
  const second = await backfill(pool, FIXTURE);
  assert.equal(second.created, 0, "re-run creates nothing");
  assert.equal(second.duplicate, 4, "re-run sees all 4 as duplicates");
  const recs2 = await pool.query("SELECT count(*)::int AS n FROM records");
  assert.equal(recs2.rows[0].n, 4, "still exactly 4 records");
});

test("index helpers: drop then rebuild the HNSW index (build-after-bulk-load)", async () => {
  const present = async () =>
    (await pool.query(
      "SELECT 1 FROM pg_indexes WHERE indexname = 'embeddings_hnsw'",
    )).rowCount > 0;

  await rebuildEmbeddingIndex(pool); // ensure baseline present (idempotent)
  assert.equal(await present(), true, "index present after rebuild");

  await dropEmbeddingIndex(pool);
  assert.equal(await present(), false, "index dropped");

  await rebuildEmbeddingIndex(pool);
  assert.equal(await present(), true, "index rebuilt");
});
