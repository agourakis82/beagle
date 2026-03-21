# B13.4 - Fallback Discipline Drill

## Current status

B13.4 is currently `GO-WITH-BLOCKER`.

The drill only closes after one live cluster run proves that VM fallback remains
explicit, bounded, recorded, and that the workspace returns cleanly to
Beagle/cluster as the default plane for the promoted scope.

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
