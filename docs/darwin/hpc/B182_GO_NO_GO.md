# B18.2 — GO / NO-GO

Status: GO

## GO Criteria

- `POST /api/darwin/workstreams/{id}/tool-return` accepts one bounded payload
- the payload is persisted canonically
- `last_handoff` reflects the bounded writeback
- memory ingest records the returned work
- Cursor / Claude Code / Codex expose the same `tool_return_path`
- restart preserves workspace/session identity
- cluster remains green
- `Slurmctld(primary)` remains `UP`

## No-Go Conditions

- payload identity does not match the live Beagle-owned session envelope
- writeback mutates lower-layer ownership or governance unexpectedly
- handoff update is missing or incoherent
- memory ingest fails in the canonical memory-enabled live path
- restart loses workspace/session identity
- cluster or Slurm regresses

## Canonical Decision

GO was earned on the live cluster with:

- `POST /api/darwin/workstreams/{id}/tool-return` returning `status=ok`
- `handoff_updated=true`
- `memory_ingested=true`
- `ledger_appended=true`
- identical `tool_return_path` exposed to Cursor / Claude Code / Codex
- restart preserving `workspace_id=b182-tool-return-0322171545`
- restart preserving `session_id=ws-20260322201907`
- cluster green and `Slurmctld(primary) UP`
