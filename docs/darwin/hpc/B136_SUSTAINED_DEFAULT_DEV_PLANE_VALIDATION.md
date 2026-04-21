# B13.6 - Sustained Default Dev Plane Validation

## Current status

B13.6 is currently `GO`.

Canonical live validation workspace:

- `b136-0321173454`

Canonical smoke evidence will live under:

- `.artifacts/darwin-hpc/sustained-default-dev-plane-validation/bootstrap-before.json`
- `.artifacts/darwin-hpc/sustained-default-dev-plane-validation/loop1.json`
- `.artifacts/darwin-hpc/sustained-default-dev-plane-validation/loop2.json`
- `.artifacts/darwin-hpc/sustained-default-dev-plane-validation/loop3.json`
- `.artifacts/darwin-hpc/sustained-default-dev-plane-validation/smoke.json`
- `.artifacts/darwin-hpc/sustained-default-dev-plane-validation/session-after-restart.json`
- `.artifacts/darwin-hpc/sustained-default-dev-plane-validation/final-cluster-health.txt`

## Objective

Prove that the already-promoted default dev plane remains stable under repeated
real use:

1. keep `beagle-cluster` as the default dev plane throughout the sequence
2. keep VM explicitly `fallback-only`
3. prove session, handoff and ledger continuity across repeated loops
4. prove restart/recovery after a heterogeneous workload sequence
5. keep cluster and Slurm green

## Validation shape

This phase runs three real loops inside the already-promoted scope
`beagle-darwin-hpc-general-noninfra`:

1. loop 1: one repo-native dev loop using the current workspace delta,
   followed by build, deploy and live validation
2. loop 2: one operator workflow using `cpu-batch-v1`
3. loop 3: one advanced operator workflow using `gpu-single-v1`, followed by
   restart/recovery proof

The validation remains cluster-first and stays on the same canonical repo:

- repo: `agourakis82/beagle`
- branch: canonical active workspace-plane branch
- default plane: `beagle-cluster`
- VM role: `fallback-only`
- promotion scope: `beagle-darwin-hpc-general-noninfra`

## Runtime shape

The phase reuses the current Beagle surfaces only:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `GET /api/darwin/hpc/control`
- `GET /api/darwin/hpc/results`
- `GET /api/darwin/hpc/results/{job_id}`
- `GET /api/darwin/hpc/results/{job_id}/manifest`
- `POST /api/darwin/bridge/execute`
- `POST /api/darwin/workspace/pilot/execute`

## Architectural decision

- the phase does not broaden scope again; it validates sustained use inside the
  already-promoted scope
- the proof is sequence-based: one repo-native loop, one CPU workflow and one
  GPU workflow on the same workspace/session line
- restart/recovery is validated at the end of the multi-loop sequence instead
  of as an isolated pilot
- fallback is not forced, but if it occurs it must remain explicit and bounded
- the phase does not reopen providers, ingress, edge, HA, topology or lower
  platform layers

## Placement

- workspace/session runtime: `crates/beagle-darwin/src/workspace_plane.rs`
- cluster policy envs: `k8s/beagle/configmap.yaml`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_sustained_default_dev_plane_validation.sh`

## Success condition

The phase closes when:

1. loop 1 completes with one real repo-native build, deploy and live validate
2. loop 2 completes with one real `cpu-batch-v1` workflow
3. loop 3 completes with one real `gpu-single-v1` workflow
4. the same workspace/session line remains coherent across the sequence
5. restart/recovery preserves the same workspace context after the three loops
6. VM remains `fallback-only` and does not regain central status by inertia
7. cluster remains green
8. Slurm remains green

## Live result

The sustained validation closed as `GO`.

Live proof from the canonical run:

1. workspace `b136-0321173454` stayed on repo `agourakis82/beagle` and branch
   `feat/darwin-hpc-governance`
2. loop 1 validated a real repo-native delta of `45` changed paths, rebuilt the
   image, redeployed it and completed one real `deepseek` bridge request
   `b136-loop1-0321173454`
3. loop 2 completed one real `cpu-batch-v1` workflow as job `48` and resolved
   published result `31`
4. loop 3 completed one real `gpu-single-v1` workflow as job `49` on
   `r740-proxmox` and resolved published result `32`
5. the same session `ws-20260321203455` survived predeploy, postdeploy and
   restart/recovery at the end of the sequence
6. the post-restart session still exposed
   `default_dev_plane=beagle-cluster`,
   `vm_fallback_role=fallback-only`,
   `promotion_scope=beagle-darwin-hpc-general-noninfra`
7. no fallback occurred during the sustained drill, and VM did not regain
   central status by inertia
8. cluster remained green and `Slurmctld(primary)` remained `UP`
