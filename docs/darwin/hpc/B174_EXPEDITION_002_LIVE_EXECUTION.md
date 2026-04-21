# B17.4 — Expedition 002 Live Execution

Status: GO

## Objective

Run the first real `Expedition 002` batch on top of the already-proven canonical path:

- Observer 2.0 snapshot ingest/retrieval
- canonical pipeline physio metadata
- bounded physio severity events
- experiment flag `hrv_aware`

## Canonical Comparison

- Condition A: `hrv_aware = true`
- Condition B: `hrv_aware = false`

Both conditions remain bounded inside the same Beagle-native pipeline path.

## Repo-native Insertion Points

- `crates/beagle-experiments/src/exp002.rs`
- `crates/beagle-experiments/src/bin/run_experiment_hrv_aware_vs_blind.rs`
- `crates/beagle-experiments/src/bin/analyze_experiments.rs`
- `crates/beagle-experiments/src/analysis.rs`
- `scripts/infrastructure/darwin-hpc/run_expedition_002.sh`
- `scripts/infrastructure/darwin-hpc/validate_expedition_002.sh`

## Expected Artifacts

Artifact root:

- `beagle/.artifacts/darwin-hpc/expedition-002-live-execution/`

Minimum proof set:

- `physio-ingest-response.json`
- `physio-latest.json`
- `experiment-tags.jsonl`
- `run-matrix.json`
- `analysis-summary.json`
- `analysis-summary.csv`
- `results-summary.json`
- `smoke.json`
- `final-cluster-health.txt`

## Canonical Live Proof

Artifact root:

- `beagle/.artifacts/darwin-hpc/expedition-002-live-execution/`

Canonical batch:

- `session_id = b174-exp002-0322124804`
- `experiment_id = beagle_exp_002_hrv_aware_vs_blind`
- `run_ids`
  - `9a19b9c2-a35f-4936-bb5e-4b35b2b33d95` (`hrv_aware`)
  - `260538d1-1265-42f0-a340-ab0bbeaf38eb` (`hrv_blind`)
  - `3fb909c0-ae1c-4979-bff1-587aa6e6bb44` (`hrv_aware`)
  - `4f758afc-2d91-41b2-99bb-ae482f58c79b` (`hrv_blind`)

Live results frozen from:

- `smoke.json`
- `run-matrix.json`
- `analysis-summary.json`
- `analysis-summary.csv`
- `results-summary.json`
- `final-cluster-health.txt`

Observed baseline:

- `2` runs completed as `hrv_aware`
- `2` runs completed as `hrv_blind`
- `pipeline_physio.snapshot_available = true` for all `4/4` runs
- `pipeline_physio.used_in_pipeline = true` only for `2/2 hrv_aware` runs
- `pipeline_physio.used_in_pipeline = false` for `2/2 hrv_blind` runs
- latest canonical physio snapshot:
  - `source = observer-b174`
  - `hr = 118`
  - `hrv_ms = 21`
  - `hrv_level = low`
  - `spo2 = 94`

## Promotion Rule

Promote to `GO` only after live proof shows:

- both conditions completed
- run metadata preserves `experiment_id`
- `hrv_aware` runs used canonical physio in pipeline
- `hrv_blind` runs stayed blind while preserving snapshot availability
- analysis artifacts were produced
- cluster stayed green
- Slurm stayed green
