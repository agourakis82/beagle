# OrangeFS Hybrid Migration Plan

This is the practical migration path from the current `Ceph + local tiers`
cluster into an `OrangeFS-first` AI/HPC data plane without breaking Kubernetes.

## Goal

End state:

- `OrangeFS` becomes the shared high-performance filesystem for:
  - datasets
  - checkpoints
  - scratch
- `zfast` / ZFS / NFS remains the user and platform layer for:
  - workspaces
  - configs
  - observability state
- local NVMe remains the near-GPU hot tier for:
  - model cache
  - shard cache
  - checkpoint spill
  - temporary runtime data

## Non-goals

This migration does **not** start by:

- deleting Ceph OSDs
- moving live workspaces first
- moving Prometheus or Grafana state into OrangeFS

## Phase 0: keep production calm

- keep `BEAGLE` on local `zfast`
- keep `SOUNIO` on local `zfast`
- keep local tiers on `r740` and `r770`
- keep Ceph as the durable legacy path until OrangeFS proves the heavy data
  plane

## Phase 1: first OrangeFS server pair

Start with:

- `t560`
- `5860`

These serve the first OrangeFS namespace while keeping compute clients on:

- `r740`
- `r770`
- incoming `DL380`

## Phase 2: first namespaces

Create and prove:

- `/orangefs/datasets`
- `/orangefs/checkpoints`
- `/orangefs/scratch`

Do **not** start by moving:

- workspaces
- platform state
- observability state

## Phase 3: benchmark and compare

Prove OrangeFS against:

- current Ceph-first shared path
- current local NVMe hot tiers

Use:

- synthetic parallel I/O
- checkpoint loops
- training canaries
- omics/fMRI-shaped data movement

## Phase 4: DL380 arrival

When the `DL380 G10` arrives:

- add it as an OrangeFS client immediately
- use its NVMe as an additional hot tier
- decide later whether to keep it compute-only or add OrangeFS server duty

## Phase 5: shrink Ceph deliberately

Only after OrangeFS proves itself for the AI/HPC data plane:

- move datasets/checkpoints/scratch away from Ceph-first patterns
- keep Ceph only for durable legacy/platform roles
- then decide whether Ceph remains reduced or exits the design entirely
