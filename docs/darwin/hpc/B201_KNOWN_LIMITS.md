# B20.1 — Known Limits

Status: GO

## Current Limits

- The habitat is `internal-only`; there is no ingress or public exposure in this phase.
- The browser IDE substrate is `openvscode-server`; a first-class Cursor remote lane is still
  deferred to the next lane-specific step.
- The workspace bootstrap is `artifact/context-first`, not a full workspace fleet manager.
- The workspace fetches context from Beagle at startup; this phase does not add live streaming
  context sync after boot.
- The workspace relies on the existing Beagle operator token path for bounded internal access.
- Authentication on the browser IDE is `none` inside the cluster boundary in this phase; the
  protection boundary is the internal `ClusterIP` service plus controlled port-forward access.
- The old official `code-server` runtime remains blocked on this cluster runtime with
  `spawn /usr/lib/code-server/lib/node EACCES`; it is no longer the canonical habitat path.
- In-pod outbound clone still shows `getaddrinfo() thread failed to start`, so repo sync from the
  workspace pod remains best-effort.
- The canonical proof path therefore still includes bounded operator-side repo snapshot hydration,
  which keeps the workspace repo-native even when in-pod clone is unreliable.

## Explicit Non-Goals

- Coder multi-workspace management
- HA
- public UI
- edge / ingress
- replacing Beagle as source of truth
- making Cursor, Claude Code, or Codex canonical state owners
