# B20.3 — GO / NO-GO

## GO

- canonical workspace attach metadata is served by Beagle
- the helper-managed attach plane works on the same workspace
- the same `workstream_id`, `workspace_id`, and `session_id` remain visible through helper-based
  attach
- restart preserves the same Beagle-owned envelope
- cluster stays green
- `Slurmctld(primary)` stays green

## NO-GO

- the attach helper creates parallel state
- attach metadata is unstable or incomplete
- attach identity drifts across restart
- cluster health regresses
- Slurm health regresses
