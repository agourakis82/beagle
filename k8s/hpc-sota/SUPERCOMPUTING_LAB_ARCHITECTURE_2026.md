# Supercomputing Lab Architecture 2026

## Goal

This is the strongest realistic architecture for the current lab if the target
is not merely "Kubernetes with GPUs" but a real hybrid AI/HPC platform.

It assumes:

- Kubernetes remains the platform control plane
- OrangeFS remains the shared AI/HPC data plane
- local NVMe remains the hot ephemeral tier
- Slurm is added as the classical HPC scheduling plane

## Core design

### 1. Platform plane

Use Kubernetes for:

- cluster lifecycle
- service discovery
- observability
- operators
- multi-tenant application plumbing
- ingress, auth, dashboards, APIs, notebooks, and internal services

Keep using:

- `JobSet`
- `Kueue`
- `RuntimeClass nvidia`
- Multus GPU fabric

This is the right substrate for cloud-native AI work.

### 2. HPC scheduling plane

Add Slurm for:

- partitioned HPC queues
- reservations
- fair-share / accounting
- `sbatch`, `srun`, `squeue`
- classical MPI/HPC workflows
- node-exclusive long-running training or simulation jobs

Best target model:

- Slurm on Kubernetes through the SchedMD Kubernetes path
- Slurm as an HPC scheduler beside Kubernetes-native batch, not a full
  replacement for Kubernetes

### 3. Shared storage plane

Use OrangeFS for:

- datasets
- checkpoints
- shared AI/HPC artifacts
- cross-node durable job state

Use Ceph for:

- generic platform PVCs
- durable services that want CSI semantics
- boring storage that should stay boring

Use local NVMe for:

- scratch
- caches
- shard staging
- fast transient per-node data

### 4. Network plane

Keep the fabric split explicit:

- management / underlay
- service / cluster traffic
- GPU / RDMA fabric

The ideal long-term shape is:

- Kubernetes CNI for ordinary pod networking
- dedicated high-performance fabric for distributed training and HPC traffic
- explicit policy around which workloads get the fast fabric

### 5. Workload model

Use three workload classes:

#### Cloud-native AI jobs

Use:

- Kubernetes
- JobSet
- Kueue
- `torchrun`

Storage:

- OrangeFS datasets/checkpoints
- local scratch

#### Classical HPC jobs

Use:

- Slurm
- containerized executors where helpful
- direct node allocations where needed

Storage:

- OrangeFS shared HPC namespace
- local scratch

#### Platform services

Use:

- Kubernetes Deployments / StatefulSets
- Ceph-backed PVCs

Storage:

- Ceph
- local host storage only when intentionally simple

## Recommended topology

### Kubernetes remains the source of truth for:

- node registration
- GPU runtime plumbing
- network attachments
- metrics
- dashboards
- secrets/config

### Slurm becomes the source of truth for:

- HPC queue semantics
- reservations
- user-facing batch policy for supercomputing-style jobs

### OrangeFS becomes the source of truth for:

- shared training data
- checkpoints
- shared HPC artifact directories

## Why this is the "most badass" architecture

Because it avoids fake purity.

It does not try to force one tool to do every job:

- Kubernetes is better at platform operations
- Slurm is better at classical HPC scheduling
- OrangeFS is better at shared AI/HPC data paths than generic PVC thinking
- Ceph is better at boring CSI-backed service storage
- NVMe is better at hot transient locality

That division of labor is what makes the lab feel like a real supercomputing
platform instead of a patched-together GPU cluster.

## Rollout order

1. Keep OrangeFS as the shared AI/HPC data plane
2. Keep the current `JobSet + Kueue` path green
3. Add a Slurm pilot beside Kubernetes, not instead of it
4. Bind one or two real HPC-style workloads to Slurm
5. Keep Ceph as the service/PVC plane
6. Make local NVMe the official scratch/cache tier

The repo path for that pilot is now:

- [slurm-pilot/README.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/README.md)

As of `2026-04-05`, that pilot is no longer just planned:

- `cert-manager` is installed
- `slurm-operator` is installed
- the Slurm pilot namespace is live
- the `gpu-orangefs` partition is up with both GPU nodes registered
- an `sbatch` smoke job has successfully written into OrangeFS
- `slurmdbd` is live with host-local MariaDB on `t560`
- the `cpu-ops` partition is live on `t560`
- a PBPK-style CPU batch job has completed through Slurm and written into
  OrangeFS
- an omics-style CPU batch job has completed through Slurm and written into
  OrangeFS
- a PL-runtime-style GPU batch job has completed through Slurm and written into
  OrangeFS
- Slurm accounts/QoS now encode the domain tracks:
  - `pbpk -> cpuops`
  - `omics -> cpuops`
  - `plruntime -> gpuorangefs`
- `PriorityWeightQOS = 10000` is now active, so QoS affects scheduling for
  real
- QoS tiers now exist for operations:
  - `burst`
  - `normal`
  - `long`
- the host MariaDB behind `slurmdbd` now has versioned hardening and daily
  backups
- the next resilience blueprint is captured in:
  - [SLURMDBD_EVOLUTION.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/SLURMDBD_EVOLUTION.md)

## Official direction references

- PyTorch elastic / `torchrun`:
  - https://docs.pytorch.org/docs/stable/elastic/quickstart
  - https://docs.pytorch.org/docs/stable/elastic/train_script.html
- PyTorch distributed:
  - https://docs.pytorch.org/docs/stable/distributed.html
- Kueue:
  - https://kueue.sigs.k8s.io/
- JobSet:
  - https://kubernetes.io/blog/2025/03/23/introducing-jobset/
- Kubernetes Services / discovery:
  - https://kubernetes.io/docs/concepts/services-networking/service/
- SchedMD Slurm on Kubernetes / Slinky:
  - https://slurm.schedmd.com/kubernetes.html
  - https://slinky.schedmd.com/
