# B25.4 — Known Limits

`B25.4` intentionally fixes determinism without widening the scheduler or
publication surface.

## Current Limits

- only one canonical deterministic binding record is persisted per workspace in
  this phase
- the canonical path still reuses the existing workspace pilot scheduler lane
- the generic result catalog is still not guaranteed to emit a fresh run-scoped
  entry for every submitted run under the same `run_label`
- when that bounded catalog path does not materialize in time, `B25.4` falls
  back to a deterministic synthetic publication derived from the submitted job
  and its artifact manifest inside the same Beagle-owned workbench envelope
- the phase proves one bounded happy-path deterministic publication, not a full
  multi-run publication history browser
- partner-dev remains operator-mediated; this phase does not add self-service
  cluster or Kubernetes access

## Not In Scope

- high availability
- broad public ingress
- unrestricted multi-user scheduling
- a second result plane
- editorial-first abstractions

## Readiness Note

`B25.4` closes the main correctness gap left by `B25.3`: the workbench no
longer treats “latest result for this profile” as the canonical binding for a
new run. Later phases can now extend experiment orchestration on top of a
deterministic run/result identity, and can separately harden the generic result
catalog so the synthetic fallback becomes less necessary over time.
