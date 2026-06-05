# Handoff - Beagle Command Center v0.4.1

Recipient: Kimi K2.6 / Moonshot AI

Sender: Codex 5.5

Scope: frontend design and architecture handoff from `Darwin Cluster Ops` to `Beagle Command Center`.

## Current State

The current implementation is `project-cockpit`, a SolidJS + Vite frontend with a Node/Express backend. The route `/projects/cluster` is implemented as `Darwin Cluster Ops`, an infrastructure dashboard and controlled ops lane.

It works as an ops surface:

- reads Kubernetes node health and Cilium state
- reads Slurm status, partitions, and recent jobs
- reads OrangeFS status and the 5860 thin-pool ceiling
- reads host freshness over SSH
- lists GPU placement
- shows active risks
- provides allowlisted doctor/smoke/host actions
- gates execution through Action Ledger proposal and confirmed intent
- writes execution receipts under `BEAGLE_DATA_DIR/cluster-ops/<run_id>/`

It does not yet work as the Beagle mental model:

- no multi-agent chat/thread
- no visual scientific pipeline
- no Darwin -> Observer -> HERMES -> Triad flow
- no three-column ATHENA/HERMES/ARGOS review
- no Memory Graph explorer
- no real-time Physio HUD
- no integrated user input for agent conversation
- no exocortex-first command center route
- no scientific context inside the Cluster Ops doctors

The most important distinction: `Darwin Cluster Ops` is an infrastructure control lane. `Beagle Command Center` must be an exocortex: scientific pipeline, adversarial agents, GraphRAG memory, physiology, and gated action.

## Files To Read First

- `docs/COMPONENT_INVENTORY.md`
- `docs/API_MAP.md`
- `docs/CONTRACT.md`
- `src/pages/ClusterOps.jsx`
- `src/pages/Cognitive.jsx`
- `server/cluster-ops-routes.mjs`
- `server/action-ledger-routes.mjs`
- `server/auth-bridge.mjs`
- `apps/beagle-monorepo/src/http.rs`
- `apps/beagle-monorepo/src/http_cognitive.rs`
- `apps/beagle-monorepo/src/http_memory.rs`

## Design Decisions Already Made

Visual system:

- dark sovereign ops palette
- semantic color, not decorative color
- teal means observed/healthy/live
- sky means remembered/cached
- slate means declared/policy
- gold means warm/attention
- red means real error or destructive risk

Typography:

- `--font-data`: Berkeley Mono / JetBrains Mono / SF Mono
- `--font-ui`: Inter / SF Pro Text
- `--font-display`: Inter / SF Pro Display

Layout:

- full-screen canvas background
- glass panels over the canvas
- `TruthBadge` and `data-truth` borders as the epistemic status language
- `/projects/cluster` uses a two-column dashboard grid after the top summary strip

Current primitive:

```jsx
<GlassPanel elevated truth={data().status === "green" ? "observed" : "remembered"}>
  <div style={{ display: "grid", "grid-template-columns": "repeat(auto-fit, minmax(120px, 1fr))" }}>
    <Metric label="nodes" value={`${ready}/${total}`} />
    <Metric label="gpus" value={`${gpuAllocatable}/${gpuCapacity}`} />
    <Metric label="slurm" value={slurmStatus} />
  </div>
</GlassPanel>
```

My recommendation: keep the semantic truth/risk language, but do not preserve the current dashboard/card composition as sacred. It is functional, but it still reads as ops telemetry rather than an exocortex.

## Technical Restrictions

Do not change these without coordinating backend work:

- `GET /api/cluster/ops/summary`
- `POST /api/cluster/ops/actions/:actionId/run`
- Action Ledger proposal/confirm/reject routes
- Beagle Core auth headers:
  - `X-Beagle-Consumer: beagle-operator`
  - `Authorization: Bearer <token>`
- worker target restriction:
  - allowed: `r770-proxmox`, `5860-proxmox`, `r740-proxmox`
  - `t560-proxmox` is propose-only for host mutation
- distinction between cluster truth, research operations, workspace habitat, and cognition

Do not treat the current Three.js topology as live truth. It is static visual scaffolding.

## What To Build Next

Create a new Beagle Command Center frontend layer without deleting `/projects/cluster`.

Suggested route:

```text
/beagle
```

or:

```text
/projects/beagle/command
```

Suggested component files:

```text
src/pages/BeagleCommandCenter.jsx
src/components/beagle/PipelineRail.jsx
src/components/beagle/AgentThread.jsx
src/components/beagle/TriadReview.jsx
src/components/beagle/MemoryGraph.jsx
src/components/beagle/PhysioHud.jsx
src/components/beagle/ActionLedgerGate.jsx
src/components/beagle/ClusterHealthDock.jsx
src/stores/beagleEvents.js
src/stores/beagleApi.js
```

Keep `/projects/cluster` as:

- ClusterHealthDock source
- doctors/actions surface
- emergency ops fallback

Do not make it the primary exocortex screen.

## Suggested Integration Plan

1. Build `beagleApi.js`
   - wraps `/api/auth/beagle-token`
   - provides `beagleGet` and `beaglePost`
   - can target `localhost:8080`, Tailnet, or Cockpit proxy

2. Build `beagleEvents.js`
   - preferred future source: `/ws/events`
   - temporary fallback: poll `/api/v1/cognitive/state` and use SSE `/api/v1/cognitive/stream` where auth permits

3. Build the Command Center route
   - left: PipelineRail
   - center: AgentThread + active stage detail
   - right: PhysioHud + ClusterHealthDock + ActionLedgerGate
   - lower or modal: TriadReview and MemoryGraph

4. Preserve ops API
   - import Cluster Ops summary as a dock/panel
   - link out to `/projects/cluster` for doctors and host actions

5. Treat every destructive action as ledger-gated
   - show risk and target
   - require explicit operator confirm
   - render ledger id and readback

## Integration Snippet

Start with an API wrapper like this:

```js
export async function getBeagleToken() {
  const res = await fetch("/api/auth/beagle-token");
  if (!res.ok) throw new Error(`token bridge ${res.status}`);
  return res.json();
}

export async function beagleFetch(path, token, init = {}) {
  const base = window.__BEAGLE_URL__ || "http://localhost:8080";
  return fetch(`${base}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      "X-Beagle-Consumer": token.consumer || "beagle-operator",
      Authorization: `Bearer ${token.token}`,
      ...(init.headers || {}),
    },
  });
}
```

For local development, if `localhost:8080` is not reachable from the browser, use Cockpit proxy routes or Vite proxy. Do not hardwire private in-cluster DNS into the frontend.

## Gaps To Close

Exact missing pieces for Beagle Command Center:

- Agent Thread: no multi-agent chat model or UI exists.
- User input: no single "talk to agents" input exists.
- Pipeline UI: no Darwin -> Observer -> HERMES -> Triad visualization exists.
- Triad Review: no ATHENA/HERMES/ARGOS three-column review exists.
- Memory Graph: GraphRAG routes exist, but no graph explorer exists.
- Physio HUD: observer routes exist, but no command-center HUD exists.
- Action Ledger gate: exists for cluster actions, but not generalized visually for agent-proposed exocortex actions.
- Scientific doctors: current doctors are infra doctors; they do not understand PBPK, Heliobiology, Scaffolds, or manuscript/review context.
- Event bus: `/ws/events` does not exist yet; current cognitive stream is SSE.
- SSE auth: `EventSource` cannot set Bearer headers, so strict-auth streaming needs a proxy or WebSocket.

## What Not To Do

- Do not rewrite the frontend from scratch.
- Do not delete `/projects/cluster`.
- Do not move ops semantics into Beagle cognition.
- Do not bypass Action Ledger for destructive actions.
- Do not imply the cluster is the Beagle. The cluster is one substrate; Beagle is the exocortex.

## Final Mental Model

The new UI should make this visible:

```text
Human intent
  -> Agent Thread
  -> Pipeline: Darwin -> Observer -> HERMES -> Triad
  -> Memory Graph + Physio HUD
  -> Action Ledger gate when the system wants to mutate infrastructure
  -> Cluster Ops backend executes only confirmed, allowlisted ops actions
```

Cluster health remains a dock. The exocortex becomes the room.
