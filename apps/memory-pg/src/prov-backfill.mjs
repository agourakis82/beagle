// prov-backfill.mjs — one-shot, idempotent heuristic classification of historical
// records' provenance actor. Only touches rows still at the conservative migration
// default ('model_generated'), so forward-path tags are never overwritten and
// re-running is a no-op. See design spec 2026-06-27-memory-provenance-trust §5.
//
// SECURITY INVARIANT (do not relax): a blind heuristic must NEVER grant a *trusted*
// actor (`user_stated` / `external_import`) to historical bulk. Those actors are
// accepted as valid orphan-ancestors and corroboration sources — granting them to
// mixed-provenance imports would launder trust onto unverified (possibly model- or
// agent-authored) content, defeating the whole point of provenance. Trusted actors are
// assigned ONLY by the forward path, where authorship is actually known. So:
//   - MemoryAtom (distilled atoms with no traced user ancestor) → model_distilled AND
//     prov_orphan=true (untrusted until corroborated). They have empty prov_derived_from,
//     so this matches exactly what the write-time orphan check would have flagged.
//   - MemoryEpisode and everything else → left at the conservative model_generated
//     default. Imports are NOT elevated to external_import here; the bulk is mixed
//     agent/codex/assistant content, not verifiably the user's own words.

/**
 * Classify existing records' provenance conservatively. Never grants a trusted actor.
 * @param {import("pg").Pool} pool
 * @returns {Promise<{distilled: number}>} count of MemoryAtoms marked model_distilled + orphan
 */
export async function backfillProvenance(pool) {
  const distilled = await pool.query(
    `UPDATE records SET prov_actor = 'model_distilled', prov_orphan = true
      WHERE source_type = 'MemoryAtom' AND prov_actor = 'model_generated'`,
  );
  return { distilled: distilled.rowCount };
}

export default backfillProvenance;
