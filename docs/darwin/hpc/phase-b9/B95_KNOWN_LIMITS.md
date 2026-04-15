# B9.5 Known Limits

## Phase Limits

B9.5 does not reopen any of the following:

- storage
- ingress
- edge exposure
- HA
- topology
- `r740` joining Kubernetes
- Slurm running inside Kubernetes
- arbitrary raw scheduler payload submission

## Workload Limits

B9.5 still excludes:

- MPI
- multi-node jobs
- interactive jobs
- arbitrary user job scripts
- arbitrary partition selection
- arbitrary GPU count selection
- broad research self-service

## Data and Service Limits

B9.5 still excludes:

- object-store artifact publication
- persistent job database
- UI work
- `slurmdbd` dependency
- storage-backed workflows

## Operational Note from B9.4

B9.4 documented that a looser network policy was temporarily required because
strict egress isolation broke the pod-to-adapter host-side path.

That issue is carried as a known limit in B9.5 unless it directly blocks
profile expansion. B9.5 is not a networking remediation phase.
