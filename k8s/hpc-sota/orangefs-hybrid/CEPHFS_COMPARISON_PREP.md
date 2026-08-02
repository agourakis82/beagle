# CephFS Comparison Prep

## Why this exists

The existing OrangeFS versus Ceph benchmark history in this repo compares:

- OrangeFS as a shared filesystem exposed through a host mount
- Ceph through `RBD` PVCs exposed as per-pod block volumes

That is still useful operationally, but it is not the cleanest shared-filesystem
versus shared-filesystem comparison.

To make the next Orange comparison fairer, the cluster needs a CephFS path.

## Current cluster state

What exists today:

- `ceph-rbd-ssd`
- `ceph-rbd-ssd-datasets`
- `ceph-rbd-ssd-checkpoints`
- `ceph-rbd-ssd-scratch`

What does not exist today:

- `CephFS` CSI deployment in repo
- a `CephFS` `StorageClass`
- an RWX shared Ceph filesystem path for the Orange proven workflow shape

## What a fairer comparison needs

1. A CephFS filesystem in the Ceph cluster
2. CephFS CSI driver deployed to Kubernetes
3. A shared RWX `StorageClass`
4. A workflow using the same logical phases as Orange:
   - one dataset writer
   - two fan-out readers
   - two concurrent checkpoint writers

## Proposed artifact split

This repo now includes starter manifests for that future round:

- [CephFS shared PVC example](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pvc-cephfs-shared-compare.example.yaml)
- [CephFS workflow pod template](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-cephfs-proven-workflow-template.example.yaml)

These are examples only until the cluster actually exposes a CephFS
`StorageClass`.

## Recommended next step

If the goal is a clean Orange-versus-Ceph comparison:

1. stand up CephFS CSI
2. create the RWX CephFS storage class
3. adapt the proven workflow runner so it can target:
   - `orangefs`
   - `cephfs`
4. compare the same workflow shape instead of comparing OrangeFS to RBD-only
   block volumes
