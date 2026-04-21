# B15.2 Known Limits

## Current limits

- this phase is constitutional, not encyclopedic; it does not attempt to
  describe every crate or every historical path in the monorepo
- the charter reflects the current one-workstream kernel, not a multi-workstream
  portfolio yet
- the constitution is repo-native and consistency-checked locally; it is not a
  new runtime authority surface by itself
- the external Darwin HPC gateway remains outside this repo's deployment
  authority, even though it is part of the current compute/result operating path
- the internal control room remains internal and query-first; B15.2 does not
  widen into public UI or mutation-heavy workflow control
- host `cargo` exists, but the local host Rust toolchain
  (`cargo/rustc 1.85.0`) remains below the current repo lockfile MSRV for some
  dependencies; live container builds remain the stronger compile proof for
  runtime code

## Interpretation

B15.2 gives the project a constitutional layer that matches the already-proven
operational kernel. It does not replace the technical contracts, smokes or
runtime modules below it; it tells them what project they belong to and what
regressions are no longer acceptable.
