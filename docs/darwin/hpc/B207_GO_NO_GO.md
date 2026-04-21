# B20.7 — GO / NO-GO

## GO criteria

- the same Beagle-owned workspace exposes at least two live sub-agents
- `core` and `experiments` remain role-separated without changing workspace identity
- restart preserves the same `workstream_id`, `workspace_id`, and `session_id`
- cluster stays green
- `Slurmctld(primary)` stays UP

## GO decision

`GO` only if both sub-agents are live, accessible, and restart-coherent.
