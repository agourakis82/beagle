# B16.2 - GO / NO-GO

## Current gate

B16.2 is `GO`.

Canonical promotion evidence:

1. `run_id=b162-portfolio-0322100055`
2. `GET /api/darwin/portfolio/workstreams` returned both canonical workstreams
3. portfolio entries matched the underlying status/handoff/last-result/timeline
   surfaces coherently
4. restart preserved:
   - `ws-20260322105541` for governance
   - `ws-20260322112605` for wave1
5. live validator passed on `.artifacts/darwin-hpc/portfolio-control-room/`

## GO conditions

B16.2 may promote to `GO` only if the live smoke proves all of the following:

1. `GET /api/darwin/portfolio/workstreams` returns `ok`
2. both canonical workstreams appear in the same portfolio response
3. portfolio entries match their underlying status/handoff/last-result/timeline
   surfaces coherently
4. restart preserves the same workstream/session identities already visible in
   the portfolio
5. cluster remains green
6. `Slurmctld(primary)` remains `UP`

## NO-GO conditions

B16.2 remains below `GO` if any of the following occur:

1. one of the canonical workstreams disappears from the portfolio view
2. the portfolio view reports mismatched identity or governance state
3. restart changes the live workstream/session identity without explanation
4. cluster or Slurm degrade during the drill

## Promotion note

The portfolio surface was promoted only after the live smoke completed and
`validate_portfolio_control_room_smoke.sh` passed against the captured
artifacts.
