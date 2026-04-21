# B26.3 GO / NO-GO

## GO criteria

- One canonical next-run proposal can be approved and dispatched
- The dispatched run is bound back into the same study
- The study update and continuation state are persisted
- The same Beagle-owned identity is preserved where applicable
- Restart remains coherent
- Cluster health remains green
- Slurm health remains green

## NO-GO criteria

- The proposal cannot be turned into a real run
- The study identity fragments across the dispatch path
- Restart loses the proposal, run update, or continuation state
- The dispatch path requires a redesign of the backplane
- The phase drifts into an unconstrained autonomous loop
