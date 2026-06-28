# B10.2 - Multi-profile Object Publication Matrix

## Objective

Prove that the object-backed result plane generalizes across workload classes
by publishing canonical bundles for `cpu-batch-v1` and `gpu-single-v1`
through the same dedicated RGW target and the same manifest contract.

## Matrix Targets

- `cpu-batch-v1`
- `gpu-single-v1`

## Required Publication Rules

- preserve the dedicated bucket `darwin-hpc-artifacts`
- do not reuse the Velero bucket `darwin-k8s-backups`
- preserve deterministic keying as
  `hpc/{profile_id}/{job_id}/{run_label}/<object-name>`
- keep the manifest structure stable
- validate remote checksums for each published object

## Special Runtime Expectation

The GPU bundle must still publish cleanly even though execution lands on
`r740-proxmox`. Publication must keep using the control-side retrieval model
instead of reopening storage or moving scheduler trust into Kubernetes.

## Live Result

- canonical run: `20260319-072237`
- `cpu-batch-v1` source job id: `31`
- `gpu-single-v1` source job id: `32`
- GPU execution landed on `r740-proxmox`
- both profiles published into `darwin-hpc-artifacts`
