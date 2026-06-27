// prov-backfill.mjs — one-shot, idempotent heuristic classification of historical
// records' provenance actor. Only touches rows still at the conservative migration
// default ('model_generated'), so forward-path tags are never overwritten and
// re-running is a no-op. See design spec 2026-06-27-memory-provenance-trust §5.

/**
 * Classify existing records' prov_actor by source_type.
 * @param {import("pg").Pool} pool
 * @returns {Promise<{distilled: number, imported: number}>}
 */
export async function backfillProvenance(pool) {
  const distilled = await pool.query(
    `UPDATE records SET prov_actor = 'model_distilled'
      WHERE source_type = 'MemoryAtom' AND prov_actor = 'model_generated'`,
  );
  const imported = await pool.query(
    `UPDATE records SET prov_actor = 'external_import'
      WHERE source_type = 'MemoryEpisode' AND prov_actor = 'model_generated'`,
  );
  return { distilled: distilled.rowCount, imported: imported.rowCount };
}

export default backfillProvenance;
