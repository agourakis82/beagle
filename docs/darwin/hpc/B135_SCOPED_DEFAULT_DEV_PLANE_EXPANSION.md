# B13.5 - Scoped Default Dev Plane Expansion

## Current status

B13.5 is currently `GO`.

Canonical live smoke run ID:

- `b135-0321132051-scoped-dev-plane-expansion`

Canonical smoke evidence will live under:

- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/bootstrap-before.json`
- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/scope-summary.json`
- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/bootstrap-after-deploy.json`
- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/bridge-execute.json`
- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/pilot.json`
- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/fallback-enter.json`
- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/fallback-return.json`
- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/smoke.json`
- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/session-after-restart.json`
- `.artifacts/darwin-hpc/scoped-dev-plane-expansion-smoke/final-cluster-health.txt`

## Objective

Expand the already-promoted default dev-plane scope without changing the
platform shape:

1. keep `Beagle/cluster` as the default dev plane
2. keep VM explicitly `fallback-only`
3. broaden the promoted Darwin/HPC/Beagle development scope in a bounded way
4. prove one real development loop inside the expanded scope
5. preserve restart, recovery, handoff and fallback discipline

## Selected scope

This phase promotes one larger but still bounded scope:

- repo: `agourakis82/beagle`
- branch: canonical active branch on the workspace plane
- promotion scope: `beagle-darwin-hpc-general-noninfra`
- default plane: `beagle-cluster`
- VM role: `fallback-only`

Included:

- `beagle-darwin`
- `beagle-monorepo`
- Darwin/HPC docs, contracts, templates and scripts
- runtime/config changes for the existing Beagle/Darwin plane

Excluded:

- edge and ingress
- HA work
- topology changes
- provider expansion
- giant cross-cutting refactors
- cluster base infrastructure
- anything that reopens B9, B10, B11 or B12

## Runtime shape

The phase reuses the current Beagle surfaces only:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `POST /api/darwin/bridge/execute`
- `POST /api/darwin/workspace/pilot/execute`
- `POST /api/darwin/workspace/fallback/start`
- `POST /api/darwin/workspace/fallback/return`
- `GET /api/darwin/hpc/results/{job_id}`
- `GET /api/darwin/hpc/results/{job_id}/manifest`

## Architectural decision

- the canonical policy is expanded in the existing workspace-plane metadata
- the phase stays cluster-first and repo-native; it does not add new surfaces,
  ingress, HA, topology or provider scope
- the proof combines build/deploy/validate, one real workflow, bounded fallback
  and restart recovery in the same phase
- VM remains a bounded escape hatch, not a concurrent primary plane

## Placement

- config/runtime policy: `crates/beagle-config/src/model.rs`
- env/config loading: `crates/beagle-config/src/lib.rs`
- workspace/session runtime: `crates/beagle-darwin/src/workspace_plane.rs`
- cluster policy envs: `k8s/beagle/configmap.yaml`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_scoped_dev_plane_expansion_smoke.sh`

## Success condition

The phase closes when:

1. live workspace policy exposes the expanded scope explicitly
2. the expanded policy still marks `beagle-cluster` as default
3. the VM role still remains `fallback-only`
4. one real workflow completes inside the expanded scope
5. fallback entry and return remain bounded and explicit
6. restart/recovery preserve session, handoff and policy continuity
7. cluster remains green
8. Slurm remains green

## Live result

The validated expansion proved that the larger bounded dev-plane scope now
holds cleanly as the canonical default:

- workspace `b135-0321132051` bootstrapped on repo `agourakis82/beagle` and
  branch `feat/darwin-hpc-governance`
- the live policy after deploy exposed
  `default_dev_plane=beagle-cluster`,
  `vm_fallback_role=fallback-only`,
  `promotion_scope=beagle-darwin-hpc-general-noninfra`
- one real `deepseek` bridge request completed successfully through the
  expanded scope
- one real `cpu-short-v1` workflow completed through the expanded scope as job
  `47`
- published result `24` remained resolvable through the current result and
  manifest surfaces
- fallback start explicitly moved the workspace to `active_dev_plane=vm-fallback`
  and return explicitly restored `active_dev_plane=beagle-cluster`
- the return preserved `duration_seconds=2` and the same session
  `ws-20260321162052` survived deploy, return and restart
- cluster remained green and Slurm remained green
