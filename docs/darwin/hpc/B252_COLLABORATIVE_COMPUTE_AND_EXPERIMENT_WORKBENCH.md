# B25.2 — Collaborative Compute & Experiment Workbench

`B25.2` turns the already-live Beagle workspace, execution, retrieval, and
compute tenancy planes into one bounded collaborative workbench.

## Purpose

The goal of this phase is to stop making the operator stitch together:

- workspace identity
- VS Code / Cursor access
- subagent choice
- compute profile selection
- partner-dev access
- execution state
- result refs
- memory / retrieval context

Instead, Beagle exposes one explicit workbench surface that keeps the same
Beagle-owned `workstream/workspace/session` identity while remaining bounded
and operator-aware.

## Scope

- reuse the already-live workspace, tenancy, subagent, retrieval, and execution
  layers
- keep Beagle as the system of truth
- keep compute selection typed and quota-aware
- keep partner-dev access bounded to the intended workspace and profiles
- do not create a new autonomous scheduler or agent runtime

## Runtime Surfaces

- `GET /api/darwin/workstreams/{workstream_id}/collaborative-workbench`
- `GET /api/darwin/workstreams/{workstream_id}/workbench-session`
- `GET /api/darwin/workstreams/{workstream_id}/compute-selection`
- `GET /api/darwin/workstreams/{workstream_id}/collaboration-access`
- `GET /api/darwin/workstreams/{workstream_id}/workbench-run`

## Crate entry paths (B25.2)

Implementation remains in `collaborative_workbench.rs`. Narrow entry modules re-export the same types:

- `beagle_darwin::workbench` — umbrella bundle + builder
- `beagle_darwin::workbench_session` — session contract
- `beagle_darwin::compute_selection` — compute selection contract
- `beagle_darwin::collaboration_access` — collaboration access contract

## Contracts (YAML)

- `contracts/collaborative-workbench-schema.yaml` (umbrella)
- `contracts/workbench-session-schema.yaml`
- `contracts/compute-selection-schema.yaml`
- `contracts/collaboration-access-schema.yaml`
- `contracts/workbench-run-schema.yaml`

## Smoke scripts

- `scripts/infrastructure/darwin-hpc/run_collaborative_compute_experiment_workbench_smoke.sh` (full implementation)
- `scripts/infrastructure/darwin-hpc/run_collaborative_workbench_smoke.sh` (alias — same behaviour)
- `scripts/infrastructure/darwin-hpc/validate_collaborative_compute_experiment_workbench_smoke.sh`
- `scripts/infrastructure/darwin-hpc/validate_collaborative_workbench_smoke.sh` (alias)

## Canonical Output

The bounded workbench freezes four contracts:

- one workbench session contract
- one compute selection contract
- one collaboration access contract
- one run contract

Together they answer:

- which remote workspace the operator and partner-dev should use
- which clients can attach to the same Beagle-owned workspace
- which subagents are available and which one is currently recommended/live
- which bounded compute profiles are selectable right now
- which execution/result refs are active
- which retrieval and memory context is shaping the current work

## Canonical Artifact Set

`beagle/.artifacts/darwin-hpc/collaborative-compute-experiment-workbench/`

- `workbench-session.json`
- `compute-selection.json`
- `collaboration-access.json`
- `workbench-run.json`
- `collaborative-workbench.json`
- `smoke.json`
- `final-cluster-health.txt`

## Canonical Outcome

`B25.2` makes Beagle feel more like a lab OS than a loose bundle of surfaces:

- the same Beagle-owned workspace/session remains canonical
- VS Code and Cursor stay available on that same workspace
- compute remains explicit, typed, and bounded through the Slurm-backed profile
  layer
- partner-dev access remains scoped rather than cluster-wide
- execution and memory context are visible in the same workbench envelope
