# B24.4 — Human Review Inbox / Follow-On Plan Queue

`B24.4` turns bounded replan guidance from `B24.3` into operator-visible review items and a same-identity follow-on plan queue.

## Scope

- materialize one canonical `ReviewInboxItem` from the latest `ReplanSuggestion`
- support bounded `approve`, `edit`, and `reject` decisions
- materialize one `FollowOnPlan` when the operator approves or edits
- keep `workstream_id`, `workspace_id`, and `session_id` unchanged
- project review state back into execution receipts, context packets, and handoff propagation

## Canonical API

- `GET /api/darwin/workstreams/{workstream_id}/review-inbox`
- `POST /api/darwin/workstreams/{workstream_id}/review-inbox`
- `GET /api/darwin/workstreams/{workstream_id}/review-inbox/decision`
- `POST /api/darwin/workstreams/{workstream_id}/review-inbox/decision`
- `GET /api/darwin/workstreams/{workstream_id}/follow-on-plan`

## Bounded behavior

- review inbox creation requires an already-recorded `ReplanSuggestion`
- operator approval stays explicit and visible
- `approve` and `edit` materialize a next candidate plan without starting it
- `reject` clears the queue for the current suggestion without autonomous continuation
- downstream execution still requires a separate approval and start step

## Notes

- `B24.4` is not an autonomous continuation loop
- follow-on plans remain queued-for-approval until a later bounded execution phase consumes them
- scientific and editorial readiness limits remain explicit in downstream layers
