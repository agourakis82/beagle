# B24.14 Manuscript Shadow Calibration / Guarded Expansion

## Goal

B24.14 stages `manuscript` into bounded shadow calibration while `implementation` and `analysis` remain on their live guarded canaries.

## Canonical Behavior

- `implementation` remains live on its guarded canary from B24.9
- `analysis` remains live on its guarded canary from B24.13
- `manuscript` stays live on explicit control in this phase
- the manuscript candidate policy is replayed in shadow only
- rollback remains explicit if the manuscript shadow candidate regresses or if the retained canaries degrade
- every artifact stays linked to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Runtime Outputs

B24.14 materializes:

- `autonomy-policy-manuscript-control`
- `autonomy-policy-manuscript-candidate`
- `manuscript-shadow-comparison`
- `manuscript-rollout-metrics`
- `manuscript-rollout-decision`

The execution record advances `autonomy_policy_calibration_status=manuscript-shadow-evaluated` while preserving `autonomy_policy_rollout_status=implementation-and-analysis-canary-live`.

## Guardrails

- no global policy flip
- no movement of `manuscript` off control in this phase
- no change to the existing implementation or analysis canary behavior
- no free-running autonomy loop
- operator visibility remains explicit in result links, context packet, and rollout decision artifacts
