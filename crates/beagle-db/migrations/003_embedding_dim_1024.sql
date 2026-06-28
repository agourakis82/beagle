-- migrate:up
-- #12 (canonical-store, ADR 0001): reconcile the pgvector backup column dimension.
--
-- nodes.embedding was VECTOR(1536) (migration 001) but every LIVE embedding index in
-- the platform is 1024-dim (BAAI/bge-m3 dense + jinaai/jina-colbert-v2). The §4.3
-- rebuild-from-Postgres procedure was therefore BROKEN (it would create a 1536-dim
-- collection incompatible with all live embeddings). This migration corrects the
-- schema to 1024 so Postgres can serve as the rebuildable source-of-record projection.
--
-- SAFE: at migration time the column held ZERO embeddings (0 rows non-null), so this is
-- a pure schema correction with no data loss. DROP+ADD (not ALTER TYPE) keeps it explicit.
DROP INDEX IF EXISTS idx_nodes_embedding;
ALTER TABLE nodes DROP COLUMN IF EXISTS embedding;
ALTER TABLE nodes ADD COLUMN embedding vector(1024);
CREATE INDEX IF NOT EXISTS idx_nodes_embedding ON nodes USING ivfflat (embedding vector_l2_ops) WITH (lists = 100);
