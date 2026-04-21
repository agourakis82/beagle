# B23.3 — GO / NO-GO

## GO

- a canonical memory compiler contract is explicit and queryable
- at least three distinct budget profiles are explicit and queryable
- compiled context packets differ meaningfully by task profile
- workstream/program context and tool launch metadata surface compiled context
- subagent handoff propagation preserves compiled context hints when present
- the same Beagle-owned identity is preserved
- restart remains coherent
- cluster stays green
- `Slurmctld(primary)` stays `UP`

## NO-GO

- the compiler is only documented and not live
- budget selection remains implicit or task-agnostic
- compiled context packets do not differ across task profiles
- context or handoff surfaces lose compiled context metadata
- restart drops compiled context coherence
- cluster or Slurm health regresses
