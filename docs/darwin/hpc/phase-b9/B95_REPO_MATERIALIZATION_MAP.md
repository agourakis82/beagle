# B9.5 Repo Materialization Map

## Canonical Repo Paths

- Documentation root: `docs/darwin/hpc/`
- Contracts: `docs/darwin/hpc/contracts/`
- Example requests: `docs/darwin/hpc/templates/`

## Canonical Implementation Homes

### Profile catalog and submission validation

`crates/beagle-darwin/` is the correct home for the Darwin-side profile catalog,
request validation rules, and scheduler-template mapping because it is the
domain crate that other surfaces can call into.

Recommended module target:

- `crates/beagle-darwin/src/hpc_profiles.rs`

### Gateway route and config integration

`apps/beagle-monorepo/` is the correct home for the stateful gateway surface
because the repo's active Axum application, `AppState`, auth middleware, and
existing job and artifact endpoints already live there.

Recommended integration targets:

- `apps/beagle-monorepo/src/http.rs`
- or, if extracted cleanly, `apps/beagle-monorepo/src/http_darwin_hpc.rs`

### Job state and artifact/status plumbing

The existing job registry is already modeled in the monorepo app, so B9.5 job
state should extend that layer instead of creating a separate state island.

Recommended target:

- `apps/beagle-monorepo/src/jobs.rs`

### Validation tooling

The scratch shell scripts are operational validation, not product docs. They
fit best under the repo's shared script tree.

Recommended target:

- `scripts/infrastructure/darwin-hpc/`

## Why `beagle-darwin-core` Is Not the Primary Home

`crates/beagle-darwin-core/` currently exposes stateless `/darwin/*` routes and
does not own the main application router, auth, or job registry. It can still
host a thin adapter later, but it is not the primary home for the B9.5 gateway
implementation.

## Scratch-to-Repo Mapping

- `phase-b9/summary/B95_WORKLOAD_CLASS_EXPANSION.md`
  -> `docs/darwin/hpc/phase-b9/B95_WORKLOAD_CLASS_EXPANSION.md`
- `phase-b9/summary/B95_GO_NO_GO.md`
  -> `docs/darwin/hpc/phase-b9/B95_GO_NO_GO.md`
- `phase-b9/summary/B95_SECURITY_BOUNDARY.md`
  -> `docs/darwin/hpc/phase-b9/B95_SECURITY_BOUNDARY.md`
- `phase-b9/summary/B95_PROFILE_CATALOG.md`
  -> `docs/darwin/hpc/phase-b9/B95_PROFILE_CATALOG.md`
- `phase-b9/summary/B95_KNOWN_LIMITS.md`
  -> `docs/darwin/hpc/phase-b9/B95_KNOWN_LIMITS.md`
- `phase-b9/contract/hpc-workload-profiles.yaml`
  -> `docs/darwin/hpc/contracts/hpc-workload-profiles.yaml`
- `phase-b9/contract/gateway-submit-schema.json`
  -> `docs/darwin/hpc/contracts/gateway-submit-schema.json`
- `phase-b9/contract/cpu-short-job.json`
  -> `docs/darwin/hpc/contracts/cpu-short-job.json`
- `phase-b9/contract/cpu-batch-job.json`
  -> `docs/darwin/hpc/contracts/cpu-batch-job.json`
- `phase-b9/contract/gpu-single-job.json`
  -> `docs/darwin/hpc/contracts/gpu-single-job.json`
- `phase-b9/templates/example_cpu_short_request.json`
  -> `docs/darwin/hpc/templates/example_cpu_short_request.json`
- `phase-b9/templates/example_cpu_batch_request.json`
  -> `docs/darwin/hpc/templates/example_cpu_batch_request.json`
- `phase-b9/templates/example_gpu_single_request.json`
  -> `docs/darwin/hpc/templates/example_gpu_single_request.json`
- `scripts/phase-b9/run_workload_profile_expansion.sh`
  -> `scripts/infrastructure/darwin-hpc/phase-b9/run_workload_profile_expansion.sh`
  (planned, not yet materialized in this pass)
- `scripts/phase-b9/validate_workload_profile_matrix.sh`
  -> `scripts/infrastructure/darwin-hpc/phase-b9/validate_workload_profile_matrix.sh`
  (planned, not yet materialized in this pass)

## Canonical Rule

`/home/devsounio/darwin-v2` remains scratch only. The canonical repo-native
representation for B9.5 begins under `docs/darwin/hpc/` in this branch.
