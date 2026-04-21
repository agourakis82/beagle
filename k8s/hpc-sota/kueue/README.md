# Kueue Admission Layer

This is the admission/governance layer for serious GPU usage.

## What this gives us

- named GPU flavors by SKU
- explicit quota per GPU class
- local queues per namespace/project
- priority classes for interactive, training, and batch work

## Apply order

1. Install Kueue controller:

```bash
/home/devsounio/beagle/k8s/hpc-sota/kueue/install-kueue.sh
```

This install path also reapplies the source-of-truth scheduling patch in:

- [/home/devsounio/beagle/k8s/hpc-sota/kueue/controller-manager-scheduling-patch.yaml](/home/devsounio/beagle/k8s/hpc-sota/kueue/controller-manager-scheduling-patch.yaml)

The intent is to keep the Kueue controller on healthy `heavy` nodes instead of
implicitly drifting back to `t560-proxmox`.

2. Apply priority classes:

```bash
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/priorityclasses.yaml
```

3. Apply the example Kueue objects after confirming CRDs are available:

```bash
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/resourceflavors.example.yaml
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/clusterqueue.example.yaml
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/localqueues.example.yaml
```

## Notes

- The example quotas match the current 3-GPU lab.
- This should evolve alongside the next GPUs you add.
- Pair this with `JobSet` for distributed training.
- The current heterogeneous training lane uses:
  - `cpu-any`
  - `gpu-any`
- Those flavors deliberately target the whole `gpu-batch` fleet so mixed-SKU
  multi-node smokes can be admitted.
- The first concrete JobSet example in this repo is:
  - `/home/devsounio/beagle/k8s/sounio-distributed-training/jobset-gpu-ddp-smoke-kueue.yaml`
- The matching helper script is:
  - `/home/devsounio/beagle/k8s/sounio-distributed-training/run-kueue-jobset-smoke.sh`
