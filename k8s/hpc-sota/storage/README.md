# Storage Classes by Workload Role

This layer separates storage semantics instead of forcing every workload into one class.

## Classes

- `ceph-rbd-ssd-datasets`
  - retain on delete
  - for reusable datasets and curated corpora
- `ceph-rbd-ssd-checkpoints`
  - retain on delete
  - for resumable training state
- `ceph-rbd-ssd-scratch`
  - delete on release
  - for preprocessing, intermediate tensors, and throwaway runs
- existing durable workspace class remains:
  - `ceph-rbd-ssd-rwop`

## Example PVCs

- [datasets PVC](/home/devsounio/beagle/k8s/hpc-sota/storage/examples/datasets-pvc.example.yaml)
- [checkpoints PVC](/home/devsounio/beagle/k8s/hpc-sota/storage/examples/checkpoints-pvc.example.yaml)
- [scratch PVC](/home/devsounio/beagle/k8s/hpc-sota/storage/examples/scratch-pvc.example.yaml)
- [dataset clone PVC](/home/devsounio/beagle/k8s/hpc-sota/storage/examples/datasets-clone-pvc.example.yaml)
- [checkpoint clone PVC](/home/devsounio/beagle/k8s/hpc-sota/storage/examples/checkpoints-clone-pvc.example.yaml)
- [Ceph RBD VolumeSnapshotClass](/home/devsounio/beagle/k8s/hpc-sota/storage/examples/volumesnapshotclass-rbd.example.yaml)
- [checkpoint VolumeSnapshot](/home/devsounio/beagle/k8s/hpc-sota/storage/examples/checkpoints-snapshot.example.yaml)
- [local NVMe tier on r740](/home/devsounio/beagle/k8s/hpc-sota/storage/local-nvme/README.md)
- [local runtime/cache tier on r770](/home/devsounio/beagle/k8s/hpc-sota/storage/local-ai-runtime-r770/README.md)
- [live PVC for local runtime/cache tier on r770](/home/devsounio/beagle/k8s/hpc-sota/storage/local-ai-runtime-r770/pvc-local-ai-runtime-r770.live.yaml)
- [workspace cutover to local zfast on t560](/home/devsounio/beagle/k8s/hpc-sota/storage/workspace-cutover/README.md)
- [Storage topology SOTA++](/home/devsounio/beagle/k8s/hpc-sota/storage/TOPOLOGY_SOTA_PLUS_PLUS.md)
- [BeeGFS hybrid moonshot](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/README.md)
- [BeeGFS hybrid role map](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/ROLE_MAP.md)
- [BeeGFS hybrid migration plan](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/MIGRATION_PLAN.md)
- [OrangeFS hybrid moonshot](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/README.md)
- [OrangeFS hybrid role map](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/ROLE_MAP.md)
- [OrangeFS hybrid migration plan](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/MIGRATION_PLAN.md)

## Why this matters

HPC/AI storage is not one thing:

- workspaces want durability and exclusivity
- datasets want retention and reproducibility
- checkpoints want retention and easy expansion
- scratch wants aggressive cleanup

## SOTA++ Layer

The next storage step for this cluster is:

- keep a retained "golden" dataset PVC
- clone datasets per run instead of mutating the source
- clone checkpoints for branch-and-resume workflows
- add CSI snapshots for checkpoint protection and rollback
- add a node-local NVMe tier for fast scratch and near-GPU cache
- add a second node-local runtime/cache tier on `r770`
- add a host-local hot tier for critical workspaces before any Ceph surgery

That gives us fast experiment fan-out without treating every run like a fresh copy job.

## Hybrid Pivot

The current `Ceph + local tiers` design is the safe live path.

The current moonshot target is:

- `BeeGFS` for the high-performance shared AI/HPC filesystem
- `zfast` / ZFS / simple NFS for user and platform storage
- local NVMe on GPU nodes as the hot tier

The strongest current-OS alternative is:

- `OrangeFS` for the shared AI/HPC filesystem
- `zfast` / ZFS / simple NFS for user and platform storage
- local NVMe on GPU nodes as the hot tier

That future direction is tracked in:

- [BeeGFS hybrid moonshot](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/README.md)
- [BeeGFS hybrid migration plan](/home/devsounio/beagle/k8s/hpc-sota/beegfs-hybrid/MIGRATION_PLAN.md)
- [OrangeFS hybrid moonshot](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/README.md)
- [OrangeFS hybrid migration plan](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/MIGRATION_PLAN.md)

## Current Live State

These PVCs already exist in namespace `beagle`:

- `training-datasets`
- `training-checkpoints`
- `training-scratch`

The storage canary already proved:

- checkpoint writes in `/checkpoints`
- scratch writes in `/scratch`

## Snapshot Note

The repo now contains snapshot manifests, but the cluster does not currently expose the CSI
snapshot CRDs/controller. Until that controller is installed, the snapshot examples are staged
in git rather than applied live.
