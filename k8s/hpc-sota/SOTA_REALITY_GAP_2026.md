# SOTA Reality Gap 2026

Last checked: 2026-05-25 13:47 America/Sao_Paulo

This note is the honest gap map between the live Darwin/Sounio lab and a
credible 2026 AI/HPC supercomputing posture.

The cluster is useful and operational. It is not yet fully SOTA. Treat this as
the operator backlog, not as a marketing label.

## Live baseline

Verified live on 2026-05-25:

- Kubernetes nodes: `4/4 Ready`
- Kubernetes version: `v1.35.5`
- Slurm controller: `UP`
- Slurm partitions:
  - `cpu-ops`
  - `gpu-orangefs`
  - `all`
- Slurm GPU workers admitted:
  - `gpuorangefs-5860-proxmox`
  - `gpuorangefs-r740-proxmox`
  - `gpuorangefs-r770-proxmox`
- GPU lease state:
  - `5860-proxmox`: `NVIDIA RTX 4000 Ada`, owner `slurm-job`, job `1969_3`
  - `r740-proxmox`: `NVIDIA RTX A5000`, owner `slurm-job`, job `1969_1`
  - `r770-proxmox`: `NVIDIA L4`, owner `slurm-job`, job `1969_2`
- Kueue:
  - `ClusterQueue/sounio-hpc`
  - `LocalQueue/beagle/hpc-batch`
  - `LocalQueue/beagle/hpc-training`
  - ResourceFlavors for `gpu-l4`, `gpu-rtx-a5000`, and `gpu-rtx-4000-ada`
  - `Topology/gpu-fabric-10-210`
  - WorkloadPriorityClasses for `hpc-interactive`, `hpc-training`, and
    `hpc-batch`
  - GPU ResourceFlavors bound to `Topology/gpu-fabric-10-210`
- RDMA substrate:
  - Multus daemonset running
  - Cilium `cni-exclusive=false`
  - `00-multus.conf` restored on all GPU nodes
  - NVIDIA Network Operator namespace present
  - RDMA shared device plugin pods present
  - `10.210` JobSet/NCCL socket smoke passed on `r770-proxmox` + `r740-proxmox`
- OrangeFS:
  - client mount active on `t560`
  - current visible capacity: `933G`
  - current usage at check time: `516G used`, `417G available`

## What is genuinely strong

### Hybrid scheduler shape

The cluster has both working lanes:

- Kubernetes + JobSet + Kueue + OrangeFS
- Slurm/Slinky + OrangeFS + Kubernetes

That is the right high-level shape. SOTA AI/HPC is not "Kubernetes instead of
Slurm" or "Slurm instead of Kubernetes"; it is split authority with a clear
contract between platform, batch, storage, and accelerator ownership.

### GPU ownership visibility

The current `ops/gpu-lease` path checks:

- declared owner
- observed Slurm jobs
- observed Kubernetes GPU pods
- observed host GPU processes
- serving deployment replicas

That is a real improvement over the earlier state where agents looked at only
one plane and concluded the wrong thing.

### Slurm guardrail for gpuorangefs

The canonical Slurm admission path is:

```bash
/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh <node> admit
```

That gate checks Cilium, ordinary pod network reachability, Slurm node
registration, and a CUDA Slurm smoke before keeping the node admitted.

This is good ops discipline.

### Kueue resource flavors exist

The cluster has SKU-aware ResourceFlavors:

- `gpu-l4`
- `gpu-rtx-a5000`
- `gpu-rtx-4000-ada`

This is better than a single undifferentiated GPU pool.

## SOTA gaps

### Gap 1: GPU lease is still a script/state-file contract

Current state:

- `ops/gpu-lease`
- `/home/devsounio/projects/sounio/GPU_LEASES.json`
- Cockpit API wrappers
- Action Ledger gate around UI transitions

Missing SOTA layer:

- controller-owned state
- reconcile loop
- explicit lease object lifecycle
- event stream for ownership changes
- automatic drift repair or quarantine
- identity-aware audit for every transition

Target:

- make GPU leases controller-backed
- expose lease state as an API object
- keep Action Ledger for destructive transitions
- make Slurm admission and serving scale changes consume the same authority

### Gap 2: Kubernetes DRA exists in the API but is not used

Current state:

- `deviceclasses.resource.k8s.io`
- `resourceclaims.resource.k8s.io`
- `resourceclaimtemplates.resource.k8s.io`
- `resourceslices.resource.k8s.io`

These API resources exist, but no live DRA objects were observed during the
check.

Missing SOTA layer:

- `DeviceClass` definitions for local accelerator classes
- `ResourceClaimTemplate` usage in GPU workloads
- DRA-backed workload examples
- Kueue DRA quota integration
- device metadata surfaced into jobs

Target:

- keep current device-plugin path stable
- add a DRA canary lane for Kubernetes-native GPU workloads
- do not pretend DRA governs Slurm until a bridge/controller exists

Progress:

- staged DRA canary manifests now exist under
  `/home/devsounio/beagle/k8s/hpc-sota/dra`
- `dra-canary-doctor.sh` validates the API and canary manifests without
  allocating GPUs
- no live `ResourceSlice` objects exist yet, so DRA is still staged, not a
  production GPU authority

### Gap 3: Kueue is topology-aware but lacks admission checks

Current state:

- `ClusterQueue/sounio-hpc`
- queueing strategy `BestEffortFIFO`
- resource flavors by GPU SKU
- GPU ResourceFlavors bound to `Topology/gpu-fabric-10-210`
- `WorkloadPriorityClass` objects exist for interactive, training, and batch
- no active workloads pending
- live `AdmissionCheck/fabric-storage-readiness` seed exists
- operator-side reconciler script exists but is not yet scheduled
- `ClusterQueue/sounio-hpc` does not yet enforce the AdmissionCheck

Missing SOTA layer:

- scheduled admission reconciliation for fabric/storage readiness
- cohort/fair-sharing policy
- explicit policy for when Kubernetes batch may borrow/compete with serving
  or Slurm

Target:

- add admission checks for GPU fabric and OrangeFS readiness
- model topology for `10.210` GPU fabric once measured
- keep Kueue scoped to Kubernetes workloads unless Slurm bridge is built

### Gap 4: Slurm is functional but not topology/block SOTA

Current state:

- Slurm GPU partition is healthy
- GPU GRES works
- QoS exists
- accounting backend is live
- worker admission has a custom gate

Missing SOTA layer:

- Slurm topology model for switch/fabric domains
- `topology.yaml` or `topology.conf`
- topology-aware partition policy
- cgroup v2 posture explicitly audited against Slurm config
- per-job GPU utilization and GPU memory accounting surfaced as first-class
  observability

Target:

- document current fabric topology in NetBox first
- generate Slurm topology config from the same source of truth
- keep one-GPU-per-node simple path working while topology is introduced

### Gap 5: RDMA/GPU fabric exists but still needs a GPU-consuming proof

Current state:

- Multus exists
- Multus is active as the primary CNI shim on GPU nodes
- RDMA shared device plugin exists
- NVIDIA Network Operator namespace exists
- `10.210` host-to-host jumbo pings pass across the GPU hosts
- `10.210.0.254` is live on `arista-7060:Vlan210` and jumbo-clean from GPU hosts
- `10.210` Kubernetes JobSet smoke passed with NCCL sockets on `net1`
- `gpu-fabric-gate.sh phase3-smoke` now refuses to create GPU pods while
  `gpu-lease` reports active Slurm/Kubernetes/host GPU use

Missing SOTA layer:

- fresh end-to-end GPUDirect RDMA proof
- measured NCCL performance across the `10.210` fabric
- fabric health dashboard
- PFC/ECN/MTU verification recorded as a repeatable gate
- GPU/NIC PCIe root-complex inventory per node

Target:

- run a fresh verbs/GPUDirect RDMA proof on all GPU pairs
- record baseline bandwidth/latency
- add the result to node admission and DL380 onboarding

### Gap 6: OrangeFS is useful but not yet the final storage plane

Current state:

- OrangeFS client mount works
- current namespace is about `933G`
- `/orangefs` is used for datasets, checkpoints, and artifacts
- `5860` remains a temporary capacity anchor in the docs

Missing SOTA layer:

- multi-terabyte backing storage
- dedicated storage devices outside fragile thin-pool illusions
- fresh benchmark matrix after every node/storage change
- clear promotion path from current repaired namespace to durable growth server

Target:

- use DL380 NVMe/local disks as the next real storage decision point
- keep workspaces and platform state off OrangeFS
- benchmark OrangeFS against local NVMe and old Ceph paths before promotion

### Gap 7: Node lifecycle is still artisanal

Current state:

- NetBox exists
- seed scripts exist
- DL380 runbook now exists
- DL380 planned NetBox/IPAM seed exists, with `.5` fabric reservations
- no fully automated bare-metal provisioning lane was observed

Missing SOTA layer:

- API-driven bare-metal lifecycle
- firmware/BIOS profile enforcement
- reproducible host bootstrap
- node conformance test before scheduler admission
- inventory-to-Kubernetes/Slurm reconciliation

Target:

- make DL380 the first disciplined node admission
- require NetBox first, Kubernetes second, OrangeFS third, Slurm fourth
- promote that path into a reusable node lifecycle controller/runbook

### Gap 8: Observability is good but not yet scheduler-native enough

Current state:

- Grafana is live
- Slurm, GPU lease, workspace, and platform doctors exist
- Prometheus alerts catch many operator issues

Missing SOTA layer:

- per-job GPU utilization correlated with Slurm job id
- queue wait, backfill, QoS, failure reason, and GPU-memory panels
- RDMA/fabric health panels
- OrangeFS server/client throughput and latency dashboards
- Action Ledger event timeline joined to scheduler mutations

Target:

- add a scheduler-native Grafana board:
  - Slurm queue and accounting
  - GPU lease owner
  - host GPU processes
  - Kueue workloads
  - OrangeFS throughput
  - RDMA fabric health

## Priority order

### P0: Keep the working cluster honest

- refresh `ops/gpu-lease status` before claiming GPU availability
- run `ops/supercomputer-readiness/sota-readiness-doctor.sh` when deciding
  whether a gap is operational breakage or a known SOTA backlog item
- keep serving deployments scaled to `0` while GPUs are batch-owned
- route heavy CPU work through Slurm, not the workspace pod
- use `68-manage-gpuorangefs-worker.sh` for Slurm GPU admission

### P1: Make DL380 the first real disciplined expansion

- inventory hardware and firmware
- allocate addresses in NetBox
- join Kubernetes as a plain worker
- prove OrangeFS client
- prove GPU runtime if GPU exists
- add GPU domain only after `nvidia-smi -L`
- admit to Slurm only through the gpuorangefs gate

### P2: Prove GPU fabric, not just GPU presence

- run fresh RDMA/NCCL canaries
- use `ops/supercomputer-readiness/gpu-fabric-gate.sh status` as the canonical
  operator entrypoint for fabric readiness
- use `ops/supercomputer-readiness/gpu-fabric-gate.sh phase3-preflight` before
  promoting the dedicated `10.210` GPU fabric
- use `ops/supercomputer-readiness/gpu-fabric-gate.sh phase3-external-preflight`
  to prove `vmbr210`/`gpufabric210`, MTU 9000, and jumbo host-to-host
  connectivity
- record per-pair bandwidth and latency
- decide whether the current `10.210` fabric is production-worthy or only lab
  experimental

### P3: Add DRA canary without breaking the old path

- create a small Kubernetes DRA-only GPU canary
- compare with current device-plugin flow
- keep Slurm authority separate

### P4: Turn GPU lease into a controller-backed authority

- keep current script as CLI
- move state behind API/controller
- emit events
- require Action Ledger for destructive transitions

### P5: Grow storage for real

- stop treating the repaired `933G` namespace as final
- use DL380 storage inventory to choose the first real growth server
- benchmark before moving more science workloads

## Source references

Primary external references consulted:

- Kubernetes Dynamic Resource Allocation:
  <https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/>
- Kubernetes v1.36 DRA update:
  <https://kubernetes.io/blog/2026/05/07/kubernetes-v1-36-dra-136-updates/>
- Kueue overview and concepts:
  <https://kueue.sigs.k8s.io/docs/overview/>
  <https://kueue.sigs.k8s.io/docs/concepts/>
- Kueue ClusterQueue:
  <https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/>
- NVIDIA GPU Operator GPUDirect RDMA/GDS:
  <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-rdma.html>
- Slurm GRES:
  <https://slurm.schedmd.com/gres.html>
- Slurm cgroup:
  <https://slurm.schedmd.com/cgroups.html>
- Slurm topology guide:
  <https://slurm.schedmd.com/topology.html>
- Slurm topology.yaml:
  <https://slurm.schedmd.com/topology.yaml.html>
