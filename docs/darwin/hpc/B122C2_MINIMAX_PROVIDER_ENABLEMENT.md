# B12.2c.2 - Cheap Provider Expansion (MiniMax)

## Current status

B12.2c.2 is currently `GO`.

Canonical live smoke request ID:

- `b122c2-minimax-0321141230`

Canonical smoke evidence will live under:

- `.artifacts/darwin-hpc/minimax-bridge-smoke/provider-summary.json`
- `.artifacts/darwin-hpc/minimax-bridge-smoke/health.json`
- `.artifacts/darwin-hpc/minimax-bridge-smoke/providers.json`
- `.artifacts/darwin-hpc/minimax-bridge-smoke/execute-minimax.json`
- `.artifacts/darwin-hpc/minimax-bridge-smoke/ledger-tail.jsonl`
- `.artifacts/darwin-hpc/minimax-bridge-smoke/smoke.json`
- `.artifacts/darwin-hpc/minimax-bridge-smoke/final-cluster-health.txt`

## Objective

Enable MiniMax as the next cheap-lane provider using the already-proven
DeepSeek and GLM-5 bridge path as the template:

1. keep the existing Beagle bridge foundation intact
2. wire MiniMax through the existing cheap API lane
3. expose MiniMax in live provider listing as implemented
4. prove one real MiniMax execute path
5. keep ledger append and cluster health intact

## Runtime shape

This phase reuses the existing bridge surfaces only:

- `GET /api/darwin/bridge/health`
- `GET /api/darwin/bridge/providers`
- `POST /api/darwin/bridge/execute`

## Architectural decision

- MiniMax is added as one provider only; no multi-provider expansion happens
  here
- the existing cheap provider request, response and ledger contracts remain
  unchanged
- MiniMax uses the official Anthropic-compatible interface, wired directly from
  the Beagle bridge runtime
- no benchmark routing, fallback magic, UI, ingress, edge, HA or human premium
  lane changes are introduced

## Placement

- bridge runtime: `crates/beagle-darwin/src/tool_bridge.rs`
- cluster secret contract: `k8s/beagle/secret.example.yaml`
- cluster config contract: `k8s/beagle/configmap.yaml`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_minimax_bridge_smoke.sh`

## Success condition

The phase closes when:

1. MiniMax appears in the live provider listing
2. MiniMax is marked implemented on the cheap API lane
3. one real MiniMax execute smoke succeeds
4. the bridge ledger records the MiniMax request
5. cluster remains green
6. no bridge redesign is required

## Live result

The validated runtime expansion proved MiniMax is now live on the Beagle cheap
lane:

- live provider listing now exposes `minimax` as `implemented=true`,
  `configured=true`, `cluster_callable=true`,
  `default_model=MiniMax-M2.7`
- the canonical cluster wiring uses
  `BEAGLE_MINIMAX_BASE_URL=https://api.minimax.io/anthropic`
- one real `minimax` execute request completed successfully through the live
  Beagle bridge path as request `b122c2-minimax-0321141230`
- the append-only bridge ledger recorded the successful MiniMax request under
  `BEAGLE_DATA_DIR/tool-bridge/tool_bridge_events.jsonl`
- cluster remained green after build, image load, deploy and smoke

## Transport note

MiniMax proved reachable from the cluster on the official Anthropic-compatible
endpoint, but the runtime required `HTTP/1.1` request pinning for the live
execute path to complete cleanly. This preserves the Beagle bridge contract
while avoiding a broader bridge redesign.
