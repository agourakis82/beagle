# B23.3 — Known Limits

- The compiler is intentionally bounded and summary-oriented. It compiles a
  task-aware slice from existing retrieval, GraphRAG, and memory hierarchy
  layers rather than creating a long-running autonomous memory planner.
- Budget allocation is profile-based, not learned online. Evidence-backed
  policy learning already exists in retrieval, but this phase does not yet make
  budget weights self-optimizing.
- The compiled context packet carries a concise preview and top memory ids, not
  a full dump of every supporting object.
- The compiler uses the existing routed retrieval and GraphRAG stack. It does
  not add a new backend, a new reranker, or a new graph runtime.
- Editorial and scientific readiness limits remain explicit. This phase does
  not change any `human-eval-pending` honesty boundaries in manuscript or
  release lanes.
