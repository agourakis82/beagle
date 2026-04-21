# CPU Preflight

This file documents the assumptions that must hold before the CPU runner
templates are turned into real runnable Jobs.

## Required Preconditions

- At least one Kubernetes node exists that is intended for heavy compute work.
- Those nodes should be labeled `sounio.dev/compute=heavy`.
- If a heavy compute node is also part of the GPU fleet, CPU Jobs must tolerate
  `sounio.dev/pool=gpu-batch:NoSchedule`.
- `sounio.dev/pool=cpu-batch` remains supported as an alternate landing zone,
  but it is not the primary path in this cluster right now.
- The standard template expects `2 CPU / 4Gi` requested and can burst up to
  `6 CPU / 24Gi`.
- The batch template expects `4 CPU / 8Gi` requested and can burst up to
  `12 CPU / 48Gi`.
- The cluster can pull `rust:1.89-bookworm`, or a mirrored equivalent is
  available.
- `cpu-standard-job.yaml` or `cpu-batch-job.yaml` is unsuspended or cloned into
  a runnable Job before actual execution.

Current intended compute-heavy nodes:

- `r770-proxmox`
- `r740-proxmox`

## Validation Checklist

- `kubectl get nodes -L sounio.dev/compute -L sounio.dev/pool`
- `kubectl describe node <cpu-node-name>`
- `kubectl top nodes` if metrics are available
- a short smoke Job lands on the intended node pool before larger runs
