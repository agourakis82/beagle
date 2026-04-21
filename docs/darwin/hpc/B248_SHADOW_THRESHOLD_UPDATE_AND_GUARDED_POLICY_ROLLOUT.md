# B24.8 — Shadow Threshold Update And Guarded Policy Rollout

`B24.8` adds the first canonical guarded rollout layer on top of the live `B24.7` calibration outputs.

## Scope

- materialize one canonical current-control policy snapshot
- materialize one canonical candidate-shadow policy snapshot
- compare both policies on the same Beagle-owned identity
- emit one canonical `PolicyRolloutMetrics` document
- emit one canonical `GuardedRolloutDecision`
- keep `analysis` on the current live policy
- stage `implementation` as the only guarded canary candidate when the shadow evidence stays non-regressive
- keep `manuscript` in review-or-block

## Canonical API

- `GET /api/darwin/workstreams/{workstream_id}/autonomy-policy-current`
- `GET /api/darwin/workstreams/{workstream_id}/autonomy-policy-candidate`
- `GET /api/darwin/workstreams/{workstream_id}/rollout-metrics`
- `GET /api/darwin/workstreams/{workstream_id}/guarded-rollout-decision`

## Bounded Behavior

- the current `B24.6` policy remains explicit control and is never discarded
- the candidate policy stays shadow-evaluated before any family can move
- only `implementation` can be staged first, and only when candidate false-auto remains `0` with no regressions
- `analysis` and `manuscript` do not lose human visibility or review safeguards in `B24.8`
- rollback is explicit and available at every stage

## Notes

- `B24.8` does not apply a new policy globally by default
- `B24.8` stages guarded rollout metadata; it does not create a free-running autonomy loop
- readiness limits remain visible in execution summary, receipt, result links, and context packet surfaces
