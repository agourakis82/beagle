# PBPK Track

This track is for physiologically based pharmacokinetic workflows that need:

- reproducible parameter datasets
- durable checkpoints and model snapshots
- queued batch execution
- optional GPU acceleration for surrogate models or hybrid fitting stages

Starting point:

- [pbpk single-gpu pilot](/home/devsounio/beagle/k8s/hpc-sota/workloads/pbpk/job-pbpk-single-gpu-orangefs.yaml)

Current result:

- `pbpk-single-gpu-orangefs` completed successfully
- runtime proof:
  - `cuda=true`
  - `device_name=NVIDIA RTX A5000`
  - `gpu_count=1`
- OrangeFS artifacts:
  - `/datasets/pbpk-summary.json`
  - `/checkpoints/pbpk-state.pt`

Storage shape:

- `/datasets/pbpk`
- `/checkpoints/pbpk`
- local `/scratch`
