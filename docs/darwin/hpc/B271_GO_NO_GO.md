# B27.1 — GO / NO-GO

## Phase: Study Continuation from Bounded Baseline (B27.1)

**Objective**: After B26.6 baseline adoption, automatically (or on-demand) create the next study proposal using the new baseline as canonical context. Maintain full identity and provenance across study boundaries.

## GO when

- `build_next_study_seed` succeeds after a successful B26.6 baseline adoption.
- New study proposal is created with `baseline_adoption_id` referencing the previous adoption.
- `workstream_context_packet` reflects the new bounded baseline.
- `same_beagle_owned_identity` remains `true` across study transition.
- Smoke artifacts include `next-study-seed.json` with correct linkage.
- Cluster health remains green and Slurm is UP after the transition.
- Restart of `beagle-core` preserves the continuation chain.

## GO-WITH-BLOCKER when

- Next study seed is created but context packet is not updated.
- Identity is preserved but some provenance fields are missing.
- Smoke passes locally but live cluster shows stale pods (reranker issue).

## NO-GO / STAGED when

- No `next_study_seed` is generated after baseline adoption.
- `same_beagle_owned_identity` becomes false during continuation.
- Study continuation breaks the B26.x chain (missing baseline reference).
- Smoke or validator was not executed against the live cluster.

## Honest status

To be set after:
- Updating `next_study_seed.rs` and `study_continuation.rs` (if exists)
- Running `run_baseline_adoption_smoke.sh` followed by new continuation smoke
- Executing `cargo check -p beagle-darwin`
- Validating live cluster behavior

**Current artifacts status**: B26.6 is live. This phase (B27.1) is the logical next step.
