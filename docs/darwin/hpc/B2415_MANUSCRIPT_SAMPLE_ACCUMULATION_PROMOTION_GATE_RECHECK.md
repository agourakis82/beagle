# B24.15 Manuscript Sample Accumulation / Promotion Gate Recheck

## Goal

B24.15 extends the bounded B24.14 manuscript shadow pass with an explicit sample-accumulation refresh. Beagle replays additional manuscript-family shadow observations from the canonical comparison set, recomputes the rolling metrics, and rechecks whether manuscript should remain `keep-shadow` or can be staged for a dedicated canary.

## Canonical Behavior

- `implementation` remains live on the guarded canary from B24.9
- `analysis` remains live on the guarded canary from B24.13
- `manuscript` remains live on explicit control in this phase
- B24.15 only stages a decision; it does not activate manuscript live
- every artifact stays linked to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Runtime Outputs

B24.15 materializes:

- `manuscript-shadow-history`
- `manuscript-soak-metrics`
- `manuscript-promotion-gate`

The execution record preserves `autonomy_policy_rollout_status=implementation-and-analysis-canary-live` and advances `autonomy_policy_calibration_status=manuscript-shadow-rechecked`.

## Promotion Gate Recheck

- `keep-shadow`: the additional bounded evidence is still insufficient or the candidate still lacks clean operator/outcome alignment for a safe staged canary
- `stage-manuscript-canary`: the accumulated rolling window now meets the bounded promotion threshold with clean metrics
- `rollback-shadow`: the recheck detects regression, a false auto-continue, alignment degradation, or loss of retained implementation/analysis canary health

## Guardrails

- no global policy flip
- no movement of `implementation` off live canary
- no movement of `analysis` off live canary
- no live manuscript activation inside B24.15
- no free-running autonomy loop
- rollback and hold remain operator-visible
- scientific and editorial readiness limits remain visible
