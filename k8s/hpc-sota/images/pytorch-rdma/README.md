Build and distribute the RDMA-capable PyTorch image used by the HPC smokes.

Example local build:

```bash
podman build -t sounio/pytorch-rdma:2.7.1-cuda12.8-rdma \
  /home/devsounio/beagle/k8s/hpc-sota/images/pytorch-rdma
```

For the current lab, we load the image directly into the GPU nodes' containerd
stores and run workloads with `imagePullPolicy: Never`.
