# B27.1 — Known Limits

## Current Known Limits (B27.1 — Study Continuation from Baseline)

### 1. No Automatic Study Launch
- `next_study_auto_launch` is hardcoded to `false` in B26.6.
- Next study must be manually triggered or scheduled.
- This is intentional (safety).

### 2. Baseline is Advisory, Not Enforced
- The new baseline is recorded but not yet enforced in the planner/intent engine.
- Planner may still propose variants outside the baseline lineage.

### 3. No Rollback Automation
- Rollback plan exists but is not yet wired to an automated rollback endpoint.
- Human operator must trigger rollback manually.

### 4. Identity Chain Depth
- Current implementation only tracks immediate previous baseline.
- Deep study history (grandparent baselines) is not yet materialized.

### 5. Performance
- Each study continuation currently does multiple JSON reads/writes.
- Not yet optimized for high-frequency study iteration.

### 6. Cluster State
- `beagle-sovereign-reranker` pod occasionally shows `ContainerStatusUnknown`.
- Does not block functionality but pollutes health checks.

---

**Next work**: 
- Wire `next_study_seed` into `intent_planner`
- Add continuation smoke test
- Improve context packet propagation

Last updated: 2026-04-01
