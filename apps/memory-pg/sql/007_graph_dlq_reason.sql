-- 007_graph_dlq_reason.sql
-- The DLQ recorded THAT a record failed extraction, never WHY. A queue you can
-- only count is a queue you cannot diagnose: the graph pipeline spent 29 days
-- emitting facts=0 with an empty DLQ and no logs, because failures were being
-- converted into empty successes upstream. With that fixed, the reason has to
-- land somewhere durable.
-- Additive + idempotent.

ALTER TABLE failed_graph  ADD COLUMN IF NOT EXISTS last_error text;
ALTER TABLE pending_graph ADD COLUMN IF NOT EXISTS last_error text;
