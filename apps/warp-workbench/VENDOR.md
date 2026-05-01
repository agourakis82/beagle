# Vendor Manifest

## Warp

- Path: `vendor/warp`
- URL: `https://github.com/warpdotdev/Warp.git`
- Commit: `805b3e2a576e689a1e414f01ed3fc51e9e704d69`
- Import mode: shallow Git submodule
- Intended use: candidate renderer/block/agent architecture for the Beagle
  Workbench bake-off.

## Boundary Rules

- Do not import `apps/warp-workbench` from `apps/beagle-monorepo`,
  `beagle-mcp-server`, or `apps/beagle-memory-engine`.
- Do not commit private terminal logs, memories, truthsets, PDFs, credentials,
  or cluster artifacts.
- All Beagle memory writes must cross the assisted-import API with secret scan,
  redaction, provenance, and audit.
