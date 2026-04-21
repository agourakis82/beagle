# B15.3 Control Room Actions GO / NO-GO

## Current status

B15.3 is `GO`.

## GO criteria

B15.3 can move to `GO` only if the live smoke proves:

1. `POST /api/darwin/workstreams/beagle-darwin-hpc-governance/hold`
   succeeds and moves the state to `held`
2. `POST /api/darwin/workstreams/beagle-darwin-hpc-governance/resume`
   succeeds and moves the state back to `canonical`
3. the same workspace id and session id remain intact across seed, hold,
   resume, and restart
4. handoff and last-result context stay coherent across the mutations
5. the bounded governance ledger records both actions explicitly
6. cluster remains green
7. Slurm remains green

## NO-GO conditions

B15.3 remains `NO-GO` if any of the following happen:

1. `hold` or `resume` diverges from the canonical Beagle-owned session identity
2. governance state fails to mutate or returns to the wrong state
3. handoff or last-result continuity breaks
4. the action ledger is missing or incomplete
5. restart loses the same session/workspace line
6. cluster health regresses
7. Slurm health regresses

## Present decision

The live smoke and validator both passed.

Decision: `GO`.

Frozen live evidence:

1. workspace: `b153-0322071243`
2. session: `ws-20260322101553`
3. seeded profile: `cpu-batch-v1`
4. submitted job id: `57`
5. published result job id: `31`
6. `hold` recorded `canonical -> held`
7. `resume` recorded `held -> canonical`
8. restart preserved the same session identity
9. cluster health remained green and `Slurmctld(primary)` stayed `UP`
