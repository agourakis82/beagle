# B16.2 - Portfolio Control Room

## Current status

B16.2 is `GO`.

Target surface:

- `GET /api/darwin/portfolio/workstreams`

Planned deliverables for this phase:

- `docs/darwin/hpc/B162_PORTFOLIO_CONTROL_ROOM.md`
- `docs/darwin/hpc/B162_GO_NO_GO.md`
- `docs/darwin/hpc/B162_KNOWN_LIMITS.md`
- `scripts/infrastructure/darwin-hpc/run_portfolio_control_room_smoke.sh`
- `scripts/infrastructure/darwin-hpc/validate_portfolio_control_room_smoke.sh`

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/portfolio-control-room/`

Canonical live run:

- `run_id=b162-portfolio-0322100055`

## Objective

Create the first internal portfolio control-room surface so the operator can
see both canonical workstreams from one Beagle-owned read view without
reopening lower layers.

The portfolio view must aggregate, per workstream:

1. governance state
2. live session/status
3. handoff presence
4. last-result reference
5. latest activity from the timeline

## Scope

Included:

- one portfolio-level read surface
- aggregation over the existing canonical workstreams
- coherence checks across control room, handoff, last-result and timeline views
- restart/recovery proof that the portfolio view remains stable

Out of scope:

- broad mutation surfaces
- new infra
- ingress/edge
- HA
- provider expansion
- topology changes

## Success condition

B16.2 closes as `GO` only after live proof that:

1. both canonical workstreams are visible in one portfolio response
2. their identities remain coherent against the underlying workstream surfaces
3. governance, handoff, result and latest activity remain coherent
4. restart does not scramble the portfolio view
5. cluster remains green
6. Slurm remains green

## Canonical proof

- portfolio surface: `GET /api/darwin/portfolio/workstreams`
- canonical workstreams visible together:
  - `beagle-darwin-hpc-governance`
  - `beagle-darwin-hpc-wave1`
- aggregated live envelopes:
  - governance: `workspace_id=b154-0322075224`, `session_id=ws-20260322105541`
  - wave1: `workspace_id=b161-wave1-0322082253`, `session_id=ws-20260322112605`
- portfolio summary was coherent:
  - `total_workstreams=2`
  - `canonical_workstreams=2`
  - `live_sessions=2`
  - `handoff_ready_workstreams=2`
  - `result_ready_workstreams=2`
  - `fallback_active_workstreams=0`
- latest activity for both workstreams replayed as `recovery_bootstrap`
- restart preserved the same workstream/session identities in the portfolio
- cluster stayed green and `Slurmctld(primary)` remained `UP`
