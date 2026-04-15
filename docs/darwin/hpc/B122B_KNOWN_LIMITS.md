# B12.2b Known Limits

## Current limits

- DeepSeek is the only cheap provider wired and validated end-to-end in this first cut
- GLM-5, Grok fast and MiniMax are represented in config and contract, but remain staged
- MCP is represented in contract and health only
- human premium providers are intentionally deferred, not executable by the cluster
- ledger persistence is append-only JSONL, not a queryable store yet
- the phase does not add UI, ingress, edge, HA or benchmark routing

## Interpretation

This foundation is intentionally small. It proves stable bridge semantics, stable placement, and stable ledger behavior before broader provider breadth or routing intelligence is added.
