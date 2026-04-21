# B21.1 — Manuscript Subagent & Evidence-to-Manuscript Loop

## Objective
Add a manuscript subagent and prove a bounded `core -> experiments ->
manuscript` continuity loop inside the same canonical Beagle-owned
workspace/session/workstream identity.

## Included
- `manuscript` subagent role inside the existing canonical workspace
- role-aware routing for `work_mode=manuscript`
- explicit `workspace-manuscript-handoff` contract
- bounded continuity from runtime + experiment context into manuscript work
- smoke + validator

## Excluded
- autonomous multi-agent orchestration
- new ingress/edge
- HA
- workspace substrate redesign
- parallel canonical state outside Beagle

## Canonical Surfaces
- `GET /api/darwin/workstreams/{id}/workspace-subagent-list`
- `GET /api/darwin/workstreams/{id}/workspace-subagent-route`
- `POST /api/darwin/workstreams/{id}/workspace-subagent-handoff`
- `GET /api/darwin/workstreams/{id}/workspace-manuscript-handoff`
- `POST /api/darwin/workstreams/{id}/workspace-manuscript-handoff`

## Canonical Loop
1. `core -> experiments` keeps the same canonical Beagle-owned session.
2. `experiments -> manuscript` freezes a bounded manuscript intent.
3. The manuscript target receives:
   - current handoff
   - current context packet
   - campaign context
   - evidence pack
   - claims
   - manuscript pack

## Identity Rule
The loop narrows focus only. It does not mint a new:
- `workstream_id`
- `workspace_id`
- `session_id`

## Boundedness
This phase is continuity, not autonomous orchestration. Every handoff remains
explicit, operator-bounded, and repo-native.
