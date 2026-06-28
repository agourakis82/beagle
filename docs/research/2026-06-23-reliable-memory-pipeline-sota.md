---
title: Reliable Capture→Ingest→Retrieve+Rerank — SOTA-grounded architecture recommendation
date: 2026-06-23
kind: deep-research-brief
generated_by: multi-agent deep-research (reliable-memory-pipeline-sota)
run_id: wf_d699e957-088
scale: 10 agents, ~465k tokens, 8 domain sweeps + adversarial failure-mode review + synthesis
verdict: Postgres+pgvector (records + separate halfvec embeddings table + HNSW + transactional outbox + SKIP-LOCKED worker + hybrid RRF + cross-encoder rerank); DROP ColBERT multivector
related: [[feedback_memory_pipeline_unreliable]], [[project_exocortex_ingest_constraints]], [[project_beagle_physiome]]
status: machine-generated; honesty ledger §8 lists the open decisions for the spec
---

This is a self-contained writing task — all the research is provided in the prompt (domain sweeps + adversarial review). I have everything needed to write the brief directly. No tools or codebase exploration required.

# Sovereign Personal-Memory System: Capture → Ingest → Retrieve+Rerank Redesign

## 1. Recommendation

Build the entire pipeline inside the **existing beagle-pg Postgres instance** and delete every non-Postgres moving part. Canonical store: a normalized `records` table (id, source_type, content, metadata JSONB, created_at, content_sha256). Index: a **separate `embeddings` table** holding `embedding halfvec(1024)` (bge-m3 dense, from the existing TEI service) with an **HNSW index (m=16, ef_construction=128, halfvec_cosine_ops)** that absorbs inserts incrementally — no rebuild, ever. Ingestion: a **transactional outbox** — every write inserts the record plus a `pending_embeddings` queue row in one transaction, drained by a **single async Rust worker using `SELECT ... FOR UPDATE SKIP LOCKED`** that content-hash-dedups, embeds in bounded batches via TEI, and upserts with `ON CONFLICT`. Retrieval: **hybrid — pgvector HNSW dense (top-50) RRF-fused (k=60) with BM25** (ParadeDB `pg_search`, falling back to native `tsvector` if the AGPL/extension dependency is unacceptable), plus a SQL recency-prior term, then **rerank the top-50 with the existing GTE/TEI cross-encoder → top 8-12 to the LLM**. **Drop ColBERT multivector entirely.** This adds zero new services, eliminates all four current failure modes, and has years of headroom before any scale concern.

## 2. Why this is RELIABLE — each element kills a current failure mode

| Current failure mode | Chosen element that eliminates it | Mechanism |
|---|---|---|
| **JSONL concurrency corruption (conc>1)** | Single Postgres write path (`INSERT` in a transaction) + SKIP LOCKED worker | Postgres row-level locking + MVCC makes concurrent writes ACID-safe by construction. No file appends, ever. SKIP LOCKED is the proven concurrency-safe queue claim. |
| **Synchronous full-reindex OOM (96 Gi)** | HNSW incremental inserts + outbox queue | HNSW is a graph, not centroid-partitioned — each `INSERT` updates the live graph in O(log N). There is no full-rebuild trigger. The worker streams bounded batches (50-200), never loading the corpus into RAM. |
| **Opaque Rust-shells-Python-passes-whole-corpus-JSON subprocess** | All retrieval + indexing is SQL inside beagle-core's existing Postgres client | No subprocess, no JSON blob, no LanceDB. Embedding is one HTTP call to the already-deployed TEI service per batch. Errors surface as SQL errors / queue `retry_count`, not opaque OOM kills. |
| **Windowing-out of old data (recency window)** | Durable Postgres store + recency *prior* (score fusion), not a hard window | All records persist forever (ACID, WAL, pg_dump). Recency is applied as `α·sim + (1−α)·0.5^(age/h)` at query time — a soft, tunable bias, never deletion. Historical queries disable decay via date filter. |

## 3. Architecture — components and data flow

**Components (all in/around beagle-pg + existing TEI):**
- `records` — canonical store (id PK, source_type, content TEXT, metadata JSONB, created_at TIMESTAMPTZ, content_sha256, decay_class).
- `embeddings` — `(record_id FK, chunk_index, embedding halfvec(1024), model_version, is_current bool, content_sha256)`. **Vertical split from `records` is mandatory** (pgvector issue #875: metadata UPDATE on an HNSW-indexed table is ~100x slower).
- `pending_embeddings` — outbox/queue (record_id, status, retry_count, locked_until, content_sha256).
- 1× Rust async **embed worker** (K8s Deployment, not CronJob).
- Existing **TEI bge-m3** (embeddings) and **TEI GTE cross-encoder** (rerank).
- `pg_search` BM25 index (or `tsvector` GIN fallback) + HNSW index.

**Data flow:**
```
CAPTURE   agent/doc/biography write
            └─► BEGIN; INSERT records(...); INSERT pending_embeddings(...); COMMIT   (atomic outbox)

INGEST    worker loop:
            UPDATE pending_embeddings SET status='processing', locked_until=now()+5min
              WHERE id IN (SELECT id ... FOR UPDATE SKIP LOCKED LIMIT 50) RETURNING *;
            chunk → sha256(chunk) → skip if hash unchanged
            TEI bge-m3 embed (bounded batch) → halfvec
            INSERT INTO embeddings ... ON CONFLICT (record_id, chunk_index)
              DO UPDATE SET embedding=..., content_sha256=...   (idempotent replay)
            DELETE queue row on success; else retry_count++; >3 → failed_embeddings (DLQ)
            assert chunk_count>0 before ack (catches silent empty extraction)
            reaper requeues rows stuck in 'processing' past locked_until

INDEX     HNSW absorbs each INSERT incrementally (no rebuild)
            weekly K8s CronJob: REINDEX INDEX CONCURRENTLY (purge tombstones)

RETRIEVE  (optional) conversation-aware query rewrite (decontextualize pronouns)
            CTE A: dense HNSW, SET LOCAL hnsw.ef_search=80, hnsw.iterative_scan=relaxed_order, top-50
            CTE B: BM25 (pg_search) top-50
            RRF fuse (k=60) + recency term (α=0.7, h per decay_class) → top-50 unique

RERANK    TEI GTE cross-encoder over top-50 (query, chunk) pairs → top 8-12 → LLM context
```
End-to-end budget at this scale: HNSW <10ms, BM25 5-40ms, RRF ~0, cross-encoder 30-90ms on A5000/L4 → well under 300ms.

## 4. The multivector decision — DROP ColBERT, go dense+rerank

**Decision: abandon jina-colbert late-interaction; use single-vector bge-m3 dense + cross-encoder rerank.** Evidence:

- **Quality is not the win it's marketed as.** As a *reranking* stage (where you already hold candidates), cross-encoders **beat** ColBERT on precision: cross-encoder nDCG@10 ~0.77-0.78 vs ColBERTv2 ~0.69. ColBERT's edge is *recall at massive scale* — irrelevant when HNSW already returns 95%+ recall on a 146k corpus.
- **Storage is the killer at this scale.** Per-token vectors cost ~500 KB/chunk → **214 GB at 438k chunks** raw, before any index. This *is* the current 96 Gi OOM, not a bug to fix around it. Dense halfvec is ~0.84 GB raw + ~1.7 GB HNSW at 438k chunks — fits in RAM trivially.
- **No Postgres-native path in stock pgvector** (it rejects ndim>1). Replicating ColBERT means a second specialized index (VectorChord, PLAID) — reintroducing the operational complexity that destroyed the current stack.
- **You already run the cross-encoder.** Dense+rerank is a config, not a new service.

The honest cost: a measured **~4-7 nDCG@10 points** vs an ideal ColBERT pipeline (ColBERT ~51.6 vs dense+rerank ~44-47 on BEIR). For a single-user personal companion, this is an acceptable, deliberate trade. **Exit ramp:** if late-interaction is later proven necessary, **VectorChord 0.3+** (`vector(d)[]` + `@#` MaxSim) is the only Postgres-native path — install as extension, re-embed multivector, no application rewrite.

## 5. Comparison table

| Design | Reliability | Ops simplicity | Incremental | Retrieval quality | Migration cost |
|---|---|---|---|---|---|
| **CHOSEN: Postgres+pgvector HNSW halfvec + outbox + BM25 RRF + cross-encoder** | **High** — ACID, WAL, crash recovery for free; single write path | **Highest** — zero new services, one backup/auth/monitor surface | **Native** — HNSW absorbs inserts, no rebuild | **High** — hybrid+rerank matches/exceeds ColBERT at this scale | **Low-med** — extension + schema + one worker; reuses TEI |
| VectorChord (IVF+RaBitQ, MaxSim) | Med-high — newer, possible WAL gap for index (verify) | High — still one Postgres | Native, faster inserts | High + native ColBERT | Med — extension swap, re-embed if multivector |
| Qdrant | High (single-node WAL) | Med — 2nd service, 2nd backup | Native | High (native sparse-dense) | Med-high — dual-write + reconciliation logic |
| Keep LanceDB, decouple reindex | **Low** — documented concurrent-write data loss (same failure class as JSONL) | Med — still a subprocess/file store | optimize() manual; bg reindex enterprise-only | Med (current) | Low effort but does not fix root cause |
| Milvus / Weaviate | High but heavy | **Low** — microservices; Milvus needs its own etcd (vetoed by t560 etcd starvation) | Native | High | High — over-engineered <100M vectors |
| Turbopuffer | n/a | n/a | n/a | n/a | **Disqualified** — cloud-only, violates sovereignty |

## 6. Migration sketch — safe phases, canonical store preserved

**Phase 0 — Prep (no traffic change).** Upgrade pgvector to **≥0.8.3** (fixes parallel-build buffer overflow 0.8.2 and HNSW-vacuum corruption 0.8.3; verify `SELECT extversion`). Create `records`, `embeddings`, `pending_embeddings`, `failed_embeddings` schemas. Set `maintenance_work_mem=1536MB`, tune `autovacuum_vacuum_scale_factor=0.01` on `embeddings`. Add NOT NULL + magnitude CHECK on the vector column (catches TEI zero-vector errors).

**Phase 1 — Backfill (read existing JSONL as source of truth).** One-shot importer reads the JSONL/LanceDB corpus, writes `records` rows, enqueues `pending_embeddings`. **Build the HNSW index AFTER bulk load** (insert-then-index is far cheaper than index-then-insert). Worker drains the queue at concurrency=1. ~438k chunks embed in ~1.7h on A5000. JSONL remains untouched and canonical during this phase.

**Phase 2 — Dual-write.** Point beagle-core's *write* path at the transactional outbox (Postgres) **in addition to** the existing JSONL append. Reads still come from the old path. Run a reconciliation query: `count(records) vs count(JSONL lines)` and content-hash spot-checks. This proves no writes are lost before trusting the new store.

**Phase 3 — Read cutover.** Flip the *retrieval* path to the hybrid+rerank SQL pipeline behind a feature flag. A/B on a held-out set of **real queries you actually asked the exocortex** (not LLM-generated — those inflate recall). Measure first-stage Recall@100 and post-rerank answer groundedness.

**Phase 4 — Decommission.** Stop JSONL appends, archive the files (do not delete — they were canonical), remove the Python subprocess and LanceDB. New canonical store = Postgres; backups via `pg_basebackup` (or `pg_dump --schema-only` + data-only + rebuild index on restore; **pre-create `CREATE EXTENSION vector` before any restore** or the restore aborts).

## 7. Risks, gotchas, mitigations, and what to measure

| Risk (verified) | Mitigation | Metric to prove it |
|---|---|---|
| Metadata UPDATE 100x slower with HNSW (#875, open) | **Vertical table split** — vectors in own table, metadata in `records`. Baseline design, not optional. | UPDATE latency on `records` stays flat (~50ms/10k rows) |
| Dead-tuple recall collapse / silent 0 results (#244) | `VACUUM` after bulk delete; weekly `REINDEX CONCURRENTLY`; iterative_scan on | Route 1% queries through exact search; alert on recall delta |
| HNSW QPS cliff when index > RAM (#700: 2110→102 QPS) | Not hit until ~2-5M vectors. halfvec halves index (~300MB). `shared_buffers ≥ 4GB`. | `pg_statio_user_indexes` disk-page reads; index_size / shared_buffers |
| Insert throughput decay at millions of rows (#810) | Single async worker at conc=1; 3 rows/s worst-case still = 259k rows/day | Queue depth + insert latency p99 trend |
| Filtered search under-returns | `hnsw.iterative_scan=relaxed_order` + tuned `max_scan_tuples`; raise ef_search | Result count vs requested K on filtered queries |
| `ef_search > ~400` → planner abandons index → 300ms+ | `SET LOCAL hnsw.ef_search=80` (never pool-leak via SET); cap at 100 | EXPLAIN ANALYZE shows index path, not seq scan |
| Operator mismatch → silent seq scan | Assert index op = query op (cosine↔cosine) in EXPLAIN after schema change | EXPLAIN ANALYZE post-deploy |
| BM25 score-fusion bug (BM25 unbounded vs cosine [-1,1]) | **Use RRF (rank-based), never raw linear combine** | Inspect fused ranks; min top-20 from each side |
| Uniform temporal decay worse than none (2509.19376) | Per-`decay_class` half-life (identity h=180d, tasks h=7-14d) via CASE | Latest@10 on recent-fact queries; no regression on historical |
| `pg_search` AGPL / extension dependency | Native `tsvector` fallback (lacks IDF but zero-dep); decide per sovereignty constraint | BM25 vs ts_rank Recall@5 on proper-noun queries |
| Mixed model-version vectors → silent nonsense recall | `model_version` + `is_current` + `source_hash` + partial HNSW index per version | nDCG on held-out set after any re-embed |

**Headline metrics to declare victory:** (1) zero ingest corruption at conc≥2 (it's now ACID); (2) peak worker RAM bounded (no 96Gi OOM); (3) ingest write latency decoupled from embed latency; (4) Recall@100 ≥ 0.95 first-stage; (5) post-rerank answer groundedness ≥ current ColBERT pipeline on real queries.

## 8. Honesty ledger — unverified claims and open questions for the spec

- **VectorChord WAL coverage for the index is UNVERIFIED.** Its predecessor pgvecto.rs explicitly lacked WAL for the index (no PITR/replication of index → crash may force full rebuild). VectorChord docs do not clearly confirm resolution. **Must verify before adopting the exit ramp** on Ceph-backed Postgres.
- **`pg_search` AGPL propagation** to beagle-core (a Postgres client) needs a license review for a sovereign-but-possibly-not-open deployment. If unacceptable, ship `tsvector` first and treat true BM25 as a later upgrade. `pg_search` "vector/hybrid coming soon" in its own roadmap means hybrid is still hand-wired via pgvector today.
- **ColBERT quality delta (~4-7 nDCG@10) is benchmark-derived, not measured on this biographical/Portuguese/Greek corpus.** Validate on real queries before concluding the trade is acceptable; multilingual content may shift the gap (consider bge-reranker-v2-m3 or jina-reranker-v3, both TEI-native, for stronger PT/EL coverage than GTE).
- **jina-reranker-v3 TEI integration unverified** (newer architecture); has no published latency benchmark. Treat as optional upgrade, not baseline.
- **Cognee incremental behavior `verified:false`** in the sweep — not a chosen component, noted only to rule out.
- **Chunking strategy is unspecified and load-bearing.** SeCom evidence: segment/topic-level beats turn-level (71.57 vs 65.58 GPT4Score) and session-level. Spec must define conversation segmentation (topic shift / time gap) and target 128-512 tokens with ~10% overlap; content-hash must be computed **post-chunking**, or chunk-boundary changes go undetected.
- **Open question for spec:** is graph/temporal-entity memory (Graphiti) in scope? It needs Neo4j/FalkorDB (no Postgres backend) and ~146k LLM extraction calls to backfill. Recommend deferring — out of scope for the reliability redesign; revisit only if multi-hop temporal queries are measured as deficient.
- **TEI throughput under backlog is a measured unknown.** Backfilling 438k chunks can saturate bge-m3; worker needs token-bucket throttle + exponential backoff with jitter. Measure TEI queue depth during Phase 1, don't assume a fixed `pg_sleep`.