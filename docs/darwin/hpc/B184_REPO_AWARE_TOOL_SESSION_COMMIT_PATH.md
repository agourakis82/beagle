# B18.4 — Repo-Aware Tool Session Commit Path

Status: GO

## Objective

Prove that one Beagle-owned multi-step tool session can produce a bounded
repo-native output while preserving coherent handoff, memory, ledger ordering,
 and recovery.

This phase extends `B18.3` from ordered writebacks to a real repo-aware output:

- one shared Beagle session envelope
- multiple premium-tool writebacks
- one bounded repo-native patch output
- one audit trail that preserves patch ref, repo refs, result refs, and handoff

## Canonical Sequence

- step 1: `codex` / `implementation`
- step 2: `claude-code` / `analysis`
- step 3: `cursor` / `note`

The final step must carry a bounded repo-native output:

- `patch_ref`
- `repo_refs.branch`
- `repo_refs.commit`
- `repo_refs.paths`

## Target Surface

- `POST /api/darwin/workstreams/{id}/tool-return`
- `GET /api/darwin/workstreams/{id}/context-packet`
- `POST /api/memory/query`

## Required Proof

- the same workstream/workspace/session survives the full loop
- a real repo-native patch artifact is produced
- the final tool writeback records `patch_ref`
- handoff remains coherent and names the repo-native output
- memory ingest preserves the writeback sequence
- the writeback ledger preserves both order and `patch_ref`
- restart preserves the same identity
- cluster stays green
- Slurm stays green

## Expected Artifacts

- `.artifacts/darwin-hpc/repo-aware-tool-session-commit/session-output.patch`
- `.artifacts/darwin-hpc/repo-aware-tool-session-commit/step-3-response.json`
- `.artifacts/darwin-hpc/repo-aware-tool-session-commit/context-packet-after-step-3.json`
- `.artifacts/darwin-hpc/repo-aware-tool-session-commit/memory-query-after-step-3.json`
- `.artifacts/darwin-hpc/repo-aware-tool-session-commit/tool-return-ledger-tail.jsonl`
- `.artifacts/darwin-hpc/repo-aware-tool-session-commit/context-packet-after-restart.json`
- `.artifacts/darwin-hpc/repo-aware-tool-session-commit/smoke.json`
- `.artifacts/darwin-hpc/repo-aware-tool-session-commit/final-cluster-health.txt`

## Canonical Live Proof

- workspace: `b184-repo-aware-0322200609`
- session: `ws-20260322230936`
- workstream: `beagle-darwin-hpc-governance`
- ordered steps:
  - `codex` / `implementation`
  - `claude-code` / `analysis`
  - `cursor` / `note`
- preserved result reference: `result:31`
- base commit: `9d22ff8`
- patch ref: `artifact:darwin-hpc/repo-aware-tool-session-commit/session-output.patch`
- patch size: `4358` bytes
- final step memory id: `cf917749-544c-56b9-9e91-ff817de67a89`
- memory hits after step 3: `3`
- restart preserved the same workspace/session identity
- cluster green and `Slurmctld(primary) UP`
