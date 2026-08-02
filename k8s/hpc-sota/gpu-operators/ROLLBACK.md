# Unsupported Operator Rollback

Use this if an unsupported GPU Operator / Network Operator trial destabilizes the current working substrate.

## Principle

The current cluster already has a working path:

- `nvidia-device-plugin`
- `rdma-shared-dp`
- `multus`
- `whereabouts`

Any unsupported operator trial must preserve a path back to that state.

## Before attempting the trial

1. Export the current manifests:

```bash
sudo kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset -o yaml > /tmp/nvidia-device-plugin-daemonset.backup.yaml
sudo kubectl get daemonset -n kube-system rdma-shared-dp-ds -o yaml > /tmp/rdma-shared-dp-ds.backup.yaml
sudo kubectl get daemonset -n kube-system kube-multus-ds -o yaml > /tmp/kube-multus-ds.backup.yaml
sudo kubectl get daemonset -n kube-system whereabouts -o yaml > /tmp/whereabouts.backup.yaml
```

2. Snapshot the node allocatable view:

```bash
sudo kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\t"}{.status.allocatable.rdma/sounio_gpu_fabric}{"\n"}{end}'
```

## If the operator trial goes bad

1. Remove operator-managed components first.
2. Re-apply the current known-good substrate from this repo:

```bash
sudo kubectl apply -k /home/devsounio/beagle/k8s/sounio-runners
sudo kubectl apply -k /home/devsounio/beagle/k8s/sounio-gpu-fabric/substrate
```

3. Confirm the cluster returned to:

- GPU allocatable on the 3 GPU nodes
- RDMA shared resource on the 3 GPU nodes
- `multus` and `whereabouts` healthy on all nodes

## Stop conditions

Abort the operator trial immediately if any of these happen:

- `nvidia.com/gpu` disappears from any working node
- `rdma/sounio_gpu_fabric` disappears from any working node
- `multus` or `whereabouts` stops scheduling on all nodes
- distributed training smoke stops working on the current substrate

