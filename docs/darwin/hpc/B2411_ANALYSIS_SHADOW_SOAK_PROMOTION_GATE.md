# B24.11 Analysis Shadow Soak / Promotion Gate

## Goal

B24.11 extends the bounded B24.10 analysis shadow pass into a bounded soak window. Beagle now accumulates explicit analysis shadow observations, computes rolling promotion metrics, and emits a promotion gate that decides whether analysis should remain shadow-only, stage a dedicated canary, or roll back the shadow candidate.

## Canonical Behavior

- implementation remains on the live guarded canary from B24.9
- analysis remains on the explicit control policy live
- manuscript remains on the explicit control policy live
- analysis candidate evaluation stays shadow-only in this phase
- every soak artifact stays attached to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Runtime Outputs

B24.11 materializes:

- `analysis-shadow-history`
- `analysis-soak-metrics`
- `analysis-promotion-gate`

The execution record keeps `autonomy_policy_rollout_status=implementation-canary-live` and advances `autonomy_policy_calibration_status=analysis-shadow-soaked`.

## Promotion Gate

- `keep-shadow`: the analysis candidate has not regressed, but the bounded soak window does not yet meet promotion criteria
- `stage-analysis-canary`: the rolling soak window has enough samples and holds zero false auto-continue, zero false review-required, and control-matching alignment
- `rollback-shadow`: the analysis candidate regresses, false auto-continue appears, alignment drops below control, or the implementation canary/manuscript control retention degrades

## Guardrails

- no global policy flip
- no manuscript movement off control
- no live analysis activation unless promotion criteria are explicitly met
- no free-running autonomy loop
- rollback and hold remain operator-visible
- readiness limits remain visible to scientific and editorial layers
