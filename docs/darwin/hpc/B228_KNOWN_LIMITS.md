# B22.8 — Known Limits

- Reranking stays bounded to the routed top-k shortlist in this phase.
- `code` retrieval remains prerank-only; code reranking is not made canonical here.
- `local-lexical` remains the complementary sparse path; this phase does not change sparse retrieval.
- `Voyage rerank-2.5-lite` stays documented as a latency fallback candidate, not the promoted default.
- The sovereign reranker is self-hosted but still bounded as a pilot lane, not a global mandatory stage.
- The sovereign reranker is now live again, but its observed latency is still
  high enough that it should remain a sovereign-only specialist lane until a
  materially faster model or export is validated.
