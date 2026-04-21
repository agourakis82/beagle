# B18.2 — Known Limits

Status: GO

## Current Limits

- the return path is bounded to one payload per call; this phase does not open
  bulk writeback or arbitrary tool-side mutation
- writeback updates `last_handoff` as a canonical summary line; it does not
  patch structured recipe or governance objects directly
- repo refs and result refs are preserved canonically, but they are not yet
  replayed in the timeline surface
- latest physio remains best-effort on the return path; the canonical live run
  completed with `latest_physio=null` in the context packet after restart
- the strong compile proof remains the containerized Rust 1.89 path because the
  host toolchain is still below the repo MSRV
