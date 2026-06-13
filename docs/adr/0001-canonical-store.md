# ADR 0001 — Canonical Store Consolidation

**Status:** Accepted  
**Date:** 2026-06-07  
**Deciders:** Beagle platform (devsounio)  
**Context:** Beagle core modernization plan item #12 — see `docs/MODERNIZATION_PLAN_2026.md`.  
**Supersedes:** `docs/adr/0001-memory-store-consolidation.md` (earlier draft; this is the
authoritative version with grounding in code readings of 2026-06-07).

---

## 0. Measured-reality update (2026-06-08) — supersedes contradicted claims below

The original body (§1–§8) was written from **code reading** on 2026-06-07. A live cluster
probe on 2026-06-08 (read-only `curl` against Qdrant + beagle-memory-engine) contradicts several
of its premises. Per the "measure, don't assume" discipline, the measured facts win and the
affected decisions are reconciled here. The rest of the ADR stands.

**Measured live topology (2026-06-08):**

| Store | MEASURED state | Original ADR claim | Verdict |
|-------|----------------|--------------------|---------|
| Qdrant `cockpit_rag` | 24 373 points, **1024-dim** (bge-m3), green, 22 016 indexed | "`beagle` collection, 1536-dim" | name+dim wrong |
| Qdrant `beagle_exocortex` | 745 points, 1024-dim, **0 indexed** (below HNSW threshold) | not mentioned | underused |
| Qdrant `beagle` | **does not exist** | "the sole canonical projection" | wrong |
| LanceDB `semantic_memory_v1` (via beagle-memory-engine) | **LIVE**: 7 026 rows on OrangeFS, `lancedb-multivector`, model `jinaai/jina-colbert-v2`, reranker `gte-reranker-modernbert`; serves `/api/memory/query` (recall smoke-test passed, relevance 1.0 on in-corpus query) | "retired / empty / row_count:0 / no eval" | **wrong — it is the live recall path** |
| pgvector `nodes.embedding` | schema is **`VECTOR(1536)`** | "seeds the 1536-dim Qdrant rebuild" | **dim mismatch**: live indexes are 1024-dim, so this column cannot seed them without re-embedding |

**Reconciled decisions (override §2.2 where they conflict):**

1. **The canonical exocortex *semantic* index is LanceDB `semantic_memory_v1`, served by the
   separate `beagle-memory-engine` process** — not retired. It is the measured, populated,
   discrimination-tested recall path and is strictly more capable than the Qdrant single-vector
   path (multivector ColBERT late-interaction + a reranker). LanceDB is therefore reclassified
   **External-Canonical** (canonical, but owned by a different service), not "retired".
2. **Qdrant remains a rebuildable vector projection** for the in-process `VectorStore` trait
   (`beagle_exocortex` collection); `cockpit_rag` belongs to the cockpit plane. The empty/0-indexed
   `beagle_exocortex` is a consolidation candidate (backfill or fold into the memory-engine index).
3. **The pgvector "rebuild seed" plan (§4.3) is currently broken**: the column is 1536-dim while
   every live index is 1024-dim. Before pgvector can seed a rebuild, either the column is re-specced
   to 1024 (bge-m3) or the rebuild path must re-embed. Until then, the rebuild source of truth for
   the semantic index is the memory-engine's own JSONL/import corpus, not pgvector.
4. **Postgres stays the relational/graph system-of-record.** Unchanged.

The runtime honesty primitive for this (plan #12, Stage 0) is now implemented:
`beagle-core/src/store_inventory.rs` (`BeagleStoreInventory`) resolves and logs each store's role
at every `core_server` startup — see acceptance criterion §7 (first box).

**Known broken item — pgvector dimension mismatch (added 2026-06-13):**
`crates/beagle-db/migrations/001_initial_schema.sql` declares `nodes.embedding VECTOR(1536)` and
the DR rebuild script (§4.3) creates the Qdrant collection with `"size":1536`. However, every live
index is **1024-dim**: Qdrant `cockpit_rag` (24 373 points, bge-m3), `beagle_exocortex` (745
points), and LanceDB `semantic_memory_v1` (7 026 rows, jina-colbert-v2). The mismatch means:
(a) any embedding written to `nodes.embedding` by a 1024-dim model is stored with incorrect
declared dimensionality, (b) the §4.3 rebuild script would create a 1536-dim Qdrant collection
that is incompatible with the live 1024-dim corpus — making the "cold backup seed" claim theater.
`BeagleStoreInventory::log()` now emits a startup WARN for this gap. The fix is eval-gated and
listed in §DEFERRED below.

---

## 1. Context

### 1.1 The current store landscape (measured, not assumed)

Five distinct storage technologies appear in the Beagle codebase. Their roles, deployment status,
and code locations are:

| Store | Crate(s) | Role claimed | Deployed? | Notes |
|-------|----------|-------------|-----------|-------|
| **Postgres + pgvector** | `beagle-hypergraph` (`storage/postgres.rs`, `types.rs`); `beagle-db` (`migrations/001_initial_schema.sql`) | Hypergraph nodes/edges with vector column; migration runner | Yes — single Postgres instance | `pgvector` is an optional feature (`database = ["sqlx", "redis", "pgvector"]`); semantic search path in `postgres.rs:1404` returns `Err("not yet supported")` — i.e. the vector column exists but is never queried |
| **Qdrant** | `beagle-core` (`implementations.rs:204-305`, `context.rs:67-80`); `beagle-rag-update` (`qdrant.rs`, `knowledge.rs`) | Live vector store behind `VectorStore` trait; `beagle-rag-update` populates it via real TEI embeddings | Yes — `qdrant.beagle.svc:6333` running; cockpit `cockpit_rag` collection (~24k points, nDCG@10 0.557, recall@10 0.65) | Default collection name `"beagle"` in `implementations.rs:222`; degrades gracefully to `NoOpVectorStore` if URL absent |
| **Neo4j** | `beagle-memory` (`neo4j.rs`, `Cargo.toml` dep `neo4rs = "0.7"`); doc references in `beagle-darwin/src/lib.rs` | Graph knowledge store | No pod/Service found | `Neo4jGraphStore` implemented (`neo4j.rs`) but depends on `neo4rs`; `beagle-memory/src/engine.rs:74` has a TODO to add it |
| **Redis** | `beagle-hypergraph` (`cache/redis.rs`, feature `database`); optional dep `redis = "1.0"` | Hot-node LRU cache for hypergraph reads | Unclear (optional dep, feature-gated) | `RedisCache` in `cache/redis.rs`; used as a read-through layer over Postgres, not a write store |
| **LanceDB** | Referenced in `docs/MODERNIZATION_PLAN_2026.md` as `semantic_memory_v1` / ColBERT index; `beagle-observer` tests | Named "production" ColBERT semantic index | Empty (`row_count:0`) until manually seeded; no native LanceDB library in image | No Rust dependency in any `Cargo.toml` — all access is via a Python sidecar; `MODERNIZATION_PLAN_2026.md` calls it "row_count:0 / index_ready:false" |

The one-sentence summary: **Postgres holds the relational/graph source of truth. Qdrant is the only
live, evaluated vector index. Neo4j has an implementation but no running pod. Redis is a read
cache. LanceDB is an empty, library-less aspirational index.**

### 1.2 Why this is a problem

- Four different stores mean four different operational runbooks, four backup schedules, and four
  failure modes — with no single source of truth to rebuild from.
- The pgvector column in `beagle-hypergraph/src/storage/postgres.rs` stores embeddings but the
  semantic search path (`postgres.rs:1404`) is unimplemented; the data is stranded.
- Qdrant is the **only** evaluated vector store (cockpit eval gate, nDCG@10 ≥ 0.55), yet
  `beagle-core` treats it as optional-degraded; the bridge stub at
  `beagle-memory/src/bridge.rs:189` has a `TODO: Implement semantic search via Qdrant` —
  pointing at the right store but never wiring it.
- The LanceDB ColBERT index is advertised as production but is empty and requires a Python
  sidecar that is not in any container spec.
- The TCR-QF module (`beagle-hypergraph/src/rag/tcr_qf.rs`) uses `rand` for "learned fusion
  weights" and references graph topology that Postgres already holds — it is a reranking heuristic
  sitting on top of the same data, not a fourth independent store.

### 1.3 The proven north-star

The cockpit coord-mcp (darwin-cluster) follows this exact pattern:  
**SQLite as system-of-record → Qdrant as single rebuildable vector projection → nDCG@10 regression
gate before any write.**  
That pattern is running, evaluated, and has a DR runbook. This ADR ports it to Beagle.

---

## 2. Decision

### 2.1 One system-of-record: Postgres

**Postgres is the canonical system-of-record for all persistent Beagle data.**

- `beagle-hypergraph` already owns the schema (`beagle-db/migrations/001_initial_schema.sql`):
  `nodes`, `hyperedges`, and the vector column on `nodes.embedding VECTOR(1536)`. This is the SoR.
- The `beagle-db` crate (`src/migrator.rs`) manages forward migrations. All schema additions go
  here via `-- migrate:up` / `-- migrate:down` markers (the missing-marker bug tracked in plan #3
  must be fixed before any new migration lands).
- SQLite is the SoR for the cockpit plane only (coord-mcp on darwin-cluster). Do not mix the two
  planes.

### 2.2 One vector index: Qdrant

**Qdrant (`qdrant.beagle.svc:6333`) is the sole vector index projection. pgvector and LanceDB are
demoted.**

#### pgvector vs. Qdrant — explicit resolution

| Criterion | pgvector | Qdrant |
|-----------|----------|--------|
| Currently deployed | Yes (embedded in Postgres pod) | Yes (dedicated pod `qdrant.beagle`) |
| Evaluated index with real corpus | No — semantic search path unimplemented (`postgres.rs:1404`) | Yes — `cockpit_rag` nDCG@10 0.557, recall@10 0.65 |
| Sparse + hybrid support (plan #8) | pgvector 0.8 adds iterative scans; no built-in BM25/SPLADE | Qdrant `/points/query` supports named vectors + RRF natively |
| Operational runbook | Backed by Postgres backup; no separate ops | Separate process; already has snapshot API |
| Reranking over-fetch (annK=32) | Possible but not implemented | Implemented via `beagle-rag-update` |
| Hot path in `beagle-core` | `NoOpVectorStore` when env absent | `QdrantVectorStore` via `implementations.rs:214` |

**Verdict: Qdrant wins.** The pgvector column (`nodes.embedding`) is retained in Postgres as a
**cold backup / rebuild seed** — it is populated when a node is written to the SoR and can be used
to rebuild the Qdrant projection if the Qdrant pod is lost. It is never queried in the hot path.

#### LanceDB

LanceDB is **retired from the production runtime.** Rationale:
- No Rust dependency exists; access requires a Python sidecar not present in any container spec.
- The named index `semantic_memory_v1` was `row_count:0` and `index_ready:false` on audit.
- No eval gate has ever validated it.

LanceDB may remain as a research/offline indexing tool in the `beagle-julia` or Python toolchain
for ColBERT-style experiments, but it must not appear in any production config, health check, or
advertised capability.

### 2.3 Redis: cache only

Redis (`beagle-hypergraph/src/cache/redis.rs`, optional feature `database`) remains **a read
cache** for hot hypergraph nodes. It is never the source of truth for any entity. If Redis is
unavailable the system falls back to Postgres reads (the `CachedPostgresStorage` wrapper already
handles this). No write goes to Redis without first committing to Postgres.

### 2.4 Neo4j: deferred, not load-bearing

Neo4j (`beagle-memory/src/neo4j.rs`, dep `neo4rs = "0.7"`) has an implementation but no
deployed pod. It is **not load-bearing** until:
1. A pod + Service exists in the cluster.
2. An eval gate validates graph traversal recall.
3. A migration from the Postgres hyperedge schema to Neo4j is staged and tested.

Until then, `Neo4jGraphStore` stays compilable but is never instantiated in `beagle-core` or
`beagle-memory/src/engine.rs`. The Apache AGE extension (Postgres-native graph) is the preferred
consolidation path if multi-hop traversal is ever needed at scale (avoids a separate process).

### 2.5 beagle-hypergraph TCR-QF: reranking module, not a store

`beagle-hypergraph/src/rag/tcr_qf.rs` implements fusion weights and multi-modal scoring. It reads
from the hypergraph data already in Postgres. It is **an optional reranking module layered over
the canonical Qdrant projection**, not a third independent vector store. Its `FusionWeights`
default values (`semantic: 0.30`, `topology: 0.15`, etc.) are currently hand-tuned; they must be
validated against the eval gate (plan #4) before the "29% improvement" claim in the file's header
can be accepted. The claim cites no benchmark.

---

## 3. Store classification

| Store | Classification | Hot path? | Rebuild source? |
|-------|---------------|-----------|-----------------|
| **Postgres** (beagle-db schema) | **System-of-record** | Yes | — (is the source) |
| **Qdrant** (`beagle.svc:6333`) | **Derived, rebuildable projection** | Yes | Postgres `nodes.embedding` column |
| **Redis** (hypergraph cache) | **Derived, ephemeral cache** | Yes (read) | Invalidated and rebuilt from Postgres on miss |
| **pgvector column** (`nodes.embedding`) | **Derived cold backup** | No | Written with each node insert; seeds Qdrant rebuild |
| **LanceDB** (`semantic_memory_v1`) | **Retired from production** | No | n/a |
| **Neo4j** | **Experimental / deferred** | No | Would be derived from Postgres hyperedges |
| **TCR-QF scoring** | **Reranking module** | Optional post-retrieval | No storage — stateless computation |

---

## 4. DR Runbook

### 4.1 Daily Postgres snapshot CronJob

Deploy as `k8s/cron/beagle-db-snapshot.yaml` (to be created during migration phase):

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: beagle-db-snapshot
  namespace: beagle
spec:
  schedule: "0 3 * * *"           # 03:00 UTC daily
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: pg-dump
              image: postgres:16-alpine
              env:
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: beagle-postgres-secret
                      key: password
              command:
                - /bin/sh
                - -c
                - |
                  DATE=$(date +%Y%m%d_%H%M%S)
                  pg_dump -h postgres.beagle.svc -U beagle -F c beagle \
                    > /snapshots/beagle_${DATE}.dump
                  # Prune snapshots older than 14 days
                  find /snapshots -name "beagle_*.dump" -mtime +14 -delete
              volumeMounts:
                - name: snapshots
                  mountPath: /snapshots
          volumes:
            - name: snapshots
              persistentVolumeClaim:
                claimName: beagle-db-snapshots-pvc   # Ceph RBD, min 20Gi
```

### 4.2 Qdrant vector projection snapshot CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: beagle-qdrant-snapshot
  namespace: beagle
spec:
  schedule: "30 3 * * *"          # 03:30 UTC daily (after Postgres dump)
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: qdrant-snapshot
              image: curlimages/curl:8.7.1
              command:
                - /bin/sh
                - -c
                - |
                  # Trigger Qdrant snapshot for both collections
                  curl -sf -XPOST \
                    http://qdrant.beagle.svc:6333/collections/beagle/snapshots
                  curl -sf -XPOST \
                    http://qdrant.beagle.svc:6333/collections/cockpit_rag/snapshots
```

### 4.3 Rebuild-from-source-of-truth procedure

If the Qdrant pod is lost or the projection is corrupted:

```bash
#!/usr/bin/env bash
# scripts/rebuild-qdrant-from-postgres.sh
# Reads the nodes.embedding column from Postgres and re-upserts into Qdrant.
# Pre-conditions: POSTGRES_URL and QDRANT_URL env vars set; TEI embedding
# service available at EMBEDDING_URL (needed only for nodes missing embeddings).

set -euo pipefail

COLLECTION="${QDRANT_COLLECTION:-beagle}"
BATCH_SIZE=256

echo "[rebuild] Dropping stale collection $COLLECTION"
curl -sf -XDELETE "$QDRANT_URL/collections/$COLLECTION" || true

echo "[rebuild] Creating collection (dim=1536, Cosine)"
curl -sf -XPUT "$QDRANT_URL/collections/$COLLECTION" \
  -H 'Content-Type: application/json' \
  -d '{"vectors":{"size":1536,"distance":"Cosine"}}'

echo "[rebuild] Streaming nodes from Postgres"
# Uses psql COPY to JSON; in practice pipe through jq to batch upsert
psql "$POSTGRES_URL" -c \
  "COPY (SELECT id, content, metadata, embedding::text
         FROM nodes WHERE deleted_at IS NULL AND embedding IS NOT NULL)
   TO STDOUT (FORMAT CSV)" \
| python3 scripts/pg_to_qdrant_upsert.py \
    --qdrant-url "$QDRANT_URL" \
    --collection "$COLLECTION" \
    --batch "$BATCH_SIZE"

echo "[rebuild] Done. Running eval gate."
cargo test -p beagle-hypergraph --test eval_regression -- --nocapture
```

Nodes that have a NULL embedding (pre-date the embedding backfill) must be re-embedded via the TEI
service before upsert. The `pg_to_qdrant_upsert.py` helper handles this by calling the TEI
endpoint at `EMBEDDING_URL` for any row with a NULL embedding column.

### 4.4 Restore from Postgres dump

```bash
# Stop beagle-core (scale to 0 to avoid writes during restore)
kubectl scale -n beagle deployment beagle-core --replicas=0

# Restore
pg_restore -h postgres.beagle.svc -U beagle -d beagle \
  --clean --no-owner /snapshots/beagle_<DATE>.dump

# Rebuild Qdrant projection
bash scripts/rebuild-qdrant-from-postgres.sh

# Resume
kubectl scale -n beagle deployment beagle-core --replicas=1
```

---

## 5. Staged Migration Plan

This plan is gated by the P1 eval harness (plan #4). No store retirement proceeds until the
eval gate confirms parity.

### Stage 0 — Inventory and label (no behavior change)

**Duration:** 1–2 days. **Risk:** None.

1. Audit every env var / config key that references a non-running store:
   - `NEO4J_URI` / `NEO4J_URL` — mark as `EXPERIMENTAL`, add a startup warning if set.
   - `LANCEDB_PATH` / any LanceDB env — mark as `RETIRED`, refuse to start if set
     (prevents silent empty-index usage).
2. Add a `BeagleStoreInventory` struct in `beagle-core/src/config.rs` that logs each store's
   resolved status (`system-of-record`, `projection`, `cache`, `experimental`, `retired`) at
   startup. This makes the advertising match the execution.
3. Add `pgvector` column backfill: for every node upserted via `CachedPostgresStorage` in
   `beagle-memory/src/bridge.rs`, ensure `nodes.embedding` is written via pgvector when an
   embedding is provided (it is already in the schema; the INSERT path must populate it).

### Stage 1 — Designate Qdrant as canonical projection (dual-read begins)

**Duration:** 1 week. **Risk:** Low. **Gate:** None yet (we are establishing the baseline here.

1. Implement `ContextBridge::retrieve_similar_context` (`beagle-memory/src/bridge.rs:189`)
   against `QdrantVectorStore::query` — this closes the TODO stub. The bridge already imports
   `beagle-hypergraph` types; it can accept an injected `Arc<dyn VectorStore>`.
2. Add shadow-read logging: for every retrieval call, log (not serve) the result from
   `nodes.embedding <-> query_vec` cosine scan in Postgres alongside the Qdrant result. Emit
   a metric `beagle_retrieval_source{source="qdrant"|"pgvector"}` with latency and hit count.
   This is the dual-read window; Qdrant is the served result.
3. Seed the eval gate baseline: run the P1 harness against the `beagle` Qdrant collection.
   Record nDCG@10 and Recall@10 as the initial baseline. Store in `data/eval/baseline.json`.

### Stage 2 — Hybrid retrieval lands (plan #8)

**Duration:** Concurrent with Stage 1 if plan #8 is merged. **Gate:** eval gate nDCG@10 ≥
baseline (non-regression).

The sparse vector (BM25/SPLADE) and RRF fusion path (`engine.rs` → `/points/query`) runs against
the canonical Qdrant projection. TCR-QF scoring (`tcr_qf.rs`) is plugged in as a post-retrieval
reranker (not a replacement index), gated by a feature flag `--features tcr-qf-rerank`. The
reranker validates on the eval gate before enabling by default.

### Stage 3 — Old stores read-only

**Duration:** 2 weeks after Stage 1 baseline established. **Gate:** eval gate parity (nDCG@10
within ±5% of Stage 1 baseline; Recall@10 non-regressed).

1. Remove the LanceDB configuration from all K8s manifests and `docker-compose*.yml` files.
   The Python sidecar (if any) is decommissioned.
2. Set Neo4j connection config (`NEO4J_URI`) to absent in all production manifests. The
   `Neo4jGraphStore` code remains compilable behind `#[cfg(feature = "neo4j-experimental")]`.
3. The pgvector shadow-read is turned off; the column remains as a cold backup seed for the
   rebuild procedure (§4.3).

**Rollback trigger:** if the eval gate drops more than 5% below baseline at any point, roll back
by re-enabling the shadow read source and filing a bug. The rollback is stateless (env var change
+ redeploy); no data is deleted.

### Stage 4 — Graph decision (deferred)

After the bakeoff (beagle-hypergraph's existing Postgres path vs. Apache AGE extension vs. Kuzu
embedded):

- If graph multi-hop traversal is needed: evaluate Apache AGE (Postgres extension, folds graph
  into the SoR, no new pod) against query patterns from `beagle-memory/src/graph.rs`.
- Until the bakeoff produces measured numbers, Neo4j is not deployed.
- Remove the Neo4j dep from `beagle-memory/Cargo.toml` only after the bakeoff concludes (to
  avoid breaking any test that imports `Neo4jGraphStore`).

---

## 6. Alternatives Considered

### 6.1 Promote pgvector to be the sole vector index (eliminate Qdrant)

**Rejected.** pgvector 0.8 supports iterative filtered scans but lacks built-in BM25/SPLADE
sparse vectors and the `/points/query` RRF fusion path that plan #8 requires. More importantly,
Qdrant is the only store with a measured, non-trivial corpus and an evaluated nDCG@10. Migrating
to pgvector would require rebuilding the eval baseline from scratch with no proven starting point.
The pgvector column is retained as a cold backup seed because it already exists in the schema —
not as a query path.

### 6.2 Use LanceDB as the canonical vector store

**Rejected.** No native Rust library; requires a Python sidecar; `semantic_memory_v1` was
`row_count:0` with `index_ready:false` on audit; no eval gate has ever validated it. LanceDB may
have a role in offline ColBERT research workflows but cannot be a production store without a
native driver and a deployed corpus.

### 6.3 Deploy Neo4j now and fold beagle-hypergraph into it

**Rejected for now.** The hyperedge schema in Postgres (`beagle-db/migrations/001_initial_schema.sql`)
already captures n-ary relationships with `JSONB` metadata. There is no measured query pattern
that Postgres BFS traversal (`beagle-hypergraph/src/graph/`) cannot satisfy at current scale.
Neo4j adds operational complexity (separate pod, separate backup, Bolt protocol driver) without a
proven performance justification. Apache AGE (Postgres-native Cypher) is the preferred path if
graph traversal becomes a bottleneck, and it does not add a new process.

### 6.4 Treat TCR-QF as a primary retrieval path with its own store

**Rejected.** `tcr_qf.rs` is a fusion heuristic over existing data. Its "29% improvement" header
claim cites no reproducible benchmark. The `FusionWeights` defaults are manually tuned, not
learned. It is useful as a post-retrieval reranker if and only if the P1 eval gate validates the
improvement on a real held-out query set.

---

## 7. Acceptance Criteria

This ADR is complete when:

- [x] `BeagleStoreInventory` startup log shows `system-of-record: postgres`, `projection: qdrant`,
      `cache: redis`, `experimental: neo4j`, and `external-canonical: lancedb/memory-engine`
      (revised from "retired" per §0) at every core_server startup. **DONE 2026-06-08** —
      `beagle-core/src/store_inventory.rs`, wired into `BeagleContext::new`, unit-tested.
- [ ] `ContextBridge::retrieve_similar_context` is implemented (no TODO stub at `bridge.rs:189`).
- [ ] LanceDB env vars are rejected at startup.
- [ ] The daily snapshot CronJobs (`beagle-db-snapshot`, `beagle-qdrant-snapshot`) are deployed
      and Green in the cluster.
- [ ] `scripts/rebuild-qdrant-from-postgres.sh` runs clean on a test namespace.
- [ ] The P1 eval gate baseline is recorded in `data/eval/baseline.json`.
- [ ] Stage 3 rollout completes with eval gate nDCG@10 within ±5% of baseline.

---

## DEFERRED — eval-gated steps NOT done in this ADR slice (2026-06-13)

The following items are explicitly deferred. None were executed here. Each requires the P1 eval
gate (nDCG@10 baseline in `data/eval/baseline.json`) to prove parity before proceeding.

1. **pgvector column dim fix (1536 → 1024)**: Alter `nodes.embedding` from `VECTOR(1536)` to
   `VECTOR(1024)` (a schema migration in `beagle-db/migrations/`). Deferred because altering a
   vector column in a live table requires a full table rewrite; needs a maintenance window and
   confirmed zero-downtime path, and the column is currently unqueried (the hot path uses Qdrant).

2. **Embedding backfill / re-embed for existing `nodes` rows**: Any row with a non-NULL embedding
   in `nodes.embedding` may carry a 1536-dim vector from a pre-bge-m3 model. Before the column
   becomes a usable rebuild seed, all existing embeddings must be regenerated via the current
   1024-dim TEI model. Deferred because it requires a batch job against the live Postgres pod,
   can be CPU/memory intensive, and must run only after the schema dim is corrected (item 1).

3. **§4.3 DR rebuild script correction**: The rebuild script in §4.3 hard-codes `"size":1536`.
   It must be updated to `"size":1024` (matching the live `bge-m3` model) and the
   `pg_to_qdrant_upsert.py` helper must validate that every vector it reads is exactly 1024-dim
   before upsert. Deferred until items 1 and 2 are complete (otherwise the script reads bad data).

4. **Dual-read window (Stage 1)**: Shadow-reading from `nodes.embedding` pgvector alongside Qdrant
   to compare recall. Deferred until the column contains valid 1024-dim embeddings (items 1–2).

5. **`beagle_exocortex` backfill-or-fold decision**: The Qdrant `beagle_exocortex` collection
   (745 points, 0 indexed, below HNSW threshold) must either be backfilled to a useful size or
   folded into the `semantic_memory_v1` LanceDB corpus managed by `beagle-memory-engine`. Deferred
   pending the eval gate baseline — cannot make a consolidation choice without measured parity.

6. **Graph store bakeoff (Stage 4)**: Apache AGE vs. Kuzu vs. current Postgres BFS for multi-hop
   traversal. Deferred until a real query pattern justifies the operational cost of an additional
   graph engine. No pod, no measured need, no action taken.

---

## 8. References

- `crates/beagle-db/migrations/001_initial_schema.sql` — canonical Postgres schema with
  `nodes.embedding VECTOR(1536)` and `hyperedges` tables.
- `crates/beagle-hypergraph/Cargo.toml` — `database = ["sqlx", "redis", "pgvector"]` feature
  gate; pgvector 0.4 with sqlx.
- `crates/beagle-hypergraph/src/storage/postgres.rs:1404` — semantic search not yet supported
  comment.
- `crates/beagle-core/src/implementations.rs:214-305` — `QdrantVectorStore` implementation with
  `points/search` hot path.
- `crates/beagle-core/src/context.rs:67-80` — Qdrant/NoOp fallback in `BeagleContext::new`.
- `crates/beagle-memory/src/bridge.rs:189` — `retrieve_similar_context` TODO stub targeting
  Qdrant.
- `crates/beagle-memory/src/neo4j.rs` — `Neo4jGraphStore` (compilable, no pod deployed).
- `crates/beagle-rag-update/src/qdrant.rs` — thin Qdrant HTTP client used for index population.
- `crates/beagle-hypergraph/src/rag/tcr_qf.rs` — TCR-QF fusion weights (reranker, not a store).
- `crates/beagle-hypergraph/src/rag/eval.rs` — `RetrievalMetrics` struct (nDCG, MRR, Recall).
- `docs/MODERNIZATION_PLAN_2026.md` — item #12 (this ADR's origin) and #18 (queue/graph
  consolidation; Pulsar-optional tracks separately).
