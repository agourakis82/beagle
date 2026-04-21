# B24.7 — Autonomy Policy Calibration And Escalation Evals

`B24.7` adds the first canonical calibration layer on top of the live `B24.6` autonomy gate.

## Scope

- materialize one canonical `AutonomyCalibrationDataset`
- compare current `B24.6` decisions against replayed and shadow-labeled outcomes
- emit one canonical `AutonomyPolicyEvalReport`
- stage one canonical `EscalationThresholds` document in `shadow-only`
- emit one canonical `ShadowPolicyComparison`
- emit one canonical `UpdatedPolicyRecommendation`
- keep every artifact on the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Canonical API

- `GET /api/darwin/workstreams/{workstream_id}/autonomy-calibration-dataset`
- `GET /api/darwin/workstreams/{workstream_id}/autonomy-policy-eval-report`
- `GET /api/darwin/workstreams/{workstream_id}/escalation-thresholds`
- `GET /api/darwin/workstreams/{workstream_id}/shadow-policy-comparison`
- `GET /api/darwin/workstreams/{workstream_id}/updated-policy-recommendation`

## Bounded Behavior

- calibration replays the observed `B24.6` follow-on chain before recommending any threshold change
- shadow samples cover `implementation`, `analysis`, and `manuscript` families
- threshold recommendations never mutate the live gate directly
- `safe_to_apply_live` stays `false` in `B24.7`
- operator visibility remains explicit in execution summary, result links, and context packet surfaces

## Notes

- `B24.7` does not create a second autonomy runtime or a free-running loop
- the live `B24.6` gate remains the only canonical dispatch decision-maker
- readiness limits remain visible to scientific and editorial layers instead of being hidden behind calibration output
