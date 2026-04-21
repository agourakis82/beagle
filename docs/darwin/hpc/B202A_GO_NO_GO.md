# B20.2a — GO / NO-GO

## GO

- native `Cursor` attach metadata is served by Beagle
- the workspace exposes a live `ssh` attach path on the same pod/PVC
- attach resolves the same `workstream_id`, `workspace_id`, and `session_id`
- restart preserves the same Beagle-owned envelope
- cluster stays green
- `Slurmctld(primary)` stays green

## NO-GO

- attach requires a parallel workspace or parallel state
- `ssh` attach is not live
- identity drifts across restart
- cluster health regresses
- Slurm health regresses
