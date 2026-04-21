# B18.1 — Memory-Aware Workstream Context Packets

Status: GO

## Objective

Create the first canonical Beagle-owned context packet for a workstream so the
same live context envelope can be handed to:

- the internal cockpit
- Cursor
- Claude Code
- Codex

The packet must remain bounded and repo-native. It does not replace lower
layers; it composes them into one operator-usable envelope.

## Target Surface

- `GET /api/darwin/workstreams/{id}/context-packet`
- `GET /api/darwin/workstreams/{id}/cockpit`
- `GET /api/darwin/workstreams/{id}/tool-dock/cursor`
- `GET /api/darwin/workstreams/{id}/tool-dock/claude-code`
- `GET /api/darwin/workstreams/{id}/tool-dock/codex`

## Canonical Packet Fields

- `workstream_id`
- `workspace_id`
- `session_id`
- `repo`
- `branch`
- `governance_state`
- `handoff`
- `last_result`
- `last_successful_task`
- `latest_physio`
- `experiment_flags`
- `memory_hits`
- `recommended_recipe`

## Runtime Path

- packet runtime: `crates/beagle-darwin/src/workstream_context_packet.rs`
- cockpit/tool dock shaping: `crates/beagle-darwin/src/workstream_cockpit.rs`
- protected HTTP surface: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- physio source: `apps/beagle-monorepo/src/http_memory.rs` via `AppState.observer`
- bounded memory search: `BeagleContext.memory_query(...)` via the existing memory spine

## Bounded Resolution Rules

- handoff, result and last successful task come from the canonical workstream
  control-room path
- latest physio is best-effort from the canonical Observer 2.0 latest snapshot
  path
- experiment flags are best-effort from the latest pipeline `run_report` when a
  `source_run_id` is available, and otherwise may fall back to recent memory
  metadata
- memory hits are bounded and compact; this phase does not dump uncontrolled
  transcript history
- recommended recipe is a bounded heuristic over the canonical recipe set and
  live task/session state

## Expected Proof

- one canonical workstream returns a valid context packet
- the cockpit and all three premium tool surfaces derive from the same
  workstream/workspace/session identity
- handoff, last result, last successful task, latest physio, experiment flags,
  bounded memory hits and recommended recipe are coherent in one place
- restart preserves packet identity coherence
- cluster stays green
- Slurm stays green

## Canonical Live Proof

- workspace: `b181-context-packet-0322165047`
- session: `ws-20260322195402`
- workstream: `beagle-darwin-hpc-governance`
- recommended recipe: `operator_cpu_loop`
- latest physio source: `observer-smoke`
- experiment provider/model: `xai` / `grok-4-1-fast-reasoning`
- bounded memory hits returned: `1`
- restart preserved the same workspace/session identity
