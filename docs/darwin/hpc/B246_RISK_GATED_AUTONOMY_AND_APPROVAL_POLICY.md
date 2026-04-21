# B24.6 — Risk-Gated Autonomy And Approval Policy

`B24.6` adds the first canonical autonomy gate on top of `B24.5`.

## Scope

- define one canonical `AutonomyPolicy`
- score one `RiskEvaluation` against the actual follow-on plan
- emit one `ApprovalGatingDecision` with bounded classes:
  - `auto-continue`
  - `review-required`
  - `blocked`
- keep the decision on the same `workstream_id`, `workspace_id`, and `session_id`
- link the gate back into the existing review inbox, follow-on plan, continuation dispatch, and execution summary surfaces

## Canonical API

- `GET /api/darwin/workstreams/{workstream_id}/autonomy-policy`
- `GET /api/darwin/workstreams/{workstream_id}/risk-evaluation`
- `GET /api/darwin/workstreams/{workstream_id}/approval-gating-decision`
- existing `review-inbox`, `review-inbox/decision`, `follow-on-plan`, and `continuation-dispatch` APIs remain canonical

## Bounded Behavior

- the gate evaluates the actual follow-on plan after review decision materializes it
- `auto-continue` only applies to the narrow low-risk approved analysis lane
- `review-required` preserves the operator-visible manual dispatch path from `B24.5`
- `blocked` prevents continuation dispatch and keeps the need to replan explicit
- no free-running autonomous loop is introduced

## Notes

- `B24.6` does not reopen the Beagle backplane or create a second orchestration plane
- operator visibility remains explicit in review inbox, execution summary, context packet, and continuation artifacts
- scientific and editorial readiness limits remain visible in downstream layers instead of being hidden behind autonomy
