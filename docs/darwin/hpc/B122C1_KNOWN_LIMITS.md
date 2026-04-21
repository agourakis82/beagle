# B12.2c.1 Known Limits

## Current limits

- this phase enables GLM-5 only; Grok fast and MiniMax remain staged
- the bridge still uses the existing cheap API request, response and ledger
  contracts
- the phase does not add routing intelligence, fallback behavior or benchmark
  selection
- human premium providers remain represented but never cluster-executed
- no UI, ingress, edge or HA work is introduced here
- the canonical cluster wiring currently relies on the Z.AI coding-plan endpoint
  configured via `BEAGLE_ZAI_BASE_URL`

## Interpretation

B12.2c.1 is a narrow provider expansion on top of the already-proven bridge
foundation. It proves breadth by one provider, not by a multi-provider control
system.
