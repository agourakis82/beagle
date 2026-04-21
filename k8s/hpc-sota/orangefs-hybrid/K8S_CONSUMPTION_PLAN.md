# OrangeFS K8s Consumption Plan

This is the first safe way to let Kubernetes consume OrangeFS without forcing it
into the role of generic PVC backend for everything.

## Principle

Use OrangeFS for:

- shared datasets
- shared checkpoints
- shared scratch for AI/HPC jobs

Do not use OrangeFS first for:

- cluster control-plane state
- Grafana / Prometheus state
- generic platform PVCs
- live workspace roots that already work on `zfast`

## First K8s path

The safest first integration is:

1. mount OrangeFS on selected GPU nodes at the host level
2. publish it into Kubernetes via `hostPath` or local PVs for canary jobs
3. only after that, consider a proper CSI-style path

## First concrete shape

### Host mountpoints

- `r740`: `/mnt/orangefs`
- `r770`: `/mnt/orangefs`
- future `DL380`: `/mnt/orangefs`

### Published paths

- `/mnt/orangefs/datasets`
- `/mnt/orangefs/checkpoints`
- `/mnt/orangefs/scratch`

### K8s usage

- canary `Job` for dataset read-through
- canary `Job` for checkpoint write/read loop
- later:
  - `hostPath` mount into training pods
  - or local PV wrappers for stable scheduling to specific nodes

## Why not replace everything at once

OrangeFS has now proven:

- current-OS viability
- single-node mount and I/O
- two-node shared namespace mount and I/O

But the right next move is still controlled adoption:

- data plane first
- platform state later, if ever

## Promotion gate

OrangeFS earns the first K8s data-plane role when:

- `r740` client canary passes
- `r770` client canary passes
- lightweight benchmark is recorded
- a dataset/checkpoint canary job succeeds from Kubernetes

Current status:

- `r740` client canary: passed
- `r770` client canary: passed
- lightweight benchmark: recorded
- first `r740` hostPath K8s canary: passed
- first `r770` hostPath K8s canary: passed
- first OrangeFS vs Ceph K8s benchmark: recorded
- first live systemd rollout on servers and GPU clients: completed

## First successful K8s canary

The first OrangeFS-backed Kubernetes canary has now succeeded on `r740`:

- pod: `orangefs-r740-canary`
- namespace: `beagle`
- node: `r740-proxmox`
- mount source on host: `/var/lib/orangefs-lab/client-runtime/mnt`
- pod-visible path: `/orangefs`

What the pod proved:

- Kubernetes could schedule onto the GPU node with the correct tolerations
- the host-mounted OrangeFS namespace was visible inside the container
- the pod created `/orangefs/checkpoints/k8s-orangefs-r740.txt`
- the file remained visible from the host OrangeFS mount after pod completion

Evidence is recorded in:

- [K8S_CANARY_RESULTS.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_CANARY_RESULTS.md)
- [K8S_R770_CANARY_RESULTS.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_R770_CANARY_RESULTS.md)
- [pod manifest](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-orangefs-r740-canary.yaml)
- [orchestrated runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-r740-canary.sh)

## Next gate

The next real promotion step is:

- compare OrangeFS against the old Ceph-backed shared path
- repeat the same K8s pattern on `r770`
- move from proof-window orchestration toward long-lived service units on `t560` and `5860`

That comparison path is now scaffolded, but not yet trustworthy enough to call a
result, because the OrangeFS host mount still needs hardening under heavier pod
lifecycle churn:

- [K8S_BENCHMARK_ATTEMPT_NOTES.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_BENCHMARK_ATTEMPT_NOTES.md)
- [K8S_BENCHMARK_RESULTS.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_BENCHMARK_RESULTS.md)
- [benchmark PVC](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pvc-ceph-rbd-ssd-scratch-bench.yaml)
- [benchmark pod](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-orangefs-vs-ceph-r740-bench.yaml)
- [systemd deployment results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/SYSTEMD_DEPLOYMENT_RESULTS.md)

Current comparison read on `r740`:

- Ceph beat OrangeFS for this benchmark profile
- OrangeFS remains real and consumable in Kubernetes
- the current OrangeFS proof island needs tuning and topology work before it can
  credibly challenge the existing Ceph path
