# B22.7 — GO / NO-GO

## GO if

- the router classifies queries into at least `general`, `code`, and `sovereign`
- the routing decision selects:
  - `voyage-4-large` for general retrieval
  - `voyage-code-3` for code retrieval
  - `bge-m3` for sovereign retrieval
- payload-aware filters still constrain routed retrieval results
- routed retrieval context appears in the canonical workstream/program context packets
- restart preserves the same `workstream_id`, `workspace_id`, and `session_id`
- cluster stays green
- `Slurmctld(primary)` stays up

## NO-GO if

- routing silently falls back to one backend for every query class
- payload filters stop constraining routed results
- context packets lose coherence or identity stability
- the router forces a retrieval-store migration or a reranking stage
