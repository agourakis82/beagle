# B12.5 Known Limits

## Current limits

- repo awareness is metadata-first; the Beagle pod does not host a live git
  checkout
- one canonical repo/branch pilot is validated at a time
- repo-aware metadata is persisted in the workspace plane, not injected into
  raw scheduler submit payloads outside the current HPC contract
- broader multi-repo orchestration remains out of scope
- the pilot reuses the current HPC/result/bridge backplane and does not change
  lower-layer semantics
- VM-based development can still exist as support, but the Beagle session now
  persists repo/branch context instead of relying on a transient local shell

## Interpretation

This phase is about making workspace recovery repo-aware on top of the live
Beagle backplane, not about turning the Beagle cluster service into a full IDE
or git hosting environment.
