# B14.2 Known Limits

## Current limits

- the registry currently contains one canonical workstream only:
  `beagle-darwin-hpc-governance`
- the phase contractizes workstreams; it does not yet define full recipe graphs
  or rollback state machines
- the registry is repo-native, but runtime ingestion still follows the current
  workspace configuration path rather than a full registry loader
- no new infra, ingress, edge, HA, topology or provider work is introduced here
- host `cargo` is now available, but the local host Rust toolchain
  (`cargo/rustc 1.85.0`) is still below the current repo lockfile MSRV for some
  dependencies; live podman builds remain the stronger compile proof until the
  host toolchain is upgraded further

## Interpretation

B14.2 is the contractization step that turns the first proven workstream into a
first-class governed object. It is the foundation for future multi-workstream
operation, not the final multi-workstream system by itself.
