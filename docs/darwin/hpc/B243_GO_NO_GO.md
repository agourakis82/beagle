# B24.3 — GO / NO-GO

`GO` when:

- one canonical execution emits `reflection`, `trajectory eval`, and `replan suggestion`
- execution receipt carries bounded quality and replan metadata
- workstream/program context and handoff remain coherent after reflection
- the same Beagle-owned identity is preserved
- restart remains coherent
- cluster and Slurm remain green

`NO-GO` when:

- reflection artifacts are missing
- trajectory eval is not auditable
- replanning becomes autonomous instead of operator-facing
- receipts/context lose identity continuity
