# BeeGFS Hybrid Moonshot

This is the practical open-source-first storage pivot for the cluster:

- `BeeGFS` as the high-performance shared filesystem for AI/HPC data paths
- `ZFS/NFS` as user and platform storage
- local NVMe on GPU nodes as the hot tier
- `Kueue` as the admission and coexistence layer for mixed workloads

## Why BeeGFS

BeeGFS is a parallel filesystem designed around:

- separate metadata and storage services
- striped file contents across storage targets
- direct client I/O to storage servers
- converged or dedicated layouts
- RDMA support on clients and servers

That is a much better match than `Ceph-first` for:

- LLM training data and checkpoints
- shared scratch
- omics pipelines
- fMRI pipelines
- PBPK ensembles
- mixed AI/HPC jobs on multiple GPU nodes

## 2026 hybrid split

### BeeGFS

Use BeeGFS for:

- `/beegfs/datasets`
- `/beegfs/checkpoints`
- `/beegfs/scratch`
- high-throughput scientific data planes

### User / platform storage

Keep user and platform data on:

- `zfast` / ZFS exports
- host-local storage
- simple NFS if needed

This includes:

- live workspaces
- service configs
- observability state
- anything that should not depend on the HPC filesystem

### Local NVMe

Use local NVMe per GPU node for:

- shard cache
- model cache
- runtime cache
- checkpoint spill
- fast temporary data near the GPU

## Important licensing reality

BeeGFS is available-source and has a self-supported Community Edition.

However, in BeeGFS 8 some features such as storage pools are licensed
enterprise features. This means the free path should not assume those features.

The serious open path is therefore:

- use core BeeGFS filesystem functionality in Community Edition
- avoid designing the first rollout around enterprise-only features
- use directory layout and service placement intentionally instead of relying on
  storage pools from day one

## Practical first production shape

### Management service

- run on `t560`
- management is not performance-critical and fits the service-heavy role

### Metadata service

- start on `t560`
- later add a second metadata service when the new node arrives or after cleanup

### Storage services

- `5860` as first storage server
- `t560` as second storage server
- optional later storage contribution from `DL380 G10` if it is not dedicated
  only to compute

### Clients

- `r740`
- `r770`
- `5860` if it remains a compute participant
- incoming `DL380 G10`

## Why this fits the mission

This cluster wants to become a small research supercomputing platform for:

- SounioLang and epistemic computation
- hypercomplex algebra workloads
- omics foundation model work
- PBPK and systems-biology jobs
- fMRI and multimodal scientific pipelines

That is exactly the kind of mixed AI/HPC environment where a fast shared
parallel filesystem plus local NVMe tiers makes more sense than a monolithic
storage platform.

## Execution files

- [first rollout plan](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/FIRST_ROLLOUT_PLAN.md)
- [package strategy for Debian 13 + PVE](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/PACKAGE_STRATEGY.md)
- [benchmark ritual](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/BENCHMARK_RITUAL.md)
- [migration plan](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/MIGRATION_PLAN.md)
- [r740 client canary install](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/install-r740-client-canary.sh)
- [r740 client canary rollback](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/rollback-r740-client-canary.sh)
- [r740 client canary results](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/CANARY_RESULTS.md)
- [config templates](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/configs/beegfs-client.conf.example)
- [client autobuild template](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/configs/beegfs-client-autobuild.conf.example)
- [synthetic benchmark harness](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/benchmark/run-synthetic.sh)
