# Sounio Platform Rollout 1-2-3-4-5-6

This is the practical order for the lab and cluster to evolve without turning
into an accidental zoo.

## 1. Network control plane

Source of truth and operator ergonomics come first.

Assets:
- `sounio-networking/lab-network-inventory.yaml`
- `sounio-networking/CONTROL_PLANE.md`
- `sounio-networking/arista-7060x-fabric.example.cfg`
- `sounio-networking/lab-dns/`

Success criteria:
- `10.100.100.x` remains the Kubernetes underlay
- `10.200.0.x` remains jumbo-clean for storage/migration
- `10.210.0.x` is reserved for the future dedicated GPU fabric
- `lab.sounio` answers for the physical hosts and gateways

## 2. Kubernetes underlay and storage lanes

Keep the fabrics boring and explicit.

Current state:
- `10.100.100.x`: live underlay
- `10.200.0.x`: live storage/migration lane
- Cilium: native/direct routing

Success criteria:
- node `InternalIP` stays on `10.100.100.x`
- Cilium stays native
- storage/migration tooling consciously uses `10.200.0.x`

## 3. GPU fabric preparation

Prepare the cluster for RoCE/GPUDirect without forcing it prematurely.

Assets:
- `sounio-gpu-fabric/HOST_NORMALIZATION.md`
- `sounio-gpu-fabric/networkattachmentdefinition-gpu-fabric-10-200.example.yaml`
- `sounio-gpu-fabric/nicclusterpolicy-rdma-shared.example.yaml`
- `sounio-gpu-fabric/jobset-rdma-gpu-smoke.example.yaml`

Success criteria:
- secondary GPU-facing NICs converge to `gpufabric0`
- Multus/Whereabouts and the RDMA shared device plugin can target one common master
- phase-2 jobs can request both GPU and RDMA resources

## 4. Distributed training on the existing fabric

Do not wait for RDMA to prove orchestration correctness.

Assets:
- `sounio-distributed-training/jobset-gpu-ddp-smoke.yaml`
- `sounio-distributed-training/jobset-rendezvous-smoke.yaml`
- `sounio-distributed-training/render-torchrun-jobset.sh`
- `sounio-distributed-training/pytorch-gpu-image-prepull-daemonset.yaml`

Success criteria:
- one worker pod per node
- coordinator derived from JobSet metadata
- same-SKU jobs render cleanly for `torchrun`
- GPU nodes are pre-warmed with the large PyTorch image

## 5. RDMA / GPUDirect phase

Only after 1-4 are healthy.

Assets:
- `sounio-gpu-fabric/preflight-rdma-hosts.sh`
- `sounio-gpu-fabric/preflight-rdma-secondary-fabric.sh`
- `sounio-gpu-fabric/rdma-perftest-pod-a.example.yaml`
- `sounio-gpu-fabric/rdma-perftest-pod-b.example.yaml`
- `sounio-gpu-fabric/jobset-rdma-gpu-smoke.example.yaml`

Success criteria:
- Network Operator and Multus installed
- `NetworkAttachmentDefinition`/`MacvlanNetwork` live
- RDMA shared device resource visible to pods
- perftest passes between two GPU nodes
- NCCL traffic can move from `eth0` to `net1`

## 6. Multi-project workspace platform

Only after the substrate is trustworthy.

Target model:
- one habitat/workspace per active project
- PVC-backed state per project
- shared CPU/GPU runner pools
- node-agnostic project workspaces
- stable entry via Tailscale and later the full operator/ingress path

Do **not** start with 21 always-on bespoke pods.

Start with:
- one workspace template
- one generator/scaffolder per repo
- project classes:
  - always-on
  - warm/on-demand
  - cold/archive

## Operator rule

If the cluster is ever in doubt:
1. trust the network inventory
2. trust the preflights
3. keep training on the current boring fabric before forcing RDMA
