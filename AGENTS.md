# Agent Instructions

Beagle is a cluster-canonical exocortex. The local workstation is only a client:
do not store canonical memory on the MacBook or in GitHub.

## Work Memory

For Codex sessions, use the Beagle MCP/local tailnet server and preserve work
memory at these points:

- start of session;
- after a meaningful plan;
- after important decisions;
- after diffs or implementation slices;
- after tests/checks;
- final summary and next action.

Preferred local wrapper:

```bash
scripts/beagle-agent-session --agent codex -- codex
```

Manual capture when needed:

```bash
scripts/beagle-work-memory-capture \
  --agent codex \
  --phase summary \
  --summary "What changed and why" \
  --test "command that passed or failed" \
  --next-action "What the next agent should do"
```

The wrapper and capture script post to cluster GraphRAG++ through
`/api/exocortex/v1/memory/assisted-import`. They never write canonical memory
locally. If content looks restricted, redact it before capture.

Optional project-file daemon:

```bash
scripts/beagle-work-memory-daemon --agent codex --once --dry-run
scripts/beagle-work-memory-daemon --agent codex
```

The daemon observes only this repo/project: branch, commit, changed files,
diffstat, and work-memory metadata. It does not observe clipboard, screenshots,
browser state, or the wider computer. Failed sends may be queued in a transient
`0600` outbox with 24h TTL; the cluster remains the only canonical memory.

## MCP Usage

Use the `beagle` MCP server for Home, GraphRAG++ search, work-memory capture,
Governor status, and audit/trust checks. The active public/local MCP surface is
non-destructive; `admin:destructive` is intentionally absent.
