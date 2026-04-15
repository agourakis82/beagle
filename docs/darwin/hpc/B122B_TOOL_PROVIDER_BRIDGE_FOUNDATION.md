# B12.2b - Beagle Tool/Provider Bridge Foundation

## Objective

Materialize the first repo-native bridge layer inside Beagle between the Darwin workspace plane, the HPC gateway, the result plane, and a cheap-provider lane.

## Architectural decision

- Beagle does not become an OpenAI/Anthropic-first paid provider gateway.
- Human premium tools such as Codex CLI and Claude Code remain operator-facing.
- The cluster only executes programmatic lanes.
- The bridge is neutral and contract-first:
  - `BridgeKind`
  - `BridgeMode`
  - `BridgeRequest`
  - `BridgeResponse`
  - `BridgeLedger`

## Runtime shape

Initial internal HTTP surface:

- `POST /api/darwin/bridge/execute`
- `GET /api/darwin/bridge/health`
- `GET /api/darwin/bridge/providers`

Initial lanes:

- human premium lane
- cheap API lane
- MCP / connector lane

## First runtime cut

The B12.2b runtime is intentionally narrow:

- the request/response contract is stable
- the ledger is append-only JSONL under `BEAGLE_DATA_DIR`
- the cluster may represent human-session tasks, but it must not execute them automatically
- DeepSeek is the first cheap API provider wired end-to-end
- GLM-5, Grok fast, MiniMax and MCP remain represented in contract and health surfaces even when not yet executable

## Current runtime finding

The bridge foundation is now live in the cluster-facing Beagle service:

- `GET /api/darwin/bridge/health` answers from the running deployment
- `GET /api/darwin/bridge/providers` exposes the initial bridge catalog
- `POST /api/darwin/bridge/execute` correctly records and defers human premium requests
- the bridge ledger is appended under `BEAGLE_DATA_DIR`
- a real `deepseek` cheap-provider execution now completes successfully through the live cluster deployment

## Success condition

The foundation is considered alive when:

1. the bridge exists in repo-native Beagle placement
2. the internal endpoints answer from the running Beagle service
3. a bridge request produces a structured response
4. a ledger event is appended under `BEAGLE_DATA_DIR`
5. no parallel architecture is created
