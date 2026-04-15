# B9.6 Known Limits

## Platform Limits

B9.6 does not reopen:

- storage
- ingress
- edge
- HA
- topology
- `r740` joining Kubernetes
- Slurm in Kubernetes

## Service Limits

B9.6 still excludes:

- raw scheduler payload submission
- arbitrary scripts
- arbitrary partition requests
- arbitrary GPU counts
- public gateway exposure
- broad research self-service

## Workload Limits

B9.6 does not add any new workload classes beyond:

- `cpu-short-v1`
- `cpu-batch-v1`
- `gpu-single-v1`

MPI and multi-node workloads remain out of scope.

## Data and Product Limits

B9.6 still excludes:

- object-store publication
- persistent job database
- UI work
- `slurmdbd`
- storage-backed workflows

## Operational Note

B9.6 is an admission and governance phase, not a networking redesign or storage
phase. Any pre-existing network-policy caveat remains a known limit unless it
directly blocks controlled research-side admission.

## Canonical Run Note

Canonical promotion run `20260319-062504` proved the research-facing gateway
path, the rejection of invalid submit parameters, and a fully green cluster
health capture with healthy Slurm output.

## Residual Environmental Risk

Earlier run `20260319-061231` captured `5860-proxmox` as `NotReady` before the
bounded environmental recovery. B9.6 no longer carries that as a promotion
blocker, but the node should still be monitored as an environmental risk rather
than treated as a gateway or Slurm design issue.
