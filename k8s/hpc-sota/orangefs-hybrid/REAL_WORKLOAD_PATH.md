# OrangeFS Real Workload Path

## Purpose

This is the practical promotion path after the proven OrangeFS workflows and
now that the full DDP training canary is green under the promoted baseline.

## First promoted workload

Use the single-job artifact probe first:

- [artifact probe job](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/job-orangefs-artifact-probe.yaml)

It validates:

- dataset writes
- checkpoint writes
- scratch writes
- GPU-node consumption from the live OrangeFS mount

without the extra moving parts of multi-rank coordination.

Current result:

- `orangefs-artifact-probe` completed successfully on `r740`
- host evidence exists at:
  - `/var/lib/orangefs-lab/client-runtime/mnt/training-orangefs/datasets/probe/dataset.json`
  - `/var/lib/orangefs-lab/client-runtime/mnt/training-orangefs/checkpoints/probe/checkpoint.pt`
- runtime proof now includes:
  - the probe reports `cuda=true`
  - the probe reports `gpu_count=1`

## Next promoted workload

The next step above the artifact probe is a real single-node CUDA pilot:

- [cuda pilot job](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/job-orangefs-cuda-pilot.yaml)

It keeps the same storage shape:

- OrangeFS for datasets
- OrangeFS for checkpoints
- local `emptyDir` scratch

but upgrades the compute side to an actual GPU training loop instead of only
artifact writes.

Current result:

- `orangefs-cuda-pilot` completed successfully on `r740`
- host evidence on `r740` exists at:
  - `/var/lib/orangefs-lab/client-runtime/mnt/training-orangefs/datasets/pilot-cuda-metrics.json`
  - `/var/lib/orangefs-lab/client-runtime/mnt/training-orangefs/checkpoints/pilot-cuda-model.pt`
- the same artifacts are also visible on:
  - `r770`
  - `t560` after mounting the OrangeFS client runtime there
- runtime payload includes:
  - `cuda=true`
  - `device_name=NVIDIA RTX A5000`
  - `gpu_count=1`
  - `steps=12`

## Why this step matters

The current DDP canary already proves that:

- OrangeFS is mounted and reachable
- Kubernetes can consume it on the GPU nodes
- distributed launch works
- the promoted `torchrun + gloo` baseline completes on both GPU nodes

The artifact probe now serves as the simplest promoted workload on top of that
baseline.

## Promotion sequence

1. Keep the DDP canary green on the promoted baseline
2. Run the artifact probe as the simplest real workload
3. Run the CUDA pilot as the next single-node promoted workload
4. Promote the first domain tracks on top of the same storage shape:
   - `pbpk`
   - `omics`
   - `pl-runtime`
5. Confirm dataset/checkpoint files exist under `training-orangefs`
6. Only after that promote additional multi-rank training jobs by default

## Current promoted domain tracks

The first domain tracks are now live on the OrangeFS baseline:

- `pbpk-single-gpu-orangefs`
- `omics-preprocess-orangefs`
- `pl-runtime-gpu-pilot-orangefs`

That means the current platform already supports:

- PBPK-style parameter/state workloads
- omics preprocessing with durable shared outputs
- new PL runtime GPU pilot work with durable metrics and checkpoints
