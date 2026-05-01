# Beagle GraphRAG++ Memory v1.2

Last updated: 2026-04-26

## Purpose

GraphRAG++ Memory v1.2 makes persistent memory the center of Beagle again. MCP is the nervous system, but memory is the tissue: every useful import should become auditable episodes, extracted atoms, temporal context, provenance, and retrievable evidence.

The v1.2 rule is:

```text
visible conversation or export
  -> OmniMemory import
  -> MemoryEpisode
  -> MemoryAtom[]
  -> hybrid temporal retrieval
```

Do not treat a transcript as final memory. A transcript is raw material.

## Canonical Logs

Append-only logs under `/var/lib/beagle/exocortex` remain the source of truth:

- `omnimemory_imports.jsonl`: raw imported conversations or user-supplied exports.
- `memory_events.jsonl`: explicit operational memory events.
- `memory_episodes.jsonl`: projected import/event envelopes with source, session, privacy, provenance, content hash, and Chronoself links.
- `memory_atoms.jsonl`: extracted decisions, hypotheses, entities, relations, projects, principles, actions, evidence, and open questions.
- `memory_projection_runs.jsonl`: idempotent projection runs with schema version, counts, duplicate count, errors, and projection hash.

Indexes, embeddings, graph stores, and caches are derived. They must be reconstructible from append-only logs.

The MacBook is not a memory authority. It is only a development console and temporary operator surface. Runtime Exocortex state must be written through `beagle-core` in the cluster, backed by the `beagle-data` PVC. GitHub stores code, manifests, docs, and schema history; it must not store private memory JSONL payloads.

## Privacy Defaults

MCP assisted import defaults to `sensitive`.

`restricted` content is rejected by `beagle_assisted_import_batch` and is skipped by the core projection. Future restricted ingestion needs a separate review path, explicit consent, and stronger audit semantics.

## Public Interfaces

Core:

- `POST /api/exocortex/v1/memory/project`
- `GET /api/exocortex/v1/memory/projection/status`
- `POST /api/exocortex/v1/graphrag/query`

MCP:

- `beagle_assisted_import_batch`
- `beagle_memory_project_graph`
- resource `beagle://memory/graph/status`

Compatibility:

- `/api/memory/query`
- `search`
- `fetch`
- `beagle_memory_query`

These read paths use GraphRAG++ when projected memory exists. If no vector backend is configured, the response explicitly degrades to lexical, graph, temporal, Chronoself, and provenance signals.

## Retrieval Contract

GraphRAG++ query responses include:

- `summary`
- `evidence[]`
- `atoms[]`
- `episodes[]`
- `relations[]`
- `temporal_context`
- `provenance`
- `confidence`
- `degraded_reason`

The current v1.2 retrieval is hybrid temporal: lexical scoring, projected graph relations, recency, Chronoself links, privacy filtering, and provenance. Vector and graph database backends can be added later without changing the canonical logs.

## Agent Workflow

For Claude, ChatGPT, Codex, or any MCP client:

1. Import only visible or explicitly provided material.
2. Use `beagle_assisted_import_batch` for conversation/project context.
3. Use `beagle_memory_project_graph` if a broader projection run is needed.
4. Confirm freshness with `beagle://memory/graph/status`.
5. Retrieve through `beagle_memory_query`, `search`, or `fetch`.

This is the difference between “saving chat history” and building the exocortex: Beagle should remember decisions, hypotheses, projects, actions, and provenance, not just text.
