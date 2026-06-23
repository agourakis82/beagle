-- 000_extensions.sql
-- Phase 0, Task 0.1 — required extensions for the reliable memory pipeline.
--
-- NOTE (Phase 0 spike result, 2026-06-23): the live beagle-pg image is
-- `pgvector/pgvector:pg16` (PostgreSQL 16.14) which ships ONLY pgvector 0.8.2.
-- `pg_search` (ParadeDB BM25) and `age` (Apache AGE) are NOT available on this
-- image and CANNOT be CREATE EXTENSION-ed until a custom Postgres image bundling
-- all three is built and the beagle-pg Stateful/Deployment is migrated onto it.
-- Also note pgvector must reach >=0.8.3 (HNSW vacuum-corruption fix) via the
-- image bump. Do NOT run this file against production until that image exists.
--
-- `age` is gated behind the Task 4.1 graph-backend decision (AGE vs recursive-CTE).
-- If recursive-CTE is chosen, drop the `age` line — it needs no extension.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;
CREATE EXTENSION IF NOT EXISTS age;
