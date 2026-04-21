# OrangeFS Multi-node K8s Benchmark Results

## Why this benchmark exists

The earlier OrangeFS vs Ceph runs were useful, but they were still biased toward:

- single-node execution
- a block-backed Ceph RBD shape
- metadata-heavy behavior

OrangeFS should also be tested in the shape it is actually meant to help with:

- shared dataset publication
- multi-node read fan-out
- shared checkpoint namespace writes

## Shape

Run ID:

- `1775353251`

Nodes:

- writer: `r740-proxmox`
- readers: `r740-proxmox`, `r770-proxmox`
- checkpoint writers: `r740-proxmox`, `r770-proxmox`

Mount source on both GPU nodes:

- `/var/lib/orangefs-lab/client-runtime/mnt`

Workload:

- dataset write: `512 MiB`
- dataset concurrent reads: `512 MiB`
- checkpoint writes: `256 MiB` per node

Artifacts:

- [runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-multinode-orangefs-benchmark.sh)
- [pod template](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-orangefs-multinode-template.yaml)

## Results

### Shared dataset publish

```text
dataset-write,orangefs-dataset-writer-r740,seq_write_mb_s,633.46
dataset-write,orangefs-dataset-writer-r740,seq_read_mb_s,241.88
dataset-write,orangefs-dataset-writer-r740,sha256,9acca8e8c22201155389f65abbf6bc9723edc7384ead80503839f49dcc56d767
```

### Concurrent shared readers

```text
dataset-read,orangefs-dataset-reader-r740,seq_read_mb_s,222.95
dataset-read,orangefs-dataset-reader-r740,sha256,9acca8e8c22201155389f65abbf6bc9723edc7384ead80503839f49dcc56d767
dataset-read,orangefs-dataset-reader-r770,seq_read_mb_s,692.44
dataset-read,orangefs-dataset-reader-r770,sha256,9acca8e8c22201155389f65abbf6bc9723edc7384ead80503839f49dcc56d767
```

### Concurrent checkpoint writes

`r770` completed cleanly:

```text
checkpoint-write,orangefs-checkpoint-writer-r770,seq_write_mb_s,904.17
checkpoint-write,orangefs-checkpoint-writer-r770,seq_read_mb_s,681.52
checkpoint-write,orangefs-checkpoint-writer-r770,sha256,a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484
```

`r740` created the full checkpoint file, but the pod did not complete cleanly in
the same window. The file was present at full size:

```text
/var/lib/orangefs-lab/client-runtime/mnt/multinode-bench-1775353251/checkpoints/checkpoint-orangefs-checkpoint-writer-r740.bin
268435456 bytes
```

## Read

This benchmark is more representative of OrangeFS’s intended role than the
single-node Ceph comparison because it tests:

- one-node publish into a shared namespace
- cross-node fan-out reads
- concurrent writes into a shared checkpoint directory

What it says right now:

- OrangeFS can publish a shared dataset and serve it across both GPU nodes
- OrangeFS can handle concurrent cross-node readers with matching hashes
- OrangeFS can persist concurrent checkpoint files from both nodes into the same
  shared namespace
- but concurrent checkpoint completion is asymmetric right now:
  - `r770` finished cleanly
  - `r740` left a valid full-size file but did not finish the pod cleanly in
    the same benchmark window

## Current conclusion

The fairness critique was valid.

The OrangeFS story is better in a multi-node shared-data benchmark than in the
earlier single-node block-style comparison.

At the same time, the checkpoint asymmetry means OrangeFS still has a real
runtime edge case to resolve before we could call it a clean promotion
candidate.

## Round 2 follow-up

After this first multi-node run, a narrower Round 2 experiment changed the
filesystem default to:

- `DefaultNumDFiles 1`

That targeted checkpoint repros directly instead of rerunning the full
benchmark first.

What happened:

- both single-node checkpoint controls succeeded
- the concurrent checkpoint repro also succeeded on both `r740` and `r770`

That means the first multi-node result should now be read more carefully:

- it successfully proved OrangeFS as a shared dataset/read fan-out system
- its checkpoint asymmetry was real at the time
- but the later Round 2 repro strongly suggests the checkpoint problem was tied
  to the default multi-datafile layout path rather than an unavoidable OrangeFS
  limit on this cluster

The larger multi-node benchmark should therefore be rerun under the Round 2
layout before making any final judgment about OrangeFS checkpoint behavior.

## Follow-up: proven workflow passed cleanly

After the monolithic benchmark remained noisy, the workflow was split into:

1. dataset publish + fan-out readers
2. concurrent checkpoint repro
3. host evidence collection

That split workflow then completed cleanly under one shared `RUN_ID` after the
Round 2 layout change.

Recorded in:

- [proven workflow results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/PROVEN_WORKFLOW_RESULTS.md)

That means this file should now be read as:

- the first fairer multi-node benchmark that exposed the right problem shape
- not the final word on OrangeFS checkpoint behavior on this cluster
