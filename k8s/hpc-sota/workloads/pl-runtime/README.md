# PL Runtime Track

This track is for the new PL runtime and compiler-style workloads that need:

- reproducible test inputs
- durable benchmark and checkpoint outputs
- queued GPU or CPU batch execution
- a clean path from single-node pilots to distributed launches

Starting point:

- [pl runtime gpu pilot](/home/devsounio/beagle/k8s/hpc-sota/workloads/pl-runtime/job-pl-runtime-gpu-pilot-orangefs.yaml)

Current status:

- `pl-runtime-gpu-pilot-orangefs` now completes successfully
- runtime proof:
  - `cuda=true`
  - `device_name=NVIDIA RTX A5000`
  - `gpu_count=1`
- current OrangeFS artifacts:
  - `/datasets/pl-runtime-metrics.json`
  - `/checkpoints/pl-runtime-state.pt`
- the durable write path now promotes scratch outputs directly inside the job
  with the hardened OrangeFS-safe helper

Storage shape:

- `/datasets/pl-runtime`
- `/checkpoints/pl-runtime`
- local `/scratch`
