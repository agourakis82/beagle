# B22.3 — Dense Backend Promotion

## Objective

Promote a stronger dense backend into the canonical hybrid retrieval spine without changing:

- Qdrant as the preferred store direction
- the sparse lexical path
- payload-aware filters
- context-packet integration

## Canonical promotion

- Promoted general dense backend: `voyage-4-large`
- Code retrieval candidate track: `voyage-code-3`
- Sovereign/self-hosted candidate track: `bge-m3`

## What changed

1. Added an explicit embedding backend contract so the dense backend is no longer an implicit side effect of store choice.
2. Promoted `voyage-4-large` as the canonical dense backend target for general retrieval.
3. Preserved `local-lexical` as the canonical sparse path.
4. Kept the retrieval collection, payload model, and context-packet integration intact.
5. Added a bounded local dense semantic path that can activate without a Qdrant migration when provider access is available.

## Runtime states

- `promoted-active`: the promoted dense backend is configured and usable.
- `auth-blocked-fallback`: the promoted backend contract is in place, but provider credentials are missing, so retrieval stays on the lexical fallback for dense scoring.
- `endpoint-missing-fallback`: the promoted backend contract is in place, but no endpoint is configured, so retrieval stays on the lexical fallback for dense scoring.

## Cluster note

The old cluster embedding endpoint `http://t560.local:8001/v1` was not resolvable from inside the cluster. B22.3 replaces that broken reference with the canonical Voyage endpoint contract shape and makes credential state explicit instead of silently assuming a local embedding plane exists.
