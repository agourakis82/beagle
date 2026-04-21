# B24.15 GO / NO-GO

## GO When

- `implementation` still resolves to the live canary lane
- `analysis` still resolves to the live canary lane
- `manuscript` still resolves to the explicit control lane
- bounded manuscript sample-accumulation artifacts are materialized on the same Beagle-owned identity
- the promotion gate recheck emits one of `keep-shadow`, `stage-manuscript-canary`, or `rollback-shadow`
- cluster health stays green
- Slurm stays green

## NO-GO When

- `implementation` falls off canary during the manuscript recheck
- `analysis` falls off canary during the manuscript recheck
- `manuscript` moves live without an explicit promotion-gate recheck
- workstream/workspace/session identity diverges across the B24.15 accumulation artifacts
- the manuscript gate becomes implicit or stops surfacing rollback/hold conditions
