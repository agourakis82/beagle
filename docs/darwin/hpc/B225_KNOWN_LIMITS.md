# B22.5 — Known Limits

- The code pilot does not reindex the canonical Qdrant collection with `voyage-code-3`.
- The dense code lane evaluates the same payload records locally to avoid cross-model vector mismatch.
- Heavy reranking remains intentionally disabled.
- This phase does not yet promote `voyage-code-3` to the canonical general dense backend.
