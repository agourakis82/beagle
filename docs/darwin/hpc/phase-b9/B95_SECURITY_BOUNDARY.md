# B9.5 Security Boundary

## Control Model

The B9.5 gateway remains a controlled policy surface. It does not become a
generic `sbatch` passthrough.

Clients submit:

- `profile_id`
- approved `parameters`

The service layer performs the scheduler mapping internally by selecting the
correct approved Slurm-side template for that profile.

## Explicit Rejections

The gateway must reject:

- unknown `profile_id` values
- extra parameters
- raw scheduler payloads
- arbitrary script bodies
- arbitrary partition selection
- arbitrary GPU count requests
- arbitrary node, CPU, memory, or walltime requests

## Boundary Preservation

B9.5 keeps the existing platform boundaries intact:

- Slurm trust stays outside Kubernetes.
- The gateway remains internal-only.
- The gateway remains stateless.
- No new ingress or edge exposure is introduced.
- No new storage dependency is introduced.
- No topology change is introduced.

## Why This Matters

This pattern preserves:

- scheduler policy control
- reproducibility
- auditability
- safer future expansion toward controlled admission

It also prevents the platform from drifting into arbitrary code submission as a
service.
