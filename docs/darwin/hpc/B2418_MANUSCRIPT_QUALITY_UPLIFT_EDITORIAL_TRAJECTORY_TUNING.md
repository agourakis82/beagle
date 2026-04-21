# B24.18 Manuscript Quality Uplift / Editorial Trajectory Tuning

## Goal

B24.18 diagnoses why `manuscript` still resolves to `keep-shadow` even after bounded sample coverage and full alignment-label coverage are already in place. The phase does not promote `manuscript`. It evaluates the manuscript trajectory itself, the adequacy of the compiled context feeding that trajectory, and the next tuned shadow-only policy candidate worth testing.

## Canonical Behavior

- `implementation` remains live on the guarded canary
- `analysis` remains live on the guarded canary
- `manuscript` remains on explicit control plus shadow in this phase
- B24.18 does not open a manuscript canary
- every artifact remains bound to the same Beagle-owned `workstream_id`, `workspace_id`, and `session_id`

## Runtime Outputs

B24.18 materializes:

- `manuscript-trajectory-quality`
- `manuscript-context-adequacy`
- `manuscript-tuning-recommendation`

The execution record advances `autonomy_policy_calibration_status=manuscript-quality-uplifted` while retaining `autonomy_policy_rollout_status=implementation-and-analysis-canary-live`.

## What Is Evaluated

### Editorial trajectory quality

- whether the observed trajectory is good enough for manuscript work
- whether the trajectory still looks like an analysis/exploration lane instead of a manuscript lane
- whether acceptance and review posture are compatible with editorial readiness

### Context adequacy

- `context_sufficiency`
- `retrieval_lane_fit`
- `GraphRAG_mode_fit`
- `truth_view_fit`
- `compiler_profile_fit`
- `task_profile_fit`
- `subagent_fit`
- `handoff_quality`
- `editorial_acceptance_fit`

### Tuned policy recommendation

- the next shadow-only candidate policy mode
- the next task family / subagent / work mode to test
- the next compiler profile, retrieval lane, GraphRAG mode, and truth view
- the expected handoff and assembly packages
- the highest-impact bounded fix to try next

## Promotion Interpretation

B24.18 deliberately keeps the promotion gate output unchanged when it still correctly says `keep-shadow`. The purpose of this phase is to explain *why* that answer remains correct and to produce a bounded tuned shadow policy candidate that can be tested next.

If the quality eval shows that the trajectory is still not manuscript-ready, the context is merely adequate-but-misaligned, or the editorial acceptance fit is still below `good-fit`, the safe action remains:

- keep `manuscript` on explicit control + shadow
- retest the tuned candidate in shadow
- only revisit staged canary promotion after the tuned shadow path proves itself
