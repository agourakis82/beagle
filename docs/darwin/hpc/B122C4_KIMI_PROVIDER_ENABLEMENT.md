# B12.2c.4 - Cheap Provider Expansion (Kimi)

## Current status

B12.2c.4 is currently `GO`.

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/kimi-bridge-smoke/provider-summary.json`
- `.artifacts/darwin-hpc/kimi-bridge-smoke/health.json`
- `.artifacts/darwin-hpc/kimi-bridge-smoke/providers.json`
- `.artifacts/darwin-hpc/kimi-bridge-smoke/execute-kimi.json`
- `.artifacts/darwin-hpc/kimi-bridge-smoke/ledger-tail.jsonl`
- `.artifacts/darwin-hpc/kimi-bridge-smoke/smoke.json`
- `.artifacts/darwin-hpc/kimi-bridge-smoke/final-cluster-health.txt`

Canonical live request ID:

- `b122c4-kimi-0321152244`

## Objective

Enable Kimi as the next cheap-lane provider using the already-proven bridge
path:

1. keep the existing Beagle bridge foundation intact
2. wire `kimi` through the existing cheap API lane
3. expose `kimi` in live provider listing as implemented
4. prove one real Kimi execute path
5. keep ledger append and cluster health intact

## Runtime shape

This phase reuses the existing bridge surfaces only:

- `GET /api/darwin/bridge/health`
- `GET /api/darwin/bridge/providers`
- `POST /api/darwin/bridge/execute`

## Architectural decision

- Kimi is added as one provider only; no multi-provider expansion happens here
- the existing cheap provider request, response and ledger contracts remain
  unchanged
- the `kimi` contract slot is backed by the Groq OpenAI-compatible
  chat-completions path
- no fallback magic, benchmark routing, UI, ingress, edge, HA or human premium
  lane changes are introduced

## Placement

- bridge runtime: `crates/beagle-darwin/src/tool_bridge.rs`
- cluster secret contract: `k8s/beagle/secret.example.yaml`
- cluster config contract: `k8s/beagle/configmap.yaml`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_kimi_bridge_smoke.sh`

## Success condition

The phase closes when:

1. Kimi appears in the live provider listing
2. Kimi is marked implemented on the cheap API lane
3. one real Kimi execute smoke succeeds
4. the bridge ledger records the Kimi request
5. cluster remains green
6. no bridge redesign is required

## Live result

The phase is now closed as `GO`.

Live proof from the canonical smoke:

1. `kimi` appears in provider listing as implemented on the cheap API lane
2. one real execute path succeeded with model
   `moonshotai/kimi-k2-instruct-0905`
3. the execute result returned `status=success` with request ID
   `b122c4-kimi-0321152244`
4. the append-only ledger recorded the canonical Kimi request
5. post-smoke cluster health stayed green and `Slurmctld(primary)` remained `UP`
6. no request, response or ledger contract redesign was required
