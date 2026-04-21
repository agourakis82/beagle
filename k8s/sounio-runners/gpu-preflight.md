# GPU Preflight

This file documents the assumptions that must hold before
`gpu-batch-job.yaml` can run as a real GPU workload.

## Required Preconditions

- A Kubernetes node exists that is intended for GPU batch work.
- That node is labeled `sounio.dev/accelerator=<gpu-sku>`.
- The node advertises a non-zero `nvidia.com/gpu` allocatable resource.
- The NVIDIA device plugin or equivalent GPU device advertising path is
  installed cluster-wide.
- An `nvidia` `RuntimeClass` exists if the NVIDIA runtime is not made the
  containerd default.
- The GPU node can pull `nvidia/cuda:12.4.1-base-ubuntu22.04`, or an equivalent
  mirrored image is already available.
- `gpu-batch-job.yaml` is unsuspended or cloned into a runnable Job before
  actual execution.

## What This Template Does Not Install

- It does not install or configure the NVIDIA device plugin.
- It does not label or taint nodes.
- It does not install Kueue.
- It does not create a GPU node pool.

## Example Node Bootstrap Commands

Use these commands on a GPU-capable node that you want to dedicate to Sounio:

```bash
kubectl label node <gpu-node-name> sounio.dev/pool=gpu-batch
kubectl taint node <gpu-node-name> sounio.dev/pool=gpu-batch:NoSchedule
kubectl label node <gpu-node-name> sounio.dev/accelerator=<gpu-sku>
kubectl get node <gpu-node-name> -o jsonpath='{.status.allocatable.nvidia\.com/gpu}{"\n"}'
```

If the last command prints nothing or `0`, the GPU job template is not ready.

## Validation Checklist

- `kubectl get nodes -L sounio.dev/accelerator`
- `kubectl get nodes -L sounio.dev/pool -L sounio.dev/accelerator`
- `kubectl describe node <gpu-node-name>` shows `nvidia.com/gpu` in
  allocatable resources.
- `kubectl get runtimeclass nvidia`
- `kubectl get pods -A | rg -i 'nvidia|device-plugin'` shows the GPU device
  plugin is running if that is how the cluster advertises GPUs.
- `kubectl run --rm -it gpu-smoke --image=nvidia/cuda:12.4.1-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","nodeSelector":{"sounio.dev/accelerator":"<gpu-sku>"},"tolerations":[{"key":"sounio.dev/pool","operator":"Equal","value":"gpu-batch","effect":"NoSchedule"}],"containers":[{"name":"gpu-smoke","image":"nvidia/cuda:12.4.1-base-ubuntu22.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}' -- nvidia-smi`
  starts on the intended GPU node and prints GPU information once the template
  is unsuspended.
- `nvidia-smi` succeeds inside the GPU Job container.

## Kueue Assumptions

Kueue is optional for this directory.

If you later decide to queue GPU work with Kueue, the cluster must already have:

- the Kueue controller and CRDs installed
- a `ClusterQueue`
- a `LocalQueue` in the workload namespace
- a GPU-capable `ResourceFlavor`

This directory does not install those pieces; it only records the assumptions so
the GPU Job template stays honest about what it needs.
