# Sounio CPU/GPU Runners

This directory contains first-pass suspended `Job` templates for offloading
heavy work from the interactive workspace.

Before the GPU template can run for real, read:
- [gpu-preflight.md](gpu-preflight.md)

Before the CPU template can run for real, read:
- [cpu-preflight.md](cpu-preflight.md)

Design intent:
- keep the workspace responsive
- run CPU-heavy work on dedicated batch nodes
- run GPU-heavy work only on nodes that explicitly advertise GPUs
- avoid coupling batch execution to the workspace pod lifecycle
- keep live labels and docs aligned so scheduling stays predictable

Recommended node conventions:
- CPU batch nodes:
  - label: `sounio.dev/pool=cpu-batch`
  - taint: `sounio.dev/pool=cpu-batch:NoSchedule`
- GPU batch nodes:
  - label: `sounio.dev/pool=gpu-batch`
  - taint: `sounio.dev/pool=gpu-batch:NoSchedule`
  - label: `sounio.dev/accelerator=<gpu-sku>`
  - plus vendor GPU resources such as `nvidia.com/gpu`

Current known SKUs in this lab:
- `sounio.dev/accelerator=nvidia-l4` on `r770-proxmox`
- `sounio.dev/accelerator=nvidia-rtx-a5000` on `r740-proxmox`
- `sounio.dev/accelerator=nvidia-rtx-4000-ada` on `5860-proxmox` once the NVIDIA stack is installed

Current pool intent:
- `r770-proxmox` and `r740-proxmox` are the current heavy compute lane
- `r770-proxmox` and `r740-proxmox` are the dedicated `gpu-batch` nodes
- `5860-proxmox` stays out of the heavy compute path until the Ada Secure Boot path is finished

Important:
- these jobs are created with `spec.suspend: true` so they are safe to apply
  before the node pool and GPU plumbing are complete
- the GPU template assumes NVIDIA device plugin support, the host default
  NVIDIA runtime, and at least one node that advertises `nvidia.com/gpu`
- the placeholder template intentionally uses `nvidia/cuda:12.4.1-base-ubuntu22.04`
  so first-run pulls stay fast while the runner still proves `nvidia-smi`
- Kueue is optional for this first pass; if you later use it, the Job still
  needs the same GPU node labels/taints and GPU allocatable resources
- output persistence is intentionally out of scope for this first pass; use pod
  logs, object storage, or a dedicated results volume in the next iteration

Runtime note for this mixed fleet:
- prefer the host default NVIDIA runtime instead of forcing
  `runtimeClassName: nvidia` in workload pods
- that keeps GPU user-space injection consistent across the current
  `containerd 1.7` and `containerd 2.x` nodes

This directory now includes:
- `runtimeclass-nvidia.yaml`
- `nvidia-device-plugin-daemonset.yaml`

Those two resources are the smallest honest bridge from a host with a working
NVIDIA driver to real `nvidia.com/gpu` scheduling in Kubernetes.

To launch a runnable copy of one of the suspended templates:

```bash
/home/devsounio/beagle/k8s/sounio-runners/run-cpu-batch.sh
/home/devsounio/beagle/k8s/sounio-runners/run-cpu-fast.sh
/home/devsounio/beagle/k8s/sounio-runners/run-cpu-big.sh
/home/devsounio/beagle/k8s/sounio-runners/run-template-job.sh cpu
/home/devsounio/beagle/k8s/sounio-runners/run-template-job.sh cpu-standard
/home/devsounio/beagle/k8s/sounio-runners/run-template-job.sh gpu
/home/devsounio/beagle/k8s/sounio-runners/run-cpu-standard.sh
```

To launch a GPU job pinned to a specific SKU:

```bash
/home/devsounio/beagle/k8s/sounio-runners/run-gpu-l4.sh
/home/devsounio/beagle/k8s/sounio-runners/run-gpu-a5000.sh
/home/devsounio/beagle/k8s/sounio-runners/run-gpu-rtx4000ada.sh
/home/devsounio/beagle/k8s/sounio-runners/run-gpu-sku-job.sh nvidia-rtx-4000-ada
```

To validate CUDA user-space quickly on a specific GPU node with the same
privileged/unconfined pod shape used for low-level smoke checks:

```bash
/home/devsounio/beagle/k8s/sounio-runners/run-gpu-userspace-smoke.sh r740-proxmox nvidia-rtx-a5000
```

To label and taint a node for one of the pools:

```bash
/home/devsounio/beagle/k8s/sounio-runners/label-node-pools.sh compute <node-name>
/home/devsounio/beagle/k8s/sounio-runners/label-node-pools.sh cpu <node-name>
/home/devsounio/beagle/k8s/sounio-runners/label-node-pools.sh gpu <node-name>
/home/devsounio/beagle/k8s/sounio-runners/label-node-pools.sh clear <node-name>
```

For the `5860-proxmox` Secure Boot blocker, read:

- [5860-secure-boot-mok.md](5860-secure-boot-mok.md)
- [prepare-5860-mok-enrollment.sh](prepare-5860-mok-enrollment.sh)

To operate the `5860` remotely from another node without hardcoding secrets in
the repo, export credentials in your shell and use:

```bash
export PROXMOX_ROOT_PASSWORD='...'
export MOK_ENROLL_PASSWORD='...'
/home/devsounio/beagle/k8s/sounio-runners/check-5860-gpu-remote.sh
/home/devsounio/beagle/k8s/sounio-runners/queue-5860-mok-remote.sh
/home/devsounio/beagle/k8s/sounio-runners/reboot-5860-for-mok-remote.sh
```
