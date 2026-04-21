# B24.2 GO / NO-GO

`GO` when:

- one canonical plan is approved before execution
- one bounded execution reaches a terminal state with explicit transitions
- receipt and result links are preserved
- context/tool/route/handoff surfaces reflect the execution summary
- workstream/workspace/session identity stays unchanged
- restart remains coherent
- cluster stays green
- Slurm stays green

`NO-GO` when:

- execution can start without approval
- execution state is implicit or not auditable
- result links cannot be traced back into Beagle-owned surfaces
- handoff continuity breaks
