# B22.4 Known Limits

- Retrieval awareness is bounded to the existing context, routing, launch, and handoff surfaces.
- This phase does not introduce heavy reranking.
- This phase does not introduce a new graph runtime.
- Retrieval-guided routing is advisory and only applies when stronger selectors are absent.
- Tool compatibility is still enforced; retrieval cannot push a tool into an unsupported subagent.
- This phase does not change the Beagle-owned identity model.
