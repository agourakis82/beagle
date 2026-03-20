# B12.7 - Single Rich Operator Workflow

## Current status

B12.7 is currently `GO`.

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/single-rich-operator-workflow-smoke/bootstrap-before.json`
- `.artifacts/darwin-hpc/single-rich-operator-workflow-smoke/pilot.json`
- `.artifacts/darwin-hpc/single-rich-operator-workflow-smoke/session-after-restart.json`
- `.artifacts/darwin-hpc/single-rich-operator-workflow-smoke/final-cluster-health.txt`

## Objective

Prove one richer operator-real workflow on top of the existing Beagle stack by
running `cpu-batch-v1` end to end while preserving repo-aware and
operator-aware context across execution and restart.

## Scope

The B12.7 pilot remains intentionally narrow:

- one richer operator workflow on `cpu-batch-v1`
- workspace bootstrap with repo/branch context
- control-surface and result-catalog preflight
- real submit, polling and result resolution through the current result plane
- persistence of operator task state, handoff and last-result linkage
- restart/recovery preserving that richer workflow context

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
- internal HTTP surface: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_single_rich_operator_workflow_smoke.sh`

## Architectural decision

- the richer workflow stays on the stable CPU path with `cpu-batch-v1`
- no GPU/r740-first operator flow is introduced here
- no bridge, result plane, control surface, ingress, edge, HA or provider layer
  is reopened
- the pilot remains metadata-first inside Beagle; richer operator context is
  persisted in the workspace plane instead of turning the Beagle pod into a
  live repo checkout

## Success condition

The phase is alive when one canonical workspace can:

1. bootstrap with repo and branch context plus clean richer-operator state
2. preflight the control surface and the current `cpu-batch-v1` result catalog
3. run one real `cpu-batch-v1` workflow through the live Beagle surface
4. resolve the published result and manifest through the current result plane
5. persist `current_task`, `last_successful_task`, `last_result` linkage and
   handoff under `BEAGLE_DATA_DIR`
6. recover the same richer workflow context after a Beagle restart

## Live result

The validated pilot proved that one canonical workspace can:

- bootstrap as workspace `b127-0320201833` in session `ws-20260320231834`
- preserve repo `agourakis82/beagle` and branch
  `feat/darwin-hpc-governance`
- preflight the live control surface and the current `cpu-batch-v1` catalog
  with `2` published results before dispatch
- run a real `cpu-batch-v1` workflow through the workspace plane with job `39`
- resolve published result `31` from run label
  `b102-20260319-072237-cpu-batch` through the current result plane
- persist `single_rich_operator_workflow` task state, handoff, last workflow
  kind and last-result linkage across Beagle rollout restart
