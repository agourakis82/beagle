# Ceph And Runtime Fabric Policy (2026-04-19)

This note captures the post-recovery state of the Beagle storage and runtime
fabric after the `t560` rootfs failure, the `5860` monitor-store outage, and
the stranded SSD PG recovery.

## What Failed

- `t560-proxmox` had plenty of total disk, but hot runtime paths were landing on
  the small `pve-root` filesystem instead of `zfast`.
- `5860-proxmox` lost a Ceph monitor because the local monitor store hit an
  effectively full root filesystem.
- `beagle-core` was historically tied to a node-local storage path on the wrong
  node, so one host-level storage issue destabilized the whole cognitive stack.

## What Is True Now

- Ceph is healthy again:
  - monitor quorum is `3/3`
  - the previously degraded SSD PG `5.1e` is `active+clean`
- `beagle-core` runs on `r770-proxmox` with Ceph-backed storage
- `project-cockpit` runs with 2 replicas on `cluster-core`
- `t560-proxmox` root pressure is resolved by moving heavy developer/runtime
  paths onto `zfast`
- `5860-proxmox` root pressure is resolved by placing OrangeFS lab state on a
  dedicated local volume instead of `/`

## Runtime Topology

- `t560-proxmox`
  - label: `sounio.dev/runtime-role=infra-control`
  - use for:
    - control-plane and infra-only services
    - workspaces and operator-style support surfaces
  - avoid for:
    - critical cluster brain services
    - anything that depends on local rootfs growth

- `r740-proxmox`
  - label: `sounio.dev/runtime-role=gpu-inference`
  - use for:
    - GPU inference serving
    - dynamo / sglang worker lane
    - GPU-adjacent low-latency model services

- `r770-proxmox`
  - label: `sounio.dev/runtime-role=cluster-core`
  - use for:
    - `beagle-core`
    - `project-cockpit`
    - sovereign embeddings/reranker
    - control-path services that define the user experience
  - local mutable cache tier:
    - `/mnt/ai-runtime`

- `5860-proxmox`
  - label: `sounio.dev/runtime-role=io-lab`
  - use for:
    - OrangeFS and storage/runtime experiments
    - overflow worker capacity only after local-volume discipline is respected

## Storage Rules

- Ceph-backed PVCs are the default for:
  - critical state
  - user-facing control-path services
  - anything whose loss or eviction breaks cognition, memory, or public access

- Local storage is appropriate only for:
  - scratch
  - caches
  - model download caches
  - build outputs
  - explicit lab datasets

- Concrete local cache tiers:
  - `t560-proxmox` -> `/zfast`
  - `r740-proxmox` -> `/mnt/hpc-local-nvme`
  - `r770-proxmox` -> `/mnt/ai-runtime`
  - `5860-proxmox` -> `/var/lib/orangefs-lab` only for OrangeFS/lab payloads,
    not generic runtime spill

- The root filesystem is not a data tier.
  - do not place long-lived caches, container stores, build trees, or lab
    payloads on `/`
  - rootfs budgets:
    - warning when `/` stays below `15%` free
    - critical when `/` stays below `10%` free
    - kubelet `DiskPressure` is a real incident, not cosmetic noise

## Sovereign Reranker Policy

- The self-hosted sovereign reranker on `r770-proxmox` is a bounded pilot lane,
  not a global retrieval default.
- Current observed behavior is acceptable for sovereign and privacy-sensitive
  short-list refinement, but expensive for broad use:
  - startup/warm readiness is slow
  - rerank calls are materially higher latency than the general Voyage lane
- Policy:
  - keep it enabled only for the sovereign lane
  - do not make it a mandatory reranking stage for `general` or `code`
  - prefer the external general reranker for low-latency broad retrieval
- If a future model or export materially improves latency without sacrificing
  sovereign requirements, it can replace the current lane intentionally rather
  than by drift.

## Ceph Rules

- Stay on the current maintained line intentionally; do not jump release lines
  based on generalized advisories without checking the actual pool topology.
- This cluster currently uses replicated pools, not EC pools.
- Keep monitor stores on hosts with real rootfs headroom.
- Treat any `pg_upmap` or `pg_upmap_items` entries as surgical debt:
  - fine during recovery
  - document them
  - remove only after confirming the balancer and CRUSH map can hold the clean
    state without them

## Scheduling Rules

- Prefer label-based placement:
  - `sounio.dev/runtime-role`
  - `sounio.dev/storage-profile`
  - `sounio.dev/cluster-tier`
- Use raw `kubernetes.io/hostname` only as:
  - a preference within a role
  - or when the hardware itself is the requirement

## Follow-Up Work

1. Keep watching Ceph until the remaining transient `remapped` PGs drain.
2. Revisit any old `pg_temp` / `pg_upmap_items` once recovery activity settles.
3. Continue migrating hostname-pinned manifests toward role labels.
4. Keep developer and lab data off root filesystems on all nodes.
