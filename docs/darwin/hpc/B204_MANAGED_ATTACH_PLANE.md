# B20.4 — Managed Attach Plane / Coder-Compatible Workspace Access

## Objective

Promote the Beagle-owned cluster workspace from helper-managed attach to a managed, coder-compatible attach path without changing the Beagle backplane, workspace identity model, or workspace substrate.

## Scope

- keep the same canonical workspace
- keep the same `workstream_id`, `workspace_id`, and `session_id`
- keep OpenVSCode Server as the browser habitat
- keep Cursor as a premium client over the same workspace
- replace the daily attach path with a stable SSH alias + config flow aligned with coder-style Remote-SSH ergonomics

## Runtime shape

- canonical surface is `GET /api/darwin/workstreams/{id}/managed-attach`
- the response now carries:
  - `managed_attach_state`
  - stable `.coder` host alias
  - managed attach transport metadata
  - SSH config snippet template
  - installer/proxy script refs
- the tool dock exposes the same Beagle-owned workspace plus the managed attach path for Cursor

## Managed attach model

- Beagle remains the system of truth
- canonical state stays in Beagle
- managed attach is private and cluster-internal
- the transport uses a stable SSH alias and a `ProxyCommand` that auto-manages the private `kubectl port-forward`, instead of manual helper-managed forwarding as the canonical workflow
- the proxy path is compatible with coder-style Remote-SSH habits and leaves room for later Desktop/Connect evolution

## Live proof

The live smoke for this phase must prove:

1. the same Beagle-owned workspace is reachable through the managed attach path
2. Cursor metadata still points to the same workspace/session/workstream identity
3. the managed SSH config/snippet is stable and reusable
4. restart preserves the same workspace/session identity
5. cluster remains green
6. Slurm remains green
