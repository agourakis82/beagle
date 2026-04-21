# B24.2 — Plan Approval & Bounded Execution Orchestrator

`B24.2` adds the first canonical execution lifecycle on top of `B24.1` planning without introducing an autonomous runtime.

## Scope

- approve a canonical `ExecutionPlan`
- start one bounded execution
- track `planned -> approved -> running -> succeeded|failed|stopped`
- emit receipts and result links
- preserve the same `workstream_id`, `workspace_id`, and `session_id`
- update subagent handoff when the selected lane is not `core`

## Canonical API

- `GET /api/darwin/workstreams/{workstream_id}/plan-execution`
- `POST /api/darwin/workstreams/{workstream_id}/plan-execution/approve`
- `POST /api/darwin/workstreams/{workstream_id}/plan-execution/start`
- `POST /api/darwin/workstreams/{workstream_id}/plan-execution/stop`
- `GET /api/darwin/workstreams/{workstream_id}/plan-execution/receipt`
- `GET /api/darwin/workstreams/{workstream_id}/plan-execution/result-links`

## Bounded behavior

- approval is explicit and operator-visible
- start records a bounded execution and closes it with receipts
- execution does not recursively plan or self-expand
- handoff updates stay on the existing Beagle subagent plane
- result links point back to Beagle-owned context, tool, route, handoff, and experiment surfaces

## Notes

- `B24.2` is not a general autonomous executor
- scientific/editorial readiness limits remain explicit in downstream layers
- Qdrant, retrieval routing, compiler policy, and GraphRAG remain unchanged
