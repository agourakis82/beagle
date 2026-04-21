# B24.7 — GO / NO-GO

`GO` requires:

- one canonical calibration dataset exists
- policy performance is measured explicitly in a canonical eval report
- threshold recommendations are produced in bounded `shadow-only` form
- at least one `auto-continue`, one `review-required`, and one `blocked` class are evaluated
- calibration stays linked to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`
- restart remains coherent after calibration materialization
- cluster health stays green
- `Slurmctld(primary)` stays reachable

`NO-GO` if:

- calibration mutates the live `B24.6` gate without operator review
- threshold recommendations create a second canonical state plane outside Beagle
- calibration hides readiness limits from downstream scientific or editorial layers
- result links, execution summary, or context packet stop showing the calibration state
- cluster or Slurm health regresses during proof
