-- 004_provenance.sql
-- P1: per-record provenance (design spec 2026-06-27-memory-provenance-trust).
-- Additive + idempotent (IF NOT EXISTS). prov_actor defaults to the conservative
-- 'model_generated' so existing rows and untagged writers never auto-enter biography.

ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_actor text NOT NULL DEFAULT 'model_generated';
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_surface text;
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_derived_from uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_confidence real;
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_asserted_at timestamptz;
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_orphan boolean NOT NULL DEFAULT false;

-- Closed actor taxonomy. Drop-then-add so re-running picks up any edit idempotently.
ALTER TABLE records DROP CONSTRAINT IF EXISTS records_prov_actor_chk;
ALTER TABLE records ADD CONSTRAINT records_prov_actor_chk
  CHECK (prov_actor IN ('user_stated','model_generated','model_distilled','external_import','system'));

CREATE INDEX IF NOT EXISTS records_prov_actor_idx ON records (prov_actor);
CREATE INDEX IF NOT EXISTS records_prov_orphan_idx ON records (prov_orphan) WHERE prov_orphan;
