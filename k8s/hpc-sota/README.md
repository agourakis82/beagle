# SOTA HPC Upgrade Pack

This package turns the current lab into the next-tier HPC/AI platform:

- `JobSet + Kueue` for GPU-aware admission and fairness
- storage classes by workload role (`workspace`, `dataset`, `checkpoint`, `scratch`)
- `GPU Operator + Network Operator` path for GPUDirect RDMA / DMA-BUF
- runbooks to promote the lab from "strong AI cluster" to "serious HPC fabric"
- a hands-on dev playbook for humans and agents:
  - [DEV_WORKFLOW.md](/home/devsounio/beagle/k8s/hpc-sota/DEV_WORKFLOW.md)
  - [AGENTS.md](/home/devsounio/beagle/k8s/hpc-sota/AGENTS.md)
  - [CLAUDE.md](/home/devsounio/beagle/k8s/hpc-sota/CLAUDE.md)
  - [STACK_SEMAPHORE.md](/home/devsounio/beagle/k8s/hpc-sota/STACK_SEMAPHORE.md)
  - [PROJECT_ONBOARDING_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/PROJECT_ONBOARDING_BLUEPRINT.md)
  - [TAILNET_DIRECT_CLUSTER_ACCESS.md](/home/devsounio/beagle/k8s/hpc-sota/TAILNET_DIRECT_CLUSTER_ACCESS.md)

## Session front door

Before touching the stack, read these in order:

1. [AGENT_BOOTSTRAP.md](/home/devsounio/beagle/k8s/hpc-sota/AGENT_BOOTSTRAP.md)
2. [STACK_SEMAPHORE.md](/home/devsounio/beagle/k8s/hpc-sota/STACK_SEMAPHORE.md)
3. [DEV_WORKFLOW.md](/home/devsounio/beagle/k8s/hpc-sota/DEV_WORKFLOW.md)
4. [PROJECT_ONBOARDING_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/PROJECT_ONBOARDING_BLUEPRINT.md)
5. [TAILNET_DIRECT_CLUSTER_ACCESS.md](/home/devsounio/beagle/k8s/hpc-sota/TAILNET_DIRECT_CLUSTER_ACCESS.md)

The semaphore is the shortest honest answer to:

- what is green
- what is yellow
- what is red
- what an agent should re-check before edits

## Design goals

- Keep interactive workspaces isolated from heavy training jobs
- Admit GPU work intentionally instead of first-come/first-served chaos
- Separate storage semantics for:
  - long-lived datasets
  - resumable checkpoints
  - disposable scratch
  - durable workspaces
- Move toward the official NVIDIA path for GPUDirect RDMA

## Directory layout

- `kueue/`
  - cluster queues, local queues, resource flavors, and priority classes
- `storage/`
  - Ceph RBD storage classes specialized by durability and reclaim behavior
- `gpu-operators/`
  - conservative example values/manifests for GPU Operator and Network Operator
- `SUPERCOMPUTING_LAB_ARCHITECTURE_2026.md`
  - target hybrid blueprint for `K8s + Slurm + OrangeFS + Ceph + NVMe`
- `slurm-pilot/`
  - no-BS pilot for `cert-manager + slurm-operator + Slurm cluster` on top of
    the current lab, with OrangeFS mounted into Slurm login/compute pods,
    `slurmdbd` accounting live, accounts/QoS for the domain tracks, and
    PBPK/omics/PL-runtime batch workloads already proven
- `ops/`
  - operator-facing shell helpers for remote control-plane access through `t560`
  - includes [ops/hpc-bootstrap.sh](/home/devsounio/beagle/k8s/hpc-sota/ops/hpc-bootstrap.sh) for a read-only agent bootstrap snapshot
- `workloads/`
  - domain tracks for `pbpk`, `omics`, and `pl-runtime`
- `PROJECT_ONBOARDING_BLUEPRINT.md`
  - canonical phase/checklist for bringing a new Darwin/Sounio project into the
    cluster with lane choice, workspace choice, canary, rollback, and handoff

## Rollout order

1. Apply `storage/` classes
2. Install Kueue CRDs/controller, then apply `kueue/`
3. Move distributed training jobs from raw `JobSet` to `suspend + Kueue admission`
4. Promote GPU networking from the current pilot to the official operator path
5. Validate GPUDirect RDMA on `10.210`

## Current cluster fit

This pack assumes the lab state already achieved:

- K8s underlay on `10.100.100.0/24`
- GPU fabric on `10.210.0.0/24`
- service/egress fabric on `10.30.0.0/24`
- GPU nodes:
  - `r770-proxmox` -> `nvidia-l4`
  - `r740-proxmox` -> `nvidia-rtx-a5000`
  - `5860-proxmox` -> `nvidia-rtx-4000-ada`

## Why this is the next right step

What we have now is strong. What this adds is operational discipline:

- GPU queues and flavors instead of ad hoc placement
- storage contracts by workload role
- official GPU/RDMA operator path instead of one-off substrate tuning
