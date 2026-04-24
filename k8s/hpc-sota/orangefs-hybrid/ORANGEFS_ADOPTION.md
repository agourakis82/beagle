# OrangeFS Adoption Path

## Decision

OrangeFS is now adopted as the experimental shared AI/HPC filesystem branch for
the cluster.

The immediate adoption scope is:

- shared datasets
- shared checkpoints
- training canaries and data-plane jobs on GPU nodes
- local pod scratch for transient write-heavy workspace

It is **not** the default backend for:

- control-plane state
- Grafana or Prometheus state
- generic platform PVCs
- workspace roots already stable on `zfast`
- text-heavy Sounio compiler scratch or `.stdout` aggregation without a local
  verification path

## Live prerequisites

Current live assumptions:

- `t560` runs `orangefs-server01.service`
- `5860` runs `orangefs-server02.service`
- `r740` runs `orangefs-client-runtime.service`
- `r770` runs `orangefs-client-runtime.service`
- `orangefs-proven-workflow-canary.timer` is active on `t560`
- `orangefs-training-canary.timer` is active on `t560`

## 2026-04-24 capacity repair

The original two-server OrangeFS baseline had a bad allocation on `5860`:

- live server02 data and metadata were still stored under
  `/var/lib/orangefs-lab/two-node/server02/*`
- that path lived on a `128G` thin LV
- the same LV was also carrying unrelated `service-fabric/registry-data`
- the result was a false cluster-level `100%` full condition even though the
  visible `/orangefs/training` tree was far smaller

The live repair moved server02 onto a dedicated thin-backed filesystem:

- mount: `/srv/orangefs-server02-store`
- live server02 paths:
  - `/srv/orangefs-server02-store/data`
  - `/srv/orangefs-server02-store/meta`
  - `/srv/orangefs-server02-store/log`

Post-repair live result:

- the GPU clients now report the OrangeFS export at roughly `933G` total
  instead of `250G`
- both `r740` and `r770` again see substantial free space
- the dedicated text-integrity probe is green on both GPU clients after the
  migration

This repair restored the namespace, but it did not yet make OrangeFS a
multi-terabyte data plane.

Current measured truth:

- `t560` server01 has room on `zfast`
- `5860` server02 is still the effective capacity ceiling
- the `5860` dedicated server02 LV is healthy, but the underlying `pve/data`
  thin pool remains nearly full

That means the next OrangeFS decision is about growth topology, not first
viability.

Detailed next-step plan:

- [multi-terabyte capacity plan](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/MULTITERABYTE_CAPACITY_PLAN.md)

## First real adoption workload

The first promoted workload is a DDP training canary that mounts OrangeFS
directly through host paths on both GPU nodes.

Artifacts:

- [OrangeFS DDP JobSet](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/jobset-ddp-training-canary-orangefs.yaml)
- [apply runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-training-canary.sh)

Current JobSet name:

- `orangefs-train`

It uses:

- `/var/lib/orangefs-lab/client-runtime/mnt/training-orangefs/datasets`
- `/var/lib/orangefs-lab/client-runtime/mnt/training-orangefs/checkpoints`

The current preferred layout is:

- OrangeFS for:
  - datasets
  - checkpoints
- local pod scratch (`emptyDir`) for transient throughput files

and restricts scheduling to nodes labeled:

- `sounio.dev/orangefs-client=true`

Current canary status:

- the OrangeFS DDP canary is now green with the current baseline:
  - `LAUNCHER_MODE=torchrun`
  - `FORCE_BACKEND=gloo`
  - OrangeFS for:
    - `/datasets`
    - `/checkpoints`
  - local pod scratch via `emptyDir`
- the JobSet now uses a fixed topology for the launcher path:
  - `leader` pinned to `r770-proxmox`
  - `worker` pinned to `r740-proxmox`
  - `NODE_RANK` from `job-global-index`
- the previous bootstrap blockers were narrowed and addressed:
  - coordinator-discovery on rank 0
  - checkpoint atomic-write path
  - scratch path hardening
- the latest live reconciliation also repaired two concrete regressions:
  - `r770` was missing `sounio/pytorch-rdma:2.7.1-cuda12.8-rdma` while the
    canary still relied on `imagePullPolicy: Never`
  - the `orangefs-hybrid` launcher wrapper had drifted back to the headless
    rendezvous service instead of the deterministic coordinator hostname
- the latest full canary completed on both ranks with:
  - dataset writes
  - checkpoint writes
  - local scratch writes
  - `JobSet orangefs-train` in `Completed`
  - confirmed again under the fixed `leader`/`worker` topology
  - current known-good run id:
    - `1775437389`

That means the current adoption baseline is strong enough for:

- durable dataset paths on OrangeFS
- durable checkpoint paths on OrangeFS
- local scratch for transient throughput files
- multi-node training canaries on GPU nodes
- first simple real workloads on GPU nodes

The automation story also improved:

- the runner now avoids the earlier fragile worker-side coordinator discovery
- after `r740` recovered from a reboot/`NotReady` episode, the promoted canary
  baseline completed again with the fixed leader/worker topology
- `t560` now also carries an active OrangeFS client mount for control-plane
  visibility into the shared training path
- the remaining work is now timer repeatability and operational polish, not
  proving the storage path

The first simple real workload also completed:

- [artifact probe job](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/job-orangefs-artifact-probe.yaml)
- result:
  - `orangefs-artifact-probe` `Complete`
  - dataset and checkpoint artifacts present on the OrangeFS host path
  - runtime proof:
    - the probe now reports `cuda=true`
    - it sees `gpu_count=1` inside the pod

There is now an explicit correctness caveat on the PVFS2 text path:

- binary dataset/checkpoint canaries remain useful
- text-heavy `.sio` and `.stdout` artifacts need a dedicated integrity probe
- the promoted Sounio campaign path now defaults to worker-local stage/run and
  worker-first fetch instead of assuming OrangeFS publication is the safe
  default

The next single-node promoted GPU workload is now ready:

- [cuda pilot job](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/job-orangefs-cuda-pilot.yaml)
- purpose:
  - keep OrangeFS for datasets and checkpoints
  - keep scratch local
  - prove real CUDA compute, not just artifact I/O
- current result:
  - `orangefs-cuda-pilot` `Complete`
  - runtime proof on `r740`:
    - `cuda=true`
    - `device_name=NVIDIA RTX A5000`
    - `gpu_count=1`
  - artifacts are visible from both GPU clients and from the mounted `t560`
    control node path

The first domain workload tracks are now also running on the same baseline:

- `pbpk-single-gpu-orangefs` completed successfully with CUDA visible in-pod
- `omics-preprocess-orangefs` completed successfully and produced:
  - `/datasets/omics-expression-summary.csv`
  - `/checkpoints/omics-preprocess-summary.json`
- `pl-runtime-gpu-pilot-orangefs` completed successfully and produced:
  - `/datasets/pl-runtime-metrics.json`
  - `/checkpoints/pl-runtime-state.pt`

Operationally, the GPU clients (`r740`, `r770`) remain the source of truth for
fresh writer-side validation. The mounted `t560` control-plane client now gives
useful visibility too, but after heavy write churn it may occasionally need a
simple `systemctl restart orangefs-client-runtime.service` to refresh a stale
view.

Detailed status:

- [training canary status](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/TRAINING_CANARY_STATUS.md)
- [real workload path](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/REAL_WORKLOAD_PATH.md)

## Why this is the right first step

This keeps the Orange adoption honest:

- real distributed workload
- real GPU nodes
- real shared filesystem paths
- no attempt to pretend OrangeFS is a generic CSI backend for everything

## Next promotion gates

1. The dedicated training-canary timer survives at least one scheduled run
2. Late elastic shutdown warnings stay non-fatal across repeated runs
3. Promote additional AI/HPC jobs onto OrangeFS by default
