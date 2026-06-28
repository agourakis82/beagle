// promote.mjs — materialize trust tiers (design spec §2/§3). Idempotent + full-table,
// so it both promotes and demotes as supporting evidence changes.

// Session key: P1.5 writes metadata.session_id; historical uses metadata.provenance.session_id.
// Fall back to the record id so an unkeyed record is its own session (never falsely merged).
const SESSION_KEY =
  "COALESCE(NULLIF(r.metadata->>'session_id',''), r.metadata->'provenance'->>'session_id', r.id::text)";

/**
 * Recompute every fact's trust_tier from the count of INDEPENDENT user_stated supporters,
 * where independence = a distinct (session, day) pair. Resets first so it demotes too.
 * @param {import("pg").Pool} pool
 * @param {{knownSpanDays?: number}} [opts]
 */
export async function promoteFacts(pool, { knownSpanDays = 7 } = {}) {
  await pool.query(
    "UPDATE facts SET trust_tier = 'unverified', independent_user_sources = 0");
  await pool.query(
    `UPDATE facts f SET
       independent_user_sources = a.n,
       trust_tier = CASE
         WHEN a.n = 1 THEN 'claimed'
         WHEN a.span_days >= $1 THEN 'known'
         ELSE 'corroborated'
       END
     FROM (
       SELECT fact_id,
              COUNT(*)                         AS n,
              MAX(day) - MIN(day)              AS span_days
         FROM (
           SELECT DISTINCT fs.fact_id, ${SESSION_KEY} AS sess, r.created_at::date AS day
             FROM fact_supports fs
             JOIN records r ON r.id = fs.source_record_id
            WHERE r.prov_actor = 'user_stated'
         ) distinct_pairs
        GROUP BY fact_id
     ) a
     WHERE f.id = a.fact_id`,
    [knownSpanDays],
  );
}

/**
 * Give every record a base tier from its own provenance (no corroboration counting):
 * orphaned distilled or model_generated/system → unverified; user_stated / external_import /
 * non-orphan distilled → claimed. The quorum (corroborated/known) lives on facts.
 * @param {import("pg").Pool} pool
 */
export async function promoteRecords(pool) {
  await pool.query(
    `UPDATE records SET trust_tier = CASE
       WHEN prov_orphan THEN 'unverified'
       WHEN prov_actor IN ('user_stated','external_import','model_distilled') THEN 'claimed'
       ELSE 'unverified'
     END`);
}

export default { promoteFacts, promoteRecords };
