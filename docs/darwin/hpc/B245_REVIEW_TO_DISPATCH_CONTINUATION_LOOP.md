# B24.5 — Review-to-Dispatch Continuation Loop

`B24.5` turns one approved `FollowOnPlan` into one dispatched continuation on the same Beagle-owned identity, while keeping execution bounded and operator-visible.

## Scope

- dispatch one approved or edited `FollowOnPlan` into the next bounded execution cycle
- chain review, dispatch, state, and receipt metadata without opening a parallel runtime
- preserve `workstream_id`, `workspace_id`, and `session_id`
- project continuation state back into execution summary, context packets, and handoff propagation

## Canonical API

- `GET /api/darwin/workstreams/{workstream_id}/continuation-dispatch`
- `POST /api/darwin/workstreams/{workstream_id}/continuation-dispatch`
- `GET /api/darwin/workstreams/{workstream_id}/continuation-receipt`
- `GET /api/darwin/workstreams/{workstream_id}/continuation-state`

## Bounded behavior

- continuation dispatch requires an existing review inbox item, review decision, and follow-on plan
- only `approved` and `edited` review decisions can dispatch a continuation
- the next execution is chained back to the previous receipt and kept operator-visible
- restart/resume stays on the same workspace/session envelope
- no autonomous looping is introduced

## Notes

- `B24.5` dispatches one continuation at a time per workspace execution thread
- continuation receipts are chained explicitly instead of replacing the source receipt
- scientific and editorial readiness limits remain explicit in downstream artifacts
