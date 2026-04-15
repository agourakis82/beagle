# B12.3 Known Limits

## Current limits

- the internal surface is JSON-first and operator-facing; there is no public UI
- the upstream Darwin HPC gateway remains the execution boundary for profiles,
  submit, status and result queries
- Beagle reaches the upstream gateway through an explicit bounded network policy
  exception from namespace `beagle` into `darwin-platform`
- freshly submitted jobs remain visible first through the job/status/artifact
  surface; the result catalog stays object-plane-backed and only lists
  published bundles
- raw scheduler payload passthrough remains blocked
- DeepSeek remains the only cheap provider validated end-to-end
- GLM-5, Grok fast and MiniMax remain staged in the cheap lane
- MCP remains contract-ready but not yet live as a runtime lane
- ingress, edge, HA and broader self-service remain out of scope

## Interpretation

This phase is intentionally about operational coherence, not provider breadth or
public product surface. The goal is to make one internal Beagle surface capable
of operating the already-proven Darwin HPC stack without reopening lower-layer
decisions.
