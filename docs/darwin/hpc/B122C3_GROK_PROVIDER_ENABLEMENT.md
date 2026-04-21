# B12.2c.3 - Cheap Provider Expansion (Grok Fast)

## Current status

B12.2c.3 is currently `GO`.

Canonical live smoke request ID:

- `b122c3-grok-0321150205`

Canonical smoke evidence will live under:

- `.artifacts/darwin-hpc/grok-bridge-smoke/provider-summary.json`
- `.artifacts/darwin-hpc/grok-bridge-smoke/health.json`
- `.artifacts/darwin-hpc/grok-bridge-smoke/providers.json`
- `.artifacts/darwin-hpc/grok-bridge-smoke/execute-grok.json`
- `.artifacts/darwin-hpc/grok-bridge-smoke/ledger-tail.jsonl`
- `.artifacts/darwin-hpc/grok-bridge-smoke/smoke.json`
- `.artifacts/darwin-hpc/grok-bridge-smoke/final-cluster-health.txt`

## Objective

Enable Grok fast as the next cheap-lane provider using the already-proven
bridge path:

1. keep the existing Beagle bridge foundation intact
2. wire `grok_fast` through the existing cheap API lane
3. expose `grok_fast` in live provider listing as implemented
4. prove one real Grok fast execute path
5. keep ledger append and cluster health intact

## Runtime shape

This phase reuses the existing bridge surfaces only:

- `GET /api/darwin/bridge/health`
- `GET /api/darwin/bridge/providers`
- `POST /api/darwin/bridge/execute`

## Architectural decision

- Grok fast is added as one provider only; no multi-provider expansion happens
  here
- the existing cheap provider request, response and ledger contracts remain
  unchanged
- the `grok_fast` contract slot is backed by the official xAI chat-completions
  path
- no fallback magic, benchmark routing, UI, ingress, edge, HA or human premium
  lane changes are introduced

## Placement

- bridge runtime: `crates/beagle-darwin/src/tool_bridge.rs`
- cluster secret contract: `k8s/beagle/secret.example.yaml`
- cluster config contract: `k8s/beagle/configmap.yaml`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_grok_bridge_smoke.sh`

## Success condition

The phase closes when:

1. Grok fast appears in the live provider listing
2. Grok fast is marked implemented on the cheap API lane
3. one real Grok fast execute smoke succeeds
4. the bridge ledger records the Grok fast request
5. cluster remains green
6. no bridge redesign is required

## Live result

The validated runtime expansion proved Grok fast is now live on the Beagle
cheap lane:

- live provider listing now exposes `grok_fast` as `implemented=true`,
  `configured=true`, `cluster_callable=true`,
  `default_model=grok-4-1-fast-reasoning`
- the canonical cluster wiring uses `XAI_API_KEY`,
  `BEAGLE_XAI_BASE_URL=https://api.x.ai/v1` and
  `BEAGLE_GROK_MODEL=grok-4-1-fast-reasoning`
- one real `grok_fast` execute request completed successfully through the live
  Beagle bridge path as request `b122c3-grok-0321150205`
- the append-only bridge ledger recorded the successful Grok fast request under
  `BEAGLE_DATA_DIR/tool-bridge/tool_bridge_events.jsonl`
- cluster remained green after build, image load, deploy and smoke
