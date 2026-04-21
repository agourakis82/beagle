# Beagle Expedition 002 — HRV-Aware vs Blind

Status: LIVE BASELINE

## Objective

Measure whether canonical physiological state changes pipeline behavior and outcomes when the same Beagle pipeline is run under:

- `hrv_aware`
- `hrv_blind`

## Canonical Conditions

- `hrv_aware`
  - canonical observer snapshot is available
  - pipeline may use physiological state
  - run metadata records `experiment_condition=hrv_aware`

- `hrv_blind`
  - canonical observer snapshot may still exist
  - pipeline must not consume it for context shaping
  - run metadata records `experiment_condition=hrv_blind`

## Frozen Fields

- `experiment_flags.hrv_aware`
- `experiment_flags.observer_enabled`
- `experiment_flags.serendipity_enabled`
- `experiment_flags.triad_enabled`
- `pipeline_physio`
- `physio_event`

## Expected Metrics

- output quality comparison
- operator acceptance comparison
- severity-conditioned outcome slices
- effect of canonical physiological state on prompt/runtime shaping

## Canonical Live Baseline

The first live baseline now exists under:

- `beagle/.artifacts/darwin-hpc/expedition-002-live-execution/`

Canonical batch:

- `session_id = b174-exp002-0322124804`
- `experiment_id = beagle_exp_002_hrv_aware_vs_blind`
- `n_total = 4`

Live result:

- `2` runs in `hrv_aware`
- `2` runs in `hrv_blind`
- canonical physio snapshot attached to all runs
- physio used in pipeline only for `hrv_aware`

Detailed frozen results live in:

- `docs/darwin/hpc/BEAGLE_EXPEDITION_002_RESULTS.md`
