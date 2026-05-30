# API Map - Darwin Cluster Ops and Beagle Core

This document maps the current frontend calls to the backend surfaces they consume. It separates the Node/Express Cockpit API from the Rust/Axum Beagle Core API.

## Runtime Boundaries

```text
Browser
  -> Vite dev proxy or production Cockpit host
  -> project-cockpit Express server on :4370
  -> local shell/kubectl/ssh/Slurm scripts for ops endpoints
  -> Beagle Core Rust/Axum on :8080 through auth bridge or direct Tailnet URL
```

Important URLs:

- Cockpit dev client: `http://localhost:4173`
- Cockpit API/server: `http://localhost:4370`
- Beagle Core in cluster: `http://beagle-core.beagle.svc.cluster.local:8080`
- Beagle Core Tailnet/public-ish: `http://beagle-core.tail21cbc4.ts.net`
- User-stated local target for Kimi integration: `http://localhost:8080`

Vite proxy:

```js
server: {
  port: 4173,
  proxy: {
    "/api": { target: "http://127.0.0.1:4370", changeOrigin: true },
    "/ws": { target: "ws://127.0.0.1:4370", ws: true }
  }
}
```

## Frontend Calls Used By `/projects/cluster`

| Frontend code | Method | Endpoint | Backend owner | Status |
| --- | --- | --- | --- | --- |
| `fetchClusterOps()` | GET | `/api/cluster/ops/summary` | Cockpit Express | real observed ops readback |
| `runClusterAction()` | POST | `/api/projects/beagle/actions/propose` | Cockpit Express Action Ledger | real ledger write |
| `runClusterAction()` | POST | `/api/projects/beagle/actions/:ledgerId/confirm-intent` | Cockpit Express Action Ledger | real ledger transition |
| `runClusterAction()` | POST | `/api/cluster/ops/actions/:actionId/run` | Cockpit Express | real allowlisted execution after ledger |

`/projects/cluster` does not currently call Beagle Core directly.

## Cluster Ops Summary

Endpoint:

```http
GET /api/cluster/ops/summary
```

Producer:

- `server/cluster-ops-routes.mjs`
- `buildClusterOpsSummary()`

Data sources:

- `kubectl get nodes`
- `kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded`
- `kubectl -n kube-system get cm cilium-config`
- `kubectl -n kube-system get ds cilium`
- `kubectl -n kube-system get ds cilium-envoy`
- `source ops/lab-ops.sh && lab_slurm_exec ...`
- `source ops/lab-ops.sh && lab_orangefs_status`
- SSH to `root@10.100.100.1`, `root@10.100.100.2`, `root@10.100.100.3`, `root@10.100.100.4`

Response schema:

```json
{
  "schema": "darwin.cluster-ops.v0",
  "generatedAt": "2026-05-22T18:35:46.000Z",
  "title": "Darwin Cluster Ops",
  "status": "green | yellow | red",
  "policy": {
    "mutationRule": "allowlisted actions require Action Ledger intent, confirmed:true, idempotency, and readback",
    "controlPlaneProtection": "t560 host mutations are propose-only in v1",
    "primaryRisk": "OrangeFS server02 on 5860 is the current storage growth ceiling"
  },
  "lanes": {
    "kubernetes": {},
    "slurm": {},
    "orangefs": {},
    "hosts": {}
  },
  "risks": [],
  "actions": []
}
```

Kubernetes lane shape:

```json
{
  "status": "healthy | attention | stale",
  "nodes": [
    {
      "name": "r740-proxmox",
      "ready": true,
      "role": "worker",
      "version": "v1.x",
      "kernel": "...",
      "osImage": "...",
      "containerRuntime": "...",
      "gpu": {
        "capacity": 1,
        "allocatable": 1,
        "accelerator": "nvidia",
        "acceleratorClass": "..."
      },
      "labels": {
        "pool": "...",
        "runtimeRole": "...",
        "orangefsClient": "...",
        "slurmGpuOrangefs": "...",
        "storageProfile": "..."
      }
    }
  ],
  "counts": {
    "nodes": 4,
    "ready": 4,
    "unhealthyPods": 0,
    "gpuCapacity": 2,
    "gpuAllocatable": 2
  },
  "unhealthyPods": [],
  "cilium": {
    "status": "observed | stale",
    "version": "image",
    "envoyImage": "image",
    "kubeProxyReplacement": "...",
    "routingMode": "...",
    "autoDirectNodeRoutes": "...",
    "devices": "...",
    "bpfLbSock": "..."
  },
  "errors": []
}
```

Slurm lane shape:

```json
{
  "status": "healthy | stale",
  "ping": "Slurmctld(primary) at ... is UP",
  "partitions": [
    {
      "partition": "gpu-orangefs",
      "availability": "up",
      "nodes": 1,
      "state": "idle",
      "nodeList": "r740-proxmox"
    }
  ],
  "recentJobs": [
    {
      "jobId": "123",
      "jobName": "job",
      "partition": "gpu-orangefs",
      "account": "...",
      "qos": "...",
      "state": "COMPLETED",
      "exitCode": "0:0",
      "start": "...",
      "end": "...",
      "nodeList": "..."
    }
  ],
  "errors": []
}
```

OrangeFS lane shape:

```json
{
  "status": "healthy | attention | stale",
  "risk": "green | yellow | red | unknown",
  "thinPoolPct": 82.5,
  "workerMounts": [
    {
      "pod": "slurm-pilot-worker-gpuorangefs-...",
      "node": "r740-proxmox",
      "mounted": true,
      "df": "..."
    }
  ],
  "capacityNote": "OrangeFS export size follows the smallest effective server backing store; 5860 server02 is the current growth ceiling.",
  "stdout": "...",
  "stderr": "",
  "error": ""
}
```

Host freshness lane shape:

```json
{
  "status": "observed | partial | blocked",
  "entries": [
    {
      "node": "r740-proxmox",
      "status": "observed | blocked",
      "rebootRequired": "yes | no | unknown",
      "aptUpgradable": 0,
      "error": ""
    }
  ]
}
```

Risk item:

```json
{
  "severity": "red | yellow",
  "layer": "orangefs | host | kubernetes | slurm",
  "code": "ORANGEFS_5860_THIN_POOL_HIGH",
  "summary": "human-readable summary"
}
```

## Cluster Ops Actions

Endpoint:

```http
GET /api/cluster/ops/actions
```

Response:

```json
{
  "schema": "darwin.cluster-ops-actions.v0",
  "generatedAt": "2026-05-22T18:35:46.000Z",
  "actionLedgerProject": "beagle",
  "actions": [
    {
      "id": "route-doctor",
      "label": "Route doctor",
      "kind": "readback",
      "summary": "Run hpc-route-doctor.",
      "risk": "low",
      "requiresTarget": false,
      "route": "/api/cluster/ops/actions/route-doctor/run",
      "requiresConfirmation": true,
      "requiresLedger": true
    }
  ],
  "truthMode": "declared"
}
```

Allowlisted `actionId` values:

- `route-doctor`
- `surface-doctor`
- `slurmdbd-doctor`
- `workspace-doctor`
- `orangefs-status`
- `slurm-nvidia-smi-smoke`
- `orangefs-text-r740`
- `orangefs-text-r770`
- `orangefs-artifact-r740`
- `orangefs-artifact-r770`
- `host-apt-dry-run`
- `host-cordon`
- `host-drain-dry-run`
- `host-drain`
- `host-uncordon`
- `host-apt-upgrade`
- `host-reboot`

Worker target enum:

- `r770-proxmox`
- `5860-proxmox`
- `r740-proxmox`

`t560-proxmox` is intentionally not a worker target for mutating host actions.

Execution endpoint:

```http
POST /api/cluster/ops/actions/:actionId/run
X-Request-ID: <idempotency-key>
Content-Type: application/json
```

Request schema:

```json
{
  "actor": "operator",
  "source": "cluster-ops-ui",
  "confirmed": true,
  "ledgerId": "uuid-from-action-ledger",
  "targetNode": "r740-proxmox",
  "idempotencyKey": "uuid"
}
```

Response schema:

```json
{
  "ok": true,
  "schema": "darwin.cluster-ops-run-result.v0",
  "action": {},
  "targetNode": "r740-proxmox",
  "ledger": {
    "projectSlug": "beagle",
    "ledger_id": "uuid",
    "status": "intent-confirmed"
  },
  "result": {
    "code": 0,
    "timedOut": false,
    "stdout": "...",
    "stderr": "..."
  },
  "receipt": {
    "runId": "20260522T183546000Z-route-doctor",
    "artifactRoot": "/var/lib/cockpit/cluster-ops/...",
    "runPacket": {}
  },
  "readback": {},
  "truthMode": "observed"
}
```

## Action Ledger API Used By Cluster Ops

Proposal:

```http
POST /api/projects/beagle/actions/propose
X-Request-ID: <idempotency-key>
```

Request schema:

```json
{
  "actor": "operator",
  "source": "cluster-ops-ui",
  "proposal": {
    "id": "cluster-route-doctor",
    "label": "Route doctor",
    "kind": "cluster-ops",
    "summary": "Run hpc-route-doctor.",
    "risk": "low",
    "actionId": "route-doctor",
    "route": "/api/cluster/ops/actions/route-doctor/run",
    "requiresConfirmation": true
  },
  "idempotencyKey": "uuid"
}
```

Response schema:

```json
{
  "ok": true,
  "schema": "darwin.action-ledger.v0",
  "action": {
    "ledger_id": "uuid",
    "status": "proposed"
  },
  "event": {
    "schema": "darwin.action-ledger-event.v0",
    "ledger_id": "uuid",
    "projectSlug": "beagle",
    "kind": "proposal",
    "status": "proposed",
    "proposal": {}
  },
  "truthMode": "observed"
}
```

Confirm intent:

```http
POST /api/projects/beagle/actions/:ledgerId/confirm-intent
X-Request-ID: <idempotency-key>
```

Request schema:

```json
{
  "actor": "operator",
  "source": "cluster-ops-ui",
  "reason": "Cluster Ops execution requested for route-doctor",
  "idempotencyKey": "uuid"
}
```

Response includes `executed: false`; the ledger records intent only.

## Beagle Core Authentication

Beagle Core protected routes require:

```http
X-Beagle-Consumer: beagle-operator
Authorization: Bearer <token>
```

Token source:

```http
GET /api/auth/beagle-token
```

Produced by `server/auth-bridge.mjs`, which reads Kubernetes Secret `beagle-core-secrets` and searches keys:

- `BEAGLE_OPERATOR_API_TOKEN`
- `BEAGLE_API_TOKEN`
- `operator-token`

Token bridge response:

```json
{
  "token": "...",
  "consumer": "beagle-operator",
  "auth_header_value": "Bearer ...",
  "consumer_header_name": "X-Beagle-Consumer",
  "consumer_header_value": "beagle-operator",
  "beagle_url": "http://beagle-core.tail21cbc4.ts.net",
  "cluster_internal_url": "http://beagle-core.beagle.svc.cluster.local:8080",
  "cached": false,
  "cache_ttl_ms": 300000,
  "truthMode": "observed",
  "issued_at": "2026-05-22T18:35:46.000Z"
}
```

## Existing Beagle Core Rust/Axum Routes

The live cluster config points at `apps/beagle-monorepo/src/bin/core_server.rs`, which builds `beagle_monorepo::http::build_router`.

Public routes:

- `GET /health`
- `GET /metrics`

Protected routes in `apps/beagle-monorepo/src/http.rs`:

- `POST /api/llm/complete`
- `GET /api/llm/complete/stream`
- `POST /api/pipeline/start`
- `GET /api/pipeline/status/:run_id`
- `GET /api/run/:run_id/artifacts`
- `GET /api/runs/recent`
- `POST /api/observer/physio`
- `GET /api/observer/physio/latest`
- `POST /api/observer/env`
- `POST /api/observer/space_weather`
- `GET /api/observer/context`
- `GET /api/observer/context/:run_id`
- `POST /api/jobs/science/start`
- `GET /api/jobs/science/status/:job_id`
- `GET /api/jobs/science/:job_id/artifacts`
- `POST /api/pcs/reason`
- `POST /api/fractal/grow`
- `POST /api/worldmodel/predict`
- `POST /api/serendipity/discover`
- `POST /api/search/pubmed`
- `POST /api/search/arxiv`
- `POST /api/search/all`
- `POST /dev/causal`
- `POST /dev/debate`
- `POST /dev/deep-research`
- `POST /dev/neurosymbolic`
- `POST /dev/parallel`
- `POST /dev/reasoning`
- `POST /dev/swarm`
- `POST /dev/temporal`
- `POST /dev/research`
- `POST /dev/void`

Protected cognitive routes:

- `GET /api/v1/cognitive/state`
- `GET /api/v1/cognitive/stream` (SSE, not WebSocket)
- `GET /api/v1/cognitive/meta_phi`
- `GET /api/v1/cognitive/phi_of_phi`
- `GET /api/v1/cognitive/tool_rhythm_phi`
- `GET /api/v1/cognitive/joint_phi`
- `POST /api/cognitive/mcp_tool_call`
- `POST /api/fractal/recurse`
- `POST /api/exocortex/process`
- `POST /api/cognitive/deep-think`

Protected memory routes:

- `POST /api/memory/ingest_chat`
- `POST /api/memory/query`
- `GET /api/memory/qdrant/health`
- `GET /api/memory/compiler`
- `GET /api/memory/compiler/budget-profile/:task_profile`
- `POST /api/memory/compiler/compile`
- `POST /api/memory/compiler/eval`
- `POST /api/memory/compiler/policy`
- `GET /api/memory/retrieval/collection`
- `POST /api/memory/retrieval/query`
- `POST /api/memory/retrieval/code/query`
- `GET /api/memory/retrieval/sovereign/backend`
- `POST /api/memory/retrieval/sovereign/query`
- `POST /api/memory/retrieval/router/query-type`
- `POST /api/memory/retrieval/router/decision`
- `POST /api/memory/retrieval/router/query`
- `GET /api/memory/retrieval/backend-matrix`
- `GET /api/memory/retrieval/dense-backend`
- `GET /api/memory/retrieval/reranking-profile`
- `POST /api/memory/retrieval/rerank/pilot`
- `POST /api/memory/retrieval/evaluate`
- `POST /api/memory/retrieval/feedback`
- `GET /api/memory/promotion-policy`
- `GET /api/memory/retention-policy`
- `GET /api/memory/temporal`
- `POST /api/memory/temporal/query`
- `POST /api/memory/graphrag/query-mode`
- `POST /api/memory/promotion/evaluate`
- `POST /api/memory/graphrag/query`
- `POST /api/memory/retrieval/policy/derive`
- `POST /api/memory/retrieval/benchmark`

Protected feedback routes:

- `POST /api/v1/feedback`
- `GET /api/v1/feedback`
- `GET /api/v1/feedback/:run_id`

Protected HPC bridge routes:

- `GET /api/darwin/hpc/control`
- `GET /api/darwin/hpc/profiles`
- `POST /api/darwin/hpc/jobs/submit`
- `GET /api/darwin/hpc/jobs/:job_id`
- `GET /api/darwin/hpc/jobs/:job_id/artifact-manifest`
- `GET /api/darwin/hpc/jobs/:job_id/stdout`
- `GET /api/darwin/hpc/jobs/:job_id/stderr`
- `GET /api/darwin/hpc/results`
- `GET /api/darwin/hpc/results/:job_id`
- `GET /api/darwin/hpc/results/:job_id/manifest`
- `POST /api/darwin/bridge/execute`
- `GET /api/darwin/bridge/health`
- `GET /api/darwin/bridge/providers`

There are many additional `/api/darwin/workstreams/:workstream_id/*` routes in `http_darwin_hpc.rs`; these are Beagle/Darwin workstream surfaces, not the Cluster Ops dashboard API.

## Beagle Core Payloads Needed For Command Center

LLM complete:

```json
{
  "prompt": "string",
  "requires_math": false,
  "requires_high_quality": false,
  "offline_required": false
}
```

Response:

```json
{
  "text": "string",
  "provider": "string",
  "tier": "string"
}
```

Physio ingest:

```json
{
  "hrv_ms": 42.0,
  "hr": 92.0,
  "spo2": 97.0,
  "source": "watch",
  "recorded_at": "2026-05-22T18:35:46.000Z"
}
```

The exact Rust struct should be treated as authoritative before final UI binding, but the handler persists `PhysioSnapshot` and emits a cognitive event.

Cognitive event stream:

```json
{
  "type": "void | fractal | phi | physio | deep_think | mcp_tool | lagged",
  "payload": {},
  "timestamp": "2026-05-22T18:35:46.000Z"
}
```

Current SSE events are typed by SSE event name. The future WebSocket contract in `CONTRACT.md` wraps the same concept in `{type,payload,timestamp,agent_id}`.

## Mocked, Declared, Or Fake/Static Today

- `src/engine/scene.js` topology is static/declared, not live from Kubernetes.
- `/api/cluster/ops/actions` is a declared allowlist, not observed state.
- Action Ledger proposal/intent is real, but does not execute by itself.
- `/api/auth/beagle-discover` is a discovery map; it lists some route intentions and compatibility aliases, not proof that every route is implemented by Cockpit.
- `src/pages/Cognitive.jsx` SSE uses `EventSource` directly against Beagle Core without headers. Under strict Bearer auth this is not production-valid unless the stream accepts token query auth or is proxied.
- `/ws/events` does not exist.
- The `/projects/cluster` page has no Beagle agent chat/thread input.
