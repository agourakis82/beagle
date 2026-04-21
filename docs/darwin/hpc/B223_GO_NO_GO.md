# B22.3 — GO / NO-GO

## GO

B22.3 is `GO` only if:

1. the dense backend contract promotes `voyage-4-large`
2. the canonical retrieval spine reports `runtime_state=promoted-active`
3. payload-aware filters still work
4. the sparse lexical path still works
5. retrieval still feeds at least one context-packet surface
6. restart remains coherent
7. cluster stays green
8. `Slurmctld(primary)` stays `UP`

## GO-WITH-BLOCKER

B22.3 is `GO-WITH-BLOCKER` if:

1. the dense backend contract is correctly promoted
2. the runtime remains on fallback because provider auth or endpoint readiness is missing
3. the retrieval spine, filters, sparse path, and context packet remain coherent
4. restart, cluster, and Slurm stay green

## NO-GO

B22.3 is `NO-GO` if:

- the dense backend contract is missing or inconsistent
- payload-aware filters regress
- the sparse path regresses
- context-packet integration regresses
- restart coherence regresses
- cluster or Slurm regress
