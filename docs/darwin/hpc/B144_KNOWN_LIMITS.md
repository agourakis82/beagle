# B14.4 Known Limits

## Current limits

- the governance model currently applies to one canonical workstream only:
  `beagle-darwin-hpc-governance`
- the first live drill validates `canonical -> held -> canonical`; rollback and
  recovery states are explicit in the contract but not yet drilled live in this
  phase
- governance transitions are reflected through the existing runtime policy, not
  through a new mutation API
- multi-workstream lifecycle coordination remains out of scope
- host `cargo` exists, but the local host Rust toolchain
  (`cargo/rustc 1.85.0`) is still below the current repo lockfile MSRV for some
  dependencies; live container builds remain the stronger compile proof

## Interpretation

B14.4 is the first lifecycle-governance layer for the canonical workstream. It
proves that explicit state transitions can be modeled and drilled live without
reopening lower layers, but it is not yet a full portfolio governance system.
