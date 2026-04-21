# B22.5 — Code Retrieval Pilot with `voyage-code-3`

## Objective

Add the first bounded code-retrieval lane on top of the canonical hybrid retrieval spine without changing:

- `Qdrant` as the long-term store direction
- `voyage-4-large` as the canonical general dense backend
- `local-lexical` as the sparse path
- the canonical memory payload and filter model

## What changes in this phase

1. Adds explicit `repo_path` and `file_type` to the canonical memory payload.
2. Exposes a bounded code retrieval query surface for repo-native code/config/script retrieval.
3. Uses `voyage-code-3` as the dense code pilot while preserving the general `voyage-4-large` lane.
4. Keeps comparison against the current general dense path explicit.
5. Preserves payload-aware filters over:
   - `repo_path`
   - `file_type`
   - `workstream_id`
   - `campaign_id`
   - `session_id`

## Important boundary

This phase does not pretend that `voyage-code-3` can safely query vectors already materialized with `voyage-4-large` in-place.

The bounded pilot therefore:

- keeps the same canonical payload collection and retrieval identity
- reuses the same repo-native memory records
- runs the code-dense lane locally over candidate records with `voyage-code-3`
- keeps the general retrieval path untouched

That gives Beagle a real code-oriented retrieval experiment without forcing a Qdrant reindex or a store migration.

## Canonical result

- General dense backend: `voyage-4-large`
- Code dense pilot backend: `voyage-code-3`
- Sparse backend: `local-lexical`
- Store direction: `Qdrant` remains canonical
