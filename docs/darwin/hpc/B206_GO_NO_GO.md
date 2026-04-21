# B20.6 GO / NO-GO

## GO

- one canonical `workspace-template` surface exists
- the same Beagle-owned workspace is reproducible through the template contract
- the workspace starts warm from the hydrated PVC-backed snapshot path
- `workstream_id`, `workspace_id`, and `session_id` remain coherent
- restart remains coherent
- cluster remains green
- `Slurmctld(primary)` remains `UP`

## NO-GO

- template metadata exists only on paper
- warm start depends on a second canonical workspace path
- restart changes identity
- cluster or Slurm health regresses
