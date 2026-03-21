# B13.2 - Repo-native Edit → Build → Deploy → Validate Loop

## Current status

B13.2 is currently `GO-WITH-BLOCKER`.

The repo-native loop is implemented, but the phase only closes after the live
cluster smoke proves one bounded code change moving from source edit to running
service validation.

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
