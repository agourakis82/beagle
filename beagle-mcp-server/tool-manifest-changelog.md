# Beagle MCP Tool Manifest Changelog

## beagle-mcp-v3.5-model-ecology-router

- Tool count: 79
- Tool manifest hash: `sha256:3397d62e813ebaf2853d9ba7eb6f90611e5500b1585e15322d63d701350ac7d2`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains absent. The new surface is role-routing and failed-write recovery, not destructive control.
- Added model ecology and LC-NE rescue tools:
  - `beagle_agent_registry`
  - `beagle_agent_route`
  - `beagle_write_probe`
  - `beagle_failed_write_inbox`
  - `beagle_failed_write_rescue`
- Beagle now exposes role-first routing for Sounio/Beagle agents and a reviewed rescue path for Claude iOS failed writes into sensitive cluster-canonical Episode+Atom/SounioMoment memory.

## beagle-mcp-v3.4-live-memory-ranking

- Tool count: 74
- Tool manifest hash: `sha256:ed740c5b25e53ba86590d10684c221a1539c68d60b2d85f292a15860b61334cb`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains absent. This is a schema-only retrieval update.
- `beagle_graphrag_query` now accepts optional `ranking_policy=strict_recent_guarded|legacy_stable`. The default core policy boosts live Workbench/Codex/Claude/Sounio memory while Stable Fact Guard protects canonical facts such as portfolio identity, Mandic RA, DOI, dates and institutional rules.
- Tool responses may include `ranking_trace`, `recency_boost_applied`, and `stable_fact_guard_applied` from core without requiring clients to change existing calls.

## beagle-mcp-v3.0-multimodal-composer

- Tool count: 74
- Tool manifest hash: `sha256:299863bdaf387f78ec91618d05972e1b66709eb06f08455bc9b000f5aa5b61ec`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from capture, visual evidence, Sounio typing, review, Apple, MCP, and local-agent surfaces.
- Added explicit multimodal capture tools:
  - `beagle_capture_session_start`
  - `beagle_capture_session_status`
  - `beagle_visual_evidence_analyze`
  - `beagle_capture_review_promote`
- The v3.0 surface makes the anti-creepy posture protocol-visible: capture sessions are user-initiated, visual analysis is local-first, external multimodal processing requires confirmation, and promotions are append-only Sounio moments or claim seeds.

## beagle-mcp-v2.9-ambient-sounio-workday

- Tool count: 70
- Tool manifest hash: `sha256:bdcdd1935751e4573f843277e0e7b940782fb6968d4371b9bf4af8fdd97d5ce6`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, Sounio Workday, ambient typing, review, PaperRun, digest, and approval surfaces.
- Added Ambient Sounio tools:
  - `beagle_sounio_moment_type`
  - `beagle_sounio_workday_status`
  - `beagle_sounio_moment_review`
- Added readable Sounio resources:
  - `beagle://sounio/workday/current`
  - `beagle://sounio/moments/recent`
- The v2.9 surface makes the everyday loop explicit: Beagle observes real work/capture surfaces, while Sounio types intentions, decisions, Claim<T> seeds, evidence and next gestures conservatively.

## beagle-mcp-v2.5-sounio-claims-theatre

- Tool count: 67
- Tool manifest hash: `sha256:f3acd71e00696b189d16df381195235a8cb2a464c0e7a06dac05c15e48be8e6e`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, Sounio, PaperRun, Theatre, digest, claim-review, and approval surfaces.
- Added Sounio Claim<T> and PaperRun Theatre tools:
  - `beagle_sounio_claim_check`
  - `beagle_sounio_paperrun_add_claim`
  - `beagle_sounio_claim_review`
  - `beagle_sounio_paperrun_theatre`
  - `beagle_sounio_public_digest`
- The v2.5 surface makes the boundary explicit: Beagle observes the research/process trace, while Sounio types claims epistemically as Belief, Contest, Knowledge, or Robust.
- Public digest remains sanitized; full trace packs and private corpus references stay cluster-only.

## beagle-mcp-v2.4-sounio-paperrun

- Tool count: 62
- Tool manifest hash: `sha256:07d659172b334b5ee0769ad6f6b2477d1c76f3979e2fa16954433aad8da8afd8`
- Security profile: `sott-non-destructive-oauth-audited`
- Notes: no tool exposes `destructiveHint=true`; `admin:destructive` remains reserved and absent from public, mobile, local-agent, Sounio, PaperRun, Temporal runner, artifact, and approval surfaces.
- Added Sounio PaperRun tools:
  - `beagle_sounio_program_check`
  - `beagle_sounio_paperrun_start`
  - `beagle_sounio_paperrun_status`
  - `beagle_sounio_paperrun_approve_step`
  - `beagle_sounio_trace_query`
- Added readable Sounio resource:
  - `beagle://sounio/paperrun/current`
- The v2.4 surface turns Sounio into an operational IR for durable cognitive workflows: program validation, PaperRun start/status, human approval, trace query, and Beagle paper artifacts remain audited, non-destructive, and linked to cluster-canonical memory.

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
