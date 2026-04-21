# B20.2a — Cursor Native Remote Attach

## Objective

Prove a native `Cursor` remote attach path to the same Beagle-owned cluster workspace without creating parallel session, handoff, or workstream state.

## Canonical Decision

- `Beagle` remains the system of truth.
- `OpenVSCode Server` remains the browser habitat.
- `Cursor` attaches to the same workspace through a native `Remote-SSH`-compatible path.
- The attach path remains cluster-internal and bounded.

## Implemented Shape

- `GET /api/darwin/workstreams/{id}/cursor-remote-lane`
- `GET /api/darwin/workstreams/{id}/cursor-native-attach`
- shared identity:
  - `workstream_id`
  - `workspace_id`
  - `session_id`
- shared context:
  - handoff
  - last result
  - recommended recipe
  - context packet
- shared workspace habitat:
  - `beagle-workspace`
  - `openvscode-server`
  - native `ssh` sidecar on the same pod/PVC

## Expected Operator Flow

1. fetch native attach metadata from Beagle
2. port-forward the workspace `ssh` service port
3. attach with `Cursor` using the same `Remote-SSH` target
4. keep writeback, handoff, and context in Beagle

## Live Proof Boundary

The phase is `GO` only if:

- the workspace remains healthy
- native `ssh` attach succeeds live
- the same Beagle-owned identity is visible through the attach path
- restart/recovery keep the same identity
- cluster stays green
- `Slurmctld(primary)` stays up
