-- 001_core.sql
-- Phase 0, Task 0.2 — core vertical-split schema (records / chunks / embeddings
-- + transactional-outbox queues). Source of truth: the plan's Task 0.2 Step 3.
-- Scaffold only — NOT executed against any DB in the Phase 0 spike.

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
