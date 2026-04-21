# CLAUDE

This workspace is already running a real AI/HPC stack. Follow the existing paths instead of inventing a new one.

Read in this order:

1. [AGENT_BOOTSTRAP.md](/home/devsounio/beagle/k8s/hpc-sota/AGENT_BOOTSTRAP.md)
2. [STACK_SEMAPHORE.md](/home/devsounio/beagle/k8s/hpc-sota/STACK_SEMAPHORE.md)
3. [DEV_WORKFLOW.md](/home/devsounio/beagle/k8s/hpc-sota/DEV_WORKFLOW.md)
4. [README.md](/home/devsounio/beagle/k8s/hpc-sota/README.md)
5. the relevant track README

## The two lanes

Use one of these lanes on purpose:

1. Kubernetes lane
   - `JobSet`
   - `Kueue`
   - distributed training
   - OrangeFS for datasets and checkpoints
2. Slurm lane
   - HPC batch
   - `PBPK`
   - `omics`
   - `pl-runtime`
   - QoS and accounting

## Default behavior

When you need to run something operationally:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota
source ops/lab-ops.sh
lab_status
lab_slurm_status
```

When you need to submit a proven workload:

```bash
lab_copy_and_run slurm-pilot/scripts/55-submit-pbpk-cpuops.sh
lab_copy_and_run slurm-pilot/scripts/57-submit-omics-cpuops.sh
lab_copy_and_run slurm-pilot/scripts/64-submit-plruntime-torch-gpucompute.sh
```

## Operational rules

1. Do not assume local `kubectl` is configured.
2. Use [ops/lab-ops.sh](/home/devsounio/beagle/k8s/hpc-sota/ops/lab-ops.sh) for remote control-plane access through `t560`.
3. Keep transient writes local and durable outputs in OrangeFS.
4. Do not use OrangeFS as shared scratch unless the workload really needs it.
5. Do not change the current `slurmdbd` backend unless the task is explicitly about that migration.
6. Prefer the existing proven scripts and manifests over new ad hoc ones.

## Current known-good paths

Slurm:

- [55-submit-pbpk-cpuops.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/55-submit-pbpk-cpuops.sh)
- [57-submit-omics-cpuops.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/57-submit-omics-cpuops.sh)
- [58-submit-plruntime-gpuorangefs.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/58-submit-plruntime-gpuorangefs.sh)
- [61-submit-plruntime-gpu-stress.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/61-submit-plruntime-gpu-stress.sh)
- [64-submit-plruntime-torch-gpucompute.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/64-submit-plruntime-torch-gpucompute.sh)

Kubernetes:

- [orangefs-hybrid/run-k8s-orangefs-training-canary.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-training-canary.sh)
- [orangefs-hybrid/run-k8s-orangefs-cuda-pilot.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-cuda-pilot.sh)
- [orangefs-hybrid/run-k8s-orangefs-artifact-probe.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-artifact-probe.sh)

## If something looks wrong

Follow this order:

1. `lab_status`
2. `lab_slurm_status`
3. `lab_orangefs_status`
4. inspect OrangeFS artifacts
5. inspect the exact script or manifest that was used

Only after that should you change infrastructure.
