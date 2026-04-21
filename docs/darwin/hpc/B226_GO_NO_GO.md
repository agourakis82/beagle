# B22.6 — GO / NO-GO

## GO

B22.6 is `GO` only if:

1. the sovereign backend profile reports `backend_id=bge-m3`
2. the sovereign runtime reports `runtime_state=sovereign-active`
3. payload-aware filters still work
4. comparison against the canonical general dense lane is explicit
5. restart remains coherent
6. cluster stays green
7. `Slurmctld(primary)` stays `UP`

## GO-WITH-BLOCKER

B22.6 is `GO-WITH-BLOCKER` if:

1. the sovereign backend profile is correct
2. the endpoint is configured but the self-hosted runtime stays on fallback
3. payload-aware filters remain coherent
4. comparison remains explicit
5. restart, cluster, and Slurm remain green

## NO-GO

B22.6 is `NO-GO` if:

- the sovereign backend profile is missing or inconsistent
- payload-aware filters regress
- the sparse path regresses
- the comparison surface regresses
- restart coherence regresses
- cluster or Slurm regress
