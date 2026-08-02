# OrangeFS Lightweight Benchmark Results

Date:

- `2026-04-04`

Host:

- `t560-proxmox`

Paths:

- OrangeFS:
  - `/zfast/orangefs-lab/two-node/mnt`
- local comparison path:
  - `/zfast/orangefs-lab/bench-local`

Parameters:

- sequential file size:
  - `128 MiB`
- metadata file count:
  - `1000`

## Results

| metric | OrangeFS | local |
| --- | ---: | ---: |
| seq write MiB/s | 963.53 | 3880.27 |
| seq read MiB/s | 684.62 | 1279.75 |
| create ops/s | 617.07 | 49304.73 |
| stat ops/s | 22328.66 | 491366.45 |
| remove ops/s | 1292.93 | 68660.03 |

SHA256 matched on both sides:

- `254bcc3fc4f27172636df4bf32de9f107f620d559b20d760197e452b97453917`

Raw CSV artifact:

- `/zfast/orangefs-lab/bench-results/20260404-214350/results.csv`

## Interpretation

This is the expected shape for a lightweight first pass:

- local storage still wins decisively for hot temporary data
- OrangeFS is already delivering non-trivial shared throughput
- OrangeFS is not trying to beat local NVMe or local ZFS at every micro-test
- the real promotion question is whether it beats the old shared path and
  behaves well for datasets, checkpoints, and multi-node jobs

That means this benchmark is a **sanity pass**, not the final verdict.

## Reusable script

- [benchmark/run-lightweight.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/benchmark/run-lightweight.sh)
