# B20.6 — Template-Backed Prebuilt Workspace / External Workspace Registration

## Objective

Freeze the first reproducible, warm-startable workspace contract on top of the already-proven Beagle-owned habitat, attach, and launch/resume stack.

## Canonical shape

- `GET /api/darwin/workstreams/{id}/workspace-template`
- same `workstream_id`
- same `workspace_id`
- same `session_id`
- same Beagle-owned handoff and context packet
- no second canonical workspace path

## What this phase adds

- a repo-native `workspace-template` contract
- explicit external-workspace-compatible registration metadata
- explicit `template`, `registration`, and `hydration` files inside the workspace context directory
- a warm-start proof path based on the hydrated PVC-backed workspace snapshot

## Runtime outputs

- `workspace-template.json`
- `external-workspace-registration.json`
- `workspace-hydration.json`

These are materialized under `/workspace/beagle/.beagle/context/` by the workspace bootstrap path and surfaced through the bounded Darwin HTTP contract.

## Warm-start stance

The canonical warm path is `template-backed-prehydrated-pvc`. On restart, the workspace preserves the hydrated snapshot and rehydrates context without changing Beagle-owned identity.

## Non-goals

- full Coder control-plane migration
- public ingress
- HA
- a second state owner outside Beagle
