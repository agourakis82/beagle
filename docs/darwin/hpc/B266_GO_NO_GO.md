# B26.6 — GO / NO-GO

## GO when

- `ensure_baseline_adoption` succeeds on the live workstream after B26.5 `GO`.  
- Plane JSON artifacts exist and match closeout (`converged`, `stop-study`, `promote-variant`).  
- Context packet exposes `bounded_study_baseline` after adoption.  
- Rollback plan and next-study seed are readable via API and on disk.  
- Restart of `beagle-core` preserves identity fields on re-fetch.  
- Cluster and Slurm health captures stay green (same bar as B26.5 smoke).

## GO-WITH-BLOCKER when

- Adoption works but context packet augmentation fails intermittently (e.g. partial plane files).  
- Validator passes locally but cluster health capture is degraded (document the blocker).

## NO-GO / STAGED when

- Closeout or promotion execution missing or inconsistent with promoted ids.  
- `same_beagle_owned_identity` is false on any artifact.  
- Smoke or validator not run against the live cluster.

## Honest status

Set in the executor report after running containerized `cargo check` / tests and live smoke + validator.
