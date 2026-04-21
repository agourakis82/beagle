# B15.4 Operator Timeline / Audit Replay Known Limits

## Current limits

- the timeline remains bounded to the canonical workstream only:
  `beagle-darwin-hpc-governance`
- the surface is read-only in this phase; it does not add new operator
  mutations
- timeline events are composed from current runtime truth:
  workspace/session state, governance ledger and fallback ledger
- this phase does not introduce a new durable event store or a new public audit
  system
- historical depth is bounded by the currently available runtime artifacts; the
  phase does not backfill every historical pilot
- multi-workstream timeline views remain out of scope

## Host / build note

The host now has `cargo`, but the local toolchain is still below the repo MSRV.
The strong compile proof for this phase therefore remains the containerized
build/test path until the host toolchain is upgraded.

## Why this is still the right phase

B15.4 is meant to make the existing workstream control room more operationally
readable without reopening the platform.

This phase deliberately stops at the narrowest useful replay surface:

1. ordered internal history
2. bounded event detail replay
3. same Beagle-owned workstream/session envelope
