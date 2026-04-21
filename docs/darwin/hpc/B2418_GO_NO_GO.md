# B24.18 Go / No-Go

## Go Criteria

- `implementation` remains live on guarded canary
- `analysis` remains live on guarded canary
- `manuscript` remains on explicit control + shadow
- `manuscript-trajectory-quality` is materialized explicitly
- `manuscript-context-adequacy` is materialized explicitly
- `manuscript-tuning-recommendation` is materialized explicitly
- the new artifacts stay bound to the same `workstream_id`, `workspace_id`, and `session_id`
- the execution state records `autonomy_policy_calibration_status=manuscript-quality-uplifted`
- restart remains coherent
- cluster stays green
- Slurm stays green

## No-Go Conditions

- manuscript is promoted to canary in this phase
- the new quality artifacts are missing or not identity-bound
- the runtime loses operator visibility
- the rollout state for `implementation` or `analysis` regresses
- the quality/tuning layer requires a parallel control plane outside Beagle

## Canonical Decision Rule

B24.18 is `GO` when Beagle can explain a continued `keep-shadow` decision with explicit quality/context/tuning evidence instead of relying on missing data, missing labels, or sample-count scarcity.
