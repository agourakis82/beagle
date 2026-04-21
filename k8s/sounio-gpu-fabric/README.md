# Sounio GPU Fabric

This directory is the phase-2 layer for multi-node GPU training.

Phase 1 is already usable:
- Kubernetes underlay on `10.100.100.0/24`
- JobSet-based coordination
- three GPU nodes visible to Kubernetes

Phase 2 is where we stop using the generic pod fabric for the hot path and move
distributed GPU traffic to a dedicated secondary network.

## Current stance

Today the cluster has a healthy secondary 100Gb fabric:
- `10.200.0.0/24`
- jumbo `9000` validated end-to-end across:
  - `t560-proxmox`
  - `r770-proxmox`
  - `r740-proxmox`
  - `5860-proxmox`

That means we have two sensible options:

1. **Pilot on `10.200.0.0/24`**
   - fastest path
   - good for early RDMA/GPUDirect validation

2. **Carve a dedicated GPU VLAN later**
   - recommended target: `10.210.0.0/24`
   - best long-term answer once you want strict isolation from storage/migration

## Why separate the GPU fabric

RDMA/RoCE deserves different treatment than generic cluster traffic:
- different congestion behavior
- likely ECN/PFC tuning
- different blast radius
- more sensitive to MTU and fabric correctness

So the right pattern is:
- `10.100` -> Kubernetes underlay
- `10.200` -> storage / migration / replication
- `10.210` -> GPU RDMA fabric once you are ready to split it fully

## Live pilot status

The lightweight substrate path is now live in the cluster:
- Multus thick plugin
- Whereabouts IPAM
- RDMA shared device plugin
- `NetworkAttachmentDefinition` `beagle/gpu-fabric-10-200-pilot`

Validated live:
- `r770-proxmox` -> `net1` on `10.200.0.131`
- `r740-proxmox` -> `net1` on `10.200.0.130`
- `5860-proxmox` -> `net1` on `10.200.0.135`
- cross-node TCP on `net1` between `r770` and `5860`
- `/dev/infiniband/*` visible in the pilot pods on all three GPU nodes
- `rdma/sounio_gpu_fabric` allocatable on:
  - `r770-proxmox`
  - `r740-proxmox`
  - `5860-proxmox`

Current honest limitation:
- the substrate is live and `torch.cuda.is_available()` has already been recovered
  on the `5860` path via host NVIDIA user-space fallback
- the most likely remaining blocker for the distributed RDMA smoke is therefore
  no longer GPU discovery itself, but the exact job manifest you use
- keep the smoke manifests aligned with the working host-lib pattern:
  - mount `/lib/x86_64-linux-gnu/libcuda.so.1`
  - mount `/lib/x86_64-linux-gnu/libnvidia-ml.so.1`
  - set `LD_LIBRARY_PATH=/nvidia-host`
  - use `runtimeClassName: nvidia`

## Operator stack for phase 2

The official NVIDIA path is:
1. Network Operator
2. secondary network on the Mellanox interface
3. RDMA shared device plugin
4. GPU Operator RDMA options if needed

On this cluster, that operator-managed path is staged separately in:

- [/home/devsounio/beagle/k8s/hpc-sota/gpu-operators/README.md](/home/devsounio/beagle/k8s/hpc-sota/gpu-operators/README.md)

Treat that path as **unsupported / experimental in this lab** until it is
validated against the live manual substrate.

The relevant official references are:
- NVIDIA GPU Operator GPUDirect RDMA docs
- NVIDIA Network Operator docs

This directory includes:
- `preflight-rdma-hosts.sh`
- `preflight-rdma-secondary-fabric.sh`
- `preflight-gpu-fabric-10-210.sh`
- `substrate/`
- `networkattachmentdefinition-gpu-fabric-10-200.example.yaml`
- `networkattachmentdefinition-gpu-fabric-10-210.example.yaml`
- `macvlan-network-10-200.example.yaml`
- `rdma-perftest-pod-a.example.yaml`
- `rdma-perftest-pod-b.example.yaml`
- `nicclusterpolicy-rdma-shared.example.yaml`
- `jobset-rdma-gpu-smoke.example.yaml`
- `jobset-rdma-gpu-smoke.v2.yaml`
- `HOST_NORMALIZATION.md`

## Important reality check

The nodes do **not** share a single identical physical NIC name for the
secondary fabric today, but the pilot bridge has been normalized with a common
altname:

- bridge altname in use for the pilot: `gpufabricbr0`

Current bridge mapping:
- `r770-proxmox` -> `vmbr1` + altname `gpufabricbr0`
- `r740-proxmox` -> `vmbr200` + altname `gpufabricbr0`
- `5860-proxmox` -> `vmbr200` + altname `gpufabricbr0`

That gives us one stable `master:` for the pilot `macvlan` attachment without
forcing a risky live rename of the raw host NICs.

## Recommended operational order

1. keep phase-1 training on `10.100`
2. validate host preflights with `preflight-rdma-hosts.sh`
3. validate the fabric itself with `preflight-rdma-secondary-fabric.sh`
4. normalize the secondary bridge altname to `gpufabricbr0`
5. install the Network Operator
6. create the secondary network attachment on `10.200`
7. validate RDMA perftest between two GPU nodes
8. only then move NCCL and `torchrun` traffic to the secondary network

## Shortest live smoke path today

For the fastest current smoke over `net1` / `10.200`, use:

```bash
/home/devsounio/beagle/k8s/sounio-gpu-fabric/run-jobset-rdma-smoke.sh
```

That runner:
- checks the Kubernetes underlay
- verifies JobSet, Multus, Whereabouts, RDMA shared device plugin, and the
  `gpu-fabric-10-200-pilot` attachment
- recreates the `sounio-rdma-ddp-smoke` JobSet cleanly
- prints placements and child-job logs

The runner now defaults to the `v2` manifest, which moves the Python control
logic into a ConfigMap-mounted script. That keeps the RDMA smoke operationally
cleaner than the original giant inline heredoc.

By default it now uses the most reliable current transport:
- rendezvous on `eth0`
- NCCL sockets on `net1`
- `NCCL_IB_DISABLE=1`

That is intentional. It gives us a trustworthy secondary-fabric smoke now,
while keeping "true verbs / RoCE user-space in the container image" as the next
separate hardening step instead of pretending it is already finished.

Useful variants:

```bash
# socket-over-net1 on the pilot fabric (default)
/home/devsounio/beagle/k8s/sounio-gpu-fabric/run-jobset-rdma-smoke.sh

# same smoke on a different NAD name
/home/devsounio/beagle/k8s/sounio-gpu-fabric/run-jobset-rdma-smoke.sh \
  --network gpu-fabric-10-210 \
  --jobset-name sounio-rdma-ddp-smoke-10-210

# opt in to a future verbs attempt explicitly
/home/devsounio/beagle/k8s/sounio-gpu-fabric/run-jobset-rdma-smoke.sh \
  --transport ib
```

## Substrate status

The repository now includes a more practical intermediate substrate in
`substrate/`:

- Multus
- Whereabouts
- RDMA shared device plugin

That path is intentionally lighter than handing the full host lifecycle to the
Network Operator. It fits this lab because the NVIDIA and RDMA host stack is
already working on the GPU nodes, and the missing piece is the Kubernetes
multi-network plumbing.

## Honest recommendation

For this cluster, the most practical near-term shape is:

- `10.100.100.x` for Kubernetes underlay
- `10.200.0.x` as the live pilot RDMA / GPUDirect fabric
- `10.210.0.x` as the later dedicated VLAN when you want a clean GPU-only QoS domain

The current manifests are therefore split intentionally:
- `10.200` = what is live now
- `10.210` = what we can promote next once the VLAN/SVI exists

That keeps the current two 100Gb fabrics useful now, while still giving you a
clean landing zone for a more serious RoCE fabric later.

## Phase-3 readiness check

Before you promote the dedicated `10.210` GPU fabric, run:

```bash
/home/devsounio/beagle/k8s/sounio-gpu-fabric/preflight-gpu-fabric-10-210.sh
```

That script confirms the Kubernetes-side substrate is ready and that the
`gpu-fabric-10-210` attachment already passes server dry-run. It intentionally
stops short of pretending the Arista/VLAN/gateway work is done for you.

When the `10.210` VLAN/gateway/DNS work is really in place, the next operational
step is:

```bash
/home/devsounio/beagle/k8s/sounio-gpu-fabric/promote-gpu-fabric-10-210.sh --apply
```

That script:
- re-runs the `10.210` preflight
- applies the `gpu-fabric-10-210` NetworkAttachmentDefinition
- launches the `v2` RDMA smoke JobSet over the dedicated fabric

When the external network side is ready, use:

```bash
/home/devsounio/beagle/k8s/sounio-gpu-fabric/cutover-gpu-fabric-10-210.sh --apply
```

And to promote plus smoke-test end to end:

```bash
/home/devsounio/beagle/k8s/sounio-gpu-fabric/cutover-gpu-fabric-10-210.sh --apply --run-smoke
```

When you are ready to do the cutover work in order, use:

```bash
/home/devsounio/beagle/k8s/sounio-gpu-fabric/cutover-gpu-fabric-10-210.sh
```

And once the final VLAN/SVI/gateway is really in place, you can run the phase-3
smoke directly:

```bash
/home/devsounio/beagle/k8s/sounio-gpu-fabric/run-jobset-rdma-smoke-10-210.sh
```

## Final fabric naming

To avoid breaking the live pilot while phase 3 comes online:

- pilot `10.200` stays on `gpufabricbr0`
- final `10.210` uses `gpufabric210`

The helper for the host-side bridge is:

```bash
/home/devsounio/beagle/k8s/sounio-gpu-fabric/host-enable-gpu-fabric-10-210.sh <host>
```
