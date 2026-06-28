# Beagle Workspace Agent

Per-workspace Notebook Terminal service for Beagle Workbench.

The pod runs two cooperating processes:

- `beagle-workspace-agent`: REST/WS API consumed through Project Cockpit.
- `beagle-pty-supervisor`: localhost-only PTY owner that survives API restarts inside the same pod.

State is written to the workspace PVC under `/workspace/.beagle/workbench`.
Canonical memory is never stored here; curated blocks are sent to Beagle Core through
`/api/exocortex/v1/memory/assisted-import` after redaction and secret scanning.
