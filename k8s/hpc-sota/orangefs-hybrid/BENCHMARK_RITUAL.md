# OrangeFS Benchmark Ritual

This benchmark ritual decides whether OrangeFS deserves promotion to the shared
AI/HPC data plane.

## What we are comparing

Compare OrangeFS against:

- the current Ceph-first shared dataset/checkpoint path
- the current local NVMe tiers on:
  - `r740`
  - `r770`

Important current limitation:

- the cluster currently exposes Ceph to Kubernetes through `RBD` storage
  classes
- there is no `CephFS` storage class in the current setup
- so the old Orange-vs-Ceph benchmark is not yet a pure shared-filesystem
  versus shared-filesystem comparison
- the fairest next comparison should either:
  - use a real `CephFS` path, or
  - explicitly compare OrangeFS shared-workflow behavior against Ceph RBD as a
    different storage shape

The point is not to beat local NVMe at every micro-benchmark.
The point is to prove OrangeFS is the right shared filesystem for multi-node
AI/HPC work.

## Benchmark layers

### 1. Metadata-heavy test

Use `mdtest` to measure:

- file create rate
- stat rate
- remove rate

This matters for:

- preprocessing
- many-file datasets
- checkpoint directory churn
- scientific pipelines with many artifacts

### 2. Data test

Use `IOR` to measure:

- file-per-process write/read
- shared-file write/read
- transfer sizes relevant to training and checkpointing

Start with:

- `2 MiB` transfer size
- repeated runs
- at least two clients

### 3. Workload-shaped tests

After synthetic tests, run:

- distributed training canary reading datasets from OrangeFS
- checkpoint write/read loops
- omics shard staging
- fMRI batch input and readback
- PBPK ensemble result fan-out

## Topology

Initial server proof:

- `t560`

First distributed server proof:

- `t560`
- `5860`

Initial clients:

- `r740`
- `r770`

Then extend to:

- `DL380 G10`

## Pass criteria

OrangeFS earns promotion when:

- client mounts are stable on current nodes
- metadata behavior is healthy and repeatable
- shared data-path performance beats the current Ceph-first path for intended
  workloads
- checkpoint behavior is reliable
- local NVMe still wins for hot temporary data, but OrangeFS clearly wins as
  the shared HPC filesystem

## Reporting format

For every benchmark round capture:

- node set used
- server layout used
- kernel version
- client path used
  - kernel module
  - FUSE
  - direct interface
- read throughput
- write throughput
- metadata ops/sec
- checkpoint timing
- comparison against Ceph-first and local-NVMe paths

## Current Kubernetes profiles

### Balanced profile

Purpose:

- mixed sequential + metadata pressure
- closer to general-purpose shared training data plus artifact churn

Current manifest:

- [balanced benchmark pod](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-orangefs-vs-ceph-r740-bench.yaml)

### Streaming profile

Purpose:

- larger sequential files
- reduced metadata pressure
- closer to dataset streaming and large checkpoint movement

Current manifest:

- [streaming benchmark pod](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-orangefs-vs-ceph-r740-bench-streaming.yaml)

Runner:

- [K8s benchmark runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-r740-benchmark.sh)

Current recorded outputs:

- [K8s benchmark results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_BENCHMARK_RESULTS.md)

## Multi-node OrangeFS profile

To reduce bias toward single-node block-style behavior, OrangeFS should also be
tested in the pattern it is supposed to help with:

- one node writes a shared dataset file
- two GPU nodes read the same shared file concurrently
- two GPU nodes write separate checkpoint files concurrently into the same
  shared namespace

Artifacts:

- [multi-node pod template](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-orangefs-multinode-template.yaml)
- [multi-node runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-multinode-orangefs-benchmark.sh)
- [multi-node results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/MULTINODE_K8S_BENCHMARK_RESULTS.md)

Current read:

- this profile is fairer to OrangeFS because it exercises shared namespace
  behavior across `r740 + r770`
- OrangeFS handled shared dataset publication and cross-node readers correctly
- concurrent checkpoint writes exposed an asymmetric completion issue that still
  needs investigation

## Proven-piece OrangeFS workflow

The monolithic multi-node benchmark is useful, but it can mix genuine
filesystem issues with runner/workflow issues.

To keep OrangeFS honest without forcing every conclusion through one large
script, use the proven-piece workflow:

1. dataset writer + cross-node fan-out readers
2. concurrent checkpoint repro
3. host evidence collection

Artifacts:

- [dataset repro pod template](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-orangefs-dataset-repro-template.yaml)
- [dataset repro runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-dataset-repro.sh)
- [checkpoint repro runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-checkpoint-repro.sh)
- [OrangeFS proven workflow runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-proven-workflow.sh)

This is now the preferred Orange-first validation path whenever the larger
multi-node benchmark becomes ambiguous.

## First clean proven-workflow pass

The split workflow has now completed cleanly under one shared `RUN_ID` after:

- the second tuning round
- `DefaultNumDFiles 1`
- separating dataset fan-out from checkpoint repros

Recorded in:

- [proven workflow results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/PROVEN_WORKFLOW_RESULTS.md)
- [proven workflow results at 512 MiB](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/PROVEN_WORKFLOW_512_RESULTS.md)

That changes the benchmark posture:

- the older monolithic benchmark is still historically useful
- but it should no longer be treated as the only Orange-vs-Ceph truth source
- the next fair comparison should be rebuilt around the proven workflow pieces
  that already pass end-to-end

## Recurring canary

Artifacts:

- [proven workflow canary runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-proven-workflow-canary.sh)
- [systemd canary service](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-proven-workflow-canary.service)
- [systemd canary timer](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-proven-workflow-canary.timer)

This gives the Orange branch a repeatable health signal based on the workflow
that actually passes on the cluster today.
