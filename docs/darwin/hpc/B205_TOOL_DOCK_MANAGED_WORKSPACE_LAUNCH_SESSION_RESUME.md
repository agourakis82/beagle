# B20.5 — Tool Dock -> Managed Workspace Launch / Session Resume

## Objective

Close the next operator bottleneck after `B20.4` by turning the existing managed attach plane into a one-gesture launch/resume path from the Beagle-owned tool dock.

This phase does not reopen the workspace substrate or attach plane. It adds a canonical launch/resume surface that:

- preserves the same `workstream_id`, `workspace_id`, and `session_id`
- exposes the same handoff and context packet immediately on resume
- keeps Cursor and browser fallback on the same Beagle-owned workspace
- stays private and cluster-internal

## Canonical Runtime Surface

- `GET /api/darwin/workstreams/{id}/workspace-launch-resume`

The response is intentionally bounded and composed from already-proven layers:

- `managed_attach`
- `workspace_habitat`
- `context_packet`

No new canonical workspace path is introduced.

## Repo-Native Helper

- `scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh`

The helper fetches the launch/resume packet, hydrates context references immediately, and delegates SSH attach to the already-proven managed attach installer when the client is `cursor` or `ssh`.

## Why This Is Canonical

`B20.4` proved managed attach. `B20.5` makes it resumable from one control surface without moving canonical state out of Beagle.

The launch/resume packet is therefore:

- not a new attach substrate
- not a second workspace path
- not a Cursor-owned state lane

It is a Beagle-owned resume envelope layered directly on top of the existing managed attach plane.
