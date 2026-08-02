# AGENTS

This file tells Codex-style agents how to work safely in this lab.

Read this first:

1. [AGENT_BOOTSTRAP.md](/home/devsounio/beagle/k8s/hpc-sota/AGENT_BOOTSTRAP.md)
2. [STACK_SEMAPHORE.md](/home/devsounio/beagle/k8s/hpc-sota/STACK_SEMAPHORE.md)
3. [DEV_WORKFLOW.md](/home/devsounio/beagle/k8s/hpc-sota/DEV_WORKFLOW.md)
4. [README.md](/home/devsounio/beagle/k8s/hpc-sota/README.md)
5. the track-specific README you are changing

## Current reality

The stack is not hypothetical.

Working lanes:

- `K8s + JobSet + Kueue + OrangeFS`
- `Slurm/Slinky + OrangeFS + K8s`

Working tracks:

- `pbpk`
- `omics`
- `pl-runtime`

The current source of truth for Slurm accounting is:

- host-local MariaDB on `t560`

Do not change that unless the task is explicitly about `slurmdbd` migration.

## How to operate

Use:

- [ops/lab-ops.sh](/home/devsounio/beagle/k8s/hpc-sota/ops/lab-ops.sh)

Normal first commands:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota
source ops/lab-ops.sh
lab_status
lab_slurm_status
```

## Decision rule

Use Slurm when the task is:

- HPC batch
- `PBPK`
- `omics`
- `pl-runtime`
- QoS / partition / accounting work

Use Kubernetes when the task is:

- distributed training
- `JobSet`
- `Kueue`
- controller-native experiments

## Hard rules

1. Prefer existing proven scripts over inventing ad hoc submit commands.
2. Use local scratch first, then promote durable outputs to OrangeFS.
3. Do not default to OrangeFS shared scratch.
4. Do not run heavy Slurm GPU jobs and heavy K8s GPU jobs concurrently unless that contention is intentional.
5. Do not touch the `slurmdbd` cutover path during unrelated work.
6. If `t560` shows stale OrangeFS visibility, restart `orangefs-client-runtime.service` there instead of assuming data corruption.

## Proven scripts

Prefer these:

- [50-submit-orangefs-smoke.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/50-submit-orangefs-smoke.sh)
- [55-submit-pbpk-cpuops.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/55-submit-pbpk-cpuops.sh)
- [57-submit-omics-cpuops.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/57-submit-omics-cpuops.sh)
- [58-submit-plruntime-gpuorangefs.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/58-submit-plruntime-gpuorangefs.sh)
- [61-submit-plruntime-gpu-stress.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/61-submit-plruntime-gpu-stress.sh)
- [64-submit-plruntime-torch-gpucompute.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/64-submit-plruntime-torch-gpucompute.sh)
- [59-prove-burst-priority.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/59-prove-burst-priority.sh)
- [63-run-qos-validation.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/63-run-qos-validation.sh)
- [orangefs-hybrid/run-k8s-orangefs-training-canary.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-training-canary.sh)
- [orangefs-hybrid/run-k8s-orangefs-cuda-pilot.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-cuda-pilot.sh)

## Validation after changes

After editing workload or scheduler behavior:

1. run `lab_status`
2. run `lab_slurm_status`
3. run the smallest relevant proven workload
4. confirm artifacts under OrangeFS
5. update the nearest README if behavior changed

## Yellow zone

These areas are intentionally not "casual edit" zones:

- [SLURMDBD_EVOLUTION.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/SLURMDBD_EVOLUTION.md)
- [values/mariadb-values.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/mariadb-values.yaml)
- [values/slurm-pilot-values.external-db.example.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.external-db.example.yaml)

Touch them only if the task is explicitly migration or resilience work.
