# B13.3 - Scoped Default Dev Plane Promotion

## Current status

B13.3 is currently `GO-WITH-BLOCKER`.

The scoped default-dev-plane promotion only closes after one live cluster smoke
proves that a bounded development scope now defaults to Beagle/cluster, with VM
remaining fallback-only for that same scope.

## Objective

Promote one bounded development scope to a default working rule:

1. Beagle/cluster becomes the primary dev plane
2. VM remains allowed only as fallback support
3. the promoted scope stays small and explicit
4. the same workspace/session/handoff/recovery model remains intact

## Selected scope

This phase promotes one canonical scope only:

- repo: `agourakis82/beagle`
- branch: the canonical active branch on the workspace plane
- workstream: small and medium Darwin/HPC/Beagle changes
- runtime policy: `default via Beagle`, `VM fallback-only`

## Runtime shape

The promotion reuses the live Beagle surfaces that already exist:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `POST /api/darwin/bridge/execute`
- `POST /api/darwin/workspace/pilot/execute`
- `GET /api/darwin/hpc/results/{job_id}`
- `GET /api/darwin/hpc/results/{job_id}/manifest`

## Architectural decision

- the promotion is made explicit in the workspace plane itself through persisted
  dev-plane policy metadata
- the phase stays repo-native and cluster-first; it does not add new surfaces,
  ingress, HA or topology changes
- the proof comes from live bootstrap/session/runtime behavior, not from policy
  prose alone
- the promoted scope stays narrow on purpose so that the new default is honest
  and reversible

## Placement

- config/runtime policy: `crates/beagle-config/src/model.rs`
- workspace/session runtime: `crates/beagle-darwin/src/workspace_plane.rs`
- cluster policy envs: `k8s/beagle/configmap.yaml`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_scoped_default_dev_plane_smoke.sh`

## Success condition

The phase closes when:

1. the workspace/bootstrap surface exposes explicit default-dev-plane policy
2. the policy states `Beagle/cluster` as default and `VM` as fallback-only
3. one real scoped workflow completes through the Beagle path
4. bridge, workspace, result lookup and recovery all remain intact
5. the promoted scope is explicit and bounded
6. cluster remains green
7. Slurm remains green
