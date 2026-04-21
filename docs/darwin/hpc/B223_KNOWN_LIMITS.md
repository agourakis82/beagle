# B22.3 — Known Limits

- The canonical dense backend contract now targets `voyage-4-large`, but live activation still depends on a valid `VOYAGE_API_KEY` or `BEAGLE_MEMORY_EMBEDDING_API_KEY`.
- The cluster did not have `QDRANT_URL` configured during the canonical B22.3 run, so store direction remains Qdrant-compatible by contract, while the live run still uses `local-memory-index`.
- Heavy reranking remains intentionally disabled in this phase.
- `voyage-code-3` and `bge-m3` are documented candidate tracks, not active canonical backends.
- This phase does not migrate away from Qdrant and does not introduce a new retrieval control plane.
