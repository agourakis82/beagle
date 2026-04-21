# B25.1 — VM-Agnostic Multi-User GPU Workspace & Compute Tenancy

Status: GO

## Objective

Freeze the first Beagle-native workspace and compute tenancy layer so the same
remote workspace can be used through `VS Code` or `Cursor`, keep repo hydration
reproducible, and scope partner-dev GPU access without handing over the full
cluster.

## Canonical shape

- `GET /api/darwin/workstreams/{id}/workspace-tenancy`
- `GET /api/darwin/workstreams/{id}/compute-tenancy`
- `GET /api/darwin/workstreams/{id}/partner-access`
- same `workstream_id`
- same `workspace_id`
- same `session_id`
- same Beagle-owned habitat, attach, launch/resume, and prehydrated template

## What this phase adds

- one canonical workspace tenancy contract
- one canonical compute tenancy contract
- one canonical partner-access contract
- one explicit `VS Code` + `Cursor` attach path to the same workspace
- one explicit repo hydration / clone model
- one explicit typed GPU tenancy model with isolated-vs-shared distinction

## Canonical recommendation

The current canonical combination is:

- `shared-workspace`
- `external-workspace-compatible`
- `template-backed-prehydrated`

That means:

- the live collaboration surface is the same shared Beagle-owned workspace
- the workspace contract remains compatible with external-workspace claim flows
- the warm-start path remains template-backed and prehydrated

## Compute stance

The live compute path remains bounded and typed:

- `cpu-short-v1`
- `cpu-batch-v1`
- `gpu-single-v1`

The live GPU path is `isolated-dedicated-gpu` through `gpu-single-v1`.
Shared or oversubscribed GPU access is only modeled explicitly in this phase;
it is not enabled live by default.

## Partner access stance

Partner-dev access is:

- workspace-scoped
- operator-mediated
- profile-scoped
- non-admin

This phase does not hand out unrestricted cluster ownership or make the partner
another state owner.
