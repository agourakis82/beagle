# B13.2 - Repo-native Edit → Build → Deploy → Validate Loop

## Current status

B13.2 is currently `GO`.

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/repo-native-dev-loop-smoke/bootstrap-before.json`
- `.artifacts/darwin-hpc/repo-native-dev-loop-smoke/patch-summary.json`
- `.artifacts/darwin-hpc/repo-native-dev-loop-smoke/deploy.json`
- `.artifacts/darwin-hpc/repo-native-dev-loop-smoke/pilot.json`
- `.artifacts/darwin-hpc/repo-native-dev-loop-smoke/smoke.json`
- `.artifacts/darwin-hpc/repo-native-dev-loop-smoke/session-after-restart.json`
- `.artifacts/darwin-hpc/repo-native-dev-loop-smoke/final-cluster-health.txt`

## Objective

Prove one small but real software iteration loop on the canonical Beagle repo:

1. make one bounded code change
2. build the Beagle image
3. load and redeploy it on the cluster
4. validate the changed runtime behavior
5. run one real workflow through the updated service
6. recover the same session cleanly after restart

## Selected code change

This phase uses one minimal, persistent code change in the live workspace plane:

- add `workspace_plane_contract_version` to the workspace session/bootstrap model
- persist that field in workspace state
- expose it through the existing bootstrap response

That gives the phase a real before/after signal without opening a large refactor
or a throwaway endpoint.

## Runtime shape

The loop reuses existing live surfaces:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `POST /api/darwin/workspace/pilot/execute`
- `GET /api/darwin/hpc/results/{job_id}`
- `GET /api/darwin/hpc/results/{job_id}/manifest`

## Architectural decision

- the code change is intentionally tiny and observable in a live response
- the proof comes from build/deploy/runtime behavior, not from static code review
- the same repo-aware workspace plane remains the canonical session and handoff
  layer
- the phase does not introduce new surfaces, ingress, HA or topology changes

## Placement

- runtime change: `crates/beagle-darwin/src/workspace_plane.rs`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_repo_native_dev_loop_smoke.sh`

## Success condition

The phase closes when:

1. the repo-native source change exists in the working tree
2. the Beagle image builds successfully
3. the updated image is loaded and redeployed on the cluster
4. the live bootstrap response exposes the new field after deploy
5. one real workflow completes through the updated service
6. session recovery after restart preserves the updated workspace context
7. cluster remains green
8. Slurm remains green

## Live result

The validated pilot proved one real repo-native development loop on the
canonical Beagle repo:

- bootstrap before deploy showed workspace `b132-0321061051` on repo
  `agourakis82/beagle` and branch `feat/darwin-hpc-governance`
- the live predeploy bootstrap response did not yet expose
  `workspace_plane_contract_version`
- the bounded source change added `workspace_plane_contract_version` with value
  `darwin-workspace-plane-v2` to the workspace plane contract
- the Beagle image rebuilt successfully as `localhost/beagle-core:dev`
- the new image loaded onto the cluster, redeployed, and exposed
  `workspace_plane_contract_version=darwin-workspace-plane-v2` in the live
  bootstrap response after deploy
- one real `cpu-short-v1` workflow completed through the updated service with
  job `45`
- published result `24` remained resolvable through the current result and
  manifest surfaces
- the same session `ws-20260321091052` recovered cleanly after restart with the
  updated workspace context preserved
