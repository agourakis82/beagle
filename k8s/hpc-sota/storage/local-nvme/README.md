# Local NVMe Tier on `r740-proxmox`

This layer is the fast local tier for April 2026 cluster work:

- very high IOPS scratch
- dataset shard cache close to GPU
- checkpoint spill and resume cache
- image and wheel cache near the training node

It is intentionally **node-local**, not a durable shared replacement for Ceph.

## Live host path

- node: `r740-proxmox`
- mount: `/mnt/hpc-local-nvme`
- filesystem: `xfs`

Subdirectories created on the host:

- `/mnt/hpc-local-nvme/scratch`
- `/mnt/hpc-local-nvme/datasets-cache`
- `/mnt/hpc-local-nvme/checkpoints-cache`
- `/mnt/hpc-local-nvme/images-cache`
- `/mnt/hpc-local-nvme/exports`

## Kubernetes objects

- [StorageClass](/home/devsounio/beagle/k8s/hpc-sota/storage/local-nvme/storageclass-local-nvme-r740.yaml)
- [PersistentVolume](/home/devsounio/beagle/k8s/hpc-sota/storage/local-nvme/pv-local-nvme-r740-scratch.yaml)
- [example PVC](/home/devsounio/beagle/k8s/hpc-sota/storage/local-nvme/pvc-local-nvme-r740-scratch.example.yaml)

## Design intent

Use this tier for:

- preprocessing
- shard-local dataset copies
- checkpoint staging before pushing to durable storage
- bursty training artifacts that do not belong on the durable tier

Do not treat this as the only copy of important data.
