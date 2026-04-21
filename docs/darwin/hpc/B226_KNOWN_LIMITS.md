# B22.6 — Known Limits

- The canonical general dense backend remains `voyage-4-large`; `BGE-M3` is a bounded sovereign lane, not the default general backend.
- The canonical code retrieval pilot remains `voyage-code-3`.
- The sovereign lane still reuses the canonical payload collection and local candidate-record path; this phase does not reindex a separate Qdrant collection.
- Heavy reranking remains intentionally disabled.
- The self-hosted embedding runtime is cluster-internal and single-replica in this phase.
