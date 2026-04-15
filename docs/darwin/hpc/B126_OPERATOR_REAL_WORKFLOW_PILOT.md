# B12.6 - Operator-Real Workflow Pilot

## Current status

B12.6 is currently `GO`.

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/operator-real-workflow-smoke/bootstrap-before.json`
- `.artifacts/darwin-hpc/operator-real-workflow-smoke/pilot.json`
- `.artifacts/darwin-hpc/operator-real-workflow-smoke/session-after-restart.json`
- `.artifacts/darwin-hpc/operator-real-workflow-smoke/final-cluster-health.txt`

## Objective

Prove one operator-real workflow on top of the existing repo-aware workspace
plane so the Beagle workspace can preserve repo, branch, operational task
context and last-result linkage across execution and restart.

## Scope

The B12.6 pilot remains intentionally narrow:

- richer operational task state in the workspace plane
- one operator-real sequence through the live Beagle surfaces
- result catalog preflight and post-run result resolution
- handoff persistence with operator context
- restart/recovery preserving the same operator context

## Runtime shape

The pilot reuses the existing internal Beagle surface:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `POST /api/darwin/workspace/pilot/execute`
- `GET /api/darwin/hpc/control`
- `GET /api/darwin/hpc/results`
- `GET /api/darwin/hpc/results/{job_id}`
- `GET /api/darwin/hpc/results/{job_id}/manifest`

## Placement

- workspace/session runtime: `crates/beagle-darwin/src/workspace_plane.rs`
- repo context model: `crates/beagle-darwin/src/repo_context.rs`
- internal HTTP surface: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_operator_real_workflow_smoke.sh`

## Architectural decision

- the operator-real pilot reuses the proven bridge, control surface, workspace
  plane, result plane and repo-aware attachment
- no new ingress, edge, HA, topology or provider expansion are introduced
- operator context is persisted in the workspace plane as metadata-first state,
  not as a live git checkout inside the Beagle pod
- the pilot keeps the HPC gateway contract intact; repo-aware/operator-aware
  state stays on the Beagle side

## Success condition

The phase is alive when one canonical workspace can:

1. bootstrap with repo and branch context plus empty operator task state
2. preflight the existing result/control surface before dispatch
3. run one real workflow from the live Beagle surface
4. resolve the published result through the current result plane
5. persist the completed operator task and handoff under `BEAGLE_DATA_DIR`
6. recover the same operator state after a Beagle restart

## Live result

The validated pilot proved that one canonical workspace can:

- bootstrap as `agourakis82/beagle` on branch `feat/darwin-hpc-governance`
- query the live control surface and the existing `cpu-short-v1` result catalog
  before dispatch
- run a real `cpu-short-v1` workflow through the workspace plane with job `38`
- resolve published result `24` and its object-backed manifest through the same
  Beagle surface
- persist `last_successful_task`, handoff, last workflow and last result linkage
  across Beagle rollout restart
