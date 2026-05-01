# HPC Cluster Placement Policy (2026-04-19)

This cluster has four materially different nodes. The failures on `t560-proxmox`
and `5860-proxmox` showed that "large machine" is not the same thing as "safe
runtime target" unless the hot paths are bound to the right storage.

## Node roles

- `t560-proxmox`
  - role: `infra-control`
  - profile: `root-plus-zfast`
  - purpose:
    - control-plane and infrastructure tooling
    - host-local administration
    - non-critical operational services
  - avoid:
    - critical Beagle control-path services
    - any workload that assumes rootfs growth is safe

- `r740-proxmox`
  - role: `gpu-inference`
  - profile: `ceph-plus-gpu`
  - purpose:
    - GPU inference and serving
    - CUDA / RDMA-heavy runtime
  - prefer:
    - `sglang-serving`
    - GPU pilot and inference-lane workloads

- `r770-proxmox`
  - role: `cluster-core`
  - profile: `ceph-core`
  - purpose:
    - Beagle control/cognitive core
    - Cockpit public/native boundary
    - agent orchestration and stateful cluster services
  - prefer:
    - `beagle-core`
    - `project-cockpit`
    - other critical control-path services

- `5860-proxmox`
  - role: `io-lab`
  - profile: `local-thin-plus-ceph`
  - purpose:
    - OrangeFS and lab-style storage/runtime experiments
    - worker/daemonset capacity once rootfs pressure is under control
  - caution:
    - local lab data must not live on the tiny root LV
    - place large lab state on a dedicated local volume, not `/`

## Labels

Live cluster labels:

- `sounio.dev/runtime-role`
- `sounio.dev/storage-profile`
- `sounio.dev/cluster-tier`

Critical manifests should target the role label first, then use hostname only as
an explicit preference when a single node is currently the right anchor.

## Storage policy

- critical state:
  - use Ceph-backed PVCs
  - do not tie the cluster brain to node-local rootfs assumptions

- local scratch / caches / build trees / lab datasets:
  - keep them off `/`
  - use dedicated local mounts, bind mounts, or explicit local volumes

- root filesystem:
  - treat as operating system space, not as a general data lake

## Availability policy

- `beagle-core` and `project-cockpit` belong on `cluster-core`
- GPU serving belongs on `gpu-inference`
- infra-only services may remain on `infra-control`
- experimental/lab data services on `io-lab` must provision dedicated local
  storage before they are trusted as stable runtime dependencies
- the sovereign reranker belongs on `cluster-core`, but only as a bounded
  specialist lane; it should not silently expand into the generic retrieval
  critical path without explicit performance evidence

## Lessons from the 2026-04-19 recovery

- `t560-proxmox` did not run out of total disk; rootfs pressure came from hot
  paths living on the wrong filesystem.
- `5860-proxmox` did not need more disks; its active OrangeFS lab data needed a
  dedicated local volume instead of the 94 GiB root LV.
- the cluster should express placement intent in labels and manifests so these
  mistakes do not silently reappear during future deployments.
- the sovereign reranker proved that "healthy" is not the same thing as "cheap"
  or "globally appropriate"; bounded high-latency services must remain explicit
  in policy.
