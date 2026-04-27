# Beagle GraphRAG++ Runtime Bake-Off

Status: v1.4 implementation contract

## Why This Exists

Beagle should not default to the most common GraphRAG stack. The exocortex needs a living graph index that can preserve provenance, temporal validity, n-ary facts, work memory, and rebuildability from the cluster-canonical JSONL logs.

The canonical source remains `/var/lib/beagle/exocortex` on the `beagle-data` PVC. Any graph/vector database is a derived runtime and must be disposable.

## Candidates

| Runtime | Role | Why It Matters | Main Risk |
| --- | --- | --- | --- |
| FalkorDB / GraphBLAS | Primary hypothesis | Sparse linear algebra plus graph-native retrieval is a strong fit for multi-hop agentic memory. Vector index in the graph can reduce dual-store drift. | Needs cluster smoke for Cypher/vector behavior and operational health. |
| Memgraph | Streaming graph candidate | Good candidate for high-frequency work-memory updates from Codex, Claude Code, Claude iOS and Beagle app. | Vector+graph maturity must beat the simpler FalkorDB path on real queries. |
| SurrealDB | Multi-model candidate | Natural shape for MemoryWorld as document+graph+vector data. | Graph traversal and hyperedge ergonomics need proof. |
| Neo4j + Qdrant | Baseline only | Mature and familiar ecosystem. | Dual-store synchronization is a poor philosophical fit for living memory provenance. |

## Dataset

The 48h bake-off uses only cluster data:

- recent `MemoryEpisode` records
- recent `MemoryAtom` records
- Claude iOS writes
- Codex / Claude Code work-memory captures
- 20 golden queries derived from real Beagle usage

No private data is committed to GitHub or staged on the MacBook.

## Promotion Criteria

| Metric | Target |
| --- | --- |
| Top-5 hit rate | Candidate must beat baseline. |
| Multi-hop correctness | Candidate must recover project + decision + hypothesis + evidence links. |
| Provenance completeness | Every result points back to Episode/Atom/World and source refs. |
| p95 latency | Must remain usable for Home, Memory Lens and MCP tools. |
| Rebuild time | Derived runtime must rebuild from JSONL without manual repair. |
| Operational simplicity | Fewer moving parts wins if accuracy is close. |
| Apple/MCP fit | Responses must decode cleanly in Beagle app and Claude/ChatGPT MCP clients. |

## v1.4 Retrieval Contract

`POST /api/exocortex/v1/graphrag/query` returns:

- `summary`
- `evidence[]`
- `atoms[]`
- `episodes[]`
- `relations[]`
- `temporal_context`
- `provenance`
- `confidence`
- `mode`
- `graph_runtime`
- `evidence_graph`
- `community_context`
- `retrieval_trace`
- `degraded_reason?`

The first implementation is GraphSearch-lite over JSONL-derived Episode+Atom memory. If FalkorDB is configured, the response exposes that runtime but still remains honest about promotion status until bake-off gates pass.

## MemoryWorld

`MemoryWorld` is the immutable session/project/import subgraph:

- content addressed by Merkle root
- temporally valid
- reconstructible from Episode+Atom logs
- safe to expose to Apple Memory Lens and MCP resources

This gives Beagle a stable unit for future global search, community summaries, contradiction tracking and agent work-memory replay.

## Current Decision

FalkorDB / GraphBLAS is the leading hypothesis. It is not considered promoted until a cluster bake-off beats the baseline on golden queries and provenance quality.

References:

- [FalkorDB vector index](https://docs.falkordb.com/cypher/indexing/vector-index)
- [GraphSearch](https://arxiv.org/abs/2509.22009)
- [Relink](https://arxiv.org/abs/2601.07192)
- [Core-based GraphRAG](https://arxiv.org/abs/2603.05207)
- [WorldDB](https://arxiv.org/abs/2604.18478)
- [Memgraph single-store vector](https://memgraph.com/blog/single-store-vector-index)
- [SurrealDB vector search](https://surrealdb.com/docs/learn/data-models/vector-search/overview)
