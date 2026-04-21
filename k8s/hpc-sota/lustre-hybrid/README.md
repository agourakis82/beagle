# Lustre Hybrid Moonshot

This directory captures the non-conventional storage pivot for the cluster:

- `Lustre` as the high-performance shared data plane
- `ZFS/NFS` as user and platform storage
- local NVMe per GPU node as the hot tier
- `Kueue` as the workload admission brain

## Why hybrid

The cluster wants to run at least three classes of work side by side:

- local and distributed LLM training
- scientific pipelines such as omics, fMRI, and PBPK
- platform workloads like workspaces, services, and observability

One storage technology is not ideal for all three.

## 2026-oriented split

### Lustre

Use Lustre for:

- large shared training datasets
- checkpoint fan-in/fan-out
- shared scratch
- high-throughput scientific data pipelines

### User / platform storage

Use host-local ZFS or simple NFS exports for:

- workspaces
- home directories
- configs
- service data that does not need a parallel filesystem

### Local NVMe

Use local NVMe per GPU node for:

- shard cache
- model cache
- runtime cache
- checkpoint spill
- high-speed temporary data

## Important support reality

The current cluster nodes run:

- Debian 13 (trixie)
- Proxmox kernels `6.17.x-pve`

That is not the normal server-side Lustre support path.

As of the late-2025 public Lustre support matrix, Lustre server testing tracks
`RHEL 8.10`, while tested clients include `RHEL 9.7`, `SLES 15 SP6`, and
`Ubuntu 22.04`.

That means the serious path is:

- keep Kubernetes on the current Debian/PVE nodes for now
- introduce one or more Lustre servers on a supported OS
- mount Lustre from compute nodes only when client support is acceptable

## Recommended first production shape

### Lustre servers

- `t560`: metadata / management candidate after cleanup
- `5860`: OST server candidate after cleanup
- `DL380 G10`: optional future OST or client/cache node once it arrives

### Lustre clients

- `r740`
- `r770`
- `5860` optionally if it remains a GPU node
- `DL380 G10`

### Keep these outside Lustre

- `BEAGLE` live workspace path on `zfast`
- `SOUNIO` live workspace path on `zfast`
- Grafana / Prometheus / K8s control-plane state

## Phased execution

1. finish draining important active work away from legacy Ceph workspace PVCs
2. keep the current local tiers live
3. stand up a supported Lustre control/storage pair outside the hot path
4. benchmark Lustre against the current local tiers and Ceph-backed data paths
5. move training datasets and checkpoints into Lustre
6. keep user/platform data on ZFS/NFS/local tiers

## Why this fits the mission

This cluster is not trying to be conventional.
It is trying to become a small research supercomputing platform for:

- epistemic computation and SounioLang
- hypercomplex algebra workloads
- omics foundation model work
- PBPK and systems-biology jobs
- fMRI and multimodal scientific pipelines

That strongly favors a storage split where the data plane is optimized for
throughput and the platform plane is optimized for operational clarity.
