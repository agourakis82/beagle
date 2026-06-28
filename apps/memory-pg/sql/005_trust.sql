-- 005_trust.sql
-- P2: trust tiers + the fact_supports multiplicity table (design spec §2/§3).
-- Additive + idempotent.

CREATE TABLE IF NOT EXISTS fact_supports (
  fact_id uuid NOT NULL REFERENCES facts(id) ON DELETE CASCADE,
  source_record_id uuid NOT NULL REFERENCES records(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fact_id, source_record_id)
);
CREATE INDEX IF NOT EXISTS fact_supports_record_idx ON fact_supports (source_record_id);

ALTER TABLE facts   ADD COLUMN IF NOT EXISTS trust_tier text NOT NULL DEFAULT 'unverified';
ALTER TABLE facts   ADD COLUMN IF NOT EXISTS independent_user_sources int NOT NULL DEFAULT 0;
ALTER TABLE records ADD COLUMN IF NOT EXISTS trust_tier text NOT NULL DEFAULT 'unverified';

ALTER TABLE facts   DROP CONSTRAINT IF EXISTS facts_trust_tier_chk;
ALTER TABLE facts   ADD CONSTRAINT facts_trust_tier_chk
  CHECK (trust_tier IN ('unverified','claimed','corroborated','known'));
ALTER TABLE records DROP CONSTRAINT IF EXISTS records_trust_tier_chk;
ALTER TABLE records ADD CONSTRAINT records_trust_tier_chk
  CHECK (trust_tier IN ('unverified','claimed','corroborated','known'));

CREATE INDEX IF NOT EXISTS facts_trust_tier_idx   ON facts   (trust_tier);
CREATE INDEX IF NOT EXISTS records_trust_tier_idx ON records (trust_tier);
