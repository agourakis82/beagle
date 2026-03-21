# B9.7 - Controlled Consumer Expansion

## Current status

B9.7 is currently `GO-WITH-BLOCKER`.

The repo-native consumer policy layer exists inside Beagle, but the phase only
closes after the live cluster smoke proves two distinct consumers using the same
internal control surface.

## Objective

Expand the Beagle/Darwin HPC stack from a single operator-centric workflow model
into a broader but still controlled consumer model.

The phase is intentionally narrow:

- one operator path remains fully capable
- one research path is added with bounded permissions
- both paths use the same Beagle internal surface
- profile restrictions remain explicit
- result retrieval stays on the existing result plane

## Consumer model

### `beagle-operator`

Primary internal operator path.

Allowed:

- workspace bootstrap and session recovery
- HPC control surface
- profile lookup
- HPC submit for approved profiles
- job/result read paths
- bridge health/providers/execute

### `darwin-research`

Controlled shared consumer path.

Allowed:

- profile lookup
- HPC submit for `cpu-short-v1`
- HPC submit for `cpu-batch-v1`
- job/result read paths

Denied:

- workspace plane
- HPC control surface
- bridge execute
- `gpu-single-v1`

## Surface reused

This phase does not add a parallel surface. It reuses the live Beagle internal
surface:

- `GET /api/darwin/consumers/self`
- `GET /api/darwin/hpc/profiles`
- `POST /api/darwin/hpc/jobs/submit`
- `GET /api/darwin/hpc/jobs/{job_id}`
- `GET /api/darwin/hpc/jobs/{job_id}/artifact-manifest`
- `GET /api/darwin/hpc/results`
- `GET /api/darwin/hpc/results/{job_id}`
- `GET /api/darwin/hpc/results/{job_id}/manifest`

Operator-only paths remain operator-only:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `POST /api/darwin/workspace/pilot/execute`
- `GET /api/darwin/hpc/control`
- `GET /api/darwin/bridge/health`
- `GET /api/darwin/bridge/providers`
- `POST /api/darwin/bridge/execute`

## Placement

- consumer policy domain: `crates/beagle-darwin/src/consumer_policy.rs`
- config wiring: `crates/beagle-config/src/model.rs`
- config loading: `crates/beagle-config/src/lib.rs`
- auth integration: `apps/beagle-monorepo/src/auth.rs`
- surface enforcement: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- cluster config: `k8s/beagle/configmap.yaml`
- cluster secret placeholders: `k8s/beagle/secret.example.yaml`
- smoke: `scripts/infrastructure/darwin-hpc/run_controlled_consumer_expansion_smoke.sh`

## Success condition

The phase closes when:

1. `beagle-operator` and `darwin-research` authenticate through the same Beagle service
2. operator access remains intact
3. research access is restricted to the allowed CPU profiles
4. denied paths return explicit `403` responses
5. an allowed research workflow completes and resolves through the current result plane
6. cluster remains green
7. Slurm remains green
