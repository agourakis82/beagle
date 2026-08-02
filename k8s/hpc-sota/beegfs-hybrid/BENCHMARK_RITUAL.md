# BeeGFS Benchmark Ritual

This is the benchmark ritual that decides whether BeeGFS earns promotion from
moonshot target to active AI/HPC data plane.

## What we are comparing

Compare BeeGFS against:

- the current Ceph-first dataset/checkpoint path
- the current local NVMe tiers on:
  - `r740`
  - `r770`

The point is not to beat local NVMe on every number.
The point is to prove BeeGFS is the right shared filesystem for multi-node work.

## Benchmark layers

### 1. Storage server baseline

Use BeeGFS built-in `StorageBench` to measure:

- raw write throughput
- raw read throughput
- target-to-target balance

This isolates server-side storage behavior before client/network effects.

### 2. Network baseline

Use BeeGFS built-in `NetBench` to measure:

- streaming network throughput from clients to storage servers
- effect of RDMA on/off
- whether the data path is bottlenecking before metadata or filesystem layout

### 3. Metadata benchmark

Use `mdtest` across multiple clients to measure:

- file create rate
- stat rate
- remove rate

This matters for:

- many-file science workloads
- preprocessing
- checkpoint directory churn

### 4. Data benchmark

Use `IOR` across multiple clients to measure:

- file-per-process write/read
- shared-file write/read
- transfer sizes relevant to training

Start with:

- `2 MiB` transfer size
- barriers enabled
- repeated runs

## Benchmark topology

Initial clients:

- `r740`
- `r770`

When `DL380 G10` arrives:

- add it to the benchmark set immediately

Initial server island:

- `t560`
- `5860`

## Workload-shaped tests

After synthetic tests, run cluster-shaped tests:

### Training data plane

- distributed training canary reading shards from BeeGFS
- checkpoint write/read loops to BeeGFS

### Scientific pipeline

- omics shard staging
- fMRI batch input/readback
- PBPK ensemble result fan-out

## Pass criteria

BeeGFS earns promotion when:

- client mounts are stable
- metadata benchmarks are healthy and repeatable
- `IOR` shared data path beats the current Ceph-first shared path for the
  intended workloads
- checkpoint write/resume is reliable
- training jobs do not regress in stability
- local NVMe still wins for hot temporary data, but BeeGFS clearly wins as the
  shared parallel filesystem

## Reporting format

For every benchmark round capture:

- node set used
- server roles used
- BeeGFS version
- kernel version
- RDMA on/off
- read throughput
- write throughput
- metadata ops/sec
- checkpoint timing
- comparison against Ceph-first and local-NVMe paths

## Final decision gate

If BeeGFS wins on:

- shared throughput
- metadata stability
- checkpoint behavior
- operational simplicity

then it becomes the primary AI/HPC shared filesystem and Ceph is reduced to a
durable legacy/platform role.
