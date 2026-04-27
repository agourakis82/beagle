# Beagle MCP Tool Manifest Changelog

## beagle-mcp-v1.8-memory-bench-hypermemory

- Tool count: 41
- Tool manifest hash: `sha256:51098dcfbafc876345ed65bfdba3b7ecd9775295a3451df8351ed5048d4496c9`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, memory-engine, benchmark, and governance surfaces.
- Added Memory Bench tools:
  - `beagle_memory_benchmark_run`
  - `beagle_memory_benchmark_status`
- `beagle_graphrag_query` now accepts `mode=hypermemory`, but HyperMemory stays derived/advisory until Memory Bench beats baseline with complete provenance and zero restricted leakage.

## beagle-mcp-v1.6-self-governing-exocortex

- Tool count: 39
- Tool manifest hash: `sha256:a8a52919fd9995a8ea7ab742d1ba1a84ecc5a0da4f46140356035f9d6eaa9899`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, memory-engine, and governance surfaces.
- Added self-governing memory tools:
  - `beagle_memory_governance_status`
  - `beagle_memory_governance_run`
  - `beagle_memory_contradictions_recent`
  - `beagle_memory_engine_eval_run`
  - `beagle_memory_engine_governance_evaluate`
- These tools expose Triad Strict candidate governance, contradiction review, shadow evals, and memory-engine governance evaluation while keeping promoted memory authority in core JSONL/Merkle/Chronoself on the cluster PVC.

## beagle-mcp-v1.5-federated-memory-engine

- Tool count: 34
- Tool manifest hash: `sha256:1d6e19bf6541cb05e4b1ba3bed9c8170c00e495e1e1f20e5f7453b5d9bdb7eb3`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, and memory-engine surfaces.
- Added federated living-memory tools:
  - `beagle_memory_engine_status`
  - `beagle_memory_mesh_query`
  - `beagle_memory_bakeoff_run`
  - `beagle_memory_candidates_list`
  - `beagle_memory_candidate_quorum`
- These tools expose the v1.5 memory-engine mesh, cluster-only bake-off runs, candidate memory items, and strict Triad quorum decisions while keeping JSONL/Merkle/Chronoself on the cluster PVC as the canonical authority.

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
