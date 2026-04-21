# BeeGFS First Rollout Plan

This is the first serious BeeGFS rollout for the current cluster shape.

## Design principles

- do not break current Kubernetes production paths
- do not move workspaces first
- start with the AI/HPC data plane
- keep local NVMe as the near-GPU hot tier
- validate on clients before widening the server footprint

## Phase A: client-first canary

Start on:

- `r740`
- `r770`

Install only:

- `beegfs-client`
- `beegfs-tools`

Add later if needed:

- `libbeegfs-ib`

Goals:

- confirm client module builds on `6.17.x-pve`
- confirm clean mounts on both GPU nodes
- confirm no regression to RDMA/NCCL jobs

## Phase B: first server island

Bring up:

- `t560`
  - `beegfs-mgmtd`
  - `beegfs-meta`
- `5860`
  - `beegfs-storage`

Optional early converged step:

- add `beegfs-storage` on `t560` as the second storage target host if we want a
  two-storage-server start

Why this shape:

- `t560` already behaves like a service and platform anchor
- `5860` has the strongest immediate case for shared storage service duty
- `r740` and `r770` stay focused on compute and hot local tiers

## Phase C: first filesystem namespaces

Create and prove:

- `/beegfs/datasets`
- `/beegfs/checkpoints`
- `/beegfs/scratch`

Do not place on BeeGFS yet:

- workspaces
- Grafana / Prometheus state
- Kubernetes control-plane state
- random platform services

## Phase D: incoming DL380 G10

When the `DL380 G10` arrives:

- make it a BeeGFS client on day one
- use its NVMe as the third hot local tier
- later decide whether it stays compute-only or contributes additional BeeGFS
  service capacity

## Rollout order

1. client canary on `r740`
2. client canary on `r770`
3. management + metadata on `t560`
4. first storage on `5860`
5. optional second storage on `t560`
6. benchmark pass
7. first training canary on BeeGFS data paths

## Exit criteria for rollout success

- client module builds on both `r740` and `r770`
- clients mount and survive reboot
- management and metadata services stay stable
- storage service exports targets correctly
- benchmark numbers beat the current Ceph-first dataset/checkpoint path for the
  intended workloads
- Kubernetes production path remains intact throughout
