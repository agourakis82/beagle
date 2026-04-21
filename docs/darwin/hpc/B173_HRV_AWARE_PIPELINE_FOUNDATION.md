# B17.3 — HRV-Aware Pipeline & Expedition 002 Foundation

Status: GO

## Objective

Turn the canonical Observer 2.0 snapshot path into pipeline-visible execution state:

- canonical pipeline physio metadata in `run_report`
- live `hrv_aware` execution flag
- bounded physio severity event recording
- repo-native Expedition 002 foundation

## Canonical Path

- pipeline runtime: `apps/beagle-monorepo/src/pipeline.rs`
- pipeline start surface: `apps/beagle-monorepo/src/http.rs`
- observer snapshot source: `crates/beagle-observer/src/lib.rs`
- thresholds source: `crates/beagle-config/src/model.rs`

## What This Phase Adds

- `experiment_flags` frozen into the canonical pipeline report
- `pipeline_physio` frozen into the canonical pipeline report
- `physio_event` recorded in bounded form when a canonical snapshot is available
- feedback log now preserves the `hrv_aware` vs `hrv_blind` condition
- Expedition 002 is grounded repo-natively for HRV-aware vs blind execution

## Expected Proof

- `run_report` contains canonical `pipeline_physio.snapshot`
- `run_report.experiment_flags.hrv_aware` is live
- `run_report.physio_event.recording_mode == bounded`
- feedback event preserves `experiment_condition`
- cluster stays green
- Slurm stays green

## Canonical Live Proof

- canonical run id: `cb4f7552-3bd1-48c3-9827-a5e1c82b2be7`
- experiment id: `beagle_exp_002_hrv_aware_vs_blind`
- artifact root: `.artifacts/darwin-hpc/hrv-aware-pipeline-green/`
- final cluster snapshot: deployment `beagle-core` `1/1`, pod `1/1 Running`, `Slurmctld(primary) UP`
