# B20.1 — Cluster Workspace Habitat

Status: GO

## Objective

Create the first real Beagle-owned cluster workspace habitat so daily work can happen inside a
stable remote IDE environment instead of being driven primarily by terminal command pasting.

## Scope

This phase adds one bounded workspace habitat:

- one canonical cluster workspace for the canonical Beagle workstream
- one browser IDE surface via an officially supported remote IDE substrate
- one Beagle-owned workspace habitat packet
- one bounded context injection path inside the workspace
- one shared identity across Beagle, cockpit, and premium tool lanes

This phase does not add:

- ingress or public exposure
- HA
- Cursor remote lane as a first-class substrate
- Coder multi-workspace management
- multi-workstream workspace orchestration

## Runtime Surface

The Beagle Darwin/HPC runtime now exposes:

- `GET /api/darwin/workstreams/{id}/workspace-habitat`
- `GET /api/darwin/workstreams/{id}/workspace-habitat/context.env`

The habitat response is built from the same Beagle-owned workstream context packet used by:

- the cockpit
- Cursor
- Claude Code
- Codex

The habitat export carries:

- `workstream_id`
- `workspace_id`
- `session_id`
- `repo`
- `branch`
- `governance_state`
- `default_dev_plane`
- `vm_fallback_role`
- `browser_url`
- `health_url`
- `context_packet_path`
- `context_env_path`
- `workspace_root`
- `context_packet_file`
- `context_env_file`

## Cluster Habitat

The first habitat is materialized under `k8s/beagle-workspace/` with:

- a dedicated `Deployment`
- a `ClusterIP` service
- a dedicated PVC for persisted workspace state
- a bounded bootstrap script in `ConfigMap`
- the official `OpenVSCode Server` image as the browser IDE substrate

The workspace substrate is:

- `openvscode-server`
- internal-only
- Beagle-owned for context and identity

At startup the workspace bootstrap path:

1. ensures the canonical repo is present
2. bootstraps the canonical Beagle workspace/session identity
3. fetches the current Beagle context packet
4. fetches the Beagle-generated `context.env`
5. starts the official `OpenVSCode Server` binary against the same Beagle-owned workspace root

## Evidence

Canonical live proof is frozen under:

- `.artifacts/darwin-hpc/cluster-workspace-habitat/workspace-context.json`
- `.artifacts/darwin-hpc/cluster-workspace-habitat/workspace-health.txt`
- `.artifacts/darwin-hpc/cluster-workspace-habitat/workspace-context-after-restart.json`
- `.artifacts/darwin-hpc/cluster-workspace-habitat/workspace-runtime-summary.json`
- `.artifacts/darwin-hpc/cluster-workspace-habitat/smoke.json`
- `.artifacts/darwin-hpc/cluster-workspace-habitat/final-cluster-health.txt`

## Outcome

`B20.1 = GO` when:

- the workspace deployment starts on-cluster
- the browser IDE responds and stays healthy
- the Beagle context is present inside the workspace
- the same `workstream_id` / `workspace_id` / `session_id` survive restart
- cluster health stays green
- `Slurmctld(primary)` stays `UP`

Current state:

- runtime and manifests are implemented
- the blocked `code-server` runtime path was replaced by the official `OpenVSCode Server`
  substrate
- the live smoke proved the workspace comes up, serves the browser IDE, injects the Beagle
  context, and survives restart with the same identity
- the habitat is now green on-cluster under the Beagle-owned envelope
