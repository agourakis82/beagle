# OrangeFS Checkpoint Repro Notes

## Why this exists

After the fairer multi-node benchmark, the next question was whether the
checkpoint-completion issue was:

- specific to `r740`
- specific to concurrent writes
- or a deeper OrangeFS read-after-write problem in the current proof island

## Reproducer

Artifacts:

- [checkpoint repro template](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-orangefs-checkpoint-repro-template.yaml)
- [checkpoint repro runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-checkpoint-repro.sh)

Test shape:

- write a `256 MiB` checkpoint file
- `fsync`
- reopen the same file immediately
- hash it completely

## Findings before Round 2

### `r740` single-node control

Even without concurrent writes, the `r740` control pod remained running and the
OrangeFS client log showed repeated:

```text
io_decode_ack_response (op_status): No such file or directory
server: tcp://10.100.100.3:3334
```

### `r770` single-node control

The same pattern also appeared on `r770` in the solo control:

```text
io_decode_ack_response (op_status): No such file or directory
server: tcp://10.100.100.3:3334
```

## Read before Round 2

This means the earlier multi-node checkpoint asymmetry was only part of the
story.

The stronger conclusion is:

- the current OrangeFS proof island has a reproducible checkpoint read-after-write
  problem
- it is not limited to concurrent writers
- it is not limited to `r740`
- the client-visible failures consistently point at `server02`

## Current best interpretation before Round 2

OrangeFS still looks better when measured as a shared dataset/data-plane system
than when measured only with the earlier single-node Ceph-biased benchmark.

But for checkpoint-style workloads, there is now a concrete blocker:

- write succeeds far enough to create a full-size file
- immediate readback can still fail with repeated `ENOENT` responses from
  `server02`

That makes checkpoint reliability, not just throughput, the next OrangeFS issue
to solve.

## Round 2: `DefaultNumDFiles 1`

The next targeted experiment changed the proof island in a narrower way:

- `DefaultNumDFiles 1`
- `server02` logging enabled with:
  - `EventLogging io,storage,distribution,server`

The goal was to stop letting the default `simple-stripe` policy decide the
checkpoint layout entirely and see whether the read-after-write bug disappeared
when the file layout stopped spanning multiple datafiles by default.

### `r740` single-node control after Round 2

```text
host=orangefs-repro-r740 phase=write mb_s=564.16
host=orangefs-repro-r740 phase=read mb_s=228.48
host=orangefs-repro-r740 sha256=a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484
```

### `r770` single-node control after Round 2

```text
host=orangefs-repro-r770 phase=write mb_s=798.88
host=orangefs-repro-r770 phase=read mb_s=604.44
host=orangefs-repro-r770 sha256=a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484
```

### Concurrent checkpoint repro after Round 2

```text
host=orangefs-repro-r740 phase=write mb_s=637.58
host=orangefs-repro-r740 phase=read mb_s=230.07
host=orangefs-repro-r740 sha256=a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484

host=orangefs-repro-r770 phase=write mb_s=573.91
host=orangefs-repro-r770 phase=read mb_s=569.19
host=orangefs-repro-r770 sha256=a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484
```

## Updated read

Round 2 changed the checkpoint story materially:

- the targeted `DefaultNumDFiles 1` experiment removed the reproducible
  read-after-write failure in both solo controls
- the concurrent checkpoint repro also completed cleanly on both GPU nodes
- this strongly suggests the earlier checkpoint bug was tied to the default
  multi-datafile layout path rather than OrangeFS viability in general

That does **not** mean the entire OrangeFS promotion case is settled.

It means the next question is narrower and healthier:

- whether the larger multi-node benchmark runner/workload still needs cleanup,
  or
- whether there is still a second issue beyond the checkpoint layout bug

## Follow-up: checkpoint fix held inside the full split workflow

The checkpoint fix did not stay isolated to the narrow repro.

After the workflow was split into:

1. dataset publish + fan-out readers
2. concurrent checkpoint repro
3. host evidence

the full OrangeFS proven workflow completed cleanly under one `RUN_ID`.

Recorded in:

- [proven workflow results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/PROVEN_WORKFLOW_RESULTS.md)

That strengthens the Round 2 read:

- `DefaultNumDFiles 1` was not just a local repro trick
- it held up when the checkpoint phase ran as part of a larger Orange-first
  workflow
