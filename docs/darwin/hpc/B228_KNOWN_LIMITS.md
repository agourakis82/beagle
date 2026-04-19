# B22.8 — Known Limits

- Reranking stays bounded to the routed top-k shortlist in this phase.
- `code` retrieval remains prerank-only; code reranking is not made canonical here.
- `local-lexical` remains the complementary sparse path; this phase does not change sparse retrieval.
- `Voyage rerank-2.5-lite` stays documented as a latency fallback candidate, not the promoted default.
- The sovereign reranker is self-hosted but still bounded as a pilot lane, not a global mandatory stage.
- The active sovereign reranker trial is now
  `Alibaba-NLP/gte-reranker-modernbert-base` on the self-hosted TEI CPU lane.
- The trial materially improved bounded sovereign rerank latency versus the
  earlier `bge-reranker-v2-m3` and `gte-multilingual-reranker-base` paths, but
  it should still stay sovereign-only until the reporting contract tells the
  truth and the lane is soaked under longer live traffic.
- The current backend reporting still leaks some old `bge-reranker-v2-m3`
  identity in pilot metadata even after the runtime was switched, so runtime
  measurements and direct sovereign reranker health checks should be treated as
  the source of truth until the reporting strings are updated.
