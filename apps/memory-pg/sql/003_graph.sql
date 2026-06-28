-- 003_graph.sql — Phase 4: bi-temporal knowledge graph (Graphiti-style, sovereign).
--
-- Decision gate (Task 4.1): AGE is NOT available in this image (only vector +
-- pg_search), so the graph is RELATIONAL with recursive-CTE traversal — which was
-- the locked decision anyway (backup-safe, no extra extension, ergonomic enough
-- for the 1-2 hop queries we need). Entities are nodes; facts are edges. Facts are
-- bi-temporal: valid_from/valid_to bound when the fact held in the world,
-- recorded_at is when we learned it. Invalidation sets valid_to = now() — facts
-- are NEVER deleted, so history is preserved and contradictions are auditable.

CREATE TABLE IF NOT EXISTS entities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  norm_name text NOT NULL,                 -- lowercased + whitespace-collapsed, for exact dedup
  type text NOT NULL DEFAULT 'unknown',
  embedding halfvec(1024),                 -- name/summary embedding for near-dup resolution
  summary text NOT NULL DEFAULT '',
  content_sha256 text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (norm_name, type)
);
CREATE INDEX IF NOT EXISTS entities_emb_hnsw ON entities
  USING hnsw (embedding halfvec_cosine_ops) WITH (m=16, ef_construction=128)
  WHERE embedding IS NOT NULL;

CREATE TABLE IF NOT EXISTS facts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
  predicate text NOT NULL,
  object_id uuid REFERENCES entities(id) ON DELETE CASCADE,  -- NULL when the object is a literal
  object_literal text,                                       -- e.g. a date, number, place name
  statement text NOT NULL,                                   -- the natural-language fact
  embedding halfvec(1024),                                   -- statement embedding (graph retrieval channel)
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_to timestamptz,                                      -- NULL = currently valid; set on invalidation
  occurred_at timestamptz,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  source_record_id uuid REFERENCES records(id) ON DELETE SET NULL,
  provenance jsonb NOT NULL DEFAULT '{}',
  confidence real NOT NULL DEFAULT 1.0,
  content_sha256 text NOT NULL,
  UNIQUE (content_sha256)
);
CREATE INDEX IF NOT EXISTS facts_subject_current ON facts (subject_id) WHERE valid_to IS NULL;
CREATE INDEX IF NOT EXISTS facts_object_current ON facts (object_id) WHERE valid_to IS NULL;
CREATE INDEX IF NOT EXISTS facts_emb_hnsw ON facts
  USING hnsw (embedding halfvec_cosine_ops) WITH (m=16, ef_construction=128)
  WHERE valid_to IS NULL AND embedding IS NOT NULL;

-- Transactional outbox for graph extraction (Task 4.3 wires the SKIP-LOCKED worker).
-- captureRecord enqueues one row per record; the worker drains it via a sovereign LLM.
CREATE TABLE IF NOT EXISTS pending_graph (
  id bigserial PRIMARY KEY,
  record_id uuid NOT NULL REFERENCES records(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending',
  retry_count int NOT NULL DEFAULT 0,
  locked_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS failed_graph (LIKE pending_graph INCLUDING ALL);
