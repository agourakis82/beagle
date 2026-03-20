# B12.4 Known Limits

## Current limits

- the workspace plane is metadata-first; it does not mount a live repo checkout
  into the Beagle pod
- the pilot is operator-facing and internal-only; there is no public workspace
  UI
- one canonical workspace pilot is validated at a time; broader self-service
  remains out of scope
- the workflow pilot reuses the current HPC/result/bridge backplane and does not
  change lower-layer semantics
- VM-based development can still exist as support, but it is no longer the only
  place where session/handoff continuity is recorded

## Interpretation

This phase is about making workspace continuity real on top of the Beagle
backplane, not about turning Beagle into a full IDE or repo-hosting platform
inside the cluster.
