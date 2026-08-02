# GPU / RDMA Operator Staging on Kubernetes 1.35.2

This directory is the **guarded staging path** for attempting NVIDIA
Network Operator and GPU Operator on this cluster.

It is intentionally marked **unsupported / experimental for this lab**.

That does **not** mean Kubernetes `1.35.2` is unsupported by NVIDIA in the
abstract. Current official docs validate:

- **GPU Operator** on Kubernetes `1.32—1.35`
- **Network Operator v26.1.0** on Kubernetes `>=1.31 and <=1.35`

What is unsupported **here** is the combination of:

- Debian GNU/Linux 13 (`trixie`) on all nodes
- Proxmox VE kernels (`6.17.x-pve`)
- an already-live manual stack for:
  - NVIDIA device plugin
  - Multus
  - Whereabouts
  - RDMA shared device plugin
  - secondary GPU fabric manifests

So the rule is simple:

- **do not install operators directly from this directory**
- **do not let operators take over drivers or networking on first contact**
- **stage controller-only first, then compare against the current manual stack**

## Official context

Primary official references:

- GPU Operator platform support:
  - https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html
- Network Operator v26.1.0 platform support:
  - https://docs.nvidia.com/networking/display/kubernetes2610/nvidia-network-operator-v26-1-0.pdf

Those docs support the Kubernetes version. They do **not** validate this
cluster's Debian/PVE host OS/kernel combination, which is why this repo treats
the operator path as **unsupported-in-cluster until proven**.

## Current cluster assumptions

The staging path assumes the cluster currently already has:

- a working `RuntimeClass` `nvidia`
- a working manual `nvidia-device-plugin-daemonset`
- a working Multus / Whereabouts / RDMA shared plugin substrate
- a live secondary GPU fabric pilot on `10.200.0.x`

That means the safest operator attempt is:

1. install **Network Operator** in a namespace, but **do not deploy a live
   `NicClusterPolicy` yet**
2. install **GPU Operator** in a namespace, but with **driver / toolkit /
   devicePlugin disabled**
3. compare cluster state before and after
4. only then consider a handoff of one component at a time

## Files

- `preflight-unsupported-k8s135.sh`
  - validates the cluster state and surfaces likely conflicts before any
    operator install attempt
- `ROLLBACK-UNSUPPORTED.md`
  - rollback notes for uninstalling staged operators and restoring the current
    manual stack expectations
- `network-operator-values.sota.example.yaml`
  - **staging-only** Network Operator Helm values
- `network-operator-controller-only.values.yaml`
  - actual low-blast-radius values used to stage the controller on this cluster
- `gpu-operator-values.example.yaml`
  - **staging-only** GPU Operator Helm values
- `nicclusterpolicy-rdma-shared.k8s135.example.yaml`
  - a conservative example `NicClusterPolicy` for later comparison only

## Recommended staging order

### Stage 0: preflight only

```bash
/home/devsounio/beagle/k8s/hpc-sota/gpu-operators/preflight-unsupported-k8s135.sh
```

If this script reports missing manual substrate, stop.
If this script reports `staging_cleanliness=DIRTY`, stop and decide whether to
roll back the partial operator state before any further attempt.

### Stage 1: Network Operator controller only

This is the only sane first operator move on this cluster.

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm upgrade --install nvidia-network-operator nvidia/network-operator \
  --namespace nvidia-network-operator \
  --create-namespace \
  --values /home/devsounio/beagle/k8s/hpc-sota/gpu-operators/network-operator-controller-only.values.yaml
```

Important:

- the controller-only path still brings up NFD components
- it does **not** apply a live `NicClusterPolicy`
- on this tainted cluster, NFD components may need explicit tolerations or
  node pinning to stage cleanly on `t560-proxmox`

### Stage 2: GPU Operator controller-only / low-blast-radius

Only after Stage 1 is healthy and quiet:

```bash
helm upgrade --install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --values /home/devsounio/beagle/k8s/hpc-sota/gpu-operators/gpu-operator-values.example.yaml
```

Important:

- the staging values disable:
  - driver
  - toolkit
  - device plugin
  - dcgm exporter
  - gfd
  - kata manager
- this keeps the current manual GPU path alive while you verify that the
  operator controller itself does not destabilize the cluster

### Stage 3: compare, then decide

Do **not** jump straight to live operator-managed RDMA.

First compare:

- namespaces / pods
- CRDs
- node labels
- runtime classes
- current manual device plugin and RDMA substrate

Only then consider a canary `NicClusterPolicy`, and only after you understand
exactly which manual resource it will replace.

## Stop conditions

Stop immediately if any of the following happen during a future live attempt:

- `gpu-operator` or `nvidia-network-operator` starts deploying driver/toolkit
  unexpectedly
- existing `nvidia-device-plugin-daemonset` or `rdma-shared-dp-ds` starts
  flapping
- Multus / Whereabouts / `gpu-fabric-10-200-pilot` stop looking healthy
- `RuntimeClass` `nvidia` changes unexpectedly
- `nvidia.com/gpu` or `rdma/sounio_gpu_fabric` allocatable drops on live nodes

## Relationship to the existing fabric path

The current live RDMA/net1 pilot remains under:

- [/home/devsounio/beagle/k8s/sounio-gpu-fabric/README.md](/home/devsounio/beagle/k8s/sounio-gpu-fabric/README.md)

That path is the fallback.

The operator path in this directory is **not** the new source of truth yet.
It is the explicit staging lane for comparing against the manual substrate.
