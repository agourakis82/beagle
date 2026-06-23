# Reliable Memory Pipeline (Postgres+pgvector + Graph) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. Phase 1 is execution-ready in full; Phases 2–4 carry concrete tasks + named spikes that are refined as each prior phase lands.

**Goal:** Replace the fragile JSONL+LanceDB+subprocess memory stack with a reliable, incremental, sovereign capture→ingest→retrieve+rerank+graph pipeline unified on the existing `beagle-pg` Postgres.

**Architecture:** New stateless Node service `apps/memory-pg/` owning the new schema + outbox workers + retrieval API, talking to `beagle-pg` and the existing TEI services (bge-m3 embed, bge-reranker-v2-m3 rerank). beagle-core dual-writes during migration; the cockpit retrieval flips behind a feature flag. (Node chosen for TDD velocity + single-user scale; the SKIP-LOCKED loop is trivial in Node. Rust is a later perf option if measured necessary.)

**Tech Stack:** Node 20 + `pg` (node-postgres), Postgres 16 + pgvector ≥0.8.3 + pg_search + Apache AGE, TEI (bge-m3, bge-reranker-v2-m3), node:test, kaniko→`192.168.3.207:5003`, K8s (tolerations + seccomp Unconfined).

**Spec:** `docs/superpowers/specs/2026-06-23-reliable-memory-pipeline-design.md`
**SOTA basis:** `docs/research/2026-06-23-reliable-memory-pipeline-sota.md`

**Branch:** `feat/memory-pg` from `main` (Beagle side). conc-1 only when touching the legacy beagle-core JSONL store during migration ([[project_exocortex_ingest_constraints]]).

---

## Phase 0 — Postgres extensions + schema (foundation)

### Task 0.1: verify/upgrade extensions (spike + gate)

**Files:** `apps/memory-pg/sql/000_extensions.sql`

- [ ] **Step 1:** Check current pgvector version: `kubectl -n beagle exec deploy/beagle-pg -- psql "$DSN" -c "SELECT extname, extversion FROM pg_extension"`. Record it.
- [ ] **Step 2:** Confirm pgvector ≥0.8.3 available in the image; if not, plan the image bump (note: HNSW-vacuum corruption is fixed in 0.8.3). Confirm `pg_search` (ParadeDB) and `age` (Apache AGE) availability for the Postgres image — **this is a spike**: if the stock `beagle-pg` image lacks them, the plan's first real task is building a Postgres image with pgvector+pg_search+age (document which are packaged).
- [ ] **Step 3:** Write `000_extensions.sql`: `CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS pg_search; CREATE EXTENSION IF NOT EXISTS age;` (AGE may be gated behind the spike result — if AGE is dropped for recursive-CTE, omit it).
- [ ] **Step 4:** Report extension availability + decision (AGE vs CTE) before proceeding. Commit.

### Task 0.2: core schema (TDD via a migration runner)

**Files:** `apps/memory-pg/sql/001_core.sql`, `apps/memory-pg/src/db.mjs`, `apps/memory-pg/test/schema.test.mjs`

- [ ] **Step 1: Write the failing test** — `ensureSchema(pool)` then assert `records`, `chunks`, `embeddings`, `pending_embeddings`, `failed_embeddings` exist with the expected columns + the HNSW index on `embeddings(embedding)`.

```js
// schema.test.mjs (excerpt) — runs against a disposable test DB (env PHYSIOME-style DSN)
import { test } from "node:test"; import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
test("schema creates tables + hnsw index", async () => {
  const pool = makePool(process.env.MEMORY_PG_TEST_DSN);
  await ensureSchema(pool);
  const t = await pool.query("select table_name from information_schema.tables where table_schema='public'");
  const names = t.rows.map(r => r.table_name);
  for (const n of ["records","chunks","embeddings","pending_embeddings","failed_embeddings"]) assert.ok(names.includes(n), n);
  const idx = await pool.query("select indexname from pg_indexes where tablename='embeddings'");
  assert.ok(idx.rows.some(r => /hnsw/i.test(r.indexname)));
  await pool.end();
});
```

- [ ] **Step 2: Run, expect FAIL** (no schema). `cd apps/memory-pg && node --test test/schema.test.mjs`
- [ ] **Step 3: Write `001_core.sql`** (the vertical-split schema from the spec):

```sql
CREATE TABLE IF NOT EXISTS records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type text NOT NULL, content text NOT NULL, metadata jsonb NOT NULL DEFAULT '{}',
  occurred_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
  content_sha256 text NOT NULL, privacy_class text NOT NULL DEFAULT 'sensitive',
  decay_class text NOT NULL DEFAULT 'identity', UNIQUE(content_sha256));
CREATE TABLE IF NOT EXISTS chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), record_id uuid NOT NULL REFERENCES records(id) ON DELETE CASCADE,
  chunk_index int NOT NULL, text text NOT NULL, content_sha256 text NOT NULL, UNIQUE(record_id, chunk_index));
CREATE TABLE IF NOT EXISTS embeddings (
  chunk_id uuid NOT NULL REFERENCES chunks(id) ON DELETE CASCADE,
  embedding halfvec(1024) NOT NULL, model_version text NOT NULL, is_current boolean NOT NULL DEFAULT true,
  PRIMARY KEY (chunk_id, model_version), CHECK (l2_norm(embedding) > 0));
CREATE INDEX IF NOT EXISTS embeddings_hnsw ON embeddings USING hnsw (embedding halfvec_cosine_ops)
  WITH (m=16, ef_construction=128) WHERE is_current;
CREATE TABLE IF NOT EXISTS pending_embeddings (
  id bigserial PRIMARY KEY, record_id uuid NOT NULL REFERENCES records(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending', retry_count int NOT NULL DEFAULT 0,
  locked_until timestamptz, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS failed_embeddings (LIKE pending_embeddings INCLUDING ALL);
```

- [ ] **Step 4:** Implement `db.mjs` `makePool` + `ensureSchema` (run the .sql files in order). **Step 5:** Run test → PASS. **Step 6:** Commit.

---

## Phase 1 — Ingestion: outbox + SKIP-LOCKED embed worker (the reliability core)

### Task 1.1: chunking (TDD, pure)

**Files:** `apps/memory-pg/src/chunk.mjs`, `test/chunk.test.mjs`

- [ ] Failing test → implement `chunkText(text, {target=384, overlap=0.1, minChars=40})` returning `[{chunk_index, text, sha256}]` with topic/segment awareness (split on blank-line/turn boundaries first, then pack to ~target tokens ≈ chars/4, ~10% overlap). **content_sha256 computed per chunk** (post-chunking). Tests: short text → 1 chunk; long → multiple with overlap; sha changes when a chunk's text changes. Commit.

### Task 1.2: capture (transactional outbox) (TDD)

**Files:** `apps/memory-pg/src/capture.mjs`, `test/capture.test.mjs`

- [ ] Failing test → implement `captureRecord(pool, {source_type, content, metadata, occurred_at, privacy_class, decay_class})`: one transaction — `INSERT records ... ON CONFLICT (content_sha256) DO NOTHING RETURNING id` + `INSERT chunks` + `INSERT pending_embeddings(record_id)`. Idempotent on content_sha256 (re-capture = no dupe). Test: capture twice → one record, one queue row; concurrent captures (Promise.all) → no corruption, correct counts. Commit.

### Task 1.3: embed worker — SKIP LOCKED loop (TDD, the heart)

**Files:** `apps/memory-pg/src/embed-worker.mjs`, `bin/embed-worker.mjs`, `test/embed-worker.test.mjs`

- [ ] **Step 1: Failing test** (stub TEI embedder) — `runOnce(pool, {embedFn, batch=50})`:
  - claims pending rows via `UPDATE pending_embeddings SET status='processing', locked_until=now()+interval '5 min' WHERE id IN (SELECT id FROM pending_embeddings WHERE status='pending' OR (status='processing' AND locked_until<now()) ORDER BY id FOR UPDATE SKIP LOCKED LIMIT $1) RETURNING *`;
  - for each, loads chunks, embeds via `embedFn`, `INSERT INTO embeddings ... ON CONFLICT (chunk_id, model_version) DO UPDATE SET embedding=excluded.embedding, is_current=true`; deletes the queue row on success; on throw → `retry_count++`, and at >3 moves the row to `failed_embeddings`.
  - asserts: after runOnce, embeddings exist for the record; queue drained; idempotent (run twice = same rows, no dupes); a throwing embedFn increments retry_count; >3 → DLQ.
- [ ] **Step 2: FAIL → Step 3: implement** `embed-worker.mjs` + `bin/embed-worker.mjs` (loop: `runOnce`; sleep when empty; token-bucket throttle for TEI; reaper is inherent via the `locked_until<now()` clause). Real `embedFn` = POST `BEAGLE_TEI_EMBED_URL` (bge-m3) batched. **Step 4: PASS. Step 5: Commit.**
- [ ] **Step 6:** Concurrency test — two `runOnce` in parallel claim disjoint rows (SKIP LOCKED), no double-embed. Commit.

### Task 1.4: worker Deployment + Dockerfile

- [ ] Dockerfile + `k8s/memory-pg/embed-worker.yaml` (Deployment, 1 replica, tolerations sounio.dev/compute+pool, seccomp Unconfined, env DSN from `beagle-pg` secret + `BEAGLE_TEI_EMBED_URL`). Build via kaniko. Deploy to a NON-production schema first. Verify the worker drains a seeded queue with bounded RAM (`kubectl top`). Commit.

---

## Phase 2 — Retrieval + rerank (hybrid → cross-encoder)

### Task 2.1: dense + BM25 + RRF fusion (TDD)

**Files:** `apps/memory-pg/src/retrieve.mjs`, `test/retrieve.test.mjs`

- [ ] Failing test (seed a few records with known content) → implement `retrieve(pool, {queryEmbedding, queryText, k=50, alpha=0.7})`:
  - CTE A dense: `SET LOCAL hnsw.ef_search=80; ... ORDER BY embedding <=> $1 LIMIT 50` (join chunks→records, is_current).
  - CTE B BM25: `... WHERE content @@@ $queryText ORDER BY paradedb.score(id) LIMIT 50` (pg_search).
  - **RRF fuse** (k=60) over the two rank lists (rank-based, never linear-combine), + recency prior `+ (1-alpha)*power(0.5, age_days/half_life(decay_class))`.
  - returns top-50 unique `{chunk_id, record_id, text, score}`. Tests: a lexical-only match is found via BM25; a semantic match via dense; RRF ranks a doc hit by both above singletons; recency prior orders ties by recency. Commit.

### Task 2.2: reranker (bge-reranker-v2-m3) (TDD)

**Files:** `apps/memory-pg/src/rerank.mjs`, `test/rerank.test.mjs`

- [ ] Failing test (stub reranker) → implement `rerank(query, candidates, {rerankFn, topN=10})` calling the TEI cross-encoder, returning reranked top-N. Real `rerankFn` = POST the bge-reranker-v2-m3 TEI service. Deploy that TEI service (`k8s/memory-pg/reranker.yaml`, mirror `beagle-sovereign-reranker`). Commit.

### Task 2.3: retrieval HTTP API + query embedding

**Files:** `apps/memory-pg/bin/serve.mjs`, `test/serve.test.mjs`

- [ ] `POST /query {query, k, tags?}` → embed query (bge-m3) → `retrieve` → `rerank` → top 8–12 `{text, source, score, occurred_at}`. Auth gate (operator token). TDD with stubs. Commit. Deploy (`k8s/memory-pg/serve.yaml`).

---

## Phase 3 — Migration (canonical JSONL preserved)

### Task 3.1: backfill importer (TDD)

**Files:** `apps/memory-pg/bin/backfill.mjs`, `test/backfill.test.mjs`

- [ ] `backfill(pool, exportFile)` streams the existing beagle-core export (the same NDJSON/JSON the legacy worker consumed — reuse the `iter_candidates` streaming idea), `captureRecord` each (idempotent on content_sha256), enqueues embeddings. **Build HNSW AFTER bulk load** (drop+recreate the index post-import). TDD on a fixture export. Then run for real against a snapshot export (JSONL untouched). Drain the worker; verify row counts. Commit.

### Task 3.2: dual-write from beagle-core

- [ ] Add a write hook in beagle-core's ingest path that POSTs new records to `memory-pg /capture` **in addition to** the JSONL append (feature-flagged `BEAGLE_DUAL_WRITE_MEMORY_PG`). Reconciliation script: `count(records)` vs JSONL line count + content-hash spot-checks. Prove no writes lost over a period. Commit.

### Task 3.3: read cutover (feature-flagged) + A/B

- [ ] Flip the cockpit/beagle-core retrieval to `memory-pg /query` behind a flag. A/B on **real queries you actually asked** (export a held-out set): first-stage Recall@100 + post-rerank groundedness vs the legacy ColBERT path. Record the measured ColBERT-vs-dense+rerank delta on the real PT/EL corpus (validates the dropped-multivector decision). Only after the A/B passes, default the flag on.

### Task 3.4: decommission

- [ ] Stop JSONL appends; **archive** (never delete) the JSONL files + the LanceDB dir; remove the Python subprocess worker + LanceDB deployment. Postgres backup via `pg_basebackup`; document restore (`CREATE EXTENSION vector, pg_search, age` BEFORE data restore). Update [[project_exocortex_ingest_constraints]] memory: the stack is replaced.

---

## Phase 4 — Temporal knowledge-graph memory (Graphiti-style, sovereign)

### Task 4.1: graph backend spike (AGE vs recursive-CTE) — DECISION GATE

- [ ] Spike both: (a) Apache AGE — `CREATE EXTENSION age`, a tiny graph, a 2-hop Cypher query; verify it works on the Ceph-backed `beagle-pg` (and that backups/WAL cover it). (b) relational bi-temporal tables + recursive CTE for 2-hop. Decide based on: works-on-our-Postgres, backup safety, query ergonomics. **Record the decision; the rest of Phase 4 follows it.**

### Task 4.2: graph schema + entity resolution (TDD)

**Files:** `apps/memory-pg/sql/002_graph.sql`, `src/graph.mjs`, `test/graph.test.mjs`

- [ ] Schema: `entities(id, name, type, embedding halfvec(1024), summary, content_sha256)` + `facts(id, subject_id, predicate, object_id, statement, embedding, valid_from, valid_to, occurred_at, provenance jsonb, confidence)`. `resolveEntity(pool, name, embedding)` dedups by name + cosine similarity threshold. TDD: same entity twice → one node; near-duplicate name+embedding → merged. Commit.

### Task 4.3: extraction worker (sovereign LLM, off `pending_graph`) (TDD)

**Files:** `src/graph-extract.mjs`, `bin/graph-worker.mjs`, `test/graph-extract.test.mjs`

- [ ] Add `pending_graph` outbox (enqueued in `captureRecord`). Worker (SKIP LOCKED) calls a **cluster-local LLM** (LiteLLM router, sovereign models ONLY — never commercial; health/biography is sensitive) with a strict extraction prompt → entities + temporally-scoped facts; `resolveEntity`; insert facts; **invalidate** contradicted facts (`SET valid_to=now()`, never delete). TDD with a stub LLM returning known triples; assert bi-temporal invalidation. Throttle + token budget for backfill. Commit.

### Task 4.4: graph retrieval channel + fusion

- [ ] `graphRetrieve(pool, {queryEmbedding, entities})` returns relevant facts/entities (vector on `facts.embedding` + multi-hop via the Task 4.1 decision). Fuse into `retrieve` (RRF over dense ⊕ BM25 ⊕ graph) before rerank. TDD: a multi-hop question answerable via graph that vector-only misses. Commit.

### Task 4.5: graph backfill (throttled, prioritized)

- [ ] Drain `pending_graph` over the existing corpus, **prioritized by recency/signal**, with a token budget + TEI/LLM throttle (don't saturate the router). Measure extraction precision on a sample. Commit.

---

## Self-Review Notes

- **Spec coverage:** Phase 0–1 = Layer 1+2 (store+vector+outbox+worker, kills corruption+OOM+subprocess); Phase 2 = Layer 3 (hybrid+rerank); Phase 3 = migration (preserves canonical JSONL); Phase 4 = Layer 4 (temporal graph). All 4 locked decisions reflected (dense+rerank, pg_search, graph in scope, bge-reranker-v2-m3). ✔
- **Spikes are explicit tasks, not placeholders:** extension availability (0.1), AGE-vs-CTE (4.1) — each a decision gate with criteria. ✔
- **Type/contract consistency:** `captureRecord` → `pending_embeddings`/`pending_graph` → workers; `embeddings` PK `(chunk_id, model_version)` used identically in worker upsert + retrieve join + reindex. ✔
- **Reliability invariants encoded in tests:** ACID concurrent capture (1.2), SKIP-LOCKED disjoint claim (1.3.6), idempotent replay (1.3), DLQ (1.3), bounded RAM (1.4), RRF-not-linear (2.1), bi-temporal invalidate-not-delete (4.3). ✔
- **Safety:** canonical JSONL archived never deleted (3.4); sovereign LLM only for extraction (4.3); conc-1 on legacy store during migration; seccomp Unconfined + tolerations on all pods.
- **Sequencing:** ship Phase 1–2 (the reliability core + retrieval) and migrate (Phase 3) BEFORE Phase 4 (graph) — the graph is additive and must not block the reliability fix.
