# B15.4 Operator Timeline / Audit Replay GO / NO-GO

## Current status

B15.4 is `GO`.

## GO criteria

B15.4 can move to `GO` only if the live smoke proves:

1. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/timeline`
   responds and returns an ordered internal timeline
2. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/timeline?limit=N`
   responds and returns the latest bounded window without changing identity
3. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/timeline/{event_id}`
   resolves a concrete event from that timeline
4. governance transitions, workflow completion, result reference, handoff
   evolution and recovery are all visible in order
5. the same workspace/session identity survives restart
6. cluster remains green
7. Slurm remains green

## NO-GO conditions

B15.4 remains `NO-GO` if any of the following happen:

1. the timeline surface is missing or returns incoherent event order
2. the timeline diverges from the Beagle-owned workspace/session identity
3. governance or recovery history disappears after restart
4. handoff or last-result references become unreadable or inconsistent
5. event detail replay fails for a timeline event that exists in the list view
6. cluster health regresses
7. Slurm health regresses

## Present decision

The live smoke and validator both passed.

Decision: `GO`.

Frozen live evidence:

1. workspace: `b154-0322075224`
2. session: `ws-20260322105541`
3. seeded profile: `cpu-batch-v1`
4. submitted job id: `58`
5. published result job id: `31`
6. timeline event count: `6`
7. bounded replay window: `hold -> resume -> recovery`
8. hold event id: `governance-transition-1774176954430-hold-1774176954430`
9. recovery event id: `recovery-bootstrap-1774176972175-b154-0322075224-3`
10. restart preserved the same session identity
11. cluster health remained green and `Slurmctld(primary)` stayed `UP`
