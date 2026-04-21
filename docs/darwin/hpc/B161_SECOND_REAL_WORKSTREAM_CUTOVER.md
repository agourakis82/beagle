# B16.1 - Second Real Workstream Cutover

## Current status

B16.1 is `GO`.

Target second workstream:

- `beagle-darwin-hpc-wave1`

Target branch lineage:

- `feat/darwin-hpc-wave1`

Planned deliverables for this phase:

- `docs/darwin/hpc/workstreams/beagle-darwin-hpc-wave1.yaml`
- `docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.repo_native_dev_loop.yaml`
- `docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.operator_cpu_loop.yaml`
- `docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.recovery_resume_loop.yaml`
- `scripts/infrastructure/darwin-hpc/run_second_real_workstream_cutover_smoke.sh`
- `scripts/infrastructure/darwin-hpc/validate_second_real_workstream_cutover_smoke.sh`

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/second-real-workstream-cutover/`

Canonical live IDs:

- `workspace_id=b161-wave1-0322082253`
- `session_id=ws-20260322112605`

## Objective

Cut over a second real Darwin/HPC workstream using the same Beagle-native
model already proven for `beagle-darwin-hpc-governance`, without reopening
lower layers.

This phase proves that the workstream operating model generalizes beyond the
first special workstream by adding one more repo-native line on the same repo,
scope and infrastructure:

1. registry-backed spec
2. repo-native recipes
3. live session/workspace identity
4. control-room visibility
5. timeline visibility
6. coherent restart/recovery

## Selected second workstream

The second workstream is:

- `beagle-darwin-hpc-wave1`

Why this line:

1. it already exists as a real repo branch: `feat/darwin-hpc-wave1`
2. it stays inside the same repo and promoted scope
3. it represents a distinct Darwin/HPC internal line without inventing a new
   product or reopening architecture
4. it is narrow enough to prove multi-workstream generalization with bounded
   risk

## Architectural decision

- the second workstream reuses the same Beagle-owned session/workspace plane
- control room, governance, cockpit and timeline remain the same internal
  surfaces
- no new infra, provider, ingress, edge or HA layer is introduced
- the runtime accepts a bounded workstream identity override only for seeding a
  non-default workstream pilot; Beagle remains the source of truth
- restart/recovery must preserve the same workspace/session identity after the
  initial live seed

## Success condition

B16.1 closed as `GO` after live proof that:

1. `beagle-darwin-hpc-wave1` is first-class in the registry
2. one real loop completes under that workstream
3. control room resolves that workstream coherently
4. timeline resolves that workstream coherently
5. restart/recovery preserves the same session/workspace identity
6. cluster remains green
7. Slurm remains green

## Canonical proof

- second workstream: `beagle-darwin-hpc-wave1`
- workspace/session: `b161-wave1-0322082253` / `ws-20260322112605`
- real loop: `cpu-batch-v1`, submitted as job `59`, completed on `t560-proxmox`
- last-result resolution stayed coherent against published result `31`
- control room listed both canonical workstreams and resolved the `wave1` spec,
  recipes, status, handoff and last-result surfaces coherently
- timeline replay returned four ordered events and exposed bounded workflow and
  recovery event detail
- restart preserved the same `workspace_id`, `session_id`,
  `default_dev_plane=beagle-cluster` and `fallback_active=false`
- cluster stayed green and `Slurmctld(primary)` remained `UP`
