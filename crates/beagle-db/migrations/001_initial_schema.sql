-- ===========================================================================
-- Beagle Hypergraph Initial Schema
-- Defines core data structures, synchronization metadata, and helper routines
-- ===========================================================================

BEGIN;

-- ===== Extensions ==========================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ===== Tables ============================================================== 
-- Nodes capture the fundamental cognitive units handled by Beagle's hypergraph
CREATE TABLE IF NOT EXISTS nodes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  content TEXT NOT NULL CHECK (length(content) > 0),
  content_type VARCHAR(50) NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  embedding VECTOR(1536),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  device_id VARCHAR(255) NOT NULL,
  version INTEGER NOT NULL DEFAULT 0,
  CONSTRAINT nodes_valid_metadata CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object')
);

-- Hyperedges encode n-ary relationships between nodes
CREATE TABLE IF NOT EXISTS hyperedges (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  label VARCHAR(255) NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  device_id VARCHAR(255) NOT NULL,
  version INTEGER NOT NULL DEFAULT 0,
  is_directed BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT hyperedges_valid_metadata CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object')
);

-- Junction table connecting nodes to hyperedges, preserving ordering and roles
CREATE TABLE IF NOT EXISTS edge_nodes (
  hyperedge_id UUID NOT NULL REFERENCES hyperedges(id) ON DELETE CASCADE,
  node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  position INTEGER NOT NULL DEFAULT 0,
  role VARCHAR(50),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (hyperedge_id, node_id, position)
);

-- Vector clocks maintain per-device synchronization state
CREATE TABLE IF NOT EXISTS sync_vector_clocks (
  device_id VARCHAR(255) PRIMARY KEY,
  clock INTEGER NOT NULL DEFAULT 0,
  last_sync TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Sync log records mutation history for conflict resolution and replay
CREATE TABLE IF NOT EXISTS sync_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  operation VARCHAR(50) NOT NULL,
  entity_type VARCHAR(50) NOT NULL,
  entity_id UUID NOT NULL,
  device_id VARCHAR(255) NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  data JSONB NOT NULL,
  CONSTRAINT sync_log_valid_data CHECK (jsonb_typeof(data) = 'object')
);

-- ===== Indexes ============================================================= 
-- Nodes indices optimise soft-delete filtering, device partitioning, and search
CREATE INDEX IF NOT EXISTS idx_nodes_deleted_at ON nodes (deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_nodes_device_id ON nodes (device_id);
CREATE INDEX IF NOT EXISTS idx_nodes_created_at ON nodes (created_at);
CREATE INDEX IF NOT EXISTS idx_nodes_content_type ON nodes (content_type);
CREATE INDEX IF NOT EXISTS idx_nodes_embedding ON nodes USING ivfflat (embedding vector_l2_ops) WITH (lists = 100);

-- Hyperedge indices accelerate retrieval by lifecycle and semantic label
CREATE INDEX IF NOT EXISTS idx_hyperedges_deleted_at ON hyperedges (deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_hyperedges_label ON hyperedges (label);

-- Edge-node indices support inverse lookups from nodes into relationships
CREATE INDEX IF NOT EXISTS idx_edge_nodes_node_id ON edge_nodes (node_id);

-- ===== Functions & Triggers ===============================================
-- Maintain updated_at timestamps automatically for mutable entities
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_nodes_updated_at ON nodes;
CREATE TRIGGER trg_nodes_updated_at
BEFORE UPDATE ON nodes
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trg_hyperedges_updated_at ON hyperedges;
CREATE TRIGGER trg_hyperedges_updated_at
BEFORE UPDATE ON hyperedges
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Recursive neighborhood query traverses hyperedges breadth-first
CREATE OR REPLACE FUNCTION query_neighborhood(start_node UUID, max_depth INTEGER)
RETURNS TABLE (node_id UUID, distance INTEGER)
LANGUAGE sql
AS $$
  WITH RECURSIVE traversal AS (
    SELECT start_node AS node_id, 0 AS distance
    UNION ALL
    SELECT en.node_id, traversal.distance + 1
    FROM traversal
    JOIN edge_nodes e
      ON e.node_id = traversal.node_id
    JOIN edge_nodes en
      ON en.hyperedge_id = e.hyperedge_id
    WHERE en.node_id <> traversal.node_id
      AND traversal.distance + 1 <= COALESCE(max_depth, traversal.distance + 1)
  ),
  ranked AS (
    SELECT node_id, distance,
           ROW_NUMBER() OVER (PARTITION BY node_id ORDER BY distance) AS rn
    FROM traversal
  )
  SELECT node_id, distance
  FROM ranked
  WHERE rn = 1
  ORDER BY distance, node_id;
$$;

-- ===== Views ===============================================================
CREATE OR REPLACE VIEW cluster_health AS
SELECT
  COUNT(*) FILTER (WHERE deleted_at IS NULL) AS active_nodes,
  COUNT(*) FILTER (WHERE deleted_at IS NOT NULL) AS deleted_nodes,
  (SELECT COUNT(*) FROM hyperedges WHERE deleted_at IS NULL) AS active_edges,
  (SELECT COUNT(*) FROM hyperedges WHERE deleted_at IS NOT NULL) AS deleted_edges,
  (SELECT COUNT(DISTINCT device_id) FROM sync_vector_clocks) AS devices_synced,
  (SELECT MAX(last_sync) FROM sync_vector_clocks) AS last_sync_time
FROM nodes;

-- ===== Seed Data ===========================================================
-- Example nodes representing Thought, Memory, and Context archetypes
INSERT INTO nodes (id, content, content_type, metadata, device_id, embedding)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'Initial philosophical insight', 'Thought', '{"tags": ["init"]}'::jsonb, 'device-alpha', NULL),
  ('00000000-0000-0000-0000-000000000002', 'Empirical observation log', 'Memory', '{"tags": ["observation"]}'::jsonb, 'device-alpha', NULL),
  ('00000000-0000-0000-0000-000000000003', 'Clinical context anchor', 'Context', '{"tags": ["clinical"]}'::jsonb, 'device-alpha', NULL)
ON CONFLICT (id) DO NOTHING;

-- Seed hyperedge linking the archetype nodes
INSERT INTO hyperedges (id, label, metadata, device_id, is_directed)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'relates', '{"strength": "moderate"}'::jsonb, 'device-alpha', FALSE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO edge_nodes (hyperedge_id, node_id, position, role)
VALUES
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 0, 'source'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 1, 'evidence'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 2, 'context')
ON CONFLICT DO NOTHING;

-- Initial synchronization state for device-alpha
INSERT INTO sync_vector_clocks (device_id, clock, last_sync)
VALUES ('device-alpha', 0, NOW())
ON CONFLICT (device_id) DO NOTHING;

-- Corresponding sync log entry capturing the bootstrap state
INSERT INTO sync_log (id, operation, entity_type, entity_id, device_id, data)
VALUES
  (
    '20000000-0000-0000-0000-000000000001',
    'INSERT',
    'hyperedge',
    '10000000-0000-0000-0000-000000000001',
    'device-alpha',
    '{
      "nodes": [
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000002",
        "00000000-0000-0000-0000-000000000003"
      ],
      "label": "relates"
    }'::jsonb
  )
ON CONFLICT (id) DO NOTHING;

COMMIT;

