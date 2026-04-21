# B20.9 Known Limits

- The handoff is explicit and bounded; it is not autonomous multi-agent
  scheduling.
- The persisted handoff is `latest-handoff-per-workspace`, not a full cross-
  subagent conversation history.
- The target receives coherent Beagle context through the canonical handoff
  surface and shared workspace state; this phase does not introduce a separate
  subagent-local state owner.
