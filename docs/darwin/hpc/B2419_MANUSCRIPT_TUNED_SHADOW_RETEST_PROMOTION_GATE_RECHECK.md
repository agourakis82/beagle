# B24.19 Manuscript Tuned Shadow Retest / Promotion Gate Recheck

## Goal

B24.19 executes a bounded recheck pass over the manuscript tuned-policy candidate introduced in B24.18. This phase does not open a manuscript canary by default. It verifies whether the tuned candidate has actually been applied on the active trajectory/context lane and whether the resulting quality posture is strong enough to justify promotion staging.

## Canonical Behavior

- `implementation` remains live on guarded canary
- `analysis` remains live on guarded canary
- `manuscript` remains explicit control + shadow unless promotion evidence is explicitly sufficient
- identity remains bound to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`
- no parallel control plane is introduced outside Beagle

## Runtime-Artifacts Used

B24.19 consumes already-live manuscript artifacts:

- `manuscript-trajectory-quality`
- `manuscript-context-adequacy`
- `manuscript-tuning-recommendation`
- `manuscript-promotion-evidence`
- `manuscript-promotion-gate`

It materializes:

- `manuscript-shadow-retest`
- `manuscript-quality-gate-recheck`

## What Is Rechecked

### Tuned candidate application

- candidate lane vs observed lane:
  - task family
  - selected subagent
  - compiler budget profile
  - GraphRAG mode
  - temporal truth view
  - context task profile
- explicit mismatch dimensions and mismatch count
- whether retest was actually applied (`retest_applied`)

### Quality readiness after retest

- `trajectory_quality`
- `context_sufficiency`
- `review_quality_label`
- `editorial_acceptance_fit`
- explicit `tuned_quality_ready` decision

### Promotion gate recheck

- consumes existing promotion evidence sufficiency
- binds to the same manuscript promotion gate identity
- emits explicit outcome:
  - `keep-shadow`, or
  - `stage-manuscript-canary` (only when bounded criteria are satisfied)

## Promotion Interpretation

B24.19 is an evidence-hardening recheck. If the tuned candidate is not actually applied or the quality posture is still below promotion standards, manuscript remains `keep-shadow`. This is expected and healthy behavior for guarded rollout.
