# B15.3 Control Room Actions Known Limits

## Current limits

- the mutation surface remains tightly bounded to the canonical workstream only:
  `beagle-darwin-hpc-governance`
- only `hold` and `resume` are exposed in this phase
- actions are blocked while a current task is still running; this phase does not
  invent semantics for mutating active workloads
- the governance ledger is repo-local runtime evidence; this phase does not add
  a new public observability surface for it
- the cockpit can display the bounded action endpoints and state, but the phase
  does not add a general authenticated browser mutation framework
- the phase does not broaden to multi-workstream control
- rollback and recovery transitions remain outside the control-room mutation
  surface in this phase; only `hold` and `resume` are exposed live

## Host / build note

The host now has `cargo`, but the local toolchain is still below the repo MSRV.
The strong compile proof for this phase therefore remains the containerized
build/test path until the host toolchain is upgraded.

## Why this is still the right phase

B15.3 is meant to make the control room operationally useful without reopening
the architecture.

This phase deliberately stops at the smallest bounded governance surface:

1. `hold`
2. `resume`
3. explicit handoff/state/ledger coherence
