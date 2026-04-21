# B18.3 — Multi-Step Tool Session Loop

Status: GO

## Objective

Prove that one Beagle-owned workstream/workspace/session can sustain multiple
successive premium-tool writebacks while preserving coherent handoff, memory,
ledger ordering, and result references.

This phase extends the `B18.2` single-step writeback into a real bounded session
loop:

- Beagle issues one shared context packet
- multiple tools write back into the same session envelope
- Beagle preserves ordered state instead of resetting per tool

## Canonical Sequence

- step 1: `codex` / `implementation`
- step 2: `claude-code` / `analysis`
- step 3: `cursor` / `note`

All three steps must share the same:

- `workstream_id`
- `workspace_id`
- `session_id`

## Target Surface

- `POST /api/darwin/workstreams/{id}/tool-return`
- `GET /api/darwin/workstreams/{id}/context-packet`
- `GET /api/darwin/workstreams/{id}/tool-dock/cursor`
- `GET /api/darwin/workstreams/{id}/tool-dock/claude-code`
- `GET /api/darwin/workstreams/{id}/tool-dock/codex`
- `POST /api/memory/query`

## Required Proof

- the same live session accepts three ordered writebacks
- `last_handoff` remains coherent after the third step
- memory query returns useful sequence hits from all three steps
- the writeback ledger preserves the tool/action ordering
- result refs remain intact through the sequence
- restart preserves the same workspace/session identity
- cluster stays green
- Slurm stays green

## Expected Artifacts

- `.artifacts/darwin-hpc/multi-step-tool-session-loop/context-packet-before.json`
- `.artifacts/darwin-hpc/multi-step-tool-session-loop/step-sequence.json`
- `.artifacts/darwin-hpc/multi-step-tool-session-loop/step-1-response.json`
- `.artifacts/darwin-hpc/multi-step-tool-session-loop/step-2-response.json`
- `.artifacts/darwin-hpc/multi-step-tool-session-loop/step-3-response.json`
- `.artifacts/darwin-hpc/multi-step-tool-session-loop/memory-query-after-step-3.json`
- `.artifacts/darwin-hpc/multi-step-tool-session-loop/tool-return-ledger-tail.jsonl`
- `.artifacts/darwin-hpc/multi-step-tool-session-loop/context-packet-after-restart.json`
- `.artifacts/darwin-hpc/multi-step-tool-session-loop/smoke.json`
- `.artifacts/darwin-hpc/multi-step-tool-session-loop/final-cluster-health.txt`

## Canonical Live Proof

- workspace: `b183-multi-step-0322185948`
- session: `ws-20260322220301`
- workstream: `beagle-darwin-hpc-governance`
- ordered steps:
  - `codex` / `implementation`
  - `claude-code` / `analysis`
  - `cursor` / `note`
- preserved result reference: `result:31`
- memory ids:
  - `0ea6d8de-e564-5660-ba91-d351e7b737d0`
  - `bdc3d1be-85ec-553f-8166-8434365d7f71`
  - `65b86eef-eb7f-5c57-bc9c-00e2a4208de0`
- memory hits after step 3: `3`
- restart preserved the same workspace/session identity
- cluster green and `Slurmctld(primary) UP`
