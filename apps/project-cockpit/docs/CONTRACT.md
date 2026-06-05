# Interface Contract - Ops Backend and Beagle Command Center Frontend

This contract defines the boundary between the current Codex-owned ops/backend surface and the Kimi-owned exocortex frontend direction.

## Ownership

Codex keeps:

- Cluster health API
- doctors execution
- SSH/Slurm/Kubernetes bridge
- OrangeFS readback
- Action Ledger gate
- existing Cockpit project/workspace APIs

Kimi creates:

- Pipeline UI
- Agent Thread
- Triad Review
- Memory Graph explorer
- Physio HUD
- Beagle Command Center layout and interaction model

Shared interface:

- REST under `/api/*`
- WebSocket under `/ws/events`
- Beagle Core Rust/Axum at `localhost:8080` or `beagle-core.beagle.svc.cluster.local:8080`
- Cockpit Express at `localhost:4370` as the public/operator boundary when needed

## Non-Negotiable Backend Semantics

Do not collapse these domains:

- cluster truth: infrastructure health and admission state
- research operations: runs/jobs/campaigns
- workspace habitat: project continuity surface
- exocortex cognition: agents, memory, physiology, pipeline, review

`Darwin Cluster Ops` is cluster truth plus controlled ops actions. `Beagle Command Center` is the exocortical operating surface above it.

## Existing REST API To Preserve

Cluster ops:

- `GET /api/cluster/ops/summary`
- `GET /api/cluster/ops/actions`
- `POST /api/cluster/ops/actions/:actionId/run`

Action Ledger:

- `GET /api/project-os/actions`
- `GET /api/projects/:slug/actions`
- `POST /api/projects/:slug/actions/propose`
- `POST /api/projects/:slug/actions/:ledgerId/confirm-intent`
- `POST /api/projects/:slug/actions/:ledgerId/reject`

Beagle auth bridge:

- `GET /api/auth/beagle-token`
- `GET /api/auth/beagle-discover`
- `GET /api/beagle/*`
- `POST /api/beagle/*`

Beagle Core protected cognitive routes:

- `GET /api/v1/cognitive/state`
- `GET /api/v1/cognitive/stream`
- `GET /api/v1/cognitive/phi_of_phi`
- `GET /api/v1/cognitive/tool_rhythm_phi`
- `POST /api/cognitive/deep-think`
- `POST /api/exocortex/process`
- `POST /api/fractal/recurse`
- `POST /api/observer/physio`
- `GET /api/observer/physio/latest`
- `POST /api/memory/query`
- `POST /api/memory/ingest_chat`
- `POST /api/pipeline/start`
- `GET /api/pipeline/status/:run_id`
- `GET /api/runs/recent`
- `POST /api/v1/feedback`
- `GET /api/v1/feedback`

Authentication for Beagle Core:

```http
X-Beagle-Consumer: beagle-operator
Authorization: Bearer <token>
```

## Required New Event Interface

New endpoint:

```http
GET /ws/events
```

Purpose:

- one multiplexed event stream for frontend state updates
- bridge cluster ops, agents, memory, physio, pipeline, and review events
- replace fragile direct `EventSource` calls where custom auth headers are needed

Event envelope:

```json
{
  "type": "string",
  "payload": {},
  "timestamp": "2026-05-22T18:35:46.000Z",
  "agent_id": "darwin | observer | athena | hermes | argos | system | operator",
  "run_id": "optional",
  "truth_mode": "observed | remembered | declared | stale",
  "schema": "beagle.event.v1"
}
```

Minimum event types:

- `cluster.summary.updated`
- `cluster.action.proposed`
- `cluster.action.confirmed`
- `cluster.action.started`
- `cluster.action.completed`
- `cluster.action.failed`
- `pipeline.run.started`
- `pipeline.stage.updated`
- `pipeline.run.completed`
- `agent.message.created`
- `agent.tool.called`
- `triad.review.updated`
- `memory.node.created`
- `memory.edge.created`
- `physio.snapshot.updated`
- `ledger.intent.required`
- `ledger.intent.confirmed`

## Pipeline UI Contract

Kimi UI name:

- Pipeline UI

Backend routes:

- `POST /api/pipeline/start`
- `GET /api/pipeline/status/:run_id`
- `GET /api/runs/recent`
- `GET /api/v1/cognitive/state`

Preferred visual stages:

```text
Darwin -> Observer -> HERMES -> Triad
```

Pipeline status shape expected by frontend:

```json
{
  "run_id": "uuid",
  "question": "string",
  "phase": "started | memory_rag | darwin_context | hermes_synthesis | triad_review | complete | failed",
  "status": "running | completed | failed",
  "started_at": "date-time",
  "updated_at": "date-time",
  "stages": [
    {
      "id": "observer",
      "label": "Observer",
      "status": "pending | running | done | failed",
      "truth_mode": "observed",
      "summary": "string"
    }
  ]
}
```

If this exact shape is not emitted yet, Kimi should add a frontend adapter rather than changing backend semantics casually.

## Agent Thread Contract

Kimi UI name:

- Agent Thread

Existing backend assets:

- `GET /api/v1/cognitive/stream` (SSE)
- `GET /api/v1/cognitive/state`
- `POST /api/cognitive/mcp_tool_call`
- existing Cockpit agent session APIs for terminal/tmux sessions

Required new shape for frontend:

```json
{
  "thread_id": "string",
  "messages": [
    {
      "id": "string",
      "agent_id": "operator | darwin | observer | athena | hermes | argos",
      "role": "user | assistant | tool | system",
      "content": "string",
      "created_at": "date-time",
      "run_id": "optional",
      "tool_calls": []
    }
  ]
}
```

Current gap:

- No Beagle Command Center text input route exists for talking to the multi-agent system as one thread.
- Existing `Cognitive.jsx` can launch deep-think but is not a chat/thread.

## Triad Review Contract

Kimi UI name:

- Triad Review

Agents:

- `ATHENA`: literature/search/context adversary
- `HERMES`: synthesis/writing/interpretation
- `ARGOS`: critique/claims/risk

Required UI shape:

```json
{
  "run_id": "string",
  "reviews": {
    "athena": {
      "status": "pending | running | done | failed",
      "claims": [],
      "evidence": [],
      "summary": "string"
    },
    "hermes": {
      "status": "pending | running | done | failed",
      "draft": "string",
      "summary": "string"
    },
    "argos": {
      "status": "pending | running | done | failed",
      "objections": [],
      "risk": "low | medium | high",
      "summary": "string"
    }
  },
  "decision": {
    "status": "needs_revision | accepted | blocked",
    "summary": "string"
  }
}
```

Current gap:

- Triad backend crates exist in the Beagle workspace, but `/projects/cluster` has no Triad Review UI.

## Memory Graph Contract

Kimi UI name:

- Memory Graph explorer

Existing backend routes:

- `POST /api/memory/query`
- `POST /api/memory/ingest_chat`
- `POST /api/memory/graphrag/query`
- `POST /api/memory/retrieval/query`
- `GET /api/memory/retrieval/backend-matrix`

Required graph response shape for UI:

```json
{
  "query": "string",
  "nodes": [
    {
      "id": "string",
      "label": "string",
      "kind": "paper | concept | run | agent | memory | artifact",
      "score": 0.92,
      "metadata": {}
    }
  ],
  "edges": [
    {
      "id": "string",
      "source": "node-id",
      "target": "node-id",
      "kind": "supports | contradicts | cites | derived_from | observed_in",
      "weight": 0.8,
      "metadata": {}
    }
  ],
  "truth_mode": "observed"
}
```

Current gap:

- `/projects/cluster` has no graph explorer.
- Existing Three.js background is not a Memory Graph.

## Physio HUD Contract

Kimi UI name:

- Physio HUD

Existing backend routes:

- `POST /api/observer/physio`
- `GET /api/observer/physio/latest`
- `GET /api/v1/cognitive/state`
- `GET /api/v1/cognitive/stream`

Preferred snapshot shape:

```json
{
  "hrv_ms": 42.0,
  "hr": 92.0,
  "spo2": 97.0,
  "hrv_level": "low | normal | high",
  "flow_state": "stressed | focused | recovery | unknown",
  "source": "watch | manual | observer-smoke",
  "recorded_at": "date-time",
  "truth_mode": "observed"
}
```

Current gap:

- Physio is represented in Beagle Core/cognitive events, but no always-visible HUD exists in Cluster Ops.

## Action Ledger Gate Contract

Any destructive or infrastructure-affecting action must use:

1. `POST /api/projects/:slug/actions/propose`
2. human/operator confirmation in UI
3. `POST /api/projects/:slug/actions/:ledgerId/confirm-intent`
4. execution route with:

```json
{
  "confirmed": true,
  "ledgerId": "uuid",
  "idempotencyKey": "uuid"
}
```

The UI must display:

- action label
- risk
- target
- ledger id
- execution output
- readback status

The UI must not execute destructive actions from an agent message alone.

## Constraints For Kimi

Kimi may:

- add new frontend components under `src/pages` and `src/components`
- create adapters around existing payloads
- add a Beagle Command Center route
- use existing design tokens or replace the layout while preserving semantics

Kimi must not:

- repurpose `/api/cluster/ops/summary` into exocortex state
- remove the Action Ledger gate
- treat research jobs as cluster health
- assume `/ws/events` exists before backend work lands
- require direct browser access to private cluster-only URLs without a proxy/auth plan
- break `/projects/cluster` as the existing ops surface
