# B10.3 - Retention / Lifecycle Policy

## Objective

Define and validate the first lifecycle policy for published HPC artifacts so
that the object result plane remains governed instead of becoming an unmanaged
dump.

## First Canonical Scope

- retention classes by profile
- lifecycle behavior by artifact type
- explicit manifest preservation semantics
- dry-run candidate discovery only
- no destructive delete in the first canonical run

## Required Artifact Types

- `artifact.bin`
- `stdout.txt`
- `stderr.txt`
- `artifact-manifest.json`

## Policy Direction

- `cpu-short-v1`: short retention
- `cpu-batch-v1`: medium retention
- `gpu-single-v1`: medium-long retention
- `artifact-manifest.json` survives longer than payload objects

## Live Result

- canonical run: `20260319-183200`
- execution mode: `dry-run-only`
- evaluated objects: `20`
- dry-run delete candidates: `0`
- cluster remained green
- Slurm remained green
