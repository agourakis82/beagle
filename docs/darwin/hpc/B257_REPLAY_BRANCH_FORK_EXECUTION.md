# B25.7 — Replay / Branch Fork Execution

## Objective

Promote the replay request from a read-only reproducibility contract into one bounded execution
path that can re-submit the latest capsule as either a replay or a branch fork without creating a
second execution plane or breaking the Beagle-owned identity model.

## Canonical scope

- The source of truth remains the latest run capsule and its derived replay request.
- Replay execution reuses the existing workbench reservation/run/result-binding lane.
- Branch fork execution also reuses the same lane, but records an explicit fork-mode receipt.
- The same `workstream_id`, `workspace_id`, and `session_id` remain preserved.
- Replay/fork receipts are persisted alongside the workspace plane so restart stays coherent.

## Execution contract

- `GET /api/darwin/workstreams/:workstream_id/replay-request` exposes the latest bounded replay
  contract with the source run label, intent text, and code-state summary.
- `POST /api/darwin/workstreams/:workstream_id/replay-execution` re-submits that contract through
  the existing bounded workbench lane.
- `execution_mode=replay` keeps the run as a straight replay of the latest source capsule.
- `execution_mode=branch-fork` keeps the same Beagle-owned identity but records an explicit fork
  receipt and derives a fork-labelled run if the operator does not provide one.

## What gets recorded

- Source lineage: `source_run_id`, `source_run_label`, `source_submitted_job_id`
- Source workload envelope: subagent, task family, compute profile, config fingerprint
- Source code envelope: branch, commit, tree-ish, dirty state, patch ref, source fingerprint
- Execution receipt: requested_by, requester_role_id, execution_mode, dispatched_run_id,
  submitted/published job ids, and the canonical API paths for replay request, run capsule, and
  run diff

## Boundedness

This phase does not introduce a source-control platform, forked workspace plane, or free-form
execution surface. It only turns the already-canonical replay request into one bounded replay/fork
entrypoint that stays inside the existing workbench orchestration envelope.
