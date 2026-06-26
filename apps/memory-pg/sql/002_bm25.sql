-- 002_bm25.sql
-- Phase 2, Task 2.1 — ParadeDB pg_search BM25 index on chunks.text for the
-- lexical channel of hybrid retrieval (dense + BM25 → RRF fusion).
--
-- Verified syntax for pg_search 0.24.1 (live memory-pg, Postgres 16.14):
--   * index:  USING bm25 (id, text) WITH (key_field='id')   -- id is the PK
--   * match:  text @@@ 'query'                               -- term-tokenized, OR semantics
--   * score:  paradedb.score(id)                             -- BM25 relevance score
--
-- The index is created idempotently (IF NOT EXISTS). `ensureSchema` runs the
-- sql/*.sql files in lexical order, so 002 follows 001 (which creates `chunks`).

CREATE INDEX IF NOT EXISTS chunks_bm25 ON chunks
  USING bm25 (id, text)
  WITH (key_field='id');
