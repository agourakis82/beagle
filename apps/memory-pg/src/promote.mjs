// promote.mjs — materialize trust tiers (design spec §2/§3).
//
// Full-table path (--full / FULL_RECOMPUTE=1, or first run when no watermark exists):
//   Resets ALL facts/records to 'unverified', then recomputes. Idempotent; both
//   promotes AND demotes as supporting evidence changes. This is the only path that
//   can catch deletions from fact_supports.
//
// Incremental path (subsequent runs, when a promote_watermarks row exists):
//   Finds only fact_supports / records whose created_at is after the last watermark,
//   resets and recomputes ONLY those rows. Typically touches < 1% of the table on a
//   6-hour cycle over 82K records / 372K facts.
//
// DEMOTION-GUARANTEE CAVEAT: the incremental path cannot re-evaluate a fact whose
// fact_supports row was DELETED since the last watermark — deletions are invisible to
// a created_at filter. Schedule --full / FULL_RECOMPUTE=1 (e.g. weekly) to catch
// orphaned or deleted supports and correctly demote those facts.

// Session key: P1.5 writes metadata.session_id; historical uses metadata.provenance.session_id.
// Fall back to the record id so an unkeyed record is its own session (never falsely merged).
const SESSION_KEY =
  "COALESCE(NULLIF(r.metadata->>'session_id',''), r.metadata->'provenance'->>'session_id', r.id::text)";

/**
 * Read the most recent promote watermark from the DB.
 * @param {import("pg").Pool} pool
 * @returns {Promise<Date|null>}
 */
async function getLastRan(pool) {
  const res = await pool.query(
    "SELECT MAX(ran_at) AS last_ran FROM promote_watermarks");
  return res.rows[0]?.last_ran ?? null;
}

/**
 * Recompute every fact's trust_tier from the count of INDEPENDENT user_stated supporters,
 * where independence = a distinct (session, day) pair.
 *
 * Incremental (default when a promote_watermarks row exists): only re-evaluates facts
 * whose supporting rows arrived after the last watermark. Much faster; misses deletions
 * (see demotion-guarantee caveat above).
 *
 * Full (--full / FULL_RECOMPUTE=1, or first run): resets ALL facts then recomputes.
 *
 * @param {import("pg").Pool} pool
 * @param {{ knownSpanDays?: number, full?: boolean, lastRan?: Date|null }} [opts]
 *   lastRan: pass the watermark read by the caller so both promoteFacts and promoteRecords
 *   use the SAME baseline within a single cycle (prevents cross-contamination when each
 *   function would otherwise re-read the table and see the other function's freshly
 *   inserted watermark).
 * @returns {Promise<number>} count of facts whose tier was updated
 */
export async function promoteFacts(pool, { knownSpanDays = 7, full = false, lastRan: lastRanOverride } = {}) {
  // Callers (promote-worker) should pass lastRan so both functions share the same
  // baseline watermark. Standalone callers (tests etc.) omit it and we read from DB.
  const lastRan = (lastRanOverride !== undefined) ? lastRanOverride : await getLastRan(pool);

  let factsUpdated = 0;

  if (!full && lastRan) {
    // --- INCREMENTAL PATH ---
    // Identify facts that gained new supporting rows since the last run.
    const affectedRes = await pool.query(
      `SELECT DISTINCT fact_id FROM fact_supports WHERE created_at > $1`,
      [lastRan]);
    const affectedIds = affectedRes.rows.map((r) => r.fact_id);

    if (affectedIds.length > 0) {
      // Reset only the affected facts to the neutral baseline.
      await pool.query(
        `UPDATE facts SET trust_tier = 'unverified', independent_user_sources = 0
         WHERE id = ANY($1)`,
        [affectedIds]);

      // Recompute trust tier for ONLY the affected facts.
      const res = await pool.query(
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
                  AND fs.fact_id = ANY($2)
             ) distinct_pairs
            GROUP BY fact_id
         ) a
         WHERE f.id = a.fact_id`,
        [knownSpanDays, affectedIds]);
      factsUpdated = res.rowCount ?? affectedIds.length;
    }
    // If affectedIds is empty, factsUpdated stays 0; watermark still advances below.
  } else {
    // --- FULL-TABLE PATH (first run, weekly recompute, or --full) ---
    // Reset everything first so the pass demotes as well as promotes.
    await pool.query(
      "UPDATE facts SET trust_tier = 'unverified', independent_user_sources = 0");
    const res = await pool.query(
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
      [knownSpanDays]);
    factsUpdated = res.rowCount ?? 0;
  }

  // Always advance the watermark so the next cycle knows where to start.
  await pool.query(
    "INSERT INTO promote_watermarks (facts_updated, records_updated) VALUES ($1, 0)",
    [factsUpdated]);
  return factsUpdated;
}

/**
 * Give every record a base tier from its own provenance (no corroboration counting):
 * orphaned distilled or model_generated/system → unverified; user_stated / external_import /
 * non-orphan distilled → claimed. The quorum (corroborated/known) lives on facts.
 *
 * Always runs full-table. An incremental path keyed on records.created_at is not viable
 * here because the corpus contains historical records with backdated created_at values
 * (e.g. past conversation imports) that would always predate any promote_watermarks entry.
 * Filtering on created_at would silently skip them on every incremental run. The UPDATE
 * itself has no joins and is just a column expression, so it is fast even at 82K rows.
 *
 * The `full` and `lastRan` params are accepted for API symmetry with promoteFacts but
 * have no effect on the execution path. A watermark row is still inserted so the
 * cycle timestamp advances consistently.
 *
 * @param {import("pg").Pool} pool
 * @param {{ full?: boolean, lastRan?: Date|null }} [opts]
 * @returns {Promise<number>} count of records whose tier was updated
 */
export async function promoteRecords(pool, { full: _full, lastRan: _lastRan } = {}) {
  // Always full-table: see rationale in JSDoc above.
  const res = await pool.query(
    `UPDATE records SET trust_tier = CASE
       WHEN prov_orphan THEN 'unverified'
       WHEN prov_actor IN ('user_stated','external_import','model_distilled') THEN 'claimed'
       ELSE 'unverified'
     END`);
  const recordsUpdated = res.rowCount ?? 0;

  // Always advance the watermark so the cycle timestamp is recorded.
  await pool.query(
    "INSERT INTO promote_watermarks (facts_updated, records_updated) VALUES (0, $1)",
    [recordsUpdated]);
  return recordsUpdated;
}

export default { promoteFacts, promoteRecords };
