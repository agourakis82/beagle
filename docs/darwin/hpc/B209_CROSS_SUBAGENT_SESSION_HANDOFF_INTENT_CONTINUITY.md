# B20.9 — Cross-Subagent Session Handoff / Intent Continuity

## Objective

Create the first bounded cross-subagent handoff path so work can move between
specialized inner environments without fragmenting the Beagle-owned
`workstream_id`, `workspace_id`, `session_id`, handoff, or result identity.

## Canonical Surface

- `POST /api/darwin/workstreams/{id}/workspace-subagent-handoff`
- `GET /api/darwin/workstreams/{id}/workspace-subagent-handoff`

## Contract

The handoff response freezes:

- source subagent
- target subagent
- same workstream/workspace/session identity
- same managed attach state and stable alias
- propagated handoff text
- carried result/recipe/physio/memory context
- target route and target activation metadata

## Boundedness

This phase is not autonomous multi-agent orchestration. The handoff is explicit,
operator-bounded, and remains inside the same canonical Beagle-owned workspace.

## Canonical Example

`core -> experiments` with `intent=analysis` and the current result/handoff
propagated into the experiments surface.
