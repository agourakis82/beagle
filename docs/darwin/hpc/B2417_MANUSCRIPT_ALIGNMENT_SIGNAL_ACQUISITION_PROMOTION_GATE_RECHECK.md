# B24.17 Manuscript Alignment Signal Acquisition / Promotion Gate Recheck

## Goal

B24.17 refreshes the bounded manuscript shadow window with explicit alignment-signal observations. Beagle now takes the B24.16 labeling layer, acquires real operator/execution-alignment signals on the same identity, and re-runs the manuscript promotion gate with enriched evidence instead of sample count alone.

## Canonical Behavior

- `implementation` remains live on the guarded canary
- `analysis` remains live on the guarded canary
- `manuscript` remains on explicit control plus shadow evaluation in this phase
- B24.17 does not force manuscript live
- every new artifact stays bound to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Runtime Outputs

B24.17 materializes:

- `manuscript-shadow-history`
- `manuscript-soak-metrics`
- `manuscript-alignment-labels`
- `manuscript-promotion-evidence`
- `manuscript-promotion-gate`

The execution record preserves `autonomy_policy_rollout_status=implementation-and-analysis-canary-live` and advances `autonomy_policy_calibration_status=manuscript-alignment-signal-acquired`.

## Explicit Alignment Signals

- `operator_alignment_label`: `aligned`, `misaligned`, or `insufficient-evidence`
- `execution_outcome_alignment_label`: `aligned`, `misaligned`, or `insufficient-evidence`
- `review_quality_label`: `operator-ready`, `needs-edit`, or `replan-required`
- `promotion_readiness_label`: `supports-stage-manuscript-canary`, `keep-shadow`, or `rollback-shadow`

The new signal-acquisition pass keeps the same bounded manuscript family samples, but refreshes the rolling window so explicit operator and execution observations are recorded on each shadow entry whenever the current review/follow-on/execution state makes that signal observable.

## Promotion Evidence

The B24.17 promotion evidence aggregates:

- explicit operator-alignment label counts
- explicit execution-outcome label counts
- label coverage across the bounded manuscript shadow window
- review-quality labeling bound to the same Beagle-owned identity
- promotion-readiness counts that tell the gate whether the evidence supports stage, hold, or rollback
- whether the labeled evidence is promotion-worthy or only confirms that manuscript should remain blocked/held in shadow

## Promotion Gate Consumption

`stage-manuscript-canary` is only available when all of the following are true:

- the bounded manuscript shadow sample threshold remains met
- false auto-continue stays at `0`
- false review-required stays at `0`
- regression count stays at `0`
- retained `implementation` and `analysis` canaries stay healthy
- explicit operator-alignment label coverage is complete for the bounded window
- explicit execution-outcome label coverage is complete for the bounded window
- explicit operator and execution labels are fully aligned
- review quality is `operator-ready`
- promotion-readiness evidence supports stage for the bounded window
- the manuscript candidate decision class is actually promotion-worthy, not merely correctly blocked in shadow

If those conditions are not met, the safe bounded decision remains `keep-shadow`. If explicit misalignment or regression labels appear, the bounded response is `rollback-shadow`. B24.17 is specifically allowed to increase labeled evidence while still keeping manuscript on shadow when the newly explicit evidence only confirms a blocked manuscript posture.
