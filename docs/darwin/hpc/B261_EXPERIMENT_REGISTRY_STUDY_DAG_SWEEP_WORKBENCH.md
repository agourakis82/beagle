# B26.1 — Experiment Registry / Study DAG / Sweep Workbench

## Objective

Create the first canonical study layer in the Beagle workbench so one study can bind multiple
related runs, represent bounded variants/sweeps, and expose comparative run outcomes without
opening a second orchestration plane.

## Canonical scope

- Study identity is Beagle-owned and anchored to the same `workstream_id`, `workspace_id`, and
  `session_id` used by workbench runs.
- Study records are derived from existing canonical artifacts (`run-capsule`, `replay-execution`,
  `run-diff`) instead of introducing a parallel scheduler.
- Variant/sweep representation is bounded to baseline/direct/replay/branch-fork run roles.
- Comparative result output is computed as explicit baseline-versus-variant category deltas.

## Runtime contract

- `GET /api/darwin/workstreams/:workstream_id/study-registry`
  generates/returns the canonical registry for the workstream workspace lane.
- `GET /api/darwin/workstreams/:workstream_id/study-dag`
  returns the bounded study DAG linking study root, variants, and run nodes.
- `GET /api/darwin/workstreams/:workstream_id/study-sweep`
  returns the variant/sweep envelope tied to concrete run ids.
- `GET /api/darwin/workstreams/:workstream_id/comparative-result-summary`
  returns a bounded comparison summary against the study baseline.

## Canonical artifacts

- `study-registry.json`: canonical study identity plus run registration ledger.
- `study-dag.json`: bounded study graph for lineage/derivation visibility.
- `study-sweep.json`: variant set and sweep metadata tied to run labels/ids.
- `comparative-result-summary.json`: baseline-relative changed categories per run and union view.

## Boundedness

This phase does not introduce a generic workflow engine, free-form DAG compiler, or external study
control plane. It only adds one bounded registry/sweep layer on top of already canonical Beagle
run artifacts.
