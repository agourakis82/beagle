# ADR 0001 — Memory store consolidation (plan #12 / #18)

**Status:** Proposed · **Date:** 2026-06-05 · **Context:** Beagle core modernization (see
`docs/MODERNIZATION_PLAN_2026.md`).

## Context (measured, not assumed)

The memory layer advertises a large multi-backend "store zoo", but most of it **is not deployed**.
Measured 2026-06-05:

- **beagle-memory-engine** is configured (env) for **9+ backends**: FalkorDB, Memgraph, SurrealDB,
  ArangoDB, ArcadeDB (network graph DBs), Kuzu, DuckDB-VSS, LanceDB (embedded/file on OrangeFS),
  TypeDB, and a `postgres-vector`. **None of the network ones are deployed** — no Services/pods exist
  for them; the env URLs point at nothing. Only the file-based paths (LanceDB/Kuzu/DuckDB on
  `/orangefs/beagle-memory-lab`) and JSONL fallbacks actually run.
- The only vector service actually running is **Qdrant** (`qdrant.beagle.svc:6333`), holding the
  cockpit's `cockpit_rag` (≈24k points, 1024-dim, TEI embeddings) — a real, healthy index
  (cockpit eval: nDCG@10 0.557 / recall@10 0.65).
- The memory-engine's named "production" index `semantic_memory_v1` (LanceDB ColBERT) ran empty until
  this cycle; it now holds 1472 rows via real TEI embeddings, served by a pure-Python JSONL fallback
  (native LanceDB lib absent from the image). See `cockpit/beagle-ops/` in darwin-cluster.
- beagle-core also nominally uses Postgres+pgvector / Redis / Neo4j / Pulsar; of these only what is
  actually deployed should be treated as load-bearing (Pulsar is hard-required by prod compose yet
  absent — see plan #18).

The proven, operational pattern is the **cockpit**: SQLite as system-of-record + a single Qdrant
projection (rebuildable, DR runbook, daily snapshot, eval regression gate). That is the north-star.

## Decision

1. **One system-of-record.** Relational SoR (Postgres for beagle-core; SQLite for the cockpit
   plane). All else is a **derived, rebuildable projection**, never a second source of truth.
2. **One vector index: Qdrant.** It is the only vector store actually running and the only one with a
   real, evaluated corpus. Demote LanceDB/DuckDB-VSS/`postgres-vector` to **experimental** (feature-
   gated), not parallel production paths. The memory-engine's semantic index becomes a *projection*
   over the SoR via Qdrant, not its own truth.
3. **At most one graph store, and only if a query pattern needs it.** The 5 undeployed network graph
   DBs (FalkorDB/Memgraph/SurrealDB/ArangoDB/ArcadeDB) + TypeDB are a **bakeoff**, not production.
   Keep the bakeoff harness (`beagle_memory_bakeoff_*`) but **remove their config from the default
   runtime** so the engine doesn't advertise/dial non-existent services. Pick at most one (Apache AGE
   inside Postgres is the lowest-footprint candidate — folds graph into the SoR; evaluate vs Kuzu
   embedded) after the bakeoff produces numbers.
4. **Treat TCR-QF / hypergraph as an optional reranking/multi-hop MODULE** over the canonical store,
   not a third stack.
5. **No store is load-bearing unless it is deployed and on the eval gate.** Config that points at a
   non-running service is deleted, not left as aspirational plumbing.

Target end-state: **2 stores** — Postgres/SQLite (SoR, optionally + AGE for graph) and Qdrant (vector
projection) — with Redis as cache only and the queue made optional (plan #18).

## Consequences

- **+** Removes the advertised-but-undeployed sprawl (a class of the platform's "advertised ≠
  executing" gap); makes retrieval measurable end-to-end against one index + the P1 eval gate.
- **+** DR + backups become tractable (one SoR + one rebuildable projection, the cockpit runbook).
- **−** Loses optionality of the bakeoff backends in production (kept behind a flag for research).
- **Risk:** migration must be staged behind dual-read/dual-write windows with the **eval gate proving
  parity** before any old store is retired (no flag-day cutover). High effort (plan rates this L/XL).

## Migration plan (staged; each stage gated by the P1 eval harness)

1. **Inventory + label** every store as `production` / `experimental` / `dead-config`; delete dead
   env/URLs from the runtime manifests (no behavior change — they pointed at nothing).
2. **Designate Qdrant the canonical vector projection**; point the memory-engine semantic path at it
   (or keep LanceDB strictly as an embedded projection rebuilt from the SoR). Write the rebuild +
   snapshot runbook (mirror the cockpit's).
3. **Seed the eval baseline** against the canonical index (needs the corpus indexed there).
4. **Dual-read window**: serve from the canonical index while shadow-reading the old paths; compare
   on the eval gate. Retire an old path only when parity holds.
5. **Graph decision** after the bakeoff: fold into Postgres (AGE) or keep Kuzu embedded; remove the
   rest.
6. **Queue**: make Pulsar optional / evaluate pgmq (plan #18) so prod can boot without it.

## Status of related work

- Vector index populated + queryable with real embeddings (plan #1) — done this cycle.
- Hybrid retrieval (dense+lexical RRF) in `beagle-memory` (plan #8) — merged.
- Eval regression gate (plan #1/P1) — merged; awaits a canonical populated corpus to seed a
  Beagle-side baseline (this ADR unblocks that).
