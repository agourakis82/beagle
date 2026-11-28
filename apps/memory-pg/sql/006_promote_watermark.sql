-- 006_promote_watermark.sql
-- Tracks the last run time (and counts) of each promote cycle so the incremental
-- paths in promoteFacts / promoteRecords can efficiently find only the
-- fact_supports / records that arrived since the previous run.
--
-- One row is inserted per function call (facts and records tracked separately via
-- their respective _updated columns). Both functions read MAX(ran_at) to establish
-- the last-known-good watermark.
--
-- Additive + idempotent (CREATE TABLE IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS promote_watermarks (
  id               serial      PRIMARY KEY,
  ran_at           timestamptz NOT NULL DEFAULT now(),
  facts_updated    int         NOT NULL DEFAULT 0,
  records_updated  int         NOT NULL DEFAULT 0
);
