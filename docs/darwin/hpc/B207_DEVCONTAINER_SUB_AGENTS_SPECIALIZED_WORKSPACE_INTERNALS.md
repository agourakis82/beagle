# B20.7 — Devcontainer Sub-Agents / Specialized Workspace Internals

## Objective

Freeze the first set of specialized inner work surfaces inside the already-proven Beagle-owned workspace habitat without creating a second workspace identity.

## Canonical shape

- `GET /api/darwin/workstreams/{id}/workspace-subagents`
- same `workstream_id`
- same `workspace_id`
- same `session_id`
- same managed attach and browser fallback
- two role-separated inner surfaces: `core` and `experiments`

## What this phase adds

- a repo-native `workspace-subagents` contract
- role-separated `core` and `experiments` env files inside `/workspace/beagle/.beagle/context/subagents/`
- role-separated `devcontainer.json` files inside `/workspace/beagle/.devcontainer/`
- a live proof that both sub-agents remain accessible before and after workspace restart

## Runtime outputs

- `workspace-subagents.json`
- `core.env`
- `experiments.env`
- `beagle-core/devcontainer.json`
- `beagle-experiments/devcontainer.json`

## Non-goals

- new workspace pods per role
- parallel canonical state
- public ingress
- HA
- a full multi-workspace orchestration plane
