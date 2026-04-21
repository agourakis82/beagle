# B14.3 - Workstream Recipes & Execution Graphs

## Current status

B14.3 is `GO`.

Canonical live validation workspace:

- `b143-0321200310`

Canonical recipe artifacts live under:

- `docs/darwin/hpc/workstreams/recipes/README.md`
- `docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.repo_native_dev_loop.yaml`
- `docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.operator_cpu_loop.yaml`
- `docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.operator_gpu_loop.yaml`
- `docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.recovery_resume_loop.yaml`

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/workstream-recipe-smoke/recipe-manifest.json`
- `.artifacts/darwin-hpc/workstream-recipe-smoke/repo-native-loop.json`
- `.artifacts/darwin-hpc/workstream-recipe-smoke/operator-cpu-loop.json`
- `.artifacts/darwin-hpc/workstream-recipe-smoke/operator-gpu-loop.json`
- `.artifacts/darwin-hpc/workstream-recipe-smoke/recovery-resume-loop.json`
- `.artifacts/darwin-hpc/workstream-recipe-smoke/smoke.json`
- `.artifacts/darwin-hpc/workstream-recipe-smoke/final-cluster-health.txt`
- `.artifacts/darwin-hpc/workstream-recipe-smoke/raw-sustained-run/`

## Objective

Turn the already-cut-over workstream into a governed runnable workstream:

1. define canonical repo-native recipes for the core loop families
2. make step order, inputs, outputs and recovery points explicit
3. validate recipe execution semantics without reopening lower layers
4. keep the validation anchored on the same canonical workstream object:
   `beagle-darwin-hpc-governance`

## Recipe set

The first canonical recipe set covers four loop families:

1. `repo_native_dev_loop`
2. `operator_cpu_loop`
3. `operator_gpu_loop`
4. `recovery_resume_loop`

Each recipe is versioned alongside the workstream spec and captures:

1. workstream identity
2. required inputs
3. ordered execution steps
4. expected outputs
5. explicit recovery points
6. success criteria

## Execution graph decision

- recipe graphs stay repo-native; they do not introduce a new workflow engine
- live validation reuses the already-proven sustained validation path to prove
  that the recipe semantics are executable on the current platform
- the phase does not add new infra, ingress, edge, HA, providers or topology
- recovery remains explicit and governed through the workstream contract

## Placement

- workstream registry root: `docs/darwin/hpc/workstreams/`
- recipe root: `docs/darwin/hpc/workstreams/recipes/`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_workstream_recipe_smoke.sh`
- smoke validator:
  `scripts/infrastructure/darwin-hpc/validate_workstream_recipe_smoke.sh`

## Success condition

The phase is now closed because:

1. the canonical workstream has explicit versioned recipes
2. at least one canonical smoke validates recipe execution semantics
3. inputs, outputs and recovery points are explicit in the recipe specs
4. cluster remains green
5. Slurm remains green
6. no lower layer is reopened

## Live result

The canonical recipe smoke closed as `GO`.

Live proof from workspace `b143-0321200310`:

1. the recipe manifest exposed four explicit recipes for
   `beagle-darwin-hpc-governance`
2. the repo-native recipe validated a real delta of `67` changed paths, rebuilt
   and redeployed `beagle-core`, and completed bridge request
   `b143-repo-0321200310` through `deepseek/deepseek-chat`
3. the CPU operator recipe completed `cpu-batch-v1` as job `52` and resolved
   published result `31`
4. the GPU operator recipe completed `gpu-single-v1` as job `53` on
   `r740-proxmox` and resolved published result `32`
5. the recovery recipe preserved the same session
   `ws-20260321230311` across deploy, GPU workflow and restart/recovery
6. the post-restart state remained on `default_dev_plane=beagle-cluster` with
   `vm_fallback_role=fallback-only`
7. fallback was not observed during the run
8. cluster remained green and `Slurmctld(primary)` remained `UP`
