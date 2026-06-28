# B10.1 Security Boundary

## Boundary Rule

Object publication remains a platform-owned action. Clients do not receive
bucket credentials, and the publication path does not dissolve the existing
gateway or Slurm trust boundaries.

## Storage Boundary

- use a dedicated bucket: `darwin-hpc-artifacts`
- do not reuse the Velero bucket: `darwin-k8s-backups`
- do not allow arbitrary bucket names from clients
- do not allow arbitrary object-key overrides from clients

## Runtime Boundary

- publication runs host-side on the control plane
- Slurm remains outside Kubernetes
- no scheduler trust moves into Kubernetes
- no new ingress or edge surface is introduced

## Live Boundary Result

- dedicated RGW user: `darwin-hpc-artifact-publisher`
- dedicated bucket: `darwin-hpc-artifacts`
- Velero bucket remains isolated and unused by B10.1
