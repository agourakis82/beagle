# B15.2 Premium Tool Dock MVP Known Limits

## Current limits

- the premium tool dock is bounded to one canonical workstream only:
  `beagle-darwin-hpc-governance`
- Beagle owns the session envelope, but the actual transport into Cursor,
  Claude Code and Codex remains outside the runtime in this MVP
- the cockpit is internal only; this phase does not add public UI, ingress,
  edge or HA
- the cockpit resolves last-result context through the existing result plane; a
  gateway failure is surfaced as bounded panel degradation, not as new fallback
  semantics
- the phase does not broaden to multi-workstream orchestration
- bounded hold/resume mutations remain outside this MVP; the cockpit is focused
  on shared visibility and launch-surface generation

## Host / build note

The host now has `cargo`, but the local toolchain is still below the repo MSRV.
The strong compile proof for this phase therefore remains the containerized
build/test path until the host toolchain is upgraded.

## Why this is still the right MVP

B15.2 is meant to convert the already-proven Beagle kernel into an experience
you can actually inhabit every day.

This phase deliberately stops short of external-tool transport or multi-surface
sprawl. It focuses on the smallest concrete payoff:

1. one cockpit
2. one shared session envelope
3. three premium work surfaces attached to that same envelope
