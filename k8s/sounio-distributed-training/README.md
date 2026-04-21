# Sounio Distributed Training

This directory is the phase-1 answer for multi-node training on the cluster.

It deliberately starts with the fabric that is already correct today:
- Kubernetes underlay on `10.100.100.0/24`
- Cilium in native/direct routing
- GPU fleet already registered in Kubernetes

The goal here is to make distributed jobs operational now, then layer RDMA on
top in phase 2 without redesigning the workflow.

As of the current cluster state, the preferred admission path is now:

- `JobSet` for distributed orchestration
- `Kueue` for queue selection and GPU admission
- `PriorityClass` for interactive vs training vs batch intent

## Why JobSet

JobSet is the right coordination layer here because it gives us:
- stable DNS and pod hostnames for each replica set
- coordinator/worker modeling
- dependency ordering via `dependsOn`
- a clean path to `torchrun`, MPI, and scheduler integration later

Official install:
- `kubectl apply --server-side -f https://github.com/kubernetes-sigs/jobset/releases/download/v0.11.1/manifests.yaml`

## What is in this directory

- `install-jobset.sh`
  - installs JobSet v0.11.1 and waits for the controller
- `preflight.sh`
  - checks the cluster underlay, JobSet controller, and available GPU nodes
- `jobset-rendezvous-smoke.yaml`
  - a lightweight rendezvous-only smoke in the same per-node JobSet pattern
- `jobset-gpu-ddp-smoke.yaml`
  - the preferred phase-1 DDP smoke: one `workers` replicatedJob, one pod per
    node, coordinator derived from JobSet metadata
- `jobset-gpu-ddp-smoke-kueue.yaml`
  - a Kueue-aware variant of the DDP smoke that targets
    `LocalQueue beagle/hpc-training` and sets explicit resource requests for
    queue accounting
- `run-jobset-smoke.sh`
  - applies the smoke test, waits for completion, and prints logs/placements
- `run-kueue-jobset-smoke.sh`
  - applies the Kueue-backed DDP smoke, prints LocalQueue/Workload state, then
    follows the child jobs to completion
- `render-torchrun-jobset.sh`
  - renders a real `torchrun`-style JobSet manifest for a homogeneous GPU SKU;
    set `KUEUE_LOCAL_QUEUE` and `PRIORITY_CLASS_NAME` to emit a
    LocalQueue-ready manifest cleanly
- `pytorch-gpu-image-prepull-daemonset.yaml`
  - warms the big PyTorch runtime image on all `gpu-batch` nodes so first-run
    DDP jobs do not spend their life in `ContainerCreating`

## Current cluster reality

The GPU fleet is heterogeneous today:
- `r770-proxmox` -> `nvidia-l4`
- `r740-proxmox` -> `nvidia-rtx-a5000`
- `5860-proxmox` -> `nvidia-rtx-4000-ada`

That means:
- **rendezvous/network smoke across all GPU nodes is good**
- **real multi-node training should usually target a single SKU**

In practice:
- use `jobset-gpu-ddp-smoke.yaml` to prove the fabric and JobSet behavior
- use `jobset-gpu-ddp-smoke-kueue.yaml` when you want the same smoke to flow
  through `Kueue` admission
- keep `jobset-rendezvous-smoke.yaml` as the ultra-light debugging smoke
- use `render-torchrun-jobset.sh` for same-SKU training once you have 2+ nodes
  or 2+ GPUs in the same accelerator pool

## Current validated state

As of 2026-04-04, the cluster has already passed these live checks:

- `jobset-gpu-ddp-smoke.yaml`
  - `backend=nccl`
  - `cuda=True`
  - `allreduce=3`
  - validated across `5860-proxmox` and `r740-proxmox`
- the RDMA pilot path in `../sounio-gpu-fabric`
  - secondary `net1` on `10.200.0.0/24`
  - pod annotations confirmed `net1` addresses on both workers
  - a live `allreduce=3` already completed there as well

That means the remaining work is no longer “can the cluster do multi-node
training at all?” The answer is already yes.

## Phase 1: no-RDMA distributed training

Phase 1 uses:
- pod networking over the `10.100.100.x` underlay
- stable JobSet DNS
- `torchrun` style rendezvous with `c10d`

This is the right first step because:
- it is operational now
- it gives you the same job lifecycle you will keep later
- it separates orchestration correctness from RDMA tuning

## Recommended shape

The best current pattern for this cluster is:

1. one `workers` `replicatedJob`
2. `replicas = number of nodes`
3. `parallelism = 1`, `completions = 1`
4. `coordinator` points at `workers[0][0]`
5. `NODE_RANK` comes from `jobset.sigs.k8s.io/job-index`

That shape is easier to reason about than a separate launcher plus indexed
completions, and it maps cleanly to `torchrun --nnodes=N --node-rank=...`.

## Phase 2: RDMA / GPUDirect

Once the dedicated GPU fabric is enabled, the same job shape stays useful.

The changes then are mostly:
- secondary network attachment
- RDMA resources in the pod spec
- NCCL and interface tuning
- optional GPUDirect RDMA validation

That next layer lives in:
- `../sounio-gpu-fabric`

## Quick start

Install JobSet if needed:

```bash
/home/devsounio/beagle/k8s/sounio-distributed-training/install-jobset.sh
```

Check readiness:

```bash
/home/devsounio/beagle/k8s/sounio-distributed-training/preflight.sh
```

Install Kueue if needed:

```bash
/home/devsounio/beagle/k8s/hpc-sota/kueue/install-kueue.sh
```

Run the DDP smoke:

```bash
/home/devsounio/beagle/k8s/sounio-distributed-training/run-jobset-smoke.sh
```

Run the Kueue-backed DDP smoke:

```bash
/home/devsounio/beagle/k8s/sounio-distributed-training/run-kueue-jobset-smoke.sh
```

That manifest carries:

- `metadata.labels.kueue.x-k8s.io/queue-name: hpc-training`
- `priorityClassName: hpc-training`

So if Kueue is installed, the resulting `Workload` should land in the
`beagle/hpc-training` LocalQueue automatically.

Keep the `JobSet.metadata.name` and `network.subdomain` reasonably short when
you copy this pattern. JobSet encodes the coordinator endpoint into a label,
and very long names can be rejected by the webhook for exceeding 63 bytes.

Render a first `torchrun` manifest:

```bash
/home/devsounio/beagle/k8s/sounio-distributed-training/render-torchrun-jobset.sh \
  my-train-job nvidia-l4 2 > /tmp/my-train-job.yaml
```

Render the same shape with Kueue admission metadata:

```bash
KUEUE_LOCAL_QUEUE=hpc-training \
PRIORITY_CLASS_NAME=hpc-training \
/home/devsounio/beagle/k8s/sounio-distributed-training/render-torchrun-jobset.sh \
  my-train-job nvidia-l4 2 > /tmp/my-train-job-kueue.yaml
```

Warm the PyTorch image on all GPU nodes:

```bash
kubectl apply -f /home/devsounio/beagle/k8s/sounio-distributed-training/pytorch-gpu-image-prepull-daemonset.yaml
```
