# B14.3 Known Limits

## Current limits

- the recipe set currently covers one canonical workstream only:
  `beagle-darwin-hpc-governance`
- recipe ingestion is still doc-and-smoke driven; the runtime does not yet load
  recipe graphs as a first-class scheduler input
- the live proof reuses the already-proven sustained validation execution path
  rather than a separate orchestration engine
- multi-workstream orchestration is still out of scope for this phase
- host `cargo` now exists, but the local host Rust toolchain
  (`cargo/rustc 1.85.0`) is still below the current repo lockfile MSRV for some
  dependencies; live container builds remain the stronger compile proof

## Interpretation

B14.3 is the first execution-graph layer for the canonical workstream. It turns
the workstream from a governed object into a governed runnable object, but it is
not yet a multi-workstream scheduler or control room.
