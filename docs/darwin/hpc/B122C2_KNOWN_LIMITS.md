# B12.2c.2 Known Limits

## Current limits

- this phase enables MiniMax only; Grok fast remains staged
- the bridge still uses the existing cheap API request, response and ledger
  contracts
- the phase does not add routing intelligence, fallback behavior or benchmark
  selection
- human premium providers remain represented but never cluster-executed
- no UI, ingress, edge or HA work is introduced here
- the canonical cluster wiring uses the MiniMax Anthropic-compatible endpoint
  configured via `BEAGLE_MINIMAX_BASE_URL`
- the current live runtime pins MiniMax requests to `HTTP/1.1` for transport
  stability on the Anthropic-compatible endpoint

## Interpretation

B12.2c.2 is a narrow provider expansion on top of the already-proven bridge
foundation. It proves breadth by one provider, not by a multi-provider control
system.
