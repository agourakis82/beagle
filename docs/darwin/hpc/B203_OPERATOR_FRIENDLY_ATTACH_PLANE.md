# B20.3 — Operator-Friendly Attach Plane

## Objective

Turn the already-proven Beagle-owned workspace attach path into a stable, low-friction operator
workflow, without changing the canonical ownership of session, handoff, workstream, or context.

## Canonical Decision

- `Beagle` remains the system of truth.
- `OpenVSCode Server` remains the browser habitat.
- `Cursor` remains a premium client over the same workspace identity.
- the attach plane becomes helper-managed and operator-friendly, instead of relying on manual
  `kubectl port-forward` as the canonical workflow.

## Implemented Shape

- `GET /api/darwin/workstreams/{id}/workspace-attach`
- repo-native helper:
  - `scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh`
- same shared identity:
  - `workstream_id`
  - `workspace_id`
  - `session_id`
- same shared context:
  - handoff
  - last result
  - recommended recipe
  - context packet

## Operator Flow

1. fetch canonical attach metadata from Beagle
2. use the repo-native helper to materialize the attach plane
3. let the helper manage bounded local port-forwards plus SSH config
4. attach through the same Beagle-owned workspace using:
   - `Cursor` Remote-SSH
   - native `ssh`
   - browser fallback

## Expected Live Outcome

The phase is `GO` only if:

- the workspace remains healthy
- the attach plane returns stable metadata live
- the helper resolves the same Beagle-owned identity live
- restart/recovery keep the same identity
- cluster stays green
- `Slurmctld(primary)` stays up
