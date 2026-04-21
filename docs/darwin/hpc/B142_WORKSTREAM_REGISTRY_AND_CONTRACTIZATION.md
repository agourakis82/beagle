# B14.2 - Workstream Registry & Contractization

## Current status

B14.2 is `GO`.

Canonical contract artifacts live under:

- `docs/darwin/hpc/workstreams/README.md`
- `docs/darwin/hpc/workstreams/registry.yaml`
- `docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml`

Live alignment proof was captured by rerunning the canonical first real
workstream cutover after expanding the runtime contract surface:

- `.artifacts/darwin-hpc/first-real-workstream-cutover/bootstrap-after-deploy.json`
- `.artifacts/darwin-hpc/first-real-workstream-cutover/session-after-restart.json`
- `.artifacts/darwin-hpc/first-real-workstream-cutover/smoke.json`
- `.artifacts/darwin-hpc/first-real-workstream-cutover/final-cluster-health.txt`

## Objective

Turn proven workstreams into first-class governed objects:

1. create a repo-native workstream registry
2. represent the already-cut-over workstream as a canonical spec
3. align runtime workstream policy with the contract fields of the registry
4. express the current cutover state through a named workstream object instead
   of only through implicit branch/workflow behavior

## Registry shape

The canonical registry now lives at:

- `docs/darwin/hpc/workstreams/registry.yaml`

Each workstream spec is repo-native and versioned alongside the platform:

- `docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml`

The spec shape covers:

1. repo and branch identity
2. scope and default dev plane
3. fallback role
4. compute profiles
5. result plane policy
6. consumer policy
7. recovery policy
8. promotion state

## Architectural decision

- the registry is repo-native and contract-first; it does not add new infra,
  ingress, HA or topology
- the current cut-over workstream is promoted from an operationally proven path
  to a named governed object
- runtime `workstream_cutover_policy` remains compatible with B14.1 while being
  expanded to reflect the registry fields
- this phase does not broaden to multiple workstreams at once
- live proof reuses the already-proven cutover path instead of introducing a
  new lower-layer smoke just for contractization

## Placement

- registry root: `docs/darwin/hpc/workstreams/`
- runtime workstream policy:
  `crates/beagle-darwin/src/workspace_plane.rs`
- config/runtime loading:
  `crates/beagle-config/src/model.rs`,
  `crates/beagle-config/src/lib.rs`
- cluster mapping:
  `k8s/beagle/configmap.yaml`

## Success condition

The phase is now closed because:

1. at least one canonical workstream is represented as a first-class spec
2. the registry is repo-native and versioned with the repo
3. the already-cut-over workstream is expressed through the registry
4. runtime workstream policy covers the canonical contract fields
5. no lower layer is reopened
6. live bootstrap and session state now expose the governed fields for repo,
   branch, scope, compute profiles, result plane policy, consumer policy,
   recovery policy and promotion state
