# SOTA Cluster Architecture 2026

Updated: 2026-05-25 12:44 UTC / 2026-05-25 09:44 America/Sao_Paulo

This is the operator-facing architecture note for the Darwin/Sounio cluster.
It compares the current lab against 2026 SOTA supercomputing and AI-factory
patterns.

## Executive Summary

The 2026 SOTA pattern is not Kubernetes versus Slurm. It is:

- Kubernetes as platform/control plane
- Slurm as HPC/batch scheduling plane
- Kueue as Kubernetes workload admission and quota plane
- explicit GPU lease authority across serving and batch
- topology-aware GPU scheduling
- separated network fabrics
- local scratch plus durable shared storage
- per-job provenance and observable capacity truth

The current Darwin/Sounio lab already has the right core ingredients:

- Kubernetes control plane
- Slurm/Slinky lane
- Kueue installed
- JobSet path
- OrangeFS shared data plane
- Ceph PVC plane
- three single-GPU nodes
- Sounio workspace and Foundry separation

The missing architectural layer was a single authoritative GPU lease controller
or runbook-backed contract that moves GPUs between:

- `serving`
- `batch`
- `maintenance`
- `quarantine`

without relying on agent memory.

## 2026 SOTA Signals

Web refresh, 2026-05-25:

- NVIDIA's current GB300 NVL72 reference architecture is explicitly
  rack-scale, dual-plane, liquid-cooled, and supports both Kubernetes and Slurm
  for non-virtualized workloads.
- NVIDIA/SchedMD's May 2026 Slurm guidance treats NVLink domains as hard
  scheduling boundaries using `topology/block`, `topology.yaml`, and segment
  sizing.
- NVIDIA's April 2026 rack-scale guidance introduces automated topology
  discovery and scheduler-ready primitives for Slurm and Kubernetes DRA.
- Kubernetes DRA is GA as of Kubernetes 1.34 and is the stable direction for
  accelerator-aware Kubernetes scheduling.
- Kueue's 2026 concepts include ResourceFlavor, ClusterQueue, AdmissionCheck,
  Topology, Topology Aware Scheduling, DRA quota management, cohorts,
  preemption, and fair sharing.
- OpenCHAMI represents the cloud-native HPC management-plane direction:
  composable services, zero-trust/OIDC, API-driven provisioning, and secure
  bootstrapping.
- TOP500 still shows the large-system pattern: heterogeneous accelerators,
  specialized interconnects, power/cooling awareness, and multiple benchmarks
  beyond raw HPL.

### Rack-Scale GPU Domains

NVIDIA's 2026 GB300 NVL72 Enterprise Reference Architecture frames the scalable
unit as a rack-scale domain: 18 compute trays, 72 Blackwell Ultra GPUs, 36 Grace
CPUs, fifth-generation NVLink, Spectrum-X scale-out networking, and explicit
support for Kubernetes and Slurm.

Important lesson for this lab:

- even at small scale, GPUs should be treated as topology domains with explicit
  ownership and scheduling state
- a model pod holding a GPU and a Slurm worker holding the same GPU pool must
  be mutually exclusive unless contention is intentional

### Slurm Topology-Aware Scheduling

NVIDIA and SchedMD's current direction for Blackwell-scale systems is Slurm
topology/block scheduling. The scheduler must understand placement domains,
not just count GPUs.

Important lesson for this lab:

- `--gres=gpu:1` is sufficient for single-card smoke tests
- production batch policy should still record node class, GPU model, fabric,
  and lease state
- as the lab grows beyond one GPU per node, topology must become first-class

### Kubernetes DRA and Kueue

Kubernetes Dynamic Resource Allocation and Kueue resource flavors represent the
cloud-native side of accelerator scheduling. Kueue is a quota/admission system
for Kubernetes workloads. It does not automatically govern Slurm jobs unless a
bridge/controller explicitly connects them.

Important lesson for this lab:

- `ClusterQueue/sounio-hpc` with `nvidia.com/gpu=3` is real for Kubernetes
  workloads
- it is not the authority for Slurm jobs today
- any doc or UI implying "Kueue manages all GPUs including Slurm" is wrong
  until a bridge exists
- DRA is the Kubernetes-native future interface for accelerator description
  and allocation; use it for K8s-native inference/training, not as a fake
  substitute for Slurm accounting
- Kueue ResourceFlavors should model our actual GPU classes, not a single
  undifferentiated `nvidia.com/gpu=3`

### Cloud-Native HPC Management Plane

OpenCHAMI and the current NVIDIA Mission Control direction both point to the
same operational lesson: cluster authority should be API-driven, composable,
auditable, and identity-aware.

Important lesson for this lab:

- shell wrappers are acceptable as the first implementation, but the target is
  a controller/API object with state, admission, audit, and rollback
- `gpu-lease` should become a Beagle/Cockpit API and eventually a Kubernetes
  CRD or controller-owned state object
- node bootstrapping, health, and ownership must be discoverable by machines,
  not reconstructed from chat transcripts

### GPU Sharing Is Workload-Specific

GPU fractions, time slicing, MIG, and DRA are useful for inference, notebooks,
small agents, and low-risk interactive work. They are not the default for HPC
batch or compiler/runtime validation where isolation and reproducibility
matter.

Important lesson for this lab:

- Sounio compiler/runtime jobs should use exclusive GPU allocation
- lightweight model serving can be parked and restored
- partial GPU sharing should only be introduced as an explicit inference/dev
  class, not as a silent batch optimization

### Storage Is a Tiered Contract

SOTA systems separate:

- hot local scratch
- high-bandwidth shared data/checkpoint storage
- service PVCs
- object/catalog/provenance storage

Important lesson for this lab:

- `/tmp` or local worker scratch is the execution tier
- OrangeFS is durable shared artifact/data storage, not default scratch
- Ceph is the boring platform PVC tier
- Sounio workspace PVC is habitat state, not job scratch

## Darwin/Sounio Current State

As of the current `gpu-lease` snapshot:

- Slurm authority: `slurm-pilot` login pod
- GPU serving: parked for batch
  - `beagle/sglang-serving` scaled to `0`
  - `beagle/ssm-probe-serving` scaled to `0`
- Slurm GPU nodes observed:
  - `gpuorangefs-r770-proxmox`: NVIDIA L4, admitted, running Slurm job
    `1889:v14d-md2`
  - `gpuorangefs-r740-proxmox`: NVIDIA RTX A5000, admitted, idle
  - `gpuorangefs-5860-proxmox`: NVIDIA RTX 4000 Ada, admitted, idle
- Kubernetes health:
  - `4/4` nodes Ready
  - no active `Pending` pods
  - no `phase=Failed` pod tombstones after the 2026-05-25 cleanup
  - `t560-proxmox` DiskPressure cleared after pruning podman/container caches
    and removing the stale `~/.cache/podman-sglang-bnb` build cache
- Surfaces:
  - Grafana tailnet responds again and the in-cluster Grafana service has
    endpoint `10.0.0.196`
  - `hpc-route-doctor.sh`, `slurmdbd-backend-doctor.sh`, and
    `hpc-surface-doctor.sh` are healthy
  - `metrics.k8s.io` is restored with a versioned Metrics Server deployment at
    `/home/devsounio/beagle/k8s/metrics-server`
  - `ProxyGroup/sounio-workspace-ingress` is back on the declared HA contract
    with two ready proxy pods
  - SlurmDBD rollback snapshot guard-rail is fresh at
    `/var/backups/slurm-pilot-mariadb/snapshots/20260525-094354`
- Host-level GPU process detection:
  - `gpu-lease status` includes a `HOST_GPU` column when local SSH to GPU
    hosts is available
  - this catches standalone Docker/model processes that do not appear as
    Kubernetes GPU pods or Slurm jobs
  - the first leak found was `r740-proxmox` host Docker containers
    `nvidia-embeddings` and `nvidia-reranker`, stopped on 2026-05-25 after the
    A5000 was observed with `17709 MiB` allocated outside the scheduler
- Kueue:
  - `ClusterQueue/sounio-hpc`
  - nominal GPU quota: `3`
  - current scope: Kubernetes workloads, not Slurm jobs
- Remaining live Prometheus noise:
  - workspace CPU and memory alerts are real pressure from interactive agents
    and tests in `sounio-workspace-control-0`, not a cluster scheduling
    failure
  - new heavy validation belongs on Slurm with OrangeFS staging, not inside the
    workspace pod
- Current lease truth:
  - `/home/devsounio/beagle/k8s/hpc-sota/ops/gpu-lease status`
  - `/home/devsounio/projects/sounio/GPU_LEASES.json`
  - `GET /api/cluster/ops/gpu-leases`
  - `GET /api/projects/sounio/gpu-leases`

## Architecture Gap

The remaining weak point is not raw infrastructure. It is automating authority
all the way into Cockpit and Action Ledger.

Today, these mechanisms are separate:

- Kubernetes Deployments consume `nvidia.com/gpu`
- Slurm worker admission uses `sounio.dev/slurm-worker-gpuorangefs=true`
- Kueue quotas exist for Kubernetes workloads
- model registry records serving intent
- docs/bulletins record live truth

The initial scripted object now says:

```text
GPU r740-proxmox is leased to batch until <condition>, so serving must stay down.
GPU 5860-proxmox is leased to serving, so Slurm must not admit it.
GPU r770-proxmox is quarantined, so neither serving nor batch may use it.
```

Agents still get confused when they bypass this object and inspect only one
layer, for example Slurm queue only or Kubernetes pods only.

## Target Contract

Introduce a GPU lease contract with these states:

- `batch`
- `serving`
- `shared-inference`
- `maintenance`
- `quarantine`

For each GPU node, record:

- node name
- GPU model
- current owner
- intended owner
- Kubernetes serving deployment, if any
- Slurm node name, if any
- Kueue flavor, if any
- admission id
- last gate job
- current Slurm job id
- current Kubernetes GPU pod
- updated timestamp

The lease transition must be idempotent:

### Serving To Batch

1. Scale serving deployment to `0`.
2. Wait for GPU pods to terminate.
3. Admit Slurm worker with `68-manage-gpuorangefs-worker.sh <node> admit`.
4. Run the canonical gate.
5. Update bulletin/model registry/lease state.

### Batch To Serving

1. Confirm Slurm node is idle.
2. Quarantine Slurm worker with `68-manage-gpuorangefs-worker.sh <node> quarantine`.
3. Scale serving deployment to `1`.
4. Wait for readiness and model endpoint probe.
5. Update bulletin/model registry/lease state.

### Maintenance

1. Drain/stop serving or Slurm use.
2. Remove the node from both schedulable surfaces.
3. Run repair/gate.
4. Return to `batch`, `serving`, or `quarantine`.

## Near-Term Implementation Plan

### Phase 1: Scripted Lease Truth

Implemented an operator-safe wrapper:

```text
/home/devsounio/beagle/k8s/hpc-sota/ops/gpu-lease
```

Commands:

```bash
gpu-lease status
gpu-lease json
gpu-lease refresh
gpu-lease serving-to-batch <node>
gpu-lease batch-to-serving <node> <deployment>
gpu-lease quarantine <node>
gpu-lease admit-batch <node>
```

It writes a JSON state file under project control:

```text
/home/devsounio/projects/sounio/GPU_LEASES.json
```

The JSON schema is currently `darwin.gpu_lease.v1`. It records physical GPU
allocatable state, Kubernetes GPU pods, serving deployments, Slurm admission,
Slurm node state, active Slurm jobs, and the observed owner.

### Phase 2: Topology And Lease Authority

Promote the lease wrapper into a first-class control-plane object:

```text
GpuLease
GpuDomain
GpuTransition
```

Minimum fields:

```text
node
slurm_node
gpu_model
gpu_uuid
topology_domain
kueue_resource_flavor
owner
intended_owner
active_workload
last_gate_job
last_transition_id
last_transition_status
updated_at
```

For the three-node lab, the topology domains are single-card domains:

```text
domain/r740-a5000       node=r740-proxmox   gpu=NVIDIA RTX A5000
domain/r770-l4          node=r770-proxmox   gpu=NVIDIA L4
domain/5860-rtx4000ada  node=5860-proxmox   gpu=NVIDIA RTX 4000 Ada
```

The declarative source for those domains is:

```text
/home/devsounio/beagle/k8s/hpc-sota/GPU_RESOURCE_DOMAINS.yaml
```

This is intentionally small, but it matches the SOTA pattern: treat even small
GPU fleets as explicit topology/resource domains so the model scales when more
GPUs arrive.

### Phase 3: Cockpit/Beagle API Surface

Implemented the first Cockpit/Beagle API surface:

```text
GET  /api/cluster/ops/gpu-leases
GET  /api/projects/sounio/gpu-leases
POST /api/cluster/ops/gpu-leases/<node>/preview
POST /api/cluster/ops/gpu-leases/<node>/apply
```

Destructive or disruptive transitions must go through Action Ledger.

Validation evidence:

- `preview` returns a dry-run command and Action Ledger proposal.
- `apply` without a confirmed ledger returns HTTP `400`.
- idempotent `admit-batch r740-proxmox` completed through the live Cockpit
  Tailnet route, Action Ledger, and returned HTTP `200` with receipt plus GPU
  lease readback.
- the route scrubs npm/Node environment variables before invoking shell
  transitions, because the legacy worker manager uses `NODE` as a target-node
  override.
- the deployed image carries `/opt/hpc-sota/ops/gpu-lease` and
  `/opt/hpc-sota/GPU_RESOURCE_DOMAINS.yaml`, so the API does not depend on
  host-local `/home/devsounio` paths inside the container.

### Phase 4: Kueue Integration

Keep Kueue as Kubernetes workload authority, but make its GPU flavor status
visible beside Slurm lease status. Do not claim Kueue governs Slurm until a
real bridge exists.

Possible bridge options:

- Slurm jobs remain Slurm-native; Kueue only gates K8s workloads.
- A custom controller maps GPU lease state to Kueue flavors and Slurm
  admission labels.
- A future Slinky/Kueue integration is adopted only after it is proven in this
  lab.

### Phase 5: Slurm Topology Readiness

Our current fleet is one GPU per node, so Slurm `--gres=gpu:1` is enough for
today's compiler/runtime gates. Still, the right architectural move is to
prepare the Slurm lane for topology-aware scheduling:

- keep `gpu-orangefs` exclusive by default
- expose GPU model as Slurm features
- prepare a future `topology.yaml` once multi-GPU or multi-node locality starts
  mattering
- reject or warn on submissions that request GPU capacity without declaring
  workload class, expected duration, artifact root, and lease intent

## What This Means For Agents

Agents must stop asking "how many GPUs exist?" as the main question.

The correct questions are:

1. How many GPUs physically exist?
2. Which GPUs are admitted to Slurm?
3. Which GPUs are consumed by Kubernetes pods?
4. Which GPUs are leased for serving versus batch?
5. Which jobs are running right now?
6. Which transition is safe?

The cluster ops answer must always include all six.

## Source Anchors

- NVIDIA GB300 NVL72 Enterprise Reference Architecture:
  https://docs.nvidia.com/enterprise-reference-architectures/nvl72-ai-factory/latest/overview.html
- NVIDIA GB300 NVL72 dual-plane networking architecture PDF:
  https://docs.nvidia.com/enterprise-reference-architectures/nvl72-ai-factory-with-gb300-nvl72-dual-plane-networking-architecture.pdf
- NVIDIA/SchedMD Slurm block scheduling for GB200 NVL72:
  https://developer.nvidia.com/blog/achieving-peak-system-and-workload-efficiency-on-nvidia-gb200-nvl72-with-slurm-block-scheduling/
- NVIDIA rack-scale topology-aware scheduling:
  https://developer.nvidia.com/blog/running-ai-workloads-on-rack-scale-supercomputers-from-hardware-to-topology-aware-scheduling/
- Slurm topology guide:
  https://slurm.schedmd.com/topology.html
- Slurm topology.yaml:
  https://slurm.schedmd.com/topology.yaml.html
- Kubernetes DRA GA in v1.34:
  https://kubernetes.io/blog/2025/09/01/kubernetes-v1-34-dra-updates/
- Kubernetes Dynamic Resource Allocation:
  https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/
- Kueue concepts:
  https://kueue.sigs.k8s.io/docs/concepts/
- Kueue ResourceFlavor:
  https://kueue.sigs.k8s.io/docs/concepts/resource_flavor/
- Kueue ClusterQueue:
  https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/
- Kueue quota administration:
  https://kueue.sigs.k8s.io/docs/tasks/manage/administer_cluster_quotas/
- NVIDIA GPU Operator GPU sharing:
  https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/26.3/gpu-sharing.html
- OpenCHAMI:
  https://openchami.dev/
- HPE Cray EX QuickSpecs:
  https://www.hpe.com/us/en/collaterals/collateral.a00094635enw.html
- TOP500:
  https://top500.org/lists/top500/
