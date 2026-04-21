# B21.2 — GO / NO-GO

## GO criteria

`B21.2 = GO` only if:

- the `manuscript` subagent assembles a structured editorial artifact
- `claims`, `evidence`, `provenance`, `review_bundle`, and `jats_pack` remain
  explicitly linked
- the output is `JATS-ready`
- `readiness_state` stays honest
- restart preserves the same `workstream/workspace/session`
- cluster remains green
- `Slurmctld(primary)` remains `UP`

## NO-GO conditions

`B21.2 != GO` if:

- assembly mints a parallel workspace/session identity
- JATS output exists but breaks claim/evidence/provenance linkage
- restart loses the latest bounded assembly record
- the run depends on hiding unresolved human-eval gaps
