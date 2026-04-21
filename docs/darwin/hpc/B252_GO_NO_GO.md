# B25.2 — GO / NO-GO

Implementation lives in `collaborative_workbench.rs` with HTTP routes and smoke/validator scripts under `scripts/infrastructure/darwin-hpc/`. Promote to **GO** after `run_collaborative_workbench_smoke.sh` (or `run_collaborative_compute_experiment_workbench_smoke.sh`) and `validate_collaborative_workbench_smoke.sh` succeed on the live cluster with artifacts under `.artifacts/darwin-hpc/collaborative-compute-experiment-workbench/`.

**Live proof (cluster):** smoke + validator have been run successfully with the relaxed result-surface rule documented in `B252_KNOWN_LIMITS.md` (last-result catalog optional when execution result-links are present).

## GO

- one canonical collaborative workbench contract exists
- the same Beagle-owned `workstream/workspace/session` identity is preserved
- VS Code and Cursor are both visible as access paths for the same workspace
- subagent selection is explicit
- compute profile selection is explicit and bounded
- partner-dev access is explicit and scoped
- execution state, result refs, and memory context are visible in the workbench
- restart remains coherent
- cluster stays green
- Slurm stays green

## NO-GO

- the workbench creates a new state owner outside Beagle
- the workbench bypasses profile-based compute tenancy
- partner-dev access requires cluster-admin or direct Kubernetes credentials
- VS Code / Cursor identity diverges from the Beagle-owned workspace/session
- execution or retrieval context is hidden behind a separate non-canonical layer
