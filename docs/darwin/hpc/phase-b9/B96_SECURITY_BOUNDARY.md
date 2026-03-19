# B9.6 Security Boundary

## Caller Boundary

B9.6 does not turn the gateway into open self-service. It authorizes one
controlled caller class:

- namespace: `darwin-research`
- service account: `darwin-research-hpc-client`

The service remains internal-only and reachable through the ClusterIP path.

## Submission Boundary

The research-facing path inherits the B9.5 submission contract unchanged:

- approved `profile_id` only
- approved `parameters` only
- no raw scheduler payloads
- no arbitrary scripts
- no arbitrary partitions
- no arbitrary GPU counts

## Trust Boundary

The adapter trust boundary remains on `t560`. Slurm remains outside Kubernetes.
B9.6 does not move scheduler trust into the cluster.

## Network Boundary

The network opening is narrow and explicit:

- egress from `darwin-research` client pods to the gateway only
- ingress into the gateway from `darwin-research` client pods only
- no ingress controller
- no edge exposure
- no public endpoint

## Why This Matters

B9.6 proves that research-facing consumption can exist without dissolving the
governance boundary that kept B9.4 and B9.5 safe.
