# B24.10 Analysis Shadow Calibration / Guarded Expansion

## Goal

B24.10 adds the first bounded analysis-family shadow calibration layer on top of the live B24.9 implementation canary. The current control policy remains canonical for live analysis execution while Beagle compares that control against an analysis-only candidate policy in shadow mode.

## Canonical Behavior

- implementation stays on the live guarded canary from B24.9
- analysis stays on the explicit control policy live
- manuscript stays on the explicit control policy live
- the candidate analysis policy is evaluated in shadow only
- every artifact stays attached to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Runtime Outputs

B24.10 materializes:

- `autonomy-policy-control`
- `autonomy-policy-analysis-candidate`
- `analysis-shadow-comparison`
- `analysis-rollout-metrics`
- `analysis-rollout-decision`

The execution record keeps `autonomy_policy_rollout_status=implementation-canary-live` and advances `autonomy_policy_calibration_status=analysis-shadow-evaluated`.

## Decision Outputs

- `keep-shadow`: no regression is detected, but the evidence is still not strong enough to stage an analysis canary
- `stage-analysis-canary`: the analysis candidate improves or at least preserves alignment with zero regression while implementation canary health remains green
- `rollback-shadow`: the analysis candidate regresses, or the implementation canary becomes unhealthy while the analysis shadow pass is active

## Guardrails

- no global policy flip
- no manuscript movement off control
- no free-running autonomy loop
- rollback remains explicit and operator-visible
- readiness limits remain visible to scientific and editorial layers
