-- 000_extensions.sql
-- Phase 0, Task 0.1 — required extensions for the reliable memory pipeline.
--
-- DECISION (post-0.1 spike, 2026-06-23): the pipeline runs on a DEDICATED
-- `memory-pg` Postgres instance (NOT the shared beagle-pg/Physiome instance),
-- built from the ParadeDB image which bundles `pg_search` (BM25) and a recent
-- pgvector (>=0.8.3, the HNSW vacuum-corruption fix). Only two extensions are
-- created here:
--
--   * vector    — pgvector, dense/HNSW vector search (must be >=0.8.3)
--   * pg_search — ParadeDB BM25 lexical search
--
-- AGE (Apache AGE / `age`) is DEFERRED: the graph backend was resolved to
-- recursive-CTE on plain Postgres (plan Task 4.1), which needs no extension.
-- Revisit AGE only if deep multi-hop graph traversal is measured as deficient.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;
