# B10.1 GO / NO-GO

## Current Status

B10.1 is currently `GO`, based on canonical run `20260319-070942`.

Current evidence:

- dedicated bucket = `darwin-hpc-artifacts`
- forbidden Velero bucket remains `darwin-k8s-backups`
- source profile = `cpu-short-v1`
- source job id = `24`
- deterministic object prefix = `hpc/cpu-short-v1/24/b96-20260319-062504/`
- remote checksum validation = successful for all four published objects
- cluster and Slurm stayed green

## GO if

1. one real approved bundle is published successfully
2. the target bucket is dedicated to HPC artifacts
3. the object key layout is deterministic
4. the manifest is enriched with object metadata
5. remote checksum validation succeeds
6. Slurm remains healthy
7. Kubernetes remains healthy

## GO-WITH-BLOCKER if

1. publication logic works
2. but one bounded RGW or credential issue prevents clean promotion
3. and the issue does not require reopening blocked platform policy

## NO-GO if

1. the Velero bucket must be reused to make the phase pass
2. PVC/PV reopening becomes necessary
3. ingress, edge, HA, or topology must change
4. Slurm health regresses
5. Kubernetes health regresses
