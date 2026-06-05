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
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/workloadpriorityclasses.yaml
```

3. Label the GPU fabric topology domain and apply the topology object:

```bash
kubectl label node r770-proxmox r740-proxmox 5860-proxmox \
  sounio.dev/gpu-fabric-domain=10-210 --overwrite

kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/topology.example.yaml
```

4. Apply the example Kueue objects after confirming CRDs are available:

```bash
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/resourceflavors.example.yaml
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/clusterqueue.example.yaml
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/localqueues.example.yaml
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/admissionchecks.example.yaml
```

5. Only after the operator-side reconciler is running, attach the admission
   check to GPU flavors:

```bash
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/kueue/clusterqueue.with-admissioncheck.example.yaml
```

The reconciler/runbook is:

- [/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/FABRIC_STORAGE_ADMISSION.md](/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/FABRIC_STORAGE_ADMISSION.md)

## Notes

- The example quotas match the current 3-GPU lab.
- This should evolve alongside the next GPUs you add.
- Pair this with `JobSet` for distributed training.
- Kueue is the authority for Kubernetes workloads only. It does not admit,
  cancel, reserve, or preempt Slurm jobs in the current lab.
- Kueue `Topology/gpu-fabric-10-210` records current GPU fabric locality, but
  it is not a substitute for the `gpu-lease` Slurm/Kubernetes ownership guard.
- `AdmissionCheck/fabric-storage-readiness` is a seed object for the next
  controller. It is intentionally not referenced from `ClusterQueue/sounio-hpc`
  yet; adding it to `spec.admissionChecksStrategy` before the reconciler is
  scheduled would hold GPU workloads indefinitely.
- The staged attachment manifest scopes the check to GPU flavors only. CPU-only
  Kueue work must not wait on GPU fabric or OrangeFS lease gates.
- The common GPU truth surface is:
  - `/home/devsounio/beagle/k8s/hpc-sota/ops/gpu-lease status`
  - `/home/devsounio/projects/sounio/GPU_LEASES.json`
- Keep Kueue ResourceFlavors aligned with the physical lease domains:
  - `gpu-l4` -> `r770-proxmox`
  - `gpu-rtx-a5000` -> `r740-proxmox`
  - `gpu-rtx-4000-ada` -> `5860-proxmox`
- The GPU ResourceFlavors are bound to `Topology/gpu-fabric-10-210` through
  `spec.topologyName`, so Kueue has an explicit locality model for the current
  three-node GPU fabric.
- Do not increase Kueue GPU quota just because Slurm has admitted a node; the
  bridge between Kueue quota and Slurm lease state does not exist yet.
- The current heterogeneous training lane uses:
  - `cpu-any`
  - `gpu-any`
- Those flavors deliberately target the whole `gpu-batch` fleet so mixed-SKU
  multi-node smokes can be admitted.
- The first concrete JobSet example in this repo is:
  - `/home/devsounio/beagle/k8s/sounio-distributed-training/jobset-gpu-ddp-smoke-kueue.yaml`
- The matching helper script is:
  - `/home/devsounio/beagle/k8s/sounio-distributed-training/run-kueue-jobset-smoke.sh`
