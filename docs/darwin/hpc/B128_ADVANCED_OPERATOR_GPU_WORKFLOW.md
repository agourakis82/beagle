# B12.8 - Advanced Operator GPU Workflow

## Current status

B12.8 is currently `GO`.

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/advanced-operator-gpu-workflow-smoke/bootstrap-before.json`
- `.artifacts/darwin-hpc/advanced-operator-gpu-workflow-smoke/pilot.json`
- `.artifacts/darwin-hpc/advanced-operator-gpu-workflow-smoke/session-after-restart.json`
- `.artifacts/darwin-hpc/advanced-operator-gpu-workflow-smoke/final-cluster-health.txt`

## Objective

Prove one advanced operator-real workflow on top of the existing Beagle stack
by running `gpu-single-v1` end to end while preserving repo-aware and
operator-aware context across execution and restart.

## Scope

The B12.8 pilot remains intentionally narrow:

- one advanced operator workflow on `gpu-single-v1`
- workspace bootstrap with repo/branch context
- control-surface and result-catalog preflight
- real submit, polling and result resolution through the current result plane
- proof that execution lands on `r740-proxmox`
- persistence of operator task state, handoff and last-result linkage
- restart/recovery preserving that advanced workflow context

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
  `scripts/infrastructure/darwin-hpc/run_advanced_operator_gpu_workflow_smoke.sh`

## Architectural decision

- the advanced operator workflow uses the already-proven `gpu-single-v1` path
  without reopening bridge, result plane, control surface, ingress, edge, HA
  or provider scope
- execution-node context is persisted metadata-first in the workspace plane so
  the Beagle session can prove `r740-proxmox` execution and preserve it after
  restart
- the pilot reuses the current published result-plane contract instead of
  redesigning publication or retrieval for GPU

## Success condition

The phase is alive when one canonical workspace can:

1. bootstrap with repo and branch context plus clean advanced-operator state
2. preflight the control surface and the current `gpu-single-v1` result catalog
3. run one real `gpu-single-v1` workflow through the live Beagle surface
4. prove that the submitted job completes on `r740-proxmox`
5. resolve the published result and manifest through the current result plane
6. persist `current_task`, `last_successful_task`, execution-node context,
   `last_result` linkage and handoff under `BEAGLE_DATA_DIR`
7. recover the same advanced workflow context after a Beagle restart

## Live result

The validated pilot proved that one canonical workspace can:

- bootstrap as workspace `b128-0320204628` in session `ws-20260320234629`
- preserve repo `agourakis82/beagle` and branch
  `feat/darwin-hpc-governance`
- preflight the live control surface and the current `gpu-single-v1` catalog
  with `2` published GPU results before dispatch
- run a real `gpu-single-v1` workflow through the workspace plane with job `41`
- prove that the submitted GPU job completed on `r740-proxmox`
- resolve published result `32` from run label
  `b102-20260319-072237-gpu-single` through the current result plane
- persist `advanced_operator_gpu_workflow` task state, execution-node context,
  handoff, last workflow kind and last-result linkage across Beagle rollout
  restart
