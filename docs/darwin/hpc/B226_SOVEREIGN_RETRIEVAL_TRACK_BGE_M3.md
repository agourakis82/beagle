# B22.6 — Sovereign Retrieval Track with `BGE-M3`

## Objective

Add the first bounded sovereign retrieval lane on top of the canonical hybrid retrieval spine without changing:

- `Qdrant` as the canonical store direction
- `voyage-4-large` as the canonical general dense backend
- `voyage-code-3` as the bounded code retrieval pilot
- `local-lexical` as the sparse path
- the canonical memory payload and filter model

## What changes in this phase

1. Adds an explicit sovereign backend profile for `BGE-M3`.
2. Wires a self-hosted `text-embeddings-inference` runtime inside the cluster.
3. Preserves payload-aware filtering over:
   - `workstream_id`
   - `campaign_id`
   - `session_id`
   - `source`
   - `repo_path`
   - `file_type`
   - `tags`
4. Keeps comparison against the canonical `voyage-4-large` lane explicit.
5. Leaves the canonical general and code retrieval lanes untouched.

## Runtime states

- `sovereign-active`: the self-hosted `BGE-M3` lane is configured and serving live embeddings.
- `sovereign-endpoint-configured-fallback`: the lane is configured, but the self-hosted endpoint is not usable yet, so retrieval falls back to the lexical dense proxy.
- `sovereign-endpoint-missing-fallback`: no sovereign endpoint is configured, so retrieval falls back to the lexical dense proxy.

## Important boundary

This phase does not replace the canonical general dense backend.

The sovereign lane is intentionally bounded:

- it reuses the same canonical memory payload collection
- it keeps the sparse lexical path active
- it evaluates `BGE-M3` as a self-hosted multilingual dense path
- it does not introduce heavy reranking or a second retrieval control plane
