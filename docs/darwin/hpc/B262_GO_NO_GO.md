# B26.2 GO / NO-GO

## GO when

- A canonical study can produce a bounded study decision
- The decision names an explicit recommended action
- The decision can generate a next-run proposal
- The decision basis is explicit and auditable
- The same Beagle-owned identity remains preserved
- Restart remains coherent
- Cluster health stays green
- Slurm health stays green

## NO-GO when

- The decision engine cannot read the canonical study state
- The next-run proposal cannot be derived from the same study
- Identity preservation is lost
- The runtime starts auto-launching the proposal
- The decision layer drifts into a full workflow engine

