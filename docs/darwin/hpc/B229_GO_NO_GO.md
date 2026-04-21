# B22.9 — GO / NO-GO

## GO if

- retrieval evaluation output is explicit for `general`, `code`, and `sovereign`
- the relevance feedback loop is live and auditable
- at least one feedback case improves relevance proxy or top-k ordering
- `retrieval-policy.json` carries evidence-backed lane decisions
- restart preserves the same `workstream_id`, `workspace_id`, and `session_id`
- cluster stays green
- `Slurmctld(primary)` stays up

## NO-GO if

- policy remains heuristic-only with no live evidence basis
- feedback silently mutates canonical state outside the request/response path
- payload filters stop constraining results after feedback
- the loop requires reopening the retrieval spine or store architecture
