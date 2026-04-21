# OrangeFS Proven Workflow Results at 512 MiB

## Why this exists

The first clean proven workflow at `256/256` showed that OrangeFS could finish
the split workflow end to end.

This file records the next scale step:

- dataset publish at `512 MiB`
- cross-node fan-out reads at `512 MiB`
- concurrent checkpoints at `512 MiB`

## Workflow

Artifacts:

- [proven workflow runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-proven-workflow.sh)
- [proven workflow baseline results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/PROVEN_WORKFLOW_RESULTS.md)

Run ID:

- `1775377192`

Nodes:

- dataset writer: `r740-proxmox`
- dataset readers: `r740-proxmox`, `r770-proxmox`
- checkpoint writers: `r740-proxmox`, `r770-proxmox`

Sizes:

- dataset: `512 MiB`
- checkpoints: `512 MiB` per node

## Results

### Dataset publish on `r740`

```text
host=orangefs-dataset-repro-writer-r740 phase=write mb_s=586.33
host=orangefs-dataset-repro-writer-r740 phase=read mb_s=236.62
sha256=9acca8e8c22201155389f65abbf6bc9723edc7384ead80503839f49dcc56d767
```

### Cross-node fan-out readers

```text
host=orangefs-dataset-repro-reader-r740 phase=read mb_s=239.30
sha256=9acca8e8c22201155389f65abbf6bc9723edc7384ead80503839f49dcc56d767

host=orangefs-dataset-repro-reader-r770 phase=read mb_s=634.76
sha256=9acca8e8c22201155389f65abbf6bc9723edc7384ead80503839f49dcc56d767
```

### Concurrent checkpoints

```text
host=orangefs-repro-r740 phase=write mb_s=615.55
host=orangefs-repro-r740 phase=read mb_s=234.63
path=/orangefs/checkpoint-repro-1775377192/checkpoint-orangefs-repro-r740.bin
sha256=9acca8e8c22201155389f65abbf6bc9723edc7384ead80503839f49dcc56d767

host=orangefs-repro-r770 phase=write mb_s=599.48
host=orangefs-repro-r770 phase=read mb_s=566.88
path=/orangefs/checkpoint-repro-1775377192/checkpoint-orangefs-repro-r770.bin
sha256=9acca8e8c22201155389f65abbf6bc9723edc7384ead80503839f49dcc56d767
```

### Host evidence from `r740`

```text
checkpoint-repro-1775377192/checkpoint-orangefs-repro-r740.bin 536870912
checkpoint-repro-1775377192/checkpoint-orangefs-repro-r770.bin 536870912
dataset-repro-1775377192/datasets/dataset.bin 536870912
```

## Read

This matters because the `512/512` run shows the clean OrangeFS workflow still
holds when the file sizes double:

- dataset publish still completes cleanly
- both readers still complete with matching hashes
- both concurrent checkpoints still complete with immediate readback
- host evidence still matches expected file sizes

This is not yet a full promotion verdict against Ceph.

It is a stronger proof that OrangeFS is behaving like a usable shared
AI/HPC filesystem on this cluster when judged by the split workflow rather than
the older monolithic benchmark.
