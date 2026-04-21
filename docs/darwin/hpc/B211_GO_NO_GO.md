# B21.1 GO / NO-GO

## GO
- `manuscript` subagent is live inside the same canonical workspace
- `work_mode=manuscript` routes to `manuscript`
- explicit `experiments -> manuscript` handoff succeeds
- `claims`, `evidence`, and `manuscript_pack` remain coherent
- restart preserves the same Beagle-owned session identity
- cluster remains green
- `Slurmctld(primary)` remains `UP`

## NO-GO
- manuscript routing mints a parallel workspace or session
- manuscript handoff loses upstream handoff continuity
- campaign artifacts disagree on `campaign_id`
- restart loses handoff, session identity, or manuscript target coherence
- cluster health or Slurm health regresses
