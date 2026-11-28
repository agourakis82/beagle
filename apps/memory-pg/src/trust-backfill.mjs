// trust-backfill.mjs — seed fact_supports for facts created before P2, from the single
// source the dedup kept (facts.source_record_id). Idempotent (ON CONFLICT DO NOTHING).

/**
 * @param {import("pg").Pool} pool
 * @returns {Promise<{inserted: number}>}
 */
export async function backfillFactSupports(pool) {
  const res = await pool.query(
    `INSERT INTO fact_supports (fact_id, source_record_id)
     SELECT id, source_record_id FROM facts
      WHERE source_record_id IS NOT NULL
     ON CONFLICT (fact_id, source_record_id) DO NOTHING`);
  return { inserted: res.rowCount };
}

export default backfillFactSupports;
