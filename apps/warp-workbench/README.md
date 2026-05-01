# Beagle Warp Workbench

`apps/warp-workbench` is the AGPL boundary for the Warp-derived Beagle
Workbench showcase. It may contain AGPL code, adapters, experiments, and
license notices related to Warp.

The rest of Beagle remains separated by protocol boundaries:

- `beagle-core`, MCP, Sounio, memory engine, and private cluster data are not
  allowed to import code from this directory.
- Canonical memory remains in the cluster through JSONL/Merkle/Chronoself and
  `/api/exocortex/v1/memory/assisted-import`.
- Private conversations, truthsets, OrangeFS artifacts, tokens, and local user
  data must never be committed here.

The initial spike uses a dual bridge:

- `beagle-terminal-v1` remains the source of Beagle workspace sessions,
  panes, blocks, and memory provenance.
- Warp-derived block/session/agent concepts are converted through
  `bridge/warp-beagle-bridge.mjs` until a bake-off decides whether Warp or
  Beagle becomes the long-term authority.

## Vendor

Warp is vendored as a Git submodule at `vendor/warp`.

Current vendor target:

- Repository: <https://github.com/warpdotdev/Warp.git>
- Commit: `805b3e2a576e689a1e414f01ed3fc51e9e704d69`
- License: Warp UI crates are MIT; the rest of Warp is AGPL v3 as documented
  upstream.

Run:

```bash
git submodule update --init --depth 1 apps/warp-workbench/vendor/warp
npm --prefix apps/warp-workbench run check
```
