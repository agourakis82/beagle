# Multus + Whereabouts

This package installs the minimum network-plumbing substrate we need for:

- secondary pod interfaces via `NetworkAttachmentDefinition`
- cluster-wide IPAM for those secondary interfaces via Whereabouts
- a clean path toward the GPU fabric pilot on `10.200.0.0/24`

Why this package exists:

- the cluster already has a healthy primary CNI (`cilium`)
- we do **not** need NVIDIA Network Operator just to get secondary networks online
- our nodes already expose Mellanox RDMA-capable HCAs on the hosts
- we want a smaller, easier-to-debug foundation before layering RDMA-specific components

What this installs:

- `NetworkAttachmentDefinition` CRD
- `kube-multus-ds` in `kube-system`
- Whereabouts CRDs
- `whereabouts` daemonset in `kube-system`

Pinned upstream images:

- Multus: `ghcr.io/k8snetworkplumbingwg/multus-cni:v4.2.4-thick`
- Whereabouts: `ghcr.io/k8snetworkplumbingwg/whereabouts:v0.9.3`

Cluster-specific note:

- this cluster uses `containerd` with `bin_dir = /usr/lib/cni`
- so Multus and Whereabouts must install their binaries into `/usr/lib/cni`
- the stock quickstart examples often assume `/opt/cni/bin`, which is wrong here

Apply:

```bash
kubectl apply -k /home/devsounio/beagle/k8s/multus-whereabouts
```

Verify:

```bash
kubectl get crd network-attachment-definitions.k8s.cni.cncf.io
kubectl get crd ippools.whereabouts.cni.cncf.io
kubectl -n kube-system get ds kube-multus-ds whereabouts
```

Next step after this package:

- create a pilot `NetworkAttachmentDefinition` for the `10.200.0.0/24` fabric
- once host interface naming is normalized, graduate the GPU fabric to its own `10.210.0.0/24` VLAN
