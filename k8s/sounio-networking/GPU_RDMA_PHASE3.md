# GPU RDMA Phase 3

This document is the next step after the live `10.200.0.0/24` pilot fabric.

Today we already have:
- Kubernetes underlay on `10.100.100.0/24`
- pilot secondary GPU fabric on `10.200.0.0/24`
- three GPU nodes with:
  - `nvidia.com/gpu`
  - `rdma/sounio_gpu_fabric`
- Multus + Whereabouts + RDMA shared device plugin live

What we do **not** have yet is a dedicated GPU-only QoS domain for serious
multi-node training. That is the purpose of phase 3.

Current update: the dedicated `10.210` host-to-host path and Arista SVI
`10.210.0.254/24` are now live and jumbo-clean from the GPU hosts. The
remaining proof is a GPU-consuming NCCL/IB smoke when Slurm releases the GPUs.

## Goal

Create a dedicated GPU RDMA fabric on:

- `10.210.0.0/24`

with:
- jumbo `9000`
- clean VLAN separation
- DNS and gateway ownership
- room for RoCE tuning without polluting the whole cluster

## Why phase 3 exists

The pilot on `10.200` is already good enough to validate:
- secondary pod attachment
- cross-node `net1`
- RDMA shared resource exposure
- early distributed-training orchestration

But long-term we do not want to mix:
- storage / migration
- backup / restore
- GPU all-reduce / NCCL / RoCE

in the same fault domain forever.

## Target shape

1. `10.100.100.0/24`
   - Kubernetes underlay
   - node `InternalIP`
   - Cilium native/direct routing

2. `10.200.0.0/24`
   - storage
   - migration
   - artifact movement
   - Ceph replication if desired

3. `10.210.0.0/24`
   - GPU RDMA fabric
   - NCCL
   - GPUDirect RDMA
   - multi-node training hot path

## Recommended network ownership

Prefer VLAN/SVI ownership on the Arista rather than ad hoc host routing.

Suggested gateway:
- `10.210.0.254` on `arista-7060:Vlan210`

Suggested DNS record:
- `gw-gpu-rdma.lab.sounio`

## Switch-side prerequisites

1. create a dedicated GPU VLAN
2. trunk it only where GPU hosts need it
3. keep MTU `9000`
4. if RoCE becomes real, apply QoS carefully and only here

Important:
- do **not** spread PFC/ECN blindly across all fabrics
- contain RoCE tuning to the GPU VLAN

## Host-side prerequisites

1. each GPU host gets the `10.210` fabric attached
2. normalize naming for the final fabric:
   - preferred raw name: `gpufabric0`
   - or bridge altname: `gpufabricbr0`
3. make sure the same CNI plugin paths exist on every node:
   - `/usr/lib/cni`
   - `/opt/cni/bin`

## Kubernetes prerequisites

1. keep the current pilot substrate healthy
2. add a second `NetworkAttachmentDefinition` for `10.210`
3. decide whether phase 3 stays:
   - bridge + `macvlan`
   - or moves to a more direct model later
4. add a second RDMA smoke and NCCL smoke over `10.210`

## Operational order

1. freeze the live pilot state on `10.200`
2. create VLAN/gateway/DNS for `10.210` - done for VLAN/SVI/gateway
3. attach the new fabric on GPU hosts
4. create `gpu-fabric-10-210` NAD
5. rerun RDMA smoke
6. rerun distributed training over the new `net1`
7. only then promote `10.210` from “lab path” to default GPU training path

The repository-side promotion entrypoint is:

```bash
/home/devsounio/beagle/k8s/sounio-gpu-fabric/promote-gpu-fabric-10-210.sh --apply
```

That intentionally handles only the Kubernetes-side promotion and smoke. The
Arista/VLAN/gateway work still needs to be real before you run it.

For the current Slurm-first operating model, use the guarded readiness watcher
instead of manually polling GPU leases:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/gpu-fabric-smoke-watch.sh \
  --watch --interval 60
```

That mode never creates smoke jobs. During an explicit operator test window,
the same watcher can run one IB smoke after the GPUs become idle:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/gpu-fabric-smoke-watch.sh \
  --run-on-ready --interval 60 --transport ib
```

## Exit criteria

Phase 3 is complete when:
- all GPU nodes can attach `net1` on `10.210`
- `rdma/sounio_gpu_fabric` remains healthy
- cross-node connectivity on `10.210` is stable
- NCCL / distributed smoke prefers `10.210` successfully
- `10.200` can go back to being mostly storage/migration
