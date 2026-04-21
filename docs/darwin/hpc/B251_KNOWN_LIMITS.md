# B25.1 — Known Limits

Status: GO

## Current limits

- The partner-dev path is `operator-mediated`; this phase does not issue a
  separate per-user Beagle or cluster identity.
- The canonical collaboration mode is still the same shared workspace; this
  phase does not create a separate multi-workspace fleet manager.
- The workspace remains `internal-only`; there is still no broad public ingress
  or HA in this phase.
- The live GPU path remains `isolated-dedicated-gpu` through `gpu-single-v1`;
  shared or oversubscribed GPU access is only modeled and documented here.
- Numeric Slurm quotas / QoS accounting are not introduced as new live runtime
  state in this phase; the bounded surface is profile-scoped and
  operator-mediated.
- `VS Code` support is through the same Remote-SSH-compatible attach path used
  by `Cursor`; there is no second IDE-specific state owner.

## Explicit non-goals

- replacing Beagle with Coder
- broad ingress or public exposure
- HA
- per-user cluster-admin access
- unbounded autonomous multi-user behavior
