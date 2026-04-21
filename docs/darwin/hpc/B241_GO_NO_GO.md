# B24.1 — GO / NO-GO

`GO` when all of the following are true:

- at least three task-family plans are generated
- each plan resolves subagent, retrieval lane, compiler profile, GraphRAG mode,
  and recipe or experiment target coherently
- workstream/program context and tool/subagent surfaces expose planner context
- the same Beagle-owned identity is preserved across the plans
- restart remains coherent
- cluster remains green
- `Slurmctld(primary)` remains `UP`

`GO-WITH-BLOCKER` if the planner runtime is live but one of the canonical task
families fails to resolve a bounded plan or a core integration surface drops the
planner metadata while the planner itself still works.

`STAGED / READY FOR LIVE SMOKE` if the planner compiles and tests repo-natively
but live artifact proof has not yet been completed.
