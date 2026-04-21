# B23.5 — GO / NO-GO

`GO` when all of the following are true:

- the compiler contract is live and names task profiles, temporal truth views,
  and bounded source kinds
- at least three distinct budget profiles are live and materially different
- compiled contexts differ across implementation, analysis, and manuscript
  work
- compiled context includes temporal truth in bounded form
- workstream/program context, tool launch metadata, and subagent handoff all
  carry compiled context
- restart remains coherent
- cluster remains green
- `Slurmctld(primary)` remains `UP`

`GO-WITH-BLOCKER` if the compiler is live but temporal context is not
materially carried into compiled packets or one of the integration surfaces
fails while the core compiler still works.

`STAGED / READY FOR LIVE SMOKE` if the repo-native compiler changes compile and
test but live artifact proof has not yet been completed.
