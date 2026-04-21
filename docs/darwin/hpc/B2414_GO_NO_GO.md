# B24.14 GO / NO-GO

## GO

- `implementation` remains on live canary
- `analysis` remains on live canary
- `manuscript` is evaluated explicitly in shadow
- `manuscript-rollout-decision` is explicit and auditable
- the same `workstream_id`, `workspace_id`, and `session_id` are preserved
- cluster and Slurm remain green

## NO-GO

- manuscript shadow regression is detected against the current control lane
- rollout loses implementation or analysis canary retention
- rollback/hold cannot be materialized explicitly
- cluster or Slurm health degrades during evaluation
