# B20.4 — GO / NO-GO

`GO` only if all of the following are true:

- the managed attach path is live on the cluster
- the path reaches the same Beagle-owned workspace
- the same `workstream_id`, `workspace_id`, and `session_id` remain intact
- the managed SSH config is stable and reusable
- restart/recovery remain coherent
- cluster stays green
- `Slurmctld(primary)` stays `UP`

`NO-GO` if the result is only a renamed helper flow, if the managed path is not actually usable, or if identity coherence regresses.
