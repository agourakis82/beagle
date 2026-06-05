# Component Inventory - Darwin Cluster Ops v0.4.1

This inventory documents the current `Darwin Cluster Ops` assets in `beagle/apps/project-cockpit` so the next frontend pass can extend the system without guessing what already exists.

## Project Shape

- App root: `/home/devsounio/beagle/apps/project-cockpit`
- Frontend framework: SolidJS 1.9 via Vite 5
- Server framework: Node.js / Express 4
- Primary ops route: `/projects/cluster`
- Primary ops page: `src/pages/ClusterOps.jsx`
- Dev client port: `4173`
- Dev server/API port: `4370`
- Vite proxy: `/api` and `/ws` proxy to `127.0.0.1:4370`
- Tailwind: not present
- TypeScript: not present; app is JSX + ESM JavaScript

## Directory Structure

```text
beagle/apps/project-cockpit/
  Dockerfile
  README.md
  index.html
  package.json
  vite.config.js
  public/
    openapi.yaml
    project-catalog.json
  server/
    action-ledger-routes.mjs
    agent-routes.mjs
    auth-bridge.mjs
    cluster-ops-routes.mjs
    contract.mjs
    index.mjs
    job-routes.mjs
    queue-routes.mjs
    scratchpad-routes.mjs
  src/
    App.jsx
    main.jsx
    pages/ClusterOps.jsx
    pages/Cognitive.jsx
    components/
    design/
    engine/scene.js
    stores/truth.js
```

`dist/` exists but is generated build output. Do not edit it directly.

## Package Dependencies

Runtime dependencies from `package.json`:

- `solid-js`
- `@solidjs/router`
- `express`
- `ws`
- `node-pty`
- `xterm`
- `xterm-addon-fit`
- `three`
- `tone`

Development dependencies:

- `vite`
- `vite-plugin-solid`
- `concurrently`

Scripts:

- `npm run dev`: Vite client only
- `npm run dev:server`: Express server only
- `npm run dev:all`: server + client
- `npm run build`: Vite production build
- `npm run start`: production Express server

## Main Route Shell

`src/App.jsx` owns app routing and the full-screen Three.js background canvas. The route added for Darwin Cluster Ops is:

```jsx
const ClusterOps = lazy(() => import("./pages/ClusterOps"));

// ...
<Route path="/projects/cluster" component={ClusterOps} />
```

The same shell also has `/cognitive`, which is closer to the future Beagle Command Center model but is not integrated into `/projects/cluster` yet.

## Darwin Cluster Ops Page

Primary file: `src/pages/ClusterOps.jsx`

Local components defined inside the page:

- `Metric`: compact label/value display using `--font-data`.
- `OpsButton`: action button for refresh/navigation/run.
- `SectionTitle`: uppercase section title with optional status.
- `NodeTable`: Kubernetes node grid with ready/role/GPU/storage/runtime columns.
- `ResultPanel`: execution output panel for allowlisted action results.
- `ClusterOps`: page component and action orchestration.

Main UI regions:

- Header: title, truth badge, status, policy text, bridge/project-os/refresh buttons.
- Summary strip: nodes, GPUs, Slurm, OrangeFS, thin pool, host SSH, risk count.
- OrangeFS 5860 Ceiling panel: thin-pool risk, worker mounts, capacity note.
- Kubernetes Nodes panel: `NodeTable`.
- Slurm Lane panel: partitions and recent jobs.
- Risks panel: active risk list from backend.
- Cilium panel: agent image, envoy image, KPR, routing mode.
- Host Freshness panel: SSH/apt/reboot freshness per host.
- Action Lane panel: target worker selector and allowlisted actions.
- GPU Placement panel: GPU-bearing nodes.

Snippet from `ClusterOps.jsx` showing the current fetch/action surface:

```jsx
const ACTION_PROJECT = "beagle";

async function fetchClusterOps() {
  return fetchWithTruth("/api/cluster/ops/summary", 60000);
}

async function postJson(path, body = {}, timeoutMs = 300000) {
  const id = body.idempotencyKey || requestId();
  const res = await fetch(path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Request-ID": id,
      "X-Darwin-Actor": "operator",
    },
    body: JSON.stringify({ ...body, idempotencyKey: id }),
    signal: AbortSignal.timeout(timeoutMs),
  });
```

Snippet showing the current `NodeTable` data expectation:

```jsx
<span style={{ "word-break": "break-word" }}>{node.name}</span>
<span style={{ color: node.ready ? "var(--truth-observed)" : "var(--state-error)" }}>
  {node.ready ? "yes" : "no"}
</span>
<span>{node.role}</span>
<span style={{ "word-break": "break-word" }}>
  {valueOf(node.gpu?.accelerator || node.gpu?.acceleratorClass)}
</span>
<span>{node.gpu?.allocatable ?? 0}/{node.gpu?.capacity ?? 0}</span>
```

Snippet showing the existing Action Ledger gate:

```jsx
const proposed = await postJson(`/api/projects/${ACTION_PROJECT}/actions/propose`, {
  ...baseBody,
  proposal: {
    id: `cluster-${action.id}`,
    label: action.label,
    kind: "cluster-ops",
    summary: target ? `${action.summary} target=${target}` : action.summary,
    risk: action.risk,
    actionId: action.id,
    route: action.route,
    requiresConfirmation: true,
  },
}, 12000);
```

## Shared Components Used

- `components/GlassPanel.jsx`: main glassmorphism panel primitive with `data-truth`.
- `components/TruthBadge.jsx`: truth chip for `observed`, `remembered`, `declared`, `stale`.
- `components/Skeleton.jsx`: loading skeleton.
- `components/CommandPalette.jsx`: global command palette.
- `components/KeyboardOverlay.jsx`: keyboard overlay.
- `components/AudioControl.jsx`: fixed global audio control.

Current `GlassPanel` snippet:

```jsx
export default function GlassPanel(props) {
  const variant = () => {
    if (props.elevated) return "glass glass--elevated";
    if (props.subtle) return "glass glass--subtle";
    return "glass";
  };

  return (
    <div class={`${variant()} ${props.class || ""}`}
      style={{ padding: props.padding || "var(--space-5)", ...(props.style || {}) }}
      data-truth={props.truth}>
      {props.children}
    </div>
  );
}
```

## Design System Files

- `src/design/reset.css`: global reset.
- `src/design/tokens.css`: semantic color, spacing, radius, transition tokens.
- `src/design/typography.css`: font stacks and type scale.
- `src/design/glass.css`: glass panel styles.
- `src/design/truth.css`: truth-mode border styles and badges.
- `src/design/motion.css`: motion primitives.
- `src/App.css`: older/global styles and xterm CSS import.

Current design decisions:

- Palette: dark sovereign/ops surface with semantic teal, sky, slate, gold, red.
- Truth colors:
  - `observed`: teal
  - `remembered`: sky
  - `declared`: slate
  - `stale`: gray
- Operational risk:
  - `green/healthy/ready`: teal
  - `yellow/warn/attention`: gold
  - `red/fail/error/critical`: red
- Typography:
  - data: Berkeley Mono / JetBrains Mono / SF Mono
  - UI/display: Inter / SF Pro
- Layout:
  - full-screen Three.js canvas as background
  - SolidJS DOM panels over canvas
  - dashboard max width around `1320px`
  - glass panels, not Tailwind cards

## Three.js Background

File: `src/engine/scene.js`

It builds a static declared topology, not a live topology:

- `r770-proxmox`
- `r740-proxmox`
- `t560-proxmox`

The scene is visual atmosphere and does not currently bind to `/api/cluster/ops/summary`.

Snippet:

```js
const nodeData = [
  { id: "r770", label: "r770-proxmox", role: "gpu", x: -3, y: 1.5, color: "healthy" },
  { id: "r740", label: "r740-proxmox", role: "gpu", x: 3, y: 1.5, color: "healthy" },
  { id: "t560", label: "t560-proxmox", role: "control", x: 0, y: -2.5, color: "control" },
];
```

## What Exists But Is Not Part Of Cluster Ops Yet

`src/pages/Cognitive.jsx` is a separate prototype route at `/cognitive`. It has:

- Beagle token bridge call via `/api/auth/beagle-token`
- direct Beagle Core calls to `/api/v1/cognitive/*`
- SSE via `/api/v1/cognitive/stream`
- Phi rhythm panels
- tool rhythm panel
- deep-think launcher

This is the closest existing code to the Beagle Command Center direction, but it is not wired into `/projects/cluster` and has an auth limitation: `EventSource` cannot set `Authorization` headers.

## Current WebSocket Assets

Existing WebSocket routes:

- `/ws/terminal`: xterm PTY bridge in `components/Terminal.jsx` and `server/index.mjs`
- `/ws/projects/:slug/agent/:kind`: tmux/kubectl agent session bridge in `server/agent-routes.mjs`

Missing WebSocket route needed by the new architecture:

- `/ws/events`

`/ws/events` does not exist today. Cognitive streaming is SSE (`/api/v1/cognitive/stream`), not WebSocket.
