# Rollback Notes for the Unsupported / Experimental Operator Path

This file exists for the day someone actually attempts the operator path on the
live cluster.

It assumes the current baseline remains:

- manual `nvidia-device-plugin-daemonset`
- manual Multus / Whereabouts / RDMA shared device plugin substrate
- live `gpu-fabric-10-200-pilot` attachment

## Principle

If an operator attempt causes any instability:

1. stop creating new CRs
2. remove the staged operator releases
3. restore the manual manifests already tracked in this repo
4. verify allocatable GPU / RDMA resources returned

## Fast rollback commands

### Uninstall staged Helm releases

```bash
helm uninstall gpu-operator -n gpu-operator || true
helm uninstall network-operator -n nvidia-network-operator || true
```

### Remove now-empty namespaces if desired

```bash
kubectl delete namespace gpu-operator --ignore-not-found --wait=false
kubectl delete namespace nvidia-network-operator --ignore-not-found --wait=false
```

### Re-apply the current manual GPU / RDMA baseline

```bash
kubectl apply -f /home/devsounio/beagle/k8s/sounio-runners/runtimeclass-nvidia.yaml
kubectl apply -f /home/devsounio/beagle/k8s/sounio-runners/nvidia-device-plugin-daemonset.yaml
kubectl apply -k /home/devsounio/beagle/k8s/sounio-gpu-fabric/substrate
```

### Re-assert the pilot NAD if needed

```bash
kubectl apply -f /home/devsounio/beagle/k8s/sounio-gpu-fabric/substrate/networkattachmentdefinition-gpu-fabric-10-200-pilot.yaml
```

## What to verify after rollback

```bash
kubectl -n kube-system get ds kube-multus-ds whereabouts rdma-shared-dp-ds nvidia-device-plugin-daemonset
kubectl get runtimeclass nvidia
kubectl -n beagle get network-attachment-definition gpu-fabric-10-200-pilot
kubectl get nodes -o json | jq -r '.items[] | [.metadata.name, (.status.allocatable["nvidia.com/gpu"] // "0"), (.status.allocatable["rdma/sounio_gpu_fabric"] // "0")] | @tsv'
```

Expected:

- GPU nodes return non-zero `nvidia.com/gpu`
- GPU nodes return non-zero `rdma/sounio_gpu_fabric`
- Multus / Whereabouts / RDMA shared plugin DaemonSets are healthy
- `RuntimeClass` `nvidia` exists

## Stop conditions that justify rollback

Rollback immediately if any of these happen:

- `nvidia.com/gpu` drops to `0` on live GPU nodes
- `rdma/sounio_gpu_fabric` disappears from live GPU nodes
- `gpu-fabric-10-200-pilot` attachment breaks
- `RuntimeClass` `nvidia` changes or disappears
- the operator starts trying to manage drivers, OFED, toolkit, or secondary
  networking before you explicitly asked it to

## Important note

This rollback path restores the **current manual baseline**.

It does **not** mean the operator path is wrong forever. It just keeps the
cluster usable while you stage the operator path more deliberately.
