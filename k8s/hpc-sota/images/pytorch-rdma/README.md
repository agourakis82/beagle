Build and distribute the RDMA-capable PyTorch image used by the HPC smokes.

Canonical lab build:

```bash
podman build \
  -t 192.168.3.207:5003/sounio/pytorch-rdma:2.7.1-cuda12.8-rdma \
  -t sounio/pytorch-rdma:2.7.1-cuda12.8-rdma \
  /home/devsounio/beagle/k8s/hpc-sota/images/pytorch-rdma

podman push --tls-verify=false \
  192.168.3.207:5003/sounio/pytorch-rdma:2.7.1-cuda12.8-rdma
```

The current lab registry is writable from the management plane at
`192.168.3.207:5003`. GPU workloads should prefer that registry with
`imagePullPolicy: IfNotPresent` so a scheduled job does not depend on an
implicit per-node image cache. Older manifests that still use
`sounio/pytorch-rdma:2.7.1-cuda12.8-rdma` plus `imagePullPolicy: Never` must be
retagged, preloaded into every target node's containerd store, or migrated to
the registry form above before use.
