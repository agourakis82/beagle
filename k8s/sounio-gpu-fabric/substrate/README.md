# Sounio GPU Fabric Substrate

This is the Kubernetes substrate for the GPU secondary network and shared RDMA
resource exposure.

It installs:
- Multus thick plugin
- Whereabouts IPAM
- Mellanox RDMA shared device plugin

It intentionally does **not** manage host drivers or OFED. In this lab, the
host RDMA and NVIDIA stack is already active and the missing gap is the
Kubernetes multi-network layer.

## What this enables

1. `NetworkAttachmentDefinition` CRD
2. secondary networks through Multus
3. secondary IPAM on the `10.200` pilot fabric through Whereabouts
4. RDMA shared resources as `rdma/sounio_gpu_fabric`

## Important constraint

The pilot NAD expects a consistent master name on each GPU node:

- `gpufabricbr0`

Before applying the pilot NAD, add that altname on each node's secondary bridge:

- `r770-proxmox` -> `vmbr1`
- `r740-proxmox` -> `vmbr200`
- `5860-proxmox` -> `vmbr200`

Example:

```bash
ip link property add dev vmbr200 altname gpufabricbr0
ip link show gpufabricbr0

To make that persistent in this lab, use:

```bash
PROXMOX_ROOT_PASSWORD='...' \
  /home/devsounio/beagle/k8s/sounio-gpu-fabric/substrate/normalize-gpufabricbr0-altname.sh
```
```

## Apply

```bash
kubectl apply -k /home/devsounio/beagle/k8s/sounio-gpu-fabric/substrate
kubectl apply -f /home/devsounio/beagle/k8s/sounio-gpu-fabric/substrate/networkattachmentdefinition-gpu-fabric-10-200-pilot.yaml
```

## Verify

```bash
kubectl get crd network-attachment-definitions.k8s.cni.cncf.io
kubectl -n kube-system get ds kube-multus-ds whereabouts rdma-shared-dp-ds
kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.allocatable.rdma\\.sounio_gpu_fabric}{"\n"}{end}'
```
