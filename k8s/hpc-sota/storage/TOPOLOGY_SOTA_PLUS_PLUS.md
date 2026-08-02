# Storage Topology SOTA++

This is the live storage model for the cluster as of April 2026.

## Principles

- keep one durable shared tier
- keep at least one hot shared tier outside Ceph
- keep near-GPU local tiers for scratch and runtime cache
- move critical workspaces out of the Ceph blast radius before major Ceph surgery
- make every tier visible in Grafana and Prometheus

## Current tiers

### Durable shared tier

- backend: Ceph
- role:
  - retained datasets
  - retained checkpoints
  - shared scratch
  - rollback path for older PVC-backed workloads
- classes:
  - `ceph-rbd-ssd-datasets`
  - `ceph-rbd-ssd-checkpoints`
  - `ceph-rbd-ssd-scratch`
  - `ceph-rbd-ssd-rwop`

### Hot shared workspace tier

- backend: `zfast` on `t560-proxmox`
- role:
  - `BEAGLE`
  - `SOUNIO`
  - fast local workspaces
  - evacuation landing zone before Ceph remodelling
- current live PVCs:
  - `beagle-core-local-data`
  - `beagle-workspace-local-data`
  - `sounio-workspace-local-data`

### Premium local NVMe tier

- backend: `nvme0n1p2` on `r740-proxmox`
- mount: `/mnt/hpc-local-nvme`
- role:
  - high-speed scratch
  - checkpoint spill
  - dataset shard cache
  - export staging
- Kubernetes:
  - `StorageClass/local-nvme-r740`
  - `PV/local-nvme-r740-scratch-pv`
  - `PVC/local-nvme-r740-scratch`

### Runtime cache tier

- backend: `/mnt/ai-runtime` on `r770-proxmox`
- mount: `/mnt/ai-runtime/k8s-local-runtime-cache`
- role:
  - model cache
  - wheel cache
  - image/runtime staging
  - inference-adjacent temporary data
- Kubernetes:
  - `StorageClass/local-ai-runtime-r770`
  - `PV/local-ai-runtime-r770-pv`
  - `PVC/local-ai-runtime-r770-cache`

## Workload placement guidance

- workspaces:
  - prefer `local-zfast-t560`
- distributed training datasets:
  - source of truth on Ceph datasets class
  - copy or cache hot shards to `local-nvme-r740` when the run benefits
- checkpoints:
  - primary durable checkpoints on Ceph
  - optional spill / temp checkpointing on `local-nvme-r740`
- runtime and inference caches:
  - prefer `local-ai-runtime-r770`

## What this unlocks

- safer Ceph maintenance because critical workspaces already have a non-Ceph home
- faster near-GPU scratch on `r740`
- dedicated runtime cache on `r770`
- one observability plane for GPU, Ceph, and local tiers

## Next surgery after this phase

1. identify the exact workload that still depends on degraded PG `5.1e`
2. decide whether to repair placement at size `3` or temporarily relax that pool
3. continue evacuating anything still living only on legacy Ceph workspace PVCs
4. only then start destructive OSD and boot-layout changes on `5860` and `t560`
