# OrangeFS Proven Workflow Results

## Scope warning

This proof remains useful, but its scope is narrower than the title alone
suggests.

As of `2026-04-21`, a later Sounio workload exposed a correctness failure on
the PVFS2 path for text-heavy compiler artifacts:

- a measurable fraction of `.sio` source files read back through OrangeFS were
  truncated and padded with spaces
- `.stdout` writes used for batch-result aggregation showed the same padding
  pattern
- that corruption was enough to silently invalidate both the Slurm stage and a
  later `kubectl tar` pull

The safe interpretation of this document is therefore:

- the workflow below proved fixed-size binary dataset/checkpoint publication and
  immediate readback under that specific canary shape
- it did **not** prove OrangeFS correctness for general text artifacts, active
  scratch, or readback-sensitive compiler pipelines
- for Sounio compile/run workloads, use local staging and local execution first,
  then publish durable outputs to OrangeFS

## Why this exists

The larger multi-node benchmark was useful, but it mixed:

- shared dataset publication
- cross-node fan-out reads
- concurrent checkpoint writes
- runner orchestration quirks

This file records the first clean end-to-end run of the split OrangeFS workflow
using one shared `RUN_ID`.

## Workflow

Artifacts:

- [dataset repro runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-dataset-repro.sh)
- [checkpoint repro runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-checkpoint-repro.sh)
- [proven workflow runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-proven-workflow.sh)

Run ID:

- `1775376996`

Nodes:

- dataset writer: `r740-proxmox`
- dataset readers: `r740-proxmox`, `r770-proxmox`
- checkpoint writers: `r740-proxmox`, `r770-proxmox`

Layout assumptions:

- two-node OrangeFS island under `systemd`
- second tuning round applied
- `DefaultNumDFiles 1`

## Results

### Dataset publish on `r740`

```text
host=orangefs-dataset-repro-writer-r740 phase=write mb_s=600.66
host=orangefs-dataset-repro-writer-r740 phase=read mb_s=249.81
sha256=a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484
```

### Cross-node fan-out readers

```text
host=orangefs-dataset-repro-reader-r740 phase=read mb_s=242.80
sha256=a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484

host=orangefs-dataset-repro-reader-r770 phase=read mb_s=551.18
sha256=a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484
```

### Concurrent checkpoints

```text
host=orangefs-repro-r740 phase=write mb_s=578.61
host=orangefs-repro-r740 phase=read mb_s=241.90
path=/orangefs/checkpoint-repro-1775376996/checkpoint-orangefs-repro-r740.bin
sha256=a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484

host=orangefs-repro-r770 phase=write mb_s=687.14
host=orangefs-repro-r770 phase=read mb_s=580.88
path=/orangefs/checkpoint-repro-1775376996/checkpoint-orangefs-repro-r770.bin
sha256=a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484
```

### Host evidence from `r740`

```text
checkpoint-repro-1775376996/checkpoint-orangefs-repro-r740.bin 268435456
checkpoint-repro-1775376996/checkpoint-orangefs-repro-r770.bin 268435456
dataset-repro-1775376996/datasets/dataset.bin 268435456
```

## Read

This is the first clean OrangeFS proof where all three layers completed under
the same workflow:

- one-node dataset publication
- two-node fan-out reads with matching hashes
- two-node concurrent checkpoint writes with immediate readback and matching
  hashes

That does not mean OrangeFS has already beaten Ceph overall on this cluster.

It does mean:

- OrangeFS was no longer blocked on checkpoint correctness for this binary
  canary shape
- the split workflow is a more trustworthy Orange-first validation path than
  the older monolithic benchmark
- the next comparison against Ceph should use this proven workflow shape, not
  the earlier mixed benchmark alone

It does **not** mean:

- OrangeFS is safe as shared scratch for `.sio` inputs, `.stdout` trees, or
  other text-heavy compiler artifacts
- OrangeFS readback is trustworthy enough to keep text aggregation on the PVFS2
  path without a local verification step
