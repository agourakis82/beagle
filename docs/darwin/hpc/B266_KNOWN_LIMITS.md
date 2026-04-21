# B26.6 — Known limits

- **Rollback is declarative:** the rollback plan lists operator steps; Beagle does not automatically revert registry, memory, or Slurm state in this phase.  
- **No auto-launch:** `NextStudySeed.auto_launch_new_study` is always `false`; opening the next study remains operator-driven.  
- **Partial plane files:** if any of receipt / adoption / rollback / seed is missing, `bounded_study_baseline_summary_from_plane` returns `None` and the context packet omits `bounded_study_baseline` until adoption completes successfully.  
- **Scientific / editorial readiness:** seeds and baseline adoption do not assert manuscript or claim readiness; limits from earlier phases remain in force.  
- **Single baseline per workspace file:** one JSON file per `workspace_id` per artifact type; competing writes are last-writer semantics from `ensure_baseline_adoption`.
