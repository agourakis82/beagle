# B24.4 — GO / NO-GO

`GO` requires:

- one canonical replan suggestion materializes into one `ReviewInboxItem`
- bounded `approve`, `edit`, and `reject` paths are supported
- one operator decision materializes one `FollowOnPlan`
- review state is visible in execution state, receipt, context, and handoff
- the same `workstream_id`, `workspace_id`, and `session_id` are preserved
- restart remains coherent
- cluster health stays green
- `Slurmctld(primary)` stays reachable

`NO-GO` if:

- inbox state is lost or detached from the execution identity
- follow-on plan materialization bypasses operator review
- review outcome is not projected into canonical context surfaces
- cluster or Slurm health regresses during proof
