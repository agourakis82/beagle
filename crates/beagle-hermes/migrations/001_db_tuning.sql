-- PostgreSQL Performance Tuning for HERMES BPSE
-- Run after initial schema creation

-- Index on manuscripts state (frequently queried)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_manuscripts_state_updated 
ON manuscripts(state, updated_at DESC);

-- Index on insights timestamp + source
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_insights_timestamp_source
ON insights(timestamp DESC, source);

-- Partial index for active manuscripts (not published)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_manuscripts_active
ON manuscripts(updated_at DESC)
WHERE state != 'Published';

-- Index for concept lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_concepts_name_lower
ON concepts(LOWER(name));

-- Composite index for synthesis queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_insights_concept_timestamp
ON insight_concepts(concept_id, insight_id, created_at DESC);

-- VACUUM and ANALYZE
VACUUM ANALYZE manuscripts;
VACUUM ANALYZE insights;
VACUUM ANALYZE concepts;

-- Configure connection pooling (requires superuser)
-- ALTER SYSTEM SET max_connections = 200;
-- ALTER SYSTEM SET shared_buffers = '4GB';
-- ALTER SYSTEM SET effective_cache_size = '12GB';
-- ALTER SYSTEM SET work_mem = '64MB';
-- SELECT pg_reload_conf();

-- Note: System-level settings require PostgreSQL restart
-- For Docker, configure in postgresql.conf or environment variables

