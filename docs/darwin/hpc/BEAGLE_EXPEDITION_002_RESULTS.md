# Beagle Expedition 002 — Results

Status: GO

## Scope

This document freezes the first live baseline for `Expedition 002`:

- condition `hrv_aware`
- condition `hrv_blind`
- bounded comparative analysis from canonical Beagle run reports

## Canonical Batch

- `session_id = b174-exp002-0322124804`
- `experiment_id = beagle_exp_002_hrv_aware_vs_blind`
- `artifact_root = beagle/.artifacts/darwin-hpc/expedition-002-live-execution/`

Run matrix:

- `9a19b9c2-a35f-4936-bb5e-4b35b2b33d95` → `hrv_aware`
- `260538d1-1265-42f0-a340-ab0bbeaf38eb` → `hrv_blind`
- `3fb909c0-ae1c-4979-bff1-587aa6e6bb44` → `hrv_aware`
- `4f758afc-2d91-41b2-99bb-ae482f58c79b` → `hrv_blind`

## Outputs

- run-level comparison matrix
- JSON summary
- CSV export
- partial interpretation of physio-aware vs blind behavior

## Frozen Baseline

- `total_runs = 4`
- `hrv_aware_runs = 2`
- `hrv_blind_runs = 2`
- `physio_snapshot_attached_runs = 4`
- `used_in_pipeline_count = 2`

Condition summary:

- `hrv_aware`
  - `pipeline_physio_used_count = 2`
  - `physio_snapshot_available_count = 2`
  - `physio_hr_mean = 118.0`
  - `physio_spo2_mean = 94.0`
  - `stress_index_mean = 1.0`
  - `avg_tokens = 2830.5`

- `hrv_blind`
  - `pipeline_physio_used_count = 0`
  - `physio_snapshot_available_count = 2`
  - `physio_hr_mean = 118.0`
  - `physio_spo2_mean = 94.0`
  - `stress_index_mean = null`
  - `avg_tokens = 3077.5`

## Interpretation

The first live baseline proves the experimental split is operationally real:

- both conditions ran under the same canonical experiment id
- both conditions preserved the same latest observer snapshot
- only the `hrv_aware` condition consumed physio in the pipeline
- the `hrv_blind` condition remained blind while still preserving snapshot traceability
- the resulting JSON/CSV outputs are analyzable for later statistical work

This is enough to treat Expedition 002 as live and paper-preparatory, but not yet statistically conclusive.

## Promotion Rule

Write canonical results into this document only after the live smoke and validator pass.
