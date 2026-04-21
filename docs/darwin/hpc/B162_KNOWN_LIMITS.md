# B16.2 - Known Limits

- this phase introduces a portfolio read surface, not portfolio-wide mutation
- the portfolio remains bounded to the current canonical workstreams already in
  the registry
- the phase does not reopen bridge, result/object plane, ingress, edge, HA or
  topology
- this is an internal operator surface, not a public UI
- local host `cargo` exists, but the stronger compile proof remains the live
  container build path because the host MSRV still trails the repo lockfile

In other words, B16.2 is the first portfolio-level visibility step, not full
multi-workstream orchestration.
