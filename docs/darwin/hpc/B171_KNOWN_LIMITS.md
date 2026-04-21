# B17.1 — Known Limits

- This phase is turn-ingest and bounded query only. It is not a full long-term memory subsystem.
- Neo4j linkage is intentionally not expanded here.
- Query is Qdrant-first when configured and otherwise falls back to a repo-native persisted local index; it is not an uncontrolled transcript dump.
- Physio attachment is best-effort. Ingest does not fail solely because physio is absent.
- Experiment flags are best-effort and bounded to the currently available Beagle runtime context.
- The current live cluster does not materialize `postgres/redis/qdrant`, so the canonical live run operated in local memory mode instead of the fuller bridge/Qdrant path.
- Local Rust is still weaker than the containerized proof path; strong compile proof remains containerized.
- MCP validation depends on local Node tool availability for the `beagle-mcp-server` package.
