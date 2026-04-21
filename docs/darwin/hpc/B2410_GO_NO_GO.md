# B24.10 GO / NO-GO

## GO When

- implementation still resolves to the live canary lane
- manuscript still resolves to the control lane
- analysis shadow artifacts are materialized on the same Beagle-owned identity
- the analysis decision is one of `keep-shadow`, `stage-analysis-canary`, or `rollback-shadow`
- cluster health stays green
- Slurm stays green

## NO-GO When

- analysis is moved live without a bounded decision artifact
- manuscript leaves control
- implementation canary disappears or silently falls back without an explicit rollback decision
- workstream/workspace/session identity diverges across artifacts
