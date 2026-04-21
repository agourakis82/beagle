# Workload Tracks

These are the first promoted workload tracks on top of the current OrangeFS
baseline.

Shared baseline:

- Kubernetes for orchestration
- JobSet + Kueue for distributed and queued batch work
- OrangeFS for durable datasets and checkpoints
- local `emptyDir` or NVMe scratch for transient throughput
- GPU jobs using the `nvidia` runtime class and the current GPU-node policy

Tracks:

- [pbpk](/home/devsounio/beagle/k8s/hpc-sota/workloads/pbpk/README.md)
- [omics](/home/devsounio/beagle/k8s/hpc-sota/workloads/omics/README.md)
- [pl-runtime](/home/devsounio/beagle/k8s/hpc-sota/workloads/pl-runtime/README.md)

Current first-run status:

- `pbpk`: green
- `omics`: green
- `pl-runtime`: green

Current operational note:

- `t560` now mounts the same OrangeFS training path for control-plane visibility
- when `t560` briefly shows stale or inconsistent reads after intense writer-side
  churn, restarting `orangefs-client-runtime.service` there restores visibility
  without changing the workload result on the GPU clients
