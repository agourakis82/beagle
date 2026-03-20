# B12.4 - Workspace Plane Attachment / Dev-in-Cluster Pilot

## Current status

B12.4 is currently `GO`.

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/workspace-plane-smoke/bootstrap-before.json`
- `.artifacts/darwin-hpc/workspace-plane-smoke/pilot.json`
- `.artifacts/darwin-hpc/workspace-plane-smoke/session-after-restart.json`
- `.artifacts/darwin-hpc/workspace-plane-smoke/final-cluster-health.txt`

## Objective

Attach one canonical workspace/dev pilot to the already-proven Beagle control
surface so that bootstrap, session recovery and one real operator workflow can
run through the cluster-hosted Beagle service.

## Scope

The B12.4 pilot is intentionally narrow:

- workspace bootstrap
- session recovery
- handoff persistence
- one operator workflow pilot
- reuse of the live internal control surface

## Runtime shape

The internal JSON-first workspace surface is:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `POST /api/darwin/workspace/pilot/execute`

## Architectural decision

- the workspace plane is metadata-first and session-first
- the Beagle pod is not turned into a full repo checkout or IDE host
- the operator workflow pilot reuses the live HPC/result/bridge backplane
- no ingress, edge, HA, provider expansion or topology changes are added here

## Placement

- workspace/session domain logic: `crates/beagle-darwin/src/workspace_plane.rs`
- internal HTTP surface: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- cluster config: `k8s/beagle/configmap.yaml`
- smoke validation: `scripts/infrastructure/darwin-hpc/run_workspace_plane_smoke.sh`

## Success condition

The phase is alive when one canonical workspace can:

1. bootstrap against the live Beagle service
2. recover its session state after Beagle restart
3. persist a clean handoff
4. run one real operator workflow through submit/status/artifact retrieval
5. reference one published result through the object-backed result plane

## Live result

The validated pilot proved that a workspace session can:

- bootstrap cleanly against the live Beagle cluster service
- submit and complete a real `cpu-short-v1` workflow through the internal control surface
- persist handoff, last job state and last published-result metadata under `BEAGLE_DATA_DIR`
- recover the same session cleanly after a Beagle rollout restart
