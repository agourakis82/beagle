# B15.1 - Internal Workstream Control Room

## Current status

B15.1 is `GO`.

Canonical live control-room workspace:

- `b151-0321212135`

Canonical deliverables for this phase:

- `crates/beagle-darwin/src/workstream_control_room.rs`
- `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- `scripts/infrastructure/darwin-hpc/run_internal_workstream_control_room_smoke.sh`
- `scripts/infrastructure/darwin-hpc/validate_internal_workstream_control_room_smoke.sh`

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/internal-workstream-control-room/bootstrap-before.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/seed-pilot.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/workstreams-list.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/workstream-detail.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/workstream-recipes.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/workstream-status.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/workstream-last-result.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/workstream-handoff.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/workstream-hold.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/workstream-resume.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/smoke.json`
- `.artifacts/darwin-hpc/internal-workstream-control-room/final-cluster-health.txt`

## Objective

Create the first internal control-room surface for the canonical workstream:

1. expose the canonical workstream through one Beagle-native operator surface
2. consolidate registry/spec, recipes, governance, handoff and last-result state
3. keep the surface internal and bounded to the already-cut-over workstream
4. avoid reopening lower layers, ingress, edge, HA or provider expansion

## Target surface

The first internal control-room surface is:

1. `GET /api/darwin/workstreams`
2. `GET /api/darwin/workstreams/{id}`
3. `GET /api/darwin/workstreams/{id}/recipes`
4. `GET /api/darwin/workstreams/{id}/status`
5. `GET /api/darwin/workstreams/{id}/last-result`
6. `GET /api/darwin/workstreams/{id}/handoff`

Bounded action endpoints are surfaced explicitly but remain disabled in this
phase:

1. `POST /api/darwin/workstreams/{id}/hold`
2. `POST /api/darwin/workstreams/{id}/resume`

## Architectural decision

- the control room is query-first; it does not introduce a new orchestration
  engine or public UI
- canonical workstream docs remain repo-native and are compiled into the
  service so the internal surface can run inside the cluster runtime image
- live state is resolved from the existing workspace/session plane and result
  plane, not from a new persistence layer
- governance mutation remains bounded to the explicit governance drill path
  already proven in `B14.4`

## Success condition

The phase is now closed because:

1. one internal control-room surface exists
2. the canonical workstream is visible and queryable there
3. recipes, governance, handoff and result state are consolidated there
4. cluster remains green
5. Slurm remains green

## Live result

The first internal workstream control room closed as `GO`.

Live proof from workspace `b151-0321212135`:

1. `GET /api/darwin/workstreams` exposed the canonical workstream
   `beagle-darwin-hpc-governance`
2. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance` consolidated
   registry entry, workstream spec, recipe set, governance status and handoff
   state in one surface
3. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/recipes`
   resolved all four canonical recipes
4. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/status` exposed
   the live seeded session `ws-20260322002454` on
   `default_dev_plane=beagle-cluster` with `fallback_active=false`
5. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/last-result`
   resolved published result `31` and its manifest through the control-room
   surface
6. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/handoff`
   preserved a real non-empty handoff from the seeded CPU workflow
7. bounded `hold` and `resume` endpoints were surfaced explicitly and returned
   `501`, keeping governance mutation out of scope for this phase
8. cluster remained green and `Slurmctld(primary)` remained `UP`
