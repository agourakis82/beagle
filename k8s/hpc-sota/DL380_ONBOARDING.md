# HP DL380 G10 Onboarding Runbook

This runbook is the safe admission path for the incoming HP DL380 G10.

The current design already treats this host as a future AI/HPC node, but it is
not yet part of the live inventory, Kubernetes cluster, GPU domain map, OrangeFS
client set, or Slurm worker pool.

## Current intended role

Source of truth:

- [orangefs-hybrid/ROLE_MAP.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/ROLE_MAP.md)
- [orangefs-hybrid/MIGRATION_PLAN.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/MIGRATION_PLAN.md)
- [orangefs-hybrid/MULTITERABYTE_CAPACITY_PLAN.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/MULTITERABYTE_CAPACITY_PLAN.md)

Day-one role:

- Kubernetes worker
- GPU compute node if a supported NVIDIA GPU is present
- local NVMe hot tier
- OrangeFS client

Preferred later role:

- real OrangeFS growth server if the NVMe or local disk inventory is suitable
- possible metadata/data split participant after the first capacity expansion

Non-goals on day one:

- do not move live workspaces onto the DL380
- do not make it an OrangeFS server before client and storage canaries pass
- do not admit it to Slurm before the Kubernetes, Cilium, OrangeFS, and GPU
  runtime checks are green

## Phase 0: hardware and firmware inventory

Record these before installing or joining anything:

- hostname target
- iLO address and access path
- serial number
- CPU model and socket count
- RAM size and DIMM layout
- GPU model, count, PCIe slot, power cabling
- NIC models, link speeds, MAC addresses, and transceiver/cable mapping
- NVMe and local disk inventory
- RAID/HBA mode
- boot mode
- Secure Boot state
- BIOS virtualization settings
- firmware baseline

Recommended hostname until contradicted by inventory:

```text
dl380-proxmox
```

Do not allocate final addresses from memory. Allocate them in NetBox first.

Current planned NetBox/IPAM reservation:

```text
hostname      dl380-proxmox
mgmt0         192.168.3.170/24
underlay0     10.100.100.5/24
storage0      10.200.0.5/24
gpufabric0    10.210.0.5/24
service0      10.30.0.5/24
switch ports  arista-7060 Ethernet34, Ethernet35
```

Treat these as planned reservations until hardware inventory confirms NIC
layout, MAC addresses, cabling, and the actual management/iLO address.

## Phase 1: NetBox and fabric admission

NetBox lives under:

- [sounio-networking/service-fabric-10g/netbox](/home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g/netbox)

Current seeded devices are:

- `t560-proxmox`
- `r770-proxmox`
- `r740-proxmox`
- `5860-proxmox`
- `arista-7060`

The DL380 must be added to:

- `netbox/seed-lab-devices-orm.py`
- NetBox device list
- NetBox interfaces
- NetBox IP addresses
- physical cable map to `arista-7060`

Current fabric prefixes:

- management LAN: `192.168.3.0/24`
- Kubernetes underlay: `10.100.100.0/24`
- storage fabric: `10.200.0.0/24`
- GPU fabric: `10.210.0.0/24`
- service fabric: `10.30.0.0/24`

Expected DL380 logical interfaces:

```text
management0   Proxmox/iLO side, usually 192.168.3.0/24
underlay0     Kubernetes underlay, 10.100.100.0/24
storage0      OrangeFS/storage, 10.200.0.0/24
gpufabric0    GPU/RDMA fabric, 10.210.0.0/24 if NICs support it
service0      optional service/egress fabric, 10.30.0.0/24 if physically wired
```

Validation:

```bash
cd /home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g
./verify-netbox.py
```

## Phase 2: OS and node baseline

Match the current node shape unless there is a deliberate migration plan:

- Proxmox/Debian host baseline compatible with the existing workers
- containerd configured with cluster registry mirrors
- stable host resolution for `k8s-api.darwin.lan -> 10.100.100.2`
- Tailscale route behavior must not reintroduce the `192.168.3.0/24` overlap
  failure documented in [AGENT_BOOTSTRAP.md](/home/devsounio/beagle/k8s/hpc-sota/AGENT_BOOTSTRAP.md)
- NVIDIA driver/runtime only after Secure Boot and kernel compatibility are
  understood

Registry mirror assets:

- [sounio-networking/service-fabric-10g/apply-containerd-registry-mirrors.sh](/home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g/apply-containerd-registry-mirrors.sh)
- [sounio-networking/service-fabric-10g/verify-registry-mirrors.sh](/home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g/verify-registry-mirrors.sh)

## Phase 3: Kubernetes worker admission

Join the node as a worker first. Do not label it into heavy lanes until the
basic node is Ready and stable.

Read-only checks:

```bash
kubectl get nodes -o wide
kubectl describe node dl380-proxmox
kubectl -n kube-system get pods --field-selector spec.nodeName=dl380-proxmox
```

Initial labels after the node is Ready:

```bash
kubectl label node dl380-proxmox sounio.dev/orangefs-client=true --overwrite
kubectl label node dl380-proxmox sounio.dev/runtime-role=cluster-expansion --overwrite
```

If the node is intended for batch GPU work:

```bash
kubectl label node dl380-proxmox sounio.dev/pool=gpu-batch --overwrite
kubectl taint node dl380-proxmox sounio.dev/pool=gpu-batch:NoSchedule
kubectl label node dl380-proxmox sounio.dev/compute=heavy --overwrite
kubectl taint node dl380-proxmox sounio.dev/compute=heavy:NoSchedule
```

Do not set `sounio.dev/slurm-worker-gpuorangefs=true` manually. Slurm admission
must go through the `68-manage-gpuorangefs-worker.sh` gate.

## Phase 4: GPU runtime admission

Only run this phase if the DL380 has a supported NVIDIA GPU.

Required checks:

```bash
kubectl get runtimeclass nvidia
kubectl get pods -A | rg -i 'nvidia|device-plugin'
kubectl get node dl380-proxmox -o jsonpath='{.status.allocatable.nvidia\.com/gpu}{"\n"}'
```

Expected result:

- allocatable `nvidia.com/gpu` is non-zero
- `nvidia-smi` works on the host
- `nvidia-smi` works inside a Kubernetes pod using `runtimeClassName: nvidia`

Reference:

- [sounio-runners/gpu-preflight.md](/home/devsounio/beagle/k8s/sounio-runners/gpu-preflight.md)

After GPU runtime is proven, add a new domain to:

- [GPU_RESOURCE_DOMAINS.yaml](/home/devsounio/beagle/k8s/hpc-sota/GPU_RESOURCE_DOMAINS.yaml)

Use a pending/factual model name until `nvidia-smi -L` confirms the GPU SKU.

## Phase 5: OrangeFS client admission

The DL380 should be an OrangeFS client before it is a Slurm worker.

Required proof points:

- client mount exists
- `/orangefs/datasets` is visible
- `/orangefs/checkpoints` is visible
- `/orangefs/scratch` is visible
- read/write canary succeeds
- local NVMe scratch path exists and is not confused with durable OrangeFS

Use current OrangeFS docs:

- [orangefs-hybrid/FIRST_ROLLOUT_PLAN.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/FIRST_ROLLOUT_PLAN.md)
- [orangefs-hybrid/K8S_CONSUMPTION_PLAN.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_CONSUMPTION_PLAN.md)
- [orangefs-hybrid/BENCHMARK_RITUAL.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/BENCHMARK_RITUAL.md)

## Phase 6: Slurm gpuorangefs admission

Only start this phase after:

- Kubernetes node is Ready
- Cilium on the node is Ready
- OrangeFS client proof passed
- GPU runtime proof passed if this is a GPU worker
- the node is represented in `GPU_RESOURCE_DOMAINS.yaml` if it has a GPU

Canonical admission command:

```bash
/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh \
  dl380-proxmox admit
```

The gate performs:

- temporary `sounio.dev/slurm-worker-gpuorangefs=true` label
- worker pod readiness wait
- Cilium health check
- ordinary pod network check to Kubernetes, Slurm controller, accounting, and
  login
- Slurm node registration check
- Slurm CUDA smoke job on the target node
- automatic quarantine if the gate fails

Status and rollback:

```bash
/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh \
  dl380-proxmox status

/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh \
  dl380-proxmox quarantine
```

## Phase 7: live authority updates

After successful admission:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota
./ops/gpu-lease refresh
./ops/gpu-lease status
```

Then update:

- [GPU_RESOURCE_DOMAINS.yaml](/home/devsounio/beagle/k8s/hpc-sota/GPU_RESOURCE_DOMAINS.yaml)
- [projects/sounio/GPU_LEASES.json](/home/devsounio/projects/sounio/GPU_LEASES.json) via `ops/gpu-lease refresh`
- [projects/sounio/AGENT_LIVE_BULLETIN.md](/home/devsounio/projects/sounio/AGENT_LIVE_BULLETIN.md)
- NetBox seed and verification evidence

## Admission hold points

Stop and do not proceed if any of these are true:

- hardware inventory is incomplete
- final IPs were not allocated in NetBox
- node cannot reach `k8s-api.darwin.lan`
- Cilium is not healthy on the node
- OrangeFS client mount is missing or flaky
- GPU is present but `nvidia.com/gpu` is not allocatable
- `68-manage-gpuorangefs-worker.sh dl380-proxmox admit` fails
- any existing GPU serving deployment was scaled or evicted without an explicit
  GPU lease transition

## First useful jobs after admission

Run smallest proofs before real workloads:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota
./ops/gpu-lease status
/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh \
  dl380-proxmox status
```

Then repeat the explicit target-node gate smoke:

```bash
TARGET_NODE=dl380-proxmox \
  bash /home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/66-gpuorangefs-gate.sh
```

Only after that passes should the node receive real Sounio/Beagle research
jobs or broader pool-level submit scripts.
