# B12.2c.1 - Cheap Provider Expansion (GLM-5 First)

## Current status

B12.2c.1 is currently `GO`.

Canonical live smoke request ID:

- `b122c1-glm5-0321135832`

Canonical smoke evidence will live under:

- `.artifacts/darwin-hpc/glm5-bridge-smoke/provider-summary.json`
- `.artifacts/darwin-hpc/glm5-bridge-smoke/health.json`
- `.artifacts/darwin-hpc/glm5-bridge-smoke/providers.json`
- `.artifacts/darwin-hpc/glm5-bridge-smoke/execute-glm5.json`
- `.artifacts/darwin-hpc/glm5-bridge-smoke/ledger-tail.jsonl`
- `.artifacts/darwin-hpc/glm5-bridge-smoke/smoke.json`
- `.artifacts/darwin-hpc/glm5-bridge-smoke/final-cluster-health.txt`

## Objective

Enable GLM-5 as the next cheap-lane provider using the already-proven DeepSeek
bridge path as the template:

1. keep the existing Beagle bridge foundation intact
2. wire GLM-5 through the existing cheap API lane
3. expose GLM-5 in live provider listing as implemented
4. prove one real GLM-5 execute path
5. keep ledger append and cluster health intact

## Runtime shape

This phase reuses the existing bridge surfaces only:

- `GET /api/darwin/bridge/health`
- `GET /api/darwin/bridge/providers`
- `POST /api/darwin/bridge/execute`

## Architectural decision

- GLM-5 is added as one provider only; no multi-provider expansion happens here
- the existing DeepSeek execution path is reused as the template
- the request, response and ledger contracts remain unchanged
- no benchmark routing, fallback magic, UI, ingress, edge, HA or human premium
  lane changes are introduced

## Placement

- bridge runtime: `crates/beagle-darwin/src/tool_bridge.rs`
- cluster secret contract: `k8s/beagle/secret.example.yaml`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_glm5_bridge_smoke.sh`

## Success condition

The phase closes when:

1. GLM-5 appears in the live provider listing
2. GLM-5 is marked implemented on the cheap API lane
3. one real GLM-5 execute smoke succeeds
4. the bridge ledger records the GLM-5 request
5. cluster remains green
6. no bridge redesign is required

## Live result

The validated runtime expansion proved GLM-5 is now live on the Beagle cheap
lane for the current coding-plan environment:

- live provider listing now exposes `glm5` as `implemented=true`,
  `configured=true`, `cluster_callable=true`, `default_model=glm-5`
- the canonical cluster wiring uses
  `BEAGLE_ZAI_BASE_URL=https://api.z.ai/api/coding/paas/v4`
- one real `glm5` execute request completed successfully through the live
  Beagle bridge path as request `b122c1-glm5-0321135832`
- the append-only bridge ledger recorded the successful GLM-5 request under
  `BEAGLE_DATA_DIR/tool-bridge/tool_bridge_events.jsonl`
- cluster remained green after build, image load, deploy and smoke
