# BeeGFS Hybrid Migration Plan

This is the practical migration path from the current `Ceph + local tiers`
cluster into a `BeeGFS-first` AI/HPC data plane without breaking Kubernetes.

## Goal

End state:

- `BeeGFS` is the shared high-performance filesystem for:
  - datasets
  - checkpoints
  - scratch
- `zfast` / ZFS / NFS is the user and platform layer for:
  - workspaces
  - service state that should stay simple
  - observability state
- local NVMe remains the near-GPU hot tier for:
  - model cache
  - shard cache
  - checkpoint spill
  - temporary runtime data

## Non-goals

This migration does **not** start by:

- ripping out Kubernetes storage
- deleting Ceph OSDs first
- moving Grafana, Prometheus, or control-plane state into BeeGFS

## Phase 0: Keep the live path stable

Before BeeGFS rollout:

- keep `BEAGLE` live workspace path on local `zfast`
- keep `SOUNIO` live workspace path on local `zfast`
- keep current local tiers on:
  - `r740`
  - `r770`
- keep Ceph only for the durable legacy path until data-plane replacement is
  proven

## Phase 1: BeeGFS control island

First production-shaped layout:

- `t560`
  - `beegfs-mgmtd`
  - first `beegfs-meta`
- `5860`
  - first `beegfs-storage`
- `t560`
  - optional second `beegfs-storage` for a two-storage-server start
- clients:
  - `r740`
  - `r770`
  - `5860` if it remains in the compute pool
  - incoming `DL380 G10`

What to validate first:

- package support on the chosen OS
- management service stability
- metadata service stability
- client mounts on `r740` and `r770`

## Phase 2: First filesystem namespaces

Start with clean namespaces:

- `/beegfs/datasets`
- `/beegfs/checkpoints`
- `/beegfs/scratch`

Do **not** start by putting:

- workspaces
- Grafana / Prometheus state
- Kubernetes control-plane data

onto BeeGFS.

## Phase 3: Benchmark and prove the data plane

Run side-by-side tests:

- BeeGFS vs current local NVMe staging
- BeeGFS vs current Ceph dataset/checkpoint path
- training checkpoint fan-out
- distributed dataloading
- scientific pipeline staging

Initial workloads to prove:

- distributed LLM training canary
- omics shard staging
- fMRI batch input pipeline
- checkpoint write/read loops

## Phase 4: DL380 arrival

When the `DL380 G10` arrives:

- install it as a BeeGFS client from day one
- use its local NVMe as another hot tier
- keep the option open for later BeeGFS storage or metadata contribution

This is the point where the cluster starts to feel much more like a
supercomputing lab and less like a single shared storage stack.

## Phase 5: Shrink Ceph on purpose

Only after BeeGFS is proven for the AI/HPC data plane:

- move datasets/checkpoints/scratch away from Ceph-first patterns
- keep Ceph for:
  - legacy PVCs
  - durable retained images
  - slow-moving platform storage that still benefits from it
- then decide whether Ceph remains a reduced durable tier or exits the design

## Success criteria

We can call the migration successful when all of these are true:

- BeeGFS clients mount cleanly on all GPU nodes
- distributed training canary uses BeeGFS data paths successfully
- checkpoints are written and resumed from BeeGFS
- local NVMe remains the fast near-GPU cache tier
- Kubernetes platform workloads do not regress
- Ceph is no longer the critical path for AI/HPC jobs

## Why this is the right shape

This cluster is not trying to become a generic cloud platform.

It is trying to become a research AI/HPC system for:

- SounioLang
- epistemic computation
- hypercomplex algebra
- omics foundation models
- PBPK
- fMRI and multimodal scientific pipelines

That mission wants:

- a parallel filesystem for the heavy shared data plane
- simple user/platform storage
- local NVMe near the GPUs

That is exactly what the `BeeGFS-first hybrid` model gives us.
