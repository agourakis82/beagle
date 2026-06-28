# Reliable Memory Pipeline — Postgres+pgvector Capture→Ingest→Retrieve+Rerank+Graph — Design

**Date:** 2026-06-23
**Author:** Demetrios Chiuratto Agourakis (with Claude)
**Status:** design — pending review
**Grounded in:** `docs/research/2026-06-23-reliable-memory-pipeline-sota.md` (SOTA brief, run wf_d699e957-088)
**Related:** [[feedback_memory_pipeline_unreliable]], [[project_exocortex_ingest_constraints]], [[project_beagle_physiome]]

## Problem

The current capture→ingestion→reranking stack is structurally fragile (the user's word: "porcaria").
Six failure modes, all patched, never fixed: JSONL append store corrupts at conc>1; every import triggers
a synchronous full reindex that OOMs (96Gi); a Rust server shells a Python subprocess passing the whole
255MB corpus as one JSON (Decimal crash, opaque "worker-unavailable"); the index is a recency window that
drops old data. Interim streaming patches stopped the OOM + Decimal crash but a full rebuild is still
embedding-bound-slow (>30min). The root causes are architectural, not bugs.

## Locked decisions (from brainstorming, 2026-06-23)

1. **Retrieval = single-vector dense (bge-m3) + cross-encoder rerank. DROP ColBERT multivector.** (ColBERT's
   per-token vectors = ~214GB at corpus scale = the literal OOM cause; cross-encoder rerank recovers precision.)
2. **Hybrid keyword side = `pg_search` (ParadeDB BM25).** AGPL accepted; license boundary documented below.
3. **Temporal knowledge-graph memory IS in scope** (Graphiti-style: entities + bi-temporal facts + multi-hop),
   built Postgres-native and sovereign (no Neo4j; LLM extraction via cluster-local models only).
4. **Reranker = `bge-reranker-v2-m3`** (multilingual, TEI-native — the corpus is PT/EL/biographical).

## Goals

- **Reliable by construction:** ACID writes (no corruption), incremental indexing (no full reindex / OOM),
  in-process SQL (no opaque subprocess), durable store (no recency window).
- **One system:** everything in the existing `beagle-pg` Postgres + existing TEI services. No LanceDB, no
  Python subprocess, no new datastore for the graph.
- **Sovereign:** health/biography never leaves the cluster; graph extraction uses cluster-local LLMs only.
- **Measurably better, not just stabler:** hybrid+rerank quality validated on *real* queries; graph enables
  multi-hop temporal questions over the biography.

## Non-Goals

- ColBERT/late-interaction (dropped; VectorChord is the documented exit ramp if ever proven necessary).
- Distributed vector DBs (Milvus/Qdrant) — over-engineered for a single-user sovereign corpus; Milvus's etcd
  is explicitly vetoed (t560 etcd starvation, [[project_t560_etcd_io_starvation]]).
- Deleting the canonical JSONL store — it is archived, never deleted, and is the migration source of truth.

## Architecture

### Layer 1 — Canonical store + vector index (the reliable core)

Tables in `beagle-pg` (vertical split is mandatory — pgvector #875: metadata UPDATE on an HNSW-indexed table
is ~100x slower):

- **`records`** — `id uuid PK, source_type text, content text, metadata jsonb, occurred_at timestamptz,
  created_at timestamptz default now(), content_sha256 text, privacy_class text, decay_class text`.
- **`chunks`** — `id uuid PK, record_id uuid FK, chunk_index int, text text, content_sha256 text,
  UNIQUE(record_id, chunk_index)`. Chunking: topic/segment-level (SeCom evidence beats turn-level),
  128–512 tokens, ~10% overlap; **content_sha256 computed post-chunking** (so boundary changes are detected).
- **`embeddings`** — `chunk_id uuid FK, embedding halfvec(1024), model_version text, is_current bool,
  PRIMARY KEY(chunk_id, model_version)`. **HNSW index** `(embedding halfvec_cosine_ops) WITH (m=16,
  ef_construction=128)`, partial `WHERE is_current`. CHECK on non-zero magnitude (catches TEI zero-vector).
- **`pending_embeddings`** / **`failed_embeddings`** — outbox queue + DLQ.

pgvector ≥ **0.8.3** (fixes 0.8.2 parallel-build overflow + 0.8.3 HNSW-vacuum corruption).

### Layer 2 — Ingestion (transactional outbox + SKIP LOCKED worker)

- **Capture** = one transaction: `INSERT records` + `INSERT pending_embeddings` (+ `pending_graph` row, Layer 4).
  ACID → concurrency corruption is impossible by construction.
- **Embed worker** (Rust Deployment, not CronJob): loop
  `UPDATE pending_embeddings SET status='processing', locked_until=now()+'5min' WHERE id IN
  (SELECT id … FOR UPDATE SKIP LOCKED LIMIT 50) RETURNING *` → chunk → sha256 → skip if unchanged →
  TEI bge-m3 batch embed (token-bucket throttle + backoff; TEI saturation is a measured unknown) →
  `INSERT embeddings … ON CONFLICT DO UPDATE` (idempotent replay) → delete queue row; on failure
  `retry_count++`, >3 → `failed_embeddings`. A **reaper** requeues rows stuck past `locked_until`.
  Peak RAM = one batch (no corpus materialization → no OOM). Insert throughput decoupled from write latency.
- **HNSW** absorbs each insert incrementally (O(log N), no rebuild). Weekly `REINDEX INDEX CONCURRENTLY` CronJob
  purges tombstones (dead-tuple recall collapse mitigation, #244).

### Layer 3 — Retrieval + rerank (hybrid → cross-encoder)

1. (optional) conversation-aware query rewrite (decontextualize pronouns).
2. **CTE A** dense: `SET LOCAL hnsw.ef_search=80, hnsw.iterative_scan=relaxed_order`; top-50 by `<=>` cosine.
3. **CTE B** BM25 via `pg_search` (`@@@`); top-50.
4. **RRF fuse** (k=60, rank-based — never linear-combine BM25's unbounded score with cosine) + recency prior
   `α·sim + (1−α)·0.5^(age/h)` with per-`decay_class` half-life (identity h=180d, tasks h=7–14d) → top-50 unique.
5. **Graph channel** (Layer 4): entity/fact hits from the temporal KG, fused into the candidate set.
6. **Rerank** the unified top-N with `bge-reranker-v2-m3` (TEI) → top 8–12 → LLM context.

### Layer 4 — Temporal knowledge-graph memory (Graphiti-style, Postgres-native, sovereign)

- **`entities`** — `id uuid PK, name text, type text, embedding halfvec(1024), summary text, content_sha256`.
  Dedup by name + embedding similarity (no duplicate "Demetrios" nodes).
- **`facts`** (edges) — `id uuid PK, subject_id FK, predicate text, object_id FK, statement text,
  embedding halfvec(1024), valid_from timestamptz, valid_to timestamptz, occurred_at, provenance jsonb,
  confidence real`. **Bi-temporal**: `valid_from/valid_to` = when the fact was true in the world;
  `created_at` = when learned. Superseded facts get `valid_to` set, never deleted (temporal history).
- **Graph queries** via **Apache AGE** (Postgres openCypher extension) for multi-hop, OR recursive CTEs if AGE
  is undesirable — decide in the plan after a spike. Either way it stays inside `beagle-pg` (no Neo4j/FalkorDB).
- **Extraction worker** (off a `pending_graph` outbox, same SKIP LOCKED pattern): for each new record, call a
  **cluster-local LLM** (LiteLLM router, sovereign models ONLY — never commercial, health/biography is
  sensitive) to extract entities + temporally-scoped facts; resolve entities; invalidate contradicted facts
  (set `valid_to`). **Incremental** — no 146k upfront backfill; a throttled background drain backfills
  prioritized by recency/signal, with a token budget. Extraction cost + hallucination are the main risks.

### Reranker deploy

`bge-reranker-v2-m3` as a TEI service (mirror the existing `beagle-sovereign-reranker` deployment), or swap
the existing reranker's model. Sovereign, on-cluster.

## Data flow

```
CAPTURE  write → BEGIN; INSERT records; INSERT pending_embeddings; INSERT pending_graph; COMMIT  (atomic)
INGEST   embed-worker: SKIP LOCKED → chunk → sha → TEI bge-m3 → ON CONFLICT upsert embeddings (incremental)
GRAPH    graph-worker: SKIP LOCKED → cluster-local LLM extract → entities+facts (bi-temporal) → AGE/CTE
INDEX    HNSW absorbs inserts; weekly REINDEX CONCURRENTLY
RETRIEVE dense(HNSW top50) ⊕ BM25(pg_search top50) ⊕ graph(facts/entities) → RRF+recency → top50
RERANK   bge-reranker-v2-m3 over top50 → top 8-12 → LLM
```

## Migration (safe phases — canonical JSONL preserved throughout)

- **Phase 0 prep:** pgvector ≥0.8.3 + pg_search + (AGE) extensions; create schemas; tune
  `maintenance_work_mem=1536MB`, `autovacuum_vacuum_scale_factor=0.01` on `embeddings`, `shared_buffers≥4GB`.
- **Phase 1 backfill:** importer reads the existing JSONL/LanceDB corpus → `records` + enqueue. **Bulk-load
  then build HNSW** (insert-then-index ≫ cheaper). Worker drains (~438k chunks ≈ hours, TEI-bound, throttled).
  JSONL untouched/canonical. Graph backfill deferred to a throttled drain.
- **Phase 2 dual-write:** beagle-core write path → outbox (Postgres) **in addition to** JSONL. Reconcile
  (`count(records)` vs JSONL lines + content-hash spot checks) → prove no writes lost.
- **Phase 3 read cutover:** flip retrieval to the hybrid+graph+rerank SQL pipeline behind a feature flag; A/B
  on **real queries you actually asked** (not LLM-generated) — first-stage Recall@100 + post-rerank groundedness.
- **Phase 4 decommission:** stop JSONL appends, **archive** the files (never delete — they were canonical),
  remove the Python subprocess + LanceDB. Backups: `pg_basebackup`; on restore `CREATE EXTENSION vector`
  (+ pg_search, age) BEFORE data restore or it aborts.

## Testing & victory metrics

- **Reliability:** zero ingest corruption at conc≥2 (ACID); worker peak RAM bounded (no 96Gi OOM); write
  latency decoupled from embed latency; reaper recovers stuck jobs; idempotent replay (re-run = no dupes).
- **Quality:** first-stage Recall@100 ≥ 0.95; post-rerank groundedness ≥ the current ColBERT pipeline on real
  queries (validates the dropped-multivector trade on the actual PT/EL corpus); BM25 vs dense ablation.
- **Graph:** multi-hop temporal queries answerable that vector-only cannot; extraction precision spot-checked;
  contradicted-fact invalidation correct.
- **Ops:** EXPLAIN ANALYZE confirms index path (not seq scan) post-deploy; operator match (cosine↔cosine).

## Risks / gotchas (from the SOTA failure-mode review + graph additions)

- Metadata UPDATE 100x slower w/ HNSW → **vertical split** (baseline). · Dead-tuple recall collapse → VACUUM +
  weekly REINDEX CONCURRENTLY + iterative_scan. · `ef_search>~400` → planner drops index → cap at ~80–100 via
  `SET LOCAL`. · BM25/cosine fusion bug → **RRF only**. · Mixed model-version vectors → `model_version` +
  `is_current` + partial index. · **pg_search AGPL** → beagle-core is a PG client; AGPL boundary accepted by
  the user — document it; tsvector remains a fallback. · **Graph extraction cost/hallucination** → sovereign
  LLM only, incremental throttled backfill, confidence scores, human-checkable provenance, bi-temporal
  invalidation not deletion. · **AGE maturity** → spike before committing vs recursive-CTE fallback. · TEI
  saturation under backfill → token-bucket + backoff, measure queue depth.

## Honesty ledger / open questions for the plan

- ColBERT quality delta (~4-7 nDCG) is benchmark-derived, **not** measured on this PT/EL/biographical corpus —
  Phase 3 A/B is the real test; bge-reranker-v2-m3 chosen partly to close the multilingual gap.
- **AGE vs recursive-CTE** for graph queries — resolve via a spike in the plan (AGE = nicer Cypher but another
  extension; CTE = zero-dep but clumsier multi-hop).
- Chunking parameters (segment detection, token window, overlap) are load-bearing — fix concretely in the plan.
- Graph backfill scale (146k records × LLM extraction) — define the throttle, token budget, and priority order.
- pg_search hybrid is still hand-wired via pgvector (its native hybrid is roadmap) — confirm the RRF wiring.
