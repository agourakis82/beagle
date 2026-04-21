# B27.1 — Study Continuation from Bounded Baseline

## Summary

Phase B27.1 provides the canonical HTTP endpoint to retrieve the **Study Continuation State** — the artifact that bridges a completed baseline adoption (B26.6) with the next study iteration.

After a variant is promoted and adopted as the new baseline, the study continuation state captures:
- The study registry identity preserved across runs
- The proposal dispatch that triggered the continuation
- The run update that records the transition
- Evidence refs linking back to B26.6 baseline and B26.3/B26.5 study execution

## Purpose

Enable programmatic access to study lineage and state transitions, supporting:
- **Workbench orchestration**: knowing which study to continue from bounded baseline
- **Audit/replay**: tracing how a study evolved across multiple runs
- **Next study seeding**: extracting the baseline context for new study variants

## Canonical Endpoint

```
GET /api/darwin/workstreams/:workstream_id/study-continuation
```

**Returns**: `StudyContinuationState` (JSON)

**Prerequisites**:
- B26.6 (baseline-adoption) must have been executed
- Study proposal dispatch must have been run (to create the continuation state)

## Key Fields

| Field | Description |
|-------|-------------|
| `continuation_state_id` | Unique identifier for this continuation record |
| `study_id` | Canonical study identifier (preserved across runs) |
| `workstream_id` | Workstream that owns this study |
| `workspace_id` | Workspace where study artifacts are stored |
| `session_id` | Session identity for lineage tracking |
| `same_beagle_owned_identity` | True if all components share Beagle-owned identity |
| `proposal_dispatch_id` | Reference to the dispatch that triggered continuation |
| `run_update_id` | Reference to the StudyRunUpdate recording this transition |
| `study_decision_id` | Reference to the decision that approved this continuation |
| `dispatched_run_id` | The actual run that was dispatched |
| `evidence_refs` | Vector of evidence references for audit trail |

## Artifacts

| Artifact | Path Pattern |
|----------|--------------|
| Study continuation state | `BEAGLE_DATA_DIR/study-continuation/{workspace_id}.json` |
| Smoke test output | `.artifacts/darwin-hpc/study-continuation/smoke.json` |

## Dependencies

- **B26.6** (baseline-adoption): Provides the bounded baseline to continue from
- **B26.3** (study proposal dispatch): Creates the continuation state

## Implementation

Source files:
- `crates/beagle-darwin/src/study_continuation.rs`: Core state structures and persistence
- `crates/beagle-darwin/src/lib.rs`: Public exports
- `apps/beagle-monorepo/src/http_darwin_hpc.rs`: HTTP endpoint handler

## Identity Preservation

The continuation state enforces Beagle-owned identity by verifying:
1. All referenced artifacts (baseline, decision, proposal) share the same `study_id`
2. All share the same `workspace_id` and `session_id` lineage
3. `same_beagle_owned_identity` is true across the entire chain

This ensures studies remain within their bounded identity envelope across multiple runs and continuations.
