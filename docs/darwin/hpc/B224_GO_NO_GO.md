# B22.4 GO / NO-GO

## GO

- workstream context packet contains explicit retrieval context
- program/campaign context packet contains explicit retrieval context
- tool dock launch metadata is retrieval-aware
- at least one subagent route is selected via `retrieval-context`
- handoff propagation carries retrieval-aware context
- restart preserves `workstream_id`, `workspace_id`, and `session_id`
- cluster remains healthy
- `Slurmctld(primary)` remains `UP`

## NO-GO

- retrieval remains invisible in the launch surfaces
- routing never uses retrieval guidance
- handoff drops retrieval context
- restart loses retrieval-aware state or identity
- cluster or Slurm health regresses
