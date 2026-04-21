# B15.1 Known Limits

## Current limits

- the control room is bounded to one canonical workstream only:
  `beagle-darwin-hpc-governance`
- the phase is query-first; `hold` and `resume` endpoints are surfaced
  explicitly but remain disabled in `B15.1`
- the registry/spec/recipe layer is compiled into the service for cluster use;
  a future phase can decide whether live doc reloading is worth introducing
- multi-workstream portfolio control remains out of scope
- host `cargo` exists, but the local host Rust toolchain
  (`cargo/rustc 1.85.0`) remains below the current repo lockfile MSRV for some
  dependencies; live container builds remain the stronger compile proof

## Interpretation

B15.1 is the first internal control-room layer for the canonical workstream. It
proves consolidated operator visibility without widening the product surface or
reopening the backplane, but it is not yet a multi-workstream mission control.
