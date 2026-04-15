# B12.6 Known Limits

## Current limits

- operator context is still metadata-first; the Beagle pod does not become a
  full IDE or live git checkout
- one canonical operator-real pilot is validated at a time
- broader multi-repo and multi-operator orchestration remain out of scope
- the pilot reuses the current HPC/result/bridge backplane and does not change
  lower-layer semantics
- VM-based development can still exist as support, but the workspace plane now
  preserves richer operator state instead of depending on a transient shell

## Interpretation

This phase is about making the workspace plane operationally faithful to one
real operator flow, not about turning Beagle into a broad self-service platform
or reopening the already-closed lower layers.
