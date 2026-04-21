# B20.6 Known Limits

- The template-backed workspace is still private/internal and cluster-scoped.
- Warm start is currently PVC-backed and hydrated by the existing workspace bootstrap path, not by a separate image-layer prebuild pipeline.
- External-workspace compatibility is bounded to coder-compatible metadata and registration shape; this phase does not introduce a full external control plane.
- The Beagle-owned workspace remains canonical; no external client becomes a state owner.
