# B14.1 - First Real Workstream Cutover

## Current status

B14.1 is currently `GO`.

Canonical live cutover workspace:

- `b141-0321174602`

Canonical smoke evidence will live under:

- `.artifacts/darwin-hpc/first-real-workstream-cutover/bootstrap-before.json`
- `.artifacts/darwin-hpc/first-real-workstream-cutover/bootstrap-after-deploy.json`
- `.artifacts/darwin-hpc/first-real-workstream-cutover/workstream-cutover-policy-summary.json`
- `.artifacts/darwin-hpc/first-real-workstream-cutover/pilot.json`
- `.artifacts/darwin-hpc/first-real-workstream-cutover/smoke.json`
- `.artifacts/darwin-hpc/first-real-workstream-cutover/session-after-restart.json`
- `.artifacts/darwin-hpc/first-real-workstream-cutover/final-cluster-health.txt`

## Objective

Promote one real workstream to canonical Beagle/cluster operation:

1. define one named workstream explicitly in live workspace policy
2. keep `beagle-cluster` as the official execution plane
3. keep VM explicitly `fallback-only`
4. prove one real workstream loop under the cut-over policy
5. preserve session, handoff, recovery and result lookup continuity

## Selected workstream

This phase cuts over one real workstream only:

- workstream: `beagle-darwin-hpc-governance`
- repo: `agourakis82/beagle`
- branch lineage: `feat/darwin-hpc-governance`
- default plane: `beagle-cluster`
- VM role: `fallback-only`
- promotion scope: `beagle-darwin-hpc-general-noninfra`

## Runtime shape

The phase reuses the current Beagle surfaces only:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `POST /api/darwin/workspace/pilot/execute`
- `GET /api/darwin/hpc/results/{job_id}`
- `GET /api/darwin/hpc/results/{job_id}/manifest`

## Architectural decision

- the phase promotes one real workstream, not all workstreams at once
- the cutover becomes explicit in workspace bootstrap/session metadata through a
  `workstream_cutover_policy`
- one real workflow proves the cut-over state, and restart/recovery confirms it
  survives beyond a single request
- fallback is not forced, but if it occurs it must remain explicit and bounded
- the phase does not reopen providers, ingress, edge, HA, topology or lower
  layers

## Placement

- workspace/session runtime: `crates/beagle-darwin/src/workspace_plane.rs`
- workspace config model/loading:
  `crates/beagle-config/src/model.rs`,
  `crates/beagle-config/src/lib.rs`
- cluster policy envs: `k8s/beagle/configmap.yaml`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_first_real_workstream_cutover_smoke.sh`

## Success condition

The phase closes when:

1. the selected workstream is explicit in live workspace state
2. the workstream policy marks `beagle-cluster` as default and VM as
   `fallback-only`
3. one real workstream loop completes through the cut-over policy
4. session, handoff and recovery remain coherent after restart
5. published result lookup remains valid
6. cluster remains green
7. Slurm remains green

## Live result

The first real workstream cutover closed as `GO`.

Live proof from the canonical run:

1. workspace `b141-0321174602` stayed on repo `agourakis82/beagle` and branch
   `feat/darwin-hpc-governance`
2. the live bootstrap/session state after deploy exposed an explicit
   `workstream_cutover_policy` for
   `beagle-darwin-hpc-governance`
3. the cutover policy marked
   `cutover_state=canonical`,
   `default_dev_plane=beagle-cluster`,
   `vm_fallback_role=fallback-only`,
   `recovery_required=true`,
   `handoff_required=true`
4. one real `gpu-single-v1` loop completed as job `50` on `r740-proxmox`
5. the workstream handoff persisted and the loop continued to resolve
   published result `32`
6. the same session `ws-20260321204603` survived predeploy, postdeploy and
   restart/recovery
7. no fallback occurred during the cutover drill, so VM remained
   `fallback-only` in practice
8. cluster remained green and `Slurmctld(primary)` remained `UP`
