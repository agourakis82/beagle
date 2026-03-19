# B10.1 - Object-backed Artifact Publication

## Objective

Publish one real approved workload bundle into the object plane using a
dedicated RGW bucket, deterministic object keys, and platform-owned
credentials.

## First Canonical Scope

- source profile: `cpu-short-v1`
- source phase: `B9.6`
- source bundle: approved gateway artifact manifest plus local bundle files
- target endpoint: `http://192.168.3.171:7480`
- target bucket: `darwin-hpc-artifacts`

## Required Published Objects

- `artifact.bin`
- `stdout.txt`
- `stderr.txt`
- `artifact-manifest.json`

## Deterministic Key Rule

`hpc/{profile_id}/{job_id}/{run_label}/<object-name>`

## Live Result

- canonical run: `20260319-070942`
- source profile: `cpu-short-v1`
- source job id: `24`
- bucket: `darwin-hpc-artifacts`
- primary object key: `hpc/cpu-short-v1/24/b96-20260319-062504/artifact.bin`
- all four published objects passed remote checksum validation
