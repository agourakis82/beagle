# B18.3 — Known Limits

Status: GO

## Current Limits

- this phase proves one bounded three-step loop; it does not open arbitrary
  long-running tool orchestration
- handoff accumulation remains string-based and bounded; it does not yet evolve
  into a structured per-step handoff object
- memory query proves useful sequence recovery, not perfect chronological replay
- the canonical ordering proof still comes from the append-only ledger, not from
  a dedicated multi-step timeline surface
- the strong compile proof remains the containerized Rust 1.89 path because the
  host toolchain is still below the repo MSRV
