# B20.8 — Role-Aware Subagent Routing / Tool Dock Specialization

## Objective
Add a bounded routing layer on top of the B20.7 sub-agents so Beagle can recommend the right inner workspace surface for the current work mode while preserving one canonical workspace/session/workstream identity.

## Included
- `workspace-subagent-list` surface
- `workspace-subagent-route` surface
- tool dock specialization with recommended sub-agent metadata
- role-tagged `core` and `experiments` inner environments
- smoke + validator

## Excluded
- autonomous multi-agent orchestration
- new public ingress
- HA
- substrate redesign
- parallel canonical state outside Beagle

## Canonical Surfaces
- `GET /api/darwin/workstreams/{id}/workspace-subagent-list`
- `GET /api/darwin/workstreams/{id}/workspace-subagent-route`
- existing tool dock surfaces enriched with:
  - `workspace_subagent_list_path`
  - `workspace_subagent_route_path`
  - `recommended_subagent_id`
  - `recommended_work_mode`

## Routing Rule
- `codex` + `implementation` resolves to `core`
- `claude-code` + `analysis` resolves to `experiments`
- `cursor` + `interactive-editing` resolves to `core`

## Identity Rule
Routing narrows focus only. It does not mint a new:
- `workstream_id`
- `workspace_id`
- `session_id`
