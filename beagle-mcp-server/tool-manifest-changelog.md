# Beagle MCP Tool Manifest Changelog

## beagle-mcp-v2.3-context-compiler-policy

- Tool count: 57
- Tool manifest hash: `sha256:f027a6f024e13f14e05823c71ba0c20c98e5b10f28e4d688f062b7bddb0fc833`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, context-compiler, policy-learner, DreamCycle, Retrieval Agent, MemoryArena, benchmark, and governance surfaces.
- Added Adaptive Context Compiler tools:
  - `beagle_context_compile`
  - `beagle_context_pack_get`
- Added Memory Policy Learner tools:
  - `beagle_memory_effectiveness_record`
  - `beagle_memory_policy_status`
- Added DreamCycle tools:
  - `beagle_dreamcycle_run`
  - `beagle_dreamcycle_status`
- `search`, `fetch`, and `beagle_retrieval_agent_query` expose `context_pack_id`, `policy_version`, policy gate, DreamCycle status and fallback metadata when available.

## beagle-mcp-v2.2-retrieval-agent-memoryarena

- Tool count: 51
- Tool manifest hash: `sha256:f518a130977549720d33980533d26852a9555b55ade97a76bf0995135fdeb577`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, retrieval-agent, MemoryArena, benchmark, and governance surfaces.
- Added Retrieval Agent tools:
  - `beagle_retrieval_agent_query`
  - `beagle_retrieval_agent_status`
- Added Private MemoryArena tools:
  - `beagle_memoryarena_benchmark_run`
  - `beagle_memoryarena_benchmark_status`
- `search` and `fetch` now prefer the v2.2 Retrieval Agent canary path, which records strategy, subqueries, evidence pack, runtime trace, fallback chain, and provenance before falling back to canonical memory query.

## beagle-mcp-v2.1-native-semantic-backbone

- Tool count: 47
- Tool manifest hash: `sha256:8744f919a9d1cbea3bb721d334e9a3e4a159dbb1390b59d49f5f9fa548308a6a`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, semantic-index, truthset, benchmark, and governance surfaces.
- `search` and `fetch` now prefer the memory-engine HyperMemory multivector hot path and fall back to canonical `/api/memory/query` if the lab is unavailable.
- `beagle_retrieval_trace` now calls the memory-engine path and returns native semantic results, MaxSim scores, graph expansion trace, reranker trace, fallback chain, truthset gate, and provenance.
- `beagle_semantic_index_status` and `beagle_semantic_index_rebuild` now describe the v2.1 LanceDB-native table contract: `semantic_memory_v1`, row count, native LanceDB status, MaxSim readiness, and embedding backend.

## beagle-mcp-v2.0-alpha-semantic-truth-backbone

- Tool count: 47
- Tool manifest hash: `sha256:3f3624a0b21cdbc44ba3a5d5f379d3306669d494b0a76f7146e2541c2e2a2ac8`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, semantic-index, truthset, benchmark, and governance surfaces.
- Added Semantic Truth Backbone tools:
  - `beagle_semantic_index_status`
  - `beagle_semantic_index_rebuild`
  - `beagle_retrieval_trace`
- `beagle_graphrag_query`, `search`, `fetch`, and mesh queries now treat `hypermemory_multivector` as the audacious v2.0-alpha hot path while preserving explicit fallback to HyperMemory and lexical+graph+temporal retrieval.

## beagle-mcp-v1.9-memory-truth-agent-os

- Tool count: 44
- Tool manifest hash: `sha256:f01ee7613c364a4acb68fcb4a9e77c070f392a2ed94c5db04d71de017de58e42`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, truthset, benchmark, and governance surfaces.
- Added Memory Truth + Agent OS tools:
  - `beagle_memory_truthset_draft`
  - `beagle_memory_truthset_review`
  - `beagle_agent_observer_status`
- `beagle_memory_benchmark_run` is now truthset-aware and reports the v1.9 promotion gate: HyperMemory must beat baseline by the configured margin with consecutive passing runs, zero restricted leaks, full provenance, and no critical regression before hot-path eligibility.

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
