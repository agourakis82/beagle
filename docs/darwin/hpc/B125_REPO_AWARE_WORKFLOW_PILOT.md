# B12.5 - Repo-aware Workflow Pilot

## Current status

B12.5 is currently `GO`.

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/repo-aware-workflow-smoke/bootstrap-before.json`
- `.artifacts/darwin-hpc/repo-aware-workflow-smoke/pilot.json`
- `.artifacts/darwin-hpc/repo-aware-workflow-smoke/session-after-restart.json`
- `.artifacts/darwin-hpc/repo-aware-workflow-smoke/final-cluster-health.txt`

## Objective

Attach canonical repo and branch context to the live Beagle workspace plane so
that one real operator workflow runs from repo-aware state and keeps that
context across restart/recovery.

## Scope

The B12.5 pilot remains intentionally narrow:

- repo context attachment to the existing workspace plane
- canonical branch awareness
- linkage between workspace, repo context and workflow execution
- restart/recovery preserving repo-aware state
- one real repo-aware workflow through the live internal control surface

## Runtime shape

The repo-aware workspace surface remains:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `POST /api/darwin/workspace/pilot/execute`

## Placement

- repo context model: `crates/beagle-darwin/src/repo_context.rs`
- workspace/session runtime: `crates/beagle-darwin/src/workspace_plane.rs`
- internal HTTP surface: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- cluster config: `k8s/beagle/configmap.yaml`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_repo_aware_workflow_smoke.sh`

## Architectural decision

- the repo-aware pilot remains metadata-first; the Beagle pod is not turned into
  a live git checkout
- canonical repo and branch are attached through workspace config and persisted
  inside session state
- the pilot reuses the already-proven bridge, control surface, result plane and
  recovery path
- no ingress, edge, HA, provider expansion or topology changes are added here

## Success condition

The phase is alive when one canonical workspace can:

1. bootstrap with canonical repo and branch metadata attached
2. persist repo-aware context in workspace/session state
3. run one real workflow from that repo-aware state
4. recover the same workspace and session after Beagle restart
5. preserve the last workflow and published-result linkage across recovery

## Live result

The validated pilot proved that one canonical workspace can:

- bootstrap with `agourakis82/beagle` on branch `feat/darwin-hpc-governance`
- run a real `cpu-short-v1` workflow through the live internal control surface
- persist repo, branch, last workflow and last published-result metadata under
  `BEAGLE_DATA_DIR`
- recover the same session cleanly after Beagle rollout restart with repo-aware
  state intact
