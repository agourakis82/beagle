# Migration From `darwin-v2`

## Status

`darwin-v2` was the incubation and operational proving tree for the Darwin HPC stack.

The canonical integration target is now the Beagle repository.

Wave 1 materializes the repo-native documentation, contracts, templates, and external infrastructure tooling inside Beagle without importing ephemeral execution evidence or rewriting the runtime stack yet.

## Canonical Repo-Native Locations

- stable phase docs: `docs/darwin/hpc/phase-b9/`, `docs/darwin/hpc/phase-b10/`, `docs/darwin/hpc/phase-b11/`
- shared contracts: `docs/darwin/hpc/contracts/`
- shared request and publication templates: `docs/darwin/hpc/templates/`
- external operational tooling: `scripts/infrastructure/darwin-hpc/`

## What Was Ported In Wave 1

- stable B9, B10, and B11 phase documentation
- stable shared contracts from the canonical `darwin-v2` tree
- stable request and publication templates
- operational validation and execution scripts that remain useful as versioned infrastructure tooling

## What Was Explicitly Not Ported

- no `phase-b*/<RUN_ID>/...` evidence trees
- no ephemeral run artifacts in Git
- no parallel `darwin-v2` subtree inside Beagle
- no new `beagle-darwin-hpc` crate
- no direct runtime port of the Python adapter or Python gateway as final product implementation

## Transitional Runtime Boundary

The current Python adapter, Python gateway, and selected Kubernetes manifest assets remain transitional.

In Wave 1, the Beagle scripts resolve docs, contracts, and templates from the Beagle repo, but some runtime and manifest defaults still point explicitly to `/root/darwin-v2` until the repo-native runtime materialization wave lands.

Operational run output now defaults to `.artifacts/darwin-hpc/` so that validation evidence can exist locally without reintroducing ephemeral phase trees into the tracked source tree.

## Migration Map

- `darwin-v2/phase-b9/summary/*` -> `docs/darwin/hpc/phase-b9/`
- `darwin-v2/phase-b10/summary/*` -> `docs/darwin/hpc/phase-b10/`
- `darwin-v2/phase-b11/summary/*` -> `docs/darwin/hpc/phase-b11/`
- `darwin-v2/phase-b9/contract/*`, `phase-b10/contract/*`, `phase-b11/contract/*` -> `docs/darwin/hpc/contracts/`
- `darwin-v2/phase-b9/templates/*`, `phase-b10/templates/*` -> `docs/darwin/hpc/templates/`
- `darwin-v2/scripts/phase-b9/*`, `phase-b10/*`, `phase-b11/*` -> `scripts/infrastructure/darwin-hpc/phase-b9/`, `phase-b10/`, `phase-b11/`

## Next Code Targets

The next repo-native code wave should materialize the Darwin HPC runtime semantics here:

- `crates/beagle-darwin/src/hpc_profiles.rs`
- `crates/beagle-darwin/src/hpc_adapter.rs`
- `crates/beagle-darwin/src/object_results.rs`
- `crates/beagle-darwin/src/result_catalog.rs`
- `apps/beagle-monorepo/src/http_darwin_hpc.rs`
