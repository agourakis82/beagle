# B24.6 — GO / NO-GO

`GO` requires:

- one canonical gating policy exists
- at least one follow-on plan is classified by policy
- bounded `auto-continue`, `review-required`, and `blocked` classes exist in code and contracts
- the gate stays linked to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`
- restart remains coherent after gating
- cluster health stays green
- `Slurmctld(primary)` stays reachable

`NO-GO` if:

- gating creates a second canonical state plane outside Beagle
- continuation dispatch ignores a `blocked` decision
- low-risk auto-continue becomes an unbounded autonomous loop
- operator-visible review and readiness limits disappear from canonical surfaces
- cluster or Slurm health regresses during proof
