# BEAGLE Exocortex — 2026 Roadmap (ResearchOps-first)

This document is the implementation plan for the **complete BEAGLE Exocortex**: a continuously-updated, research-driven personal scientific exocortex with measurable retrieval quality.

## Baseline (already implemented in this repo)

- **Core server**: `apps/beagle-monorepo/` (Axum API + pipelines).
- **Exocortex orchestration**: `crates/beagle-exocortex/` (identity, context, memory bridge, orchestrator).
- **LLM routing**: `crates/beagle-llm/` (tiered router, providers, usage stats).
- **Continuous RAG update (Rust)**: `crates/beagle-rag-update/`
  - `darwin-incremental-indexer` (git diff incremental re-index + delete-on-removed)
  - `darwin-knowledge-manager` (PDF/docs/books → separate Qdrant collections)
  - `darwin-research-harvester` (literature backends → `darwin-papers`)
  - `darwin-web-harvester` (URLs → `darwin-docs`)
- **GitHub push trigger**: `POST /webhooks/github/push` (HMAC via `GITHUB_WEBHOOK_SECRET`) triggers incremental indexing for the pushed repo.
- **Auto-update via systemd**: `scripts/systemd/` timers for incremental indexing and research harvesting.

## 2026 Goals (what “complete” means)

1. **Fresh knowledge, continuously**: repos + papers + web docs are kept current with provenance and deletion semantics.
2. **SOTA briefs on autopilot**: curated topics produce structured, cited summaries and “what changed since last week”.
3. **Retrieval quality is measurable**: evaluation gates prevent silent regressions (recall@k, MRR, citation validity).
4. **Cost-aware multi-model**: default routing favors cheap providers (MiniMax → Grok → DeepSeek) with hard quotas.
5. **Operational reliability**: retries, rate limits, observability, and webhook-based error notifications.

## Workstreams (implementation order)

### A) Provenance + ingestion ledger (P0)

- Add a small **ingestion ledger** (Postgres or sqlite) to record per document:
  - `doc_id`, `source_type`, `source_url/path`, `hash`, `fetched_at`, `license`, `tags`, `collection`, `status`
- Enforce **idempotent re-ingest** by `doc_id` + content hash (skip unchanged; delete+replace on change).
- Define a **license/robots policy layer** for deep web harvesting (allow/deny lists, robots.txt respect, attribution fields).

### B) Deep web ingestion (P0 → P1)

- Add sources beyond single URLs:
  - RSS/Atom feeds (journals, arXiv categories, lab blogs)
  - sitemaps (docs sites), simple crawling with depth limits
- Improve extraction:
  - HTML: boilerplate removal + keep headings/lists/code blocks
  - PDFs: optional “full text” fetch when legally allowed + local indexing via `pdftotext`

### C) ResearchOps loop (P1)

- Standardize **topic registry** (`scripts/darwin-research-topics.yaml`) for:
  - multi-query runs, per-topic tags, backend lists, max-results, enabled flags
- Add a “nightly” pipeline:
  1) harvest (papers + web)
  2) synthesize brief (LLM) with citations
  3) run eval suite
  4) notify webhook on failures or drift

### D) Retrieval + ranking upgrades (P1 → P2)

- Hybrid search across collections (`BEAGLE_QDRANT_COLLECTIONS=darwin-repos,darwin-papers,darwin-docs,darwin-books`).
- Optional reranking and query routing by domain (code vs papers vs docs).
- Citation hygiene: store stable `doc_id`, `source_url`, and for repos: `repo`, `file`, `commit`.

### E) Evaluation harness (P1)

- Create a small `beagle-eval` crate or `darwin-eval` binary that:
  - runs “golden queries” → asserts expected `doc_id` appears in top-k
  - measures recall@k / MRR and saves trend history
  - validates citations (URL reachable optional, DOI format, repo commit present)

### F) Integrations (P2)

- MCP tooling: expose “trigger index / trigger harvest / status” actions via the existing MCP server.
- Optional UI: minimal dashboard for “what changed”, eval drift, and corpus health.

## Provider policy (MiniMax → Grok → DeepSeek)

- Set:
  - `BEAGLE_ROUTING_POLICY=minimax-grok-deepseek`
  - `MINIMAX_API_KEY=...` (rotate if ever pasted into chat/logs)
  - `MINIMAX_API_BASE=https://api.minimax.io/anthropic/v1`
  - `DEEPSEEK_API_KEY=...` (only for math tier)

## Build note (Ubuntu 26 / Python 3.13)

If `cargo` fails with PyO3 “Python 3.13 newer than supported”, build with:
`PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1 cargo check --locked --offline -p beagle-monorepo`

