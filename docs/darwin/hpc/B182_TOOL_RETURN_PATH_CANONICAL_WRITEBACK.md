# B18.2 — Tool Return Path / Canonical Writeback

Status: GO

## Objective

Create the first bounded return path so Cursor, Claude Code, and Codex can send
structured work outcomes back into the same Beagle-owned workstream/workspace/session
identity.

This phase closes the first canonical writeback loop:

- tools receive one shared context packet from Beagle
- tools return one bounded outcome payload to Beagle
- Beagle persists the return canonically without handing over state ownership

## Target Surface

- `POST /api/darwin/workstreams/{id}/tool-return`
- `GET /api/darwin/workstreams/{id}/tool-dock/cursor`
- `GET /api/darwin/workstreams/{id}/tool-dock/claude-code`
- `GET /api/darwin/workstreams/{id}/tool-dock/codex`

## Canonical Payload Fields

- `workstream_id`
- `workspace_id`
- `session_id`
- `tool`
- `action_type`
- `summary`
- `memory_text`
- `handoff_patch`
- `result_refs`
- `repo_refs.branch`
- `repo_refs.commit`
- `repo_refs.paths`

## Runtime Path

- writeback runtime: `crates/beagle-darwin/src/workstream_tool_return.rs`
- tool dock shaping: `crates/beagle-darwin/src/workstream_cockpit.rs`
- protected HTTP surface: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- memory writeback: existing Beagle memory spine via `BeagleContext.memory_ingest_session(...)`

## Bounded Writeback Rules

- the route workstream id must match the payload workstream id
- the payload workspace/session ids must match the current Beagle-owned live identity
- tools do not mutate canonical repo or governance state
- handoff is updated as a bounded canonical summary line, not as arbitrary state takeover
- repo/result refs are preserved as structured metadata and ledger fields
- memory ingest is bounded to one structured turn tagged with:
  - `workstream_id`
  - `workspace_id`
  - `session_id`
  - `tool-return`
  - `tool`
  - `action_type`

## Expected Proof

- one tool return payload is accepted
- handoff is updated coherently on the same live session
- memory ingest records the returned work
- the tool dock exposes the same writeback endpoint for Cursor, Claude Code, and Codex
- restart preserves the same workstream/workspace/session identity
- cluster stays green
- Slurm stays green

## Canonical Live Proof

- workspace: `b182-tool-return-0322171545`
- session: `ws-20260322201907`
- workstream: `beagle-darwin-hpc-governance`
- tool/action: `codex` / `implementation`
- returned memory id: `284a084d-2e35-54b2-bcd5-ed50eb6ebf70`
- published result reference preserved: `result:31`
- recommended recipe after restart: `beagle-darwin-hpc-governance.operator_cpu_loop`
- memory hits after writeback: `2`
- restart preserved the same workspace/session identity

Canonical artifacts:

- `.artifacts/darwin-hpc/tool-return-path/tool-return-response.json`
- `.artifacts/darwin-hpc/tool-return-path/context-packet-after-return.json`
- `.artifacts/darwin-hpc/tool-return-path/memory-query-after-return.json`
- `.artifacts/darwin-hpc/tool-return-path/context-packet-after-restart.json`
- `.artifacts/darwin-hpc/tool-return-path/tool-return-ledger-tail.jsonl`
- `.artifacts/darwin-hpc/tool-return-path/smoke.json`
- `.artifacts/darwin-hpc/tool-return-path/final-cluster-health.txt`
