# B20.5 — GO / NO-GO

## GO Criteria

`B20.5 = GO` only if:

- one-gesture launch/resume works from the Beagle-owned control surface
- the same `workstream_id`, `workspace_id`, and `session_id` are preserved
- the same handoff/context packet are available immediately on resume
- Cursor and browser fallback remain coherent
- restart remains coherent
- cluster remains green
- `Slurmctld(primary)` remains `UP`

## No-Go Conditions

Do not promote if:

- launch/resume is only a renamed copy of `managed-attach`
- a second canonical workspace identity is introduced
- Cursor gains a parallel state lane
- restart changes the canonical workspace/session identity
