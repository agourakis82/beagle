# Beagle v3.2 Workbench AGPL Boundary

Beagle v3.2 introduces a public showcase boundary for agentic terminal work:
`apps/warp-workbench`.

## Decision

- The Warp-derived Workbench layer is AGPL-3.0-only.
- Beagle core services, MCP, Sounio, memory engine, and cluster data remain
  separated by protocol boundaries.
- Private memories, truthsets, OrangeFS/PVC artifacts, terminal logs, tokens,
  and personal data must never be committed to GitHub.

## Architecture

- `apps/warp-workbench/vendor/warp` vendors Warp as a shallow Git submodule.
- `apps/warp-workbench/bridge` maps Warp-derived concepts to Beagle Terminal
  Protocol v1 without making Warp the authority yet.
- `BeagleWorkbenchKit` is the Apple AGPL boundary for terminal/workbench UX on
  macOS, iPadOS, iOS, watchOS, and visionOS.
- `project-cockpit` remains the gateway to cluster workspace panes and emits
  bridge metadata for Beagle/Warp bake-off evaluation.

## Memory Rule

Terminal blocks may be auto-imported only after secret scan/redaction.
`restricted_local_only` blocks never become canonical memory. Canonical memory
still flows through `/api/exocortex/v1/memory/assisted-import` into the cluster.
