# B26.7 — Sounio Dedicated Cluster Workspace

This phase adds a first-class `sounio-lang-main` workstream and a dedicated
`sounio-workspace` habitat inside the existing `beagle` namespace.

## Goal

Move day-to-day Sounio development off the unstable local VM and onto the live
cluster without hijacking the existing Beagle workspace.

## What is canonical in this phase

- `github.com/sounio-lang/sounio.git` on `main` is hydrated into
  `/workspace/sounio`
- the Beagle API resolves workspace habitat/attach/launch-resume per workstream
- `sounio-lang-main` keeps its own:
  - `workstream_id`
  - `workspace_id`
  - `session_id`
  - service
  - PVC
  - managed attach alias
- the workspace is CPU-first for interactive editing
- GPU/large work remains Slurm-routed and explicit
- the workspace bootstrap insists on a real `.git` checkout
- if in-container `git`/`curl` hydration is impaired, the rollout uses an
  explicit host-side git seed to materialize the canonical checkout into the
  same Beagle-owned workspace root without creating parallel state outside the
  cluster workspace

## Expected operator surfaces

- `/api/darwin/workstreams/sounio-lang-main/workspace-habitat`
- `/api/darwin/workstreams/sounio-lang-main/workspace-habitat/context.env`
- `/api/darwin/workstreams/sounio-lang-main/managed-attach`
- `/api/darwin/workstreams/sounio-lang-main/workspace-launch-resume`

## Runtime identity

- `workstream_id=sounio-lang-main`
- `workspace_id=sounio-cluster-pilot`
- `session_id=ws-cluster-sounio-habitat`
- attach alias: `sounio-cluster-pilot.coder`

## Acceptance shape

- browser IDE works
- managed attach works
- `/workspace/sounio` is a real git clone
- the SSH attach shell carries the same bounded compiler/tooling baseline needed
  for `make check`
- `bin/souc --version` works
- baseline workspace context is restart-safe
