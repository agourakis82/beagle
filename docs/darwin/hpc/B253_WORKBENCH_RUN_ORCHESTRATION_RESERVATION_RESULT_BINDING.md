# B25.3 — Workbench Run Orchestration / Reservation Flow / Result Binding

`B25.3` turns the already-live collaborative workbench into a bounded
run-oriented surface. The workbench no longer stops at access, tenancy, and
context; it can now reserve compute, dispatch one bounded run, track scheduler
state, and bind published results back into the same Beagle-owned
`workstream/workspace/session` identity.

## Purpose

The goal of this phase is to stop making the operator stitch together:

- a compute reservation
- a selected bounded profile
- a workbench run dispatch
- scheduler-backed execution state
- result refs and receipts
- workspace/session continuity after restart

Instead, Beagle exposes one explicit orchestration path that keeps the run in
the same bounded workbench envelope.

## Scope

- reuse the already-live collaborative workbench from `B25.2`
- reuse the existing Slurm-backed workspace pilot path instead of inventing a
  second scheduler lane
- keep partner-dev access bounded by the already-live role/profile scopes
- keep result refs in the Beagle-owned result plane
- do not create a scheduler bypass or free-form cluster access path

## Runtime Surfaces

- `POST /api/darwin/workstreams/{workstream_id}/workbench-run`
- `GET /api/darwin/workstreams/{workstream_id}/workbench-reservation`
- `GET /api/darwin/workstreams/{workstream_id}/workbench-run-orchestration`
- `GET /api/darwin/workstreams/{workstream_id}/workbench-result-binding`

## Canonical Output

The bounded orchestration layer freezes three contracts:

- one workbench reservation contract
- one workbench run contract
- one workbench result binding contract

Together they answer:

- who requested the run and under which bounded role
- which compute profile was reserved and why it is allowed
- which subagent/task family the run belongs to
- which scheduler-backed lifecycle states were observed
- which job/result/manifest refs are now attached to the same workbench
- whether restart recovery still preserves the same Beagle-owned identity

## Canonical Lifecycle

The canonical workbench run lifecycle is:

- `reserved`
- `queued`
- `running`
- `succeeded`
- `failed`
- `stopped`

`B25.3` only needs to prove one bounded happy-path run, but the schema freezes
the full lifecycle so later phases can layer richer controls on top of the same
surface.

## Canonical Artifact Set

`beagle/.artifacts/darwin-hpc/workbench-orchestration/`

- `workbench-reservation.json`
- `workbench-run.json`
- `workbench-execution-state.json`
- `workbench-result-binding.json`
- `workbench-context-after-run.json`
- `smoke.json`
- `final-cluster-health.txt`

## Contracts and entrypoints

- `docs/darwin/hpc/contracts/workbench-reservation-schema.yaml`
- `docs/darwin/hpc/contracts/workbench-run-schema.yaml`
- `docs/darwin/hpc/contracts/workbench-result-binding-schema.yaml`
- `docs/darwin/hpc/contracts/workbench-orchestration-bundle-schema.yaml` (agregado
  `WorkbenchRunOrchestrationBundle`)
- Crate: `beagle_darwin::workbench_orchestration` reexporta reserva, run e binding.

## Smoke (cluster)

- `scripts/infrastructure/darwin-hpc/run_workbench_orchestration_smoke.sh`
- `scripts/infrastructure/darwin-hpc/validate_workbench_orchestration_smoke.sh`
- Aliases B25.3:
  `run_workbench_run_orchestration_smoke.sh` /
  `validate_workbench_run_orchestration_smoke.sh`

## Canonical Outcome

`B25.3` makes the workbench feel like an actual lab operating surface:

- one canonical reservation is created in the same Beagle-owned workspace
- one bounded run is dispatched from that reservation
- execution state is tracked through the scheduler-backed lifecycle
- published result refs and manifest receipts are rebound to the same
  workstream/workspace/session
- partner-dev remains bounded to the intended profiles and shared workspace lane
- restart remains coherent after the run completes
