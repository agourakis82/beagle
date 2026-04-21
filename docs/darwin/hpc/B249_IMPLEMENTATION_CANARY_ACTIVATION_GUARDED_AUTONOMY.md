# B24.9 — Implementation Canary Activation Guarded Autonomy

`B24.9` activates the first live guarded autonomy canary on top of the `B24.8` rollout layer.

## Scope

- preserve one explicit live control autonomy policy
- activate one explicit live implementation canary autonomy policy
- keep `analysis` and `manuscript` on control
- emit one canonical `CanaryRolloutMetrics` document
- emit one canonical `CanaryRollbackDecision`
- preserve the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Canonical API

- `GET /api/darwin/workstreams/{workstream_id}/autonomy-policy-control`
- `GET /api/darwin/workstreams/{workstream_id}/autonomy-policy-canary`
- `GET /api/darwin/workstreams/{workstream_id}/canary-rollout-metrics`
- `GET /api/darwin/workstreams/{workstream_id}/canary-rollback-decision`

## Bounded Behavior

- `implementation` is the only family that can move to the live canary lane in `B24.9`
- `analysis` remains on the current control policy
- `manuscript` remains on the current control policy
- rollback stays explicit and operator-visible at every stage
- `B24.9` does not apply the candidate policy globally

## Notes

- the canary rollout stays bounded to follow-on autonomy gating; it does not create a free-running loop
- readiness limits remain visible in execution state, receipt, result links, and context packet surfaces
- if implementation regressions appear, rollback returns all families to the control policy immediately
