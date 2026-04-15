# B13.4 - Fallback Discipline Drill

## Current status

B13.4 is currently `GO`.

Canonical drill evidence lives under:

- `.artifacts/darwin-hpc/fallback-discipline-drill/bootstrap-after-deploy.json`
- `.artifacts/darwin-hpc/fallback-discipline-drill/fallback-enter.json`
- `.artifacts/darwin-hpc/fallback-discipline-drill/fallback-return.json`
- `.artifacts/darwin-hpc/fallback-discipline-drill/bridge-execute.json`
- `.artifacts/darwin-hpc/fallback-discipline-drill/smoke.json`
- `.artifacts/darwin-hpc/fallback-discipline-drill/session-after-restart.json`
- `.artifacts/darwin-hpc/fallback-discipline-drill/final-cluster-health.txt`

## Objective

Prove fallback discipline for the already-promoted scope:

1. Beagle remains the default working plane
2. VM fallback is explicit, bounded and recorded
3. return to the canonical Beagle plane is explicit and recorded
4. session, handoff and ledger remain coherent
5. cluster and Slurm remain green

## Scope

This phase applies only to the already-promoted scope:

- repo: `agourakis82/beagle`
- branch: canonical active branch on the workspace plane
- promotion scope: `beagle-darwin-hpc-small-medium`
- default plane: `beagle-cluster`
- VM role: `fallback-only`

## Runtime shape

The drill reuses the existing Beagle surface plus one bounded fallback control:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `POST /api/darwin/workspace/fallback/start`
- `POST /api/darwin/workspace/fallback/return`
- `POST /api/darwin/bridge/execute`
- `GET /api/darwin/hpc/control`
- `GET /api/darwin/hpc/results`

## Architectural decision

- fallback discipline is modeled inside the workspace plane itself, not as an
  undocumented operator habit
- fallback events are recorded in session state and an append-only JSONL ledger
  under `BEAGLE_DATA_DIR`
- the drill remains short and explicit; it does not attempt to make VM a real
  concurrent control plane
- the proof comes from live runtime state before, during and after fallback

## Placement

- workspace/runtime state: `crates/beagle-darwin/src/workspace_plane.rs`
- internal HTTP surface: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_fallback_discipline_drill.sh`

## Success condition

The phase closes when:

1. fallback start is explicit and recorded
2. fallback return is explicit and recorded with duration
3. the workspace returns to `beagle-cluster` as active plane
4. handoff and ledger both preserve the fallback reason and return
5. the same session remains coherent after restart
6. cluster remains green
7. Slurm remains green

## Live result

The validated drill proved that VM stays bounded and explicit for the promoted
scope:

- workspace `b134-0321073224` bootstrapped on repo `agourakis82/beagle` and
  branch `feat/darwin-hpc-governance` with active plane `beagle-cluster`
- fallback start explicitly moved the live workspace state to
  `active_dev_plane=vm-fallback` with reason `bounded_vm_fallback_drill`
- fallback return explicitly moved the workspace back to
  `active_dev_plane=beagle-cluster` with reason `fallback_window_closed` and
  `duration_seconds=2`
- both fallback events were persisted in session state and in the append-only
  fallback ledger under `BEAGLE_DATA_DIR/workspace-plane/fallback_discipline_events.jsonl`
- one real `deepseek` cheap-lane request still completed cleanly after return
- the same session `ws-20260321103225` remained canonical after restart, with
  fallback history and return handoff preserved
