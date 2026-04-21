# B23.1 — GO / NO-GO

## GO if

- memory hierarchy is explicit and serialized as `episodic`, `semantic`, and `procedural`
- GraphRAG works in bounded form over canonical Beagle entities
- context packets expose usable GraphRAG metadata
- the same `workstream_id`, `workspace_id`, and `session_id` remain coherent
- restart preserves graph-aware retrieval behavior
- cluster stays green
- `Slurmctld(primary)` stays up

## NO-GO if

- hierarchy remains implicit or heuristic-only with no explicit artifact
- GraphRAG requires a new graph database or parallel canonical store
- payload-aware retrieval filters stop constraining the supporting records
- context packets lose coherence or identity continuity after restart
