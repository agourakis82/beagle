# B12.3 - Beagle Internal Control Surface

## Objective

Build the first unified internal control surface in Beagle on top of the
already-proven Darwin HPC backplane.

## Scope

The B12.3 surface unifies, inside the running Beagle service:

- HPC profiles
- approved job submission
- normalized job status
- result catalog and lookup
- object-backed manifest retrieval
- bridge health/providers/execute
- operator-facing control summary

## Runtime shape

The internal JSON-first surface is:

- `GET /api/darwin/hpc/control`
- `GET /api/darwin/hpc/profiles`
- `POST /api/darwin/hpc/jobs/submit`
- `GET /api/darwin/hpc/jobs/{job_id}`
- `GET /api/darwin/hpc/jobs/{job_id}/artifact-manifest`
- `GET /api/darwin/hpc/jobs/{job_id}/stdout`
- `GET /api/darwin/hpc/jobs/{job_id}/stderr`
- `GET /api/darwin/hpc/results`
- `GET /api/darwin/hpc/results/{job_id}`
- `GET /api/darwin/hpc/results/{job_id}/manifest`
- `GET /api/darwin/bridge/health`
- `GET /api/darwin/bridge/providers`
- `POST /api/darwin/bridge/execute`

## Architectural decision

- Beagle becomes the internal control surface, not a replacement scheduler.
- The proven Darwin HPC gateway remains the upstream execution/control boundary.
- The proven object/result plane remains the artifact source of truth.
- The bridge foundation from B12.2b remains intact and is not redesigned here.
- No UI, ingress, edge, HA, raw scheduler payloads or provider expansion are
  added in this phase.

## Placement

- stateful internal HTTP surface: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- upstream result/gateway integration: `crates/beagle-darwin/src/result_catalog.rs`
- object-backed retrieval integration: `crates/beagle-darwin/src/object_results.rs`
- bridge ledger/operator view reuse: `crates/beagle-darwin/src/tool_bridge_ledger.rs`

## Live result

- current status: `GO`
- validated on the live Beagle cluster service in namespace `beagle`
- smoke captured at `2026-03-20T11:58:05-03:00`
- fresh submit/status path validated with `cpu-short-v1` job `34`
- published result lookup/manifest path validated with published `gpu-single-v1`
  job `32`
- bridge health/providers and human-premium deferred execution validated through
  the same internal surface

## Success condition

The phase is alive when one authenticated Beagle surface can:

1. list approved HPC profiles
2. submit one approved HPC workload profile
3. resolve normalized job status
4. list/query already-published results from the object plane
5. retrieve an object-backed manifest for a published result
6. expose bridge health/providers
7. show recent bridge ledger entries
