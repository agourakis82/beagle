# B23.5 — Known Limits

- The compiler stays bounded and does not create a separate autonomous memory
  runtime.
- Temporal memory is carried as a compact truth slice and summary, not as a
  full historical dump.
- The compiler still relies on the already-live retrieval lanes and does not
  introduce a new embedding backend or reranker.
- GraphRAG remains bounded to the existing local/global/drift modes.
- Editorial/scientific readiness limits remain explicit and are not hidden by
  compiled context.
