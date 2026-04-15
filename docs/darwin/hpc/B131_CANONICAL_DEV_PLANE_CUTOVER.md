# B13.1 - Canonical Dev Plane Cutover

## Current status

B13.1 is currently `GO`.

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/canonical-dev-cutover-smoke/bootstrap-before.json`
- `.artifacts/darwin-hpc/canonical-dev-cutover-smoke/bridge-execute.json`
- `.artifacts/darwin-hpc/canonical-dev-cutover-smoke/pilot.json`
- `.artifacts/darwin-hpc/canonical-dev-cutover-smoke/session-after-restart.json`
- `.artifacts/darwin-hpc/canonical-dev-cutover-smoke/final-cluster-health.txt`

## Objective

Prove one clean canonical dev-plane cutover where a real repo-aware workflow
runs primarily through the Beagle/cluster workspace plane instead of treating a
VM session as the mandatory center of work.

## Scope

The phase stays deliberately narrow:

- one canonical repo
- one canonical branch
- one operator-facing development loop
- one real bridge step on the cheap API lane
- one real workflow execution through the existing workspace plane
- result lookup through the current Beagle surfaces
- restart/recovery preserving the same session and handoff context

## Runtime shape

The cutover pilot reuses the live internal Beagle surface:

- `GET /api/darwin/workspace/bootstrap`
- `GET /api/darwin/workspace/session`
- `GET /api/darwin/hpc/control`
- `GET /api/darwin/hpc/results`
- `GET /api/darwin/hpc/results/{job_id}`
- `GET /api/darwin/hpc/results/{job_id}/manifest`
- `GET /api/darwin/bridge/health`
- `GET /api/darwin/bridge/providers`
- `POST /api/darwin/bridge/execute`
- `POST /api/darwin/workspace/pilot/execute`

## Architectural decision

- the cutover pilot is session-first and repo-aware, not editor-first
- the canonical repo checkout stays in the working tree on the current branch;
  Beagle becomes the canonical session, handoff and workflow plane
- the bridge step proves that a real development-side reasoning action can run
  from the cluster-hosted Beagle service
- the workflow step proves that the same session can submit, resolve and recover
  without reopening lower layers

## Placement

- workspace/session runtime: `crates/beagle-darwin/src/workspace_plane.rs`
- internal HTTP surface: `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- smoke validation:
  `scripts/infrastructure/darwin-hpc/run_canonical_dev_cutover_smoke.sh`

## Success condition

The phase closes when one canonical workspace can:

1. bootstrap with repo and branch context through the live Beagle service
2. recover its prior session state and handoff metadata
3. execute one real bridge request on the live cheap API lane
4. execute one real workflow through the workspace plane
5. resolve the published result through the current result plane
6. preserve repo, branch, handoff, ledger and last workflow across restart
7. leave the VM as an allowed fallback, but not the mandatory center for this pilot

## Live result

The validated pilot proved that one canonical development loop can:

- bootstrap workspace `b131-0320231730` on repo `agourakis82/beagle` and branch
  `feat/darwin-hpc-governance`
- execute one real cheap-lane bridge request through `deepseek`
- persist the bridge request in the append-only ledger under `BEAGLE_DATA_DIR`
- run one real `cpu-short-v1` workflow through the workspace plane with job `44`
- resolve published result `24` through the current result plane
- persist handoff, last workflow and last result context in the workspace session
- recover the same session `ws-20260321021731` cleanly after Beagle rollout restart
