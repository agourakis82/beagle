# B12.7 Known Limits

## Current limits

- the richer operator workflow is still single-profile and single-workspace at
  a time
- `cpu-batch-v1` is the chosen next step; GPU remains out of scope as the
  primary operator flow for now
- operator context remains metadata-first; the Beagle pod is not a full IDE or
  live git checkout
- the pilot reuses the current HPC/result/bridge backplane and does not change
  lower-layer semantics
- result resolution still reuses the current published object-plane results
  rather than materializing a new publication path in this phase

## Interpretation

This phase is about proving one richer but still stable operator workflow on
top of the current Beagle stack, not about broadening topology, providers or
self-service.
