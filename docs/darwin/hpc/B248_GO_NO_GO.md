# B24.8 — GO / NO-GO

`GO` requires:

- one explicit current-control policy exists
- one explicit candidate-shadow policy exists
- rollout metrics compare control vs candidate explicitly
- at least one guarded rollout decision is produced
- `implementation` is evaluated independently from `analysis` and `manuscript`
- rollback remains explicit
- the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id` are preserved
- restart remains coherent after rollout materialization
- cluster health stays green
- `Slurmctld(primary)` stays reachable

`NO-GO` if:

- the candidate policy replaces the control policy globally by default
- `analysis` or `manuscript` lose review coverage without evidence
- rollback is missing or implicit
- rollout state escapes the canonical Beagle execution record
- result links, execution summary, or context packet stop showing the rollout state
- cluster or Slurm health regresses during proof
