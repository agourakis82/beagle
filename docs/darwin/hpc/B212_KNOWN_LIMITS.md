# B21.2 — Known Limits

- The assembly is bounded to one canonical campaign/workstream packet at a
  time; it is not a general editorial orchestration layer.
- The exported manuscript remains `JATS-ready`, not a submission pipeline.
- `readiness_state` intentionally stays honest. If human judgment is still
  pending for the campaign, the JATS artifact keeps that state.
- The assembly lives inside the same Beagle-owned workspace/session identity;
  it does not create external editorial state ownership.
- Attach remains governed by the already-closed B20 workspace stack; this phase
  does not add ingress, HA, or public distribution paths.
