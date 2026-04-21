# B20.2 — Cursor Remote Lane on the Same Workspace

Status: GO

## Objective

Expose the first canonical Cursor lane for the Beagle-owned cluster workspace without creating a
parallel state silo.

This phase keeps:

- `Beagle` as the source of truth for workstream, workspace, session, handoff, results, and
  governance
- the existing `OpenVSCode Server` habitat as the stable browser-first substrate
- `Cursor` as a premium client lane over the same workspace identity

## Scope

This phase adds:

- one bounded internal route for Cursor connection metadata
- one Cursor-specific remote lane object built from the same workspace habitat and context packet
- one small tool-dock enrichment so `tool-dock/cursor` points at the same canonical remote lane
- one workspace env export carrying the Cursor lane path inside the workspace itself
- one live smoke and validator on top of the already-green cluster workspace habitat

This phase does not add:

- a new workspace substrate
- ingress or public exposure
- HA
- a separate state model for Cursor
- a Coder control plane
- an SSH/Coder remote attach transport inside the workspace pod

## Runtime Surface

The Beagle Darwin/HPC runtime now exposes:

- `GET /api/darwin/workstreams/{id}/cursor-remote-lane`

The `tool-dock/cursor` surface now also points to:

- `remote_lane_kind=cursor-remote-lane`
- `remote_lane_path=/api/darwin/workstreams/{id}/cursor-remote-lane`

The Cursor lane is assembled from the same Beagle-owned envelope as the habitat and context
packet, carrying:

- `workstream_id`
- `workspace_id`
- `session_id`
- `repo`
- `branch`
- `governance_state`
- `program_id`
- `campaign_id`
- `workspace_habitat_path`
- `workspace_habitat_env_path`
- `context_packet_path`
- `tool_return_path`
- `recommended_recipe_id`
- connection metadata for the same remote workspace

## Connection Model

The Cursor lane is intentionally Beagle-owned and metadata-rich:

- same workspace identity as the Beagle habitat
- same context packet and `context.env`
- same result/handoff/workstream envelope
- recommended transport: `kubectl port-forward` to the internal workspace service
- native premium attach is closed in `B20.2a` on top of this lane contract

## Evidence

Canonical live proof is frozen under:

- `.artifacts/darwin-hpc/cursor-remote-lane/cursor-remote-lane.json`
- `.artifacts/darwin-hpc/cursor-remote-lane/tool-cursor.json`
- `.artifacts/darwin-hpc/cursor-remote-lane/workspace-context.json`
- `.artifacts/darwin-hpc/cursor-remote-lane/workspace-context-after-restart.json`
- `.artifacts/darwin-hpc/cursor-remote-lane/workspace-runtime-summary.json`
- `.artifacts/darwin-hpc/cursor-remote-lane/smoke.json`
- `.artifacts/darwin-hpc/cursor-remote-lane/final-cluster-health.txt`

## Outcome

`B20.2 = GO` when:

- the same canonical workspace habitat remains green
- the Cursor lane resolves from the same `workstream_id` / `workspace_id` / `session_id`
- the tool dock points `cursor` at the same remote lane path
- the Beagle context exported inside the workspace carries the Cursor lane path
- restart remains coherent
- cluster stays green
- `Slurmctld(primary)` stays `UP`

Current honest state:

- the canonical Cursor lane metadata is live and restart-coherent
- the lane is explicitly bound to the same Beagle-owned workspace habitat
- native remote attach is now proven by `B20.2a`, without changing the lane's Beagle-owned
  identity model
