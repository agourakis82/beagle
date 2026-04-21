# B24.12 GO / NO-GO

## GO When

- implementation still resolves to the live canary lane
- manuscript still resolves to the control lane
- bounded analysis sample-accumulation artifacts are materialized on the same Beagle-owned identity
- the promotion gate recheck emits one of `keep-shadow`, `stage-analysis-canary`, or `rollback-shadow`
- cluster health stays green
- Slurm stays green

## NO-GO When

- analysis moves live without an explicit promotion-gate recheck
- manuscript leaves control
- implementation canary disappears or silently degrades
- workstream/workspace/session identity diverges across the B24.12 accumulation artifacts
