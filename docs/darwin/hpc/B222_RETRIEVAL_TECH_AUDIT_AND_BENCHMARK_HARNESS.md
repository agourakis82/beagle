# B22.2 - Retrieval Technology Audit & Benchmark Harness

## Intent

B22.2 does not replace the B22.1 retrieval spine. It audits it, benchmarks it, and makes the next bounded upgrade explicit.

The canonical baseline remains:

- collection-backed hybrid retrieval
- payload-aware filtering
- context-packet integration
- Beagle-owned identity and memory lineage

The new layer adds:

- benchmark reports for the current retrieval path
- an explicit embedding backend matrix
- an explicit reranking profile
- a bounded recommendation surface for the next upgrade

## Narrow insertion points

The phase is intentionally narrow:

- `beagle-memory` owns the benchmark and audit types
- the benchmark runner sits on top of `hybrid_retrieve`
- `http_memory` exposes benchmark, backend-matrix, and reranking-profile surfaces
- the workstream context packet remains the consumer, not the place where the audit logic lives

## Canonical questions answered

The harness answers, repo-natively:

1. Whether Qdrant should remain the preferred store direction.
2. Whether `local-fallback-dense` is still acceptable as the active dense backbone.
3. Whether reranking should be added now or kept as a deferred hook.
4. Which dense backend path is best for:
   - general retrieval
   - code retrieval
   - multilingual retrieval
   - sovereign/self-hosted retrieval

## Canonical recommendation shape

The benchmark report emits a bounded recommendation:

- keep Qdrant as the preferred long-term store direction
- promote a stronger dense backend before making reranking canonical
- keep reranking hook-ready but disabled
- keep code-oriented and multilingual/self-hosted backends as bounded next pilots, not immediate global defaults

## GO shape

`B22.2 = GO` when:

- the benchmark harness runs against the live B22.1 retrieval spine
- the backend matrix is explicit
- a reranking profile exists
- a recommendation artifact is produced
- restart stays coherent
- cluster and Slurm stay green
