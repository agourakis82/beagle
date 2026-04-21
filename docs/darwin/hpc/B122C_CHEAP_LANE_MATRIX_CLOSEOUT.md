# B12.2c - Cheap Lane Matrix Closeout

## Current status

The cheap API lane is now effectively `CLOSED / LIVE` for the currently
promoted provider set:

- `deepseek`
- `glm5`
- `minimax`
- `grok_fast`
- `kimi`

This document is the canonical matrix-level closeout for the cheap provider
lane. The phase-specific provider documents remain valid as promotion history,
but this file is the authority for the current live matrix state.

## Canonical live defaults

- `deepseek` -> `deepseek-chat`
- `glm5` -> `glm-5`
- `minimax` -> `MiniMax-M2.7`
- `grok_fast` -> `grok-4-1-fast-reasoning`
- `kimi` -> `moonshotai/kimi-k2-instruct-0905`

## Canonical live evidence

- DeepSeek foundation smoke:
  `.artifacts/darwin-hpc/tool-bridge-smoke/execute-cheap.json`
  Request ID: `b122b-cheap-smoke`
- GLM-5 provider smoke:
  `.artifacts/darwin-hpc/glm5-bridge-smoke/execute-glm5.json`
  Request ID: `b122c1-glm5-0321135832`
- MiniMax provider smoke:
  `.artifacts/darwin-hpc/minimax-bridge-smoke/execute-minimax.json`
  Request ID: `b122c2-minimax-0321141230`
- Grok fast provider smoke:
  `.artifacts/darwin-hpc/grok-bridge-smoke/execute-grok.json`
  Request ID: `b122c3-grok-0321150205`
- Kimi provider smoke:
  `.artifacts/darwin-hpc/kimi-bridge-smoke/execute-kimi.json`
  Request ID: `b122c4-kimi-0321152244`

## Superseded evidence

- `grok_fast` with `grok-4-1-fast-non-reasoning` is superseded by the later
  canonical run using `grok-4-1-fast-reasoning`
- the superseded request remains useful as history only:
  `b122c3-grok-0321144918`

## What is now proven

1. the Beagle bridge foundation remained stable while expanding cheap-provider
   breadth
2. each promoted cheap provider completed a real live execute path
3. the append-only bridge ledger recorded real provider appends
4. image rebuild, rollout and post-smoke cluster health stayed intact through
   the promotions
5. no bridge contract redesign was required to reach multi-provider cheap-lane
   coverage

## Operational note

- local absence of `cargo` remains a confidence gap on this host
- it is not a promotion blocker because the live smokes rebuilt the image,
  published it into the cluster runtime and completed real deploy validation

## Practical interpretation

For the current Beagle scope, the cheap-lane matrix should be treated as
effectively closed. Further work should return to the main Beagle/Darwin/HPC
track unless a new cheap provider is explicitly promoted as a new canonical
phase.
