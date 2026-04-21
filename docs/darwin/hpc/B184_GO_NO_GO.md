# B18.4 — GO / NO-GO

Status: GO

## GO Criteria

- one Beagle-owned session survives all three tool steps
- the final writeback records a non-empty `patch_ref`
- a real repo-native patch artifact exists for that `patch_ref`
- `repo_refs.branch`, `repo_refs.commit`, and `repo_refs.paths` are preserved
- handoff remains coherent after the repo-aware output is attached
- memory query remains useful across the full loop
- restart preserves the same identity
- cluster remains green
- `Slurmctld(primary)` remains `UP`

## No-Go Conditions

- the patch output is missing, empty, or not audit-friendly
- `patch_ref` is not preserved in the final writeback path
- repo refs become incoherent or detached from the session identity
- handoff loses coherence after the repo-aware output is attached
- restart loses identity
- cluster or Slurm regresses

## Canonical Decision

GO was earned on the live cluster with:

- a real repo-native patch artifact at `artifact:darwin-hpc/repo-aware-tool-session-commit/session-output.patch`
- the final `cursor` writeback preserving `patch_ref`, `repo_refs.branch`, `repo_refs.commit`, and `repo_refs.paths`
- ordered ledger replay across `codex -> claude-code -> cursor`
- `last_handoff` preserving the patch output after restart
- memory query returning all three tool sources
- restart preserving `workspace_id=b184-repo-aware-0322200609`
- restart preserving `session_id=ws-20260322230936`
- cluster green and `Slurmctld(primary) UP`
