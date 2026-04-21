# B24.13 Analysis Canary Activation / Guarded Autonomy Expansion

## Goal

B24.13 promotes `analysis` from staged promotion status into a live guarded canary after the bounded B24.12 sample-accumulation gate clears it.

## Canonical Behavior

- `implementation` remains live on its guarded canary from B24.9
- `analysis` becomes live on its own guarded canary in this phase
- `manuscript` remains live on explicit control
- rollback remains explicit and immediate if the analysis canary regresses
- every artifact stays linked to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Runtime Outputs

B24.13 materializes:

- `autonomy-policy-analysis-control`
- `autonomy-policy-implementation-canary`
- `autonomy-policy-analysis-canary`
- `analysis-canary-metrics`
- `analysis-canary-rollback-decision`

The execution record advances `autonomy_policy_rollout_status=implementation-and-analysis-canary-live` while preserving the prior bounded calibration evidence.

## Guardrails

- no global policy flip
- no manuscript movement off control
- no free-running autonomy loop
- operator visibility remains explicit in result links, context packet, and rollback artifacts
- rollback disables only the analysis canary; implementation can remain live if healthy
