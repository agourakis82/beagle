# B26.5 Known Limits

- The promotion execution artifact is only as accurate as the convergence gate inputs; if the study registry, sweep, or comparative summary drift, the closeout identity must be revalidated separately.
- Run-diff lineage data is derived from the most recent bounded continuation run; if lineage artifacts are missing the promotion execution still records the best variant but the run-scoped diff is best-effort.
- The proofs live under the workspace plane and are not yet pushed to downstream analytics; operators must export the new artifact if additional tooling needs it.
- The smoke script currently runs through the same HPC service port forward as B26.4; it does not re-run continuation workstreams, so it cannot uncover issues that only appear during a new run submission.
