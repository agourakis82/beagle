# B24.12 Analysis Sample Accumulation / Promotion Gate Recheck

## Goal

B24.12 extends the bounded B24.11 shadow soak with an explicit sample-accumulation refresh. Beagle replays additional analysis-family shadow observations from the canonical comparison set, recomputes the rolling metrics, and rechecks whether analysis should remain `keep-shadow` or can be staged for a dedicated canary.

## Canonical Behavior

- implementation remains live on the guarded canary from B24.9
- analysis remains live on the explicit control policy in this phase
- manuscript remains live on the explicit control policy in this phase
- B24.12 only stages a decision; it does not activate analysis live
- every artifact stays linked to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Runtime Outputs

B24.12 materializes:

- `analysis-sample-accumulation`
- `analysis-sample-accumulation-metrics`
- `analysis-promotion-gate-recheck`

The execution record keeps `autonomy_policy_rollout_status=implementation-canary-live` and advances `autonomy_policy_calibration_status=analysis-shadow-rechecked`.

## Promotion Gate Recheck

- `keep-shadow`: the additional bounded evidence is still insufficient or the candidate remains too conservative
- `stage-analysis-canary`: the accumulated rolling window now meets the bounded promotion threshold with clean metrics
- `rollback-shadow`: the recheck detects regression, a false auto-continue, alignment degradation, or loss of implementation/manuscript retention

## Guardrails

- no global policy flip
- no manuscript movement off control
- no live analysis activation inside B24.12
- no free-running autonomy loop
- rollback and hold remain operator-visible
- scientific and editorial readiness limits remain visible
