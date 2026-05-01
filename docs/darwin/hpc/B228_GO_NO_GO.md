# B22.8 — GO / NO-GO

## GO if

- the reranking profile is live as `b228-bounded-reranking-pilot`
- the general reranking lane uses `voyage-rerank-2.5`
- the sovereign reranking lane uses `Alibaba-NLP/gte-reranker-modernbert-base`
- prerank/postrank comparison is explicit
- payload-aware filters still constrain results after reranking
- reranking context appears in the canonical workstream/program context packets
- restart preserves the same `workstream_id`, `workspace_id`, and `session_id`
- cluster stays green
- `Slurmctld(primary)` stays up

## NO-GO if

- reranking silently replaces the dense lanes instead of layering on top of them
- payload filters stop constraining the candidate set
- reranking is forced globally across every lane
- context packets lose coherence or identity stability
- the sovereign reranking runtime never becomes live
