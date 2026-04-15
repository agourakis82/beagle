# B10.4 - Lifecycle Enforcement Canary

## Objective

Execute one bounded destructive lifecycle action against explicitly disposable
object sets only, proving that retention enforcement works without touching
canonical production result bundles.

## Preferred Boundary

- dedicated disposable prefix: `hpc-retention-canary/`
- same bucket family: `darwin-hpc-artifacts`
- no delete against production prefix `hpc/`

## Required Proof

- canary objects are created under the disposable prefix only
- destructive delete selects only the canary objects
- production result objects remain intact
- post-delete verification matches the delete plan
- Kubernetes remains green
- Slurm remains green

## First Canonical Shape

- profile model: `cpu-short-v1`
- canary job id: `0`
- four disposable objects:
  `artifact.bin`, `stdout.txt`, `stderr.txt`, `artifact-manifest.json`

## Live Result

- canonical run: `20260319-184000`
- canary prefix:
  `hpc-retention-canary/cpu-short-v1/0/b104-20260319-184000/`
- deleted canary objects: `4 / 4`
- preserved production objects checked: `3`
- production prefix delta: `0`
- Kubernetes remained green
- Slurm remained green
