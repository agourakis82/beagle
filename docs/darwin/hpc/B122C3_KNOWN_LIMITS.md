# B12.2c.3 Known Limits

## Current limits

- this phase enables Grok fast only; it does not add any further cheap
  providers
- the bridge still uses the existing cheap API request, response and ledger
  contracts
- the phase does not add routing intelligence, fallback behavior or benchmark
  selection
- human premium providers remain represented but never cluster-executed
- no UI, ingress, edge or HA work is introduced here
- the canonical cluster wiring uses the xAI chat-completions endpoint via
  `BEAGLE_XAI_BASE_URL`
- MiniMax `HTTP/1.1` pinning remains preserved as an existing operational
  compatibility rule; this phase does not alter it

## Interpretation

B12.2c.3 is a narrow provider expansion on top of the already-proven bridge
foundation. It proves breadth by one provider, not by a multi-provider control
system.
