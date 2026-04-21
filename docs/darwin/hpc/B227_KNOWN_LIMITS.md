# B22.7 — Known Limits

- Query typing is heuristic and bounded; it is not a learned classifier.
- `local-lexical` remains the only sparse path in this phase.
- Heavy reranking and late interaction remain intentionally disabled.
- The router selects between existing lanes; it does not introduce a new retrieval store or a new
  control plane.
- Code and sovereign lanes remain bounded pilots/tracks even though they are now routable.
