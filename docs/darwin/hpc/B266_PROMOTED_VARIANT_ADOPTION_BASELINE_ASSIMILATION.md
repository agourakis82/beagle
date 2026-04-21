# B26.6 — Promoted variant adoption / baseline assimilation

## Purpose

Materialize the **bounded baseline** after B26.5: the promoted variant is recorded as the canonical baseline for planner, workbench context, and future study **seeds**, without auto-launching a new study and **without** removing explicit rollback.

## Answers (canonical)

1. **How is the promoted variant recorded as the new baseline?**  
   `ensure_baseline_adoption` reads `study-promotion-execution` plus `study-closeout-summary`, validates `converged` / `stop-study` / `promote-variant`, then writes `promoted-variant-receipt` and `baseline-adoption` JSON under the workspace plane (`workspace-plane/promoted-variant-receipt/{workspace}.json`, `workspace-plane/baseline-adoption/{workspace}.json`).

2. **Where is baseline adoption made explicit?**  
   In the **baseline adoption** artifact and HTTP surface `GET /api/darwin/workstreams/{id}/baseline-adoption`, which returns `BaselineAdoptionBundle` (receipt, adoption, rollback plan, next-study seed, workbench context snapshot, echo of promotion execution).

3. **How do planner / workbench / study surfaces consume the baseline?**  
   - **Workbench / context packet:** `resolve_workstream_context_packet` calls `apply_baseline_adoption_to_packet`, which loads a `BoundedStudyBaselineSummary` when all B26.6 plane files exist and sets `packet.bounded_study_baseline`.  
   - **Planner:** `build_intent_execution_plan` adds a B26.6 stop-condition line and extends the execution plan `note` when `bounded_study_baseline` is present.  
   - **Study:** `next-study-seed` JSON and `GET .../next-study-seed` expose the deferred next-study seed (`auto_launch_new_study: false`).

4. **How is rollback represented?**  
   `baseline-rollback-plan` artifact with ordered operator-visible steps and `restores_archived_variant_ids`, plus `GET /api/darwin/workstreams/{id}/baseline-rollback-plan`. No automatic rollback execution in this phase.

5. **How is a next-study seed derived?**  
   `build_next_study_seed` (crate `next_study_seed`) builds `NextStudySeed` from adoption/receipt anchors, comparator hints from archived variant ids, and explicit deferral of launch.

6. **How is Beagle-owned identity preserved?**  
   All artifacts carry `study_id`, `workstream_id`, `workspace_id`, `session_id`, and `same_beagle_owned_identity`; adoption validates alignment with closeout and promotion execution.

## Non-goals (this phase)

- Auto-launching a new comparative study.  
- Removing or hiding rollback.  
- Ingress / edge / HA changes.  
- Replacing B26.5 or earlier phases.

## Related contracts

- `contracts/promoted-variant-receipt-schema.yaml`  
- `contracts/baseline-adoption-schema.yaml`  
- `contracts/baseline-rollback-schema.yaml`  
- `contracts/next-study-seed-schema.yaml`  
- `contracts/workbench-context-after-baseline-schema.yaml`

## Proof scripts

- `scripts/infrastructure/darwin-hpc/run_baseline_adoption_smoke.sh`  
- `scripts/infrastructure/darwin-hpc/validate_baseline_adoption_smoke.sh`
