# B22.1 Known Limits

- Dense retrieval prefers Qdrant when configured; otherwise it falls back to a bounded local dense proxy over the same local memory store.
- Sparse retrieval is lexical and intentionally bounded in this phase.
- Named vectors are not turned on yet.
- Reranking is not elevated beyond a narrow placeholder hook in this phase.
- This phase does not reopen publication, DOI, Crossref, or DataCite work.
- This phase does not change the current `claim-linked-human-eval-pending` state where it already applies elsewhere in the stack.
