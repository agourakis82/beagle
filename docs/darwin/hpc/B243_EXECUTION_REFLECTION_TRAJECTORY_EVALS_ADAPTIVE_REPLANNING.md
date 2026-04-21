# B24.3 — Execution Reflection, Trajectory Evals & Adaptive Replanning

`B24.3` adds bounded post-execution reflection on top of the operator-approved execution lifecycle from `B24.2`.

## Scope

- emit one canonical `ExecutionReflection`
- evaluate one bounded execution trajectory
- attach one operator-facing adaptive `ReplanSuggestion`
- preserve the same `workstream_id`, `workspace_id`, and `session_id`
- project reflection state back into receipts, context packets, and handoff propagation

## Canonical API

- `GET /api/darwin/workstreams/{workstream_id}/plan-execution`
- `GET /api/darwin/workstreams/{workstream_id}/plan-execution/receipt`
- `GET /api/darwin/workstreams/{workstream_id}/plan-execution/result-links`
- `GET /api/darwin/workstreams/{workstream_id}/plan-execution/reflection`
- `GET /api/darwin/workstreams/{workstream_id}/plan-execution/trajectory-eval`
- `GET /api/darwin/workstreams/{workstream_id}/plan-execution/replan-suggestion`

## Bounded behavior

- reflection stays read-only and operator-visible
- trajectory eval compares the observed lifecycle against the expected bounded path
- replanning emits guidance, not autonomous execution
- receipts link reflection and replan artifacts back into the same Beagle-owned envelope

## Notes

- `B24.3` is not a full planner-executor-reflector loop
- operator approval remains required before any next execution starts
- scientific/editorial readiness limits remain explicit in downstream layers
