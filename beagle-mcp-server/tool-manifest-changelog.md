# Beagle MCP Tool Manifest Changelog

## beagle-mcp-v1.4-graphrag-runtime

- Tool count: 29
- Tool manifest hash: `sha256:2de2ca00307cdde27e6fab412bf56e07c827885c73a65e1885dd09fb929d5d67`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public surfaces.
- Added GraphRAG++ living-memory tools:
  - `beagle_memory_graph_status`
  - `beagle_memory_bakeoff_status`
  - `beagle_graphrag_query`
  - `beagle_work_memory_capture`
- These tools expose runtime/bake-off status, evidence-graph retrieval and Codex/Claude Code work-memory capture while keeping JSONL on the cluster PVC as the canonical store.

## beagle-mcp-v1.2

- Tool count: 25
- Tool manifest hash: `sha256:bea92c67638a38f2de59086abb3f8bd5227db8ca9a08d78a257b741a38bcb5e3`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public surfaces.
- Added `beagle_assisted_import_batch` and `beagle_memory_project_graph` so MCP agents write visible context as GraphRAG++ Episode+Atom memory instead of loose transcripts.
- Compatibility update: `beagle_memory_ingest_chat` now routes Claude/ChatGPT-style chat imports through the same assisted import pipeline, preserving the legacy tool name while producing projected GraphRAG++ memory and audit records.
