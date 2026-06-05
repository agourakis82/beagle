# Beagle Native Apple — Architecture (reset)

This document is the single source of truth after the 2026 reset.
If something is not listed here as live, assume it is **not wired**.

## Product

**One Mac app:** `Beagle` (`BeagleWorkbench` SPM product today).

- **Primary surface:** MacBook (M3 Max) — SwiftUI, signed `.app` later
- **Backend spine:** t560-proxmox — Project Cockpit + Beagle monorepo
- **Not the product:** Zed/MCP shells, mock demos, parallel “Beagle IDE” launchers

## Layers

```text
┌──────────────────────────────────────┐
│ Beagle.app (SwiftUI)                 │
│  WorkbenchStore  ← only UI state     │
└───────────────┬──────────────────────┘
                │ HTTPS (Tailscale / tunnel)
┌───────────────▼──────────────────────┐
│ Project Cockpit :4370                │
│  /api/catalog/executive              │
│  /api/projects/:slug/go-work-now     │
│  /api/cluster/ops/summary            │
└───────────────┬──────────────────────┘
                │
┌───────────────▼──────────────────────┐
│ Beagle monorepo :8080                │
│  /api/exocortex/process  (not in UI)   │
│  PersonalExocortex crate               │
└──────────────────────────────────────┘
```

## Live today (reset build)

| Wire | Endpoint | UI |
|------|----------|-----|
| Project catalog | `GET /api/catalog/executive` | Sidebar projects + Connection health |
| Workspace | `GET /api/projects/:slug/go-work-now?depth=deep` | Header, tabs → agents |
| Cluster ops | `GET /api/cluster/ops/summary` | Supercomputing window + Connection health |
| Multimodel turns | `GET /api/projects/darwin-mfc/multimodel/turns` | Conversation canvas |
| Composer send | `WS /ws/projects/darwin-mfc/multimodel-chat` (fallback: agent-terminal POST) | Darwin-MFC chat slug |
| Exocortex Φ | `POST /api/beagle/api/exocortex/process` | Exocortex inspector + `/exocortex` |
| Workbench presence | `GET /api/workbench/:slug/context/presence` | Memory inspector |
| Recent context | `GET /api/workbench/:slug/context/recent` | Memory inspector (read-only) |
| Lease guard | local observe-then-gate | Composer blocks patch/commit until resend |
| GraphRAG | `POST /api/workbench/:slug/context/graphrag/query` | GraphRAG inspector + `/graphrag` |
| Handoffs board | `GET /api/workbench/:slug/context/messages/board` | Memory inspector (read-only) |
| Multimodel providers | `GET .../multimodel/providers` | Agent inspector |
| Zellij send | `POST /api/projects/:slug/workspace/zellij/send` | Composer `/send`, tab routing, agent PTY fallback |
| Zellij screen | `POST /api/projects/:slug/workspace/zellij/screen` | Zellij inspector peek |
| Zellij status | `GET /api/projects/:slug/workspace/zellij/status` | Connection + Zellij inspector |
| Agent PTY input | `POST /api/projects/:slug/agent/session/:kind/input` | Zellij routing when pod live |
| Multimodel stop | `WS { type: "stop" }` on multimodel-chat | Composer stop button + `/stop` |
| Agent PTY live | `WS /ws/projects/:slug/agent/:kind` | Terminal canvas + direct PTY input |
| Handoffs mutate | `POST .../context/messages/send` + reply/claim/complete | Handoffs inspector + `/handoff` |
| Handoff compile | `GET .../context/messages/:id/compile` | Handoffs inspector + `/handoff-compile` |

## Code map

| Path | Role |
|------|------|
| `BeagleSuite/Sources/BeagleCore/` | Models, `TruthMode`, `CockpitClient` |
| `BeagleSuite/Sources/BeagleCore/CockpitClient+Workbench.swift` | go-work-now, cluster, multimodel, exocortex |
| `BeagleSuite/Sources/BeagleWorkbench/WorkbenchStore.swift` | **Live store** — wires + multimodel + lease guard |
| `BeagleSuite/Sources/BeagleWorkbench/WorkbenchRootView.swift` | Root navigation + command palette |
| `BeagleSuite/Sources/BeagleWorkbench/FocusSidebarView.swift` | Project sidebar |
| `BeagleSuite/Sources/BeagleWorkbench/FocusConversationView.swift` | Chat canvas + composer |
| `BeagleSuite/Sources/BeagleWorkbench/MultimodelChatWebSocket.swift` | Realtime multimodel WS |
| `BeagleSuite/Sources/BeagleWorkbench/ConnectionHealthView.swift` | Connection wires inspector |
| `BeagleSuite/Sources/BeagleWorkbench/ComposerCommandDeck.swift` | Bold composer: delivery pills, provider chips, stop |
| `BeagleSuite/Sources/BeagleWorkbench/ZellijDepthPanel.swift` | Zellij transport, screen peek, agent pods |
| `BeagleSuite/Sources/BeagleWorkbench/AgentTerminalWebSocket.swift` | Live agent pod PTY bridge |
| `BeagleSuite/Sources/BeagleWorkbench/AgentTerminalCanvas.swift` | Bold terminal canvas (PTY + zellij peek) |
| `BeagleSuite/Sources/BeagleWorkbench/HandoffsDepthPanel.swift` | Handoff compose/reply/claim/complete + compile viewer |
| `BeagleSuite/Sources/BeagleWorkbench/BeagleWorkbenchApp.swift` | App entry + legacy canvas views |
| `BeagleSuite/Sources/BeagleCockpit/` | Secondary app target — **not shipped** yet |
| `darwin-zed/` | Editor lab — **secondary**, not Beagle product |

## Mac dev loop

```bash
# on t560 — start API + tunnel to Mac (if needed)
cd beagle/beagle-ios/BeagleSuite
./start-workbench-live-bridge.sh

# on Mac
cd ~/dev/beagle-workbench-codex-liquid
./build-workbench-on-mac.sh
BEAGLE_COCKPIT_URL=http://127.0.0.1:4370 swift run BeagleWorkbench
```

Default Cockpit URL: `http://127.0.0.1:4370` (override with `BEAGLE_COCKPIT_URL`).

## Phase 1 gate (dev foundation)

Run on **t560** (starts Cockpit + SSH tunnel to Mac if needed):

```bash
cd beagle/beagle-ios/BeagleSuite
./start-workbench-live-bridge.sh   # if tunnel down
./doctor-beagle-workbench.sh
```

Expected **PASS**:

- `project-cockpit-api.service active`
- `beagle-workbench-cockpit-tunnel.service active`
- t560: catalog (9 projects), workspace (`sounio` status), cluster summary
- Mac via tunnel: same three endpoints on `http://127.0.0.1:4370`

Local-only on t560 (skip Mac checks):

```bash
CHECK_MAC=0 ./doctor-beagle-workbench.sh
```

On **Mac** before running the app:

```bash
export BEAGLE_COCKPIT_URL=http://127.0.0.1:4370
./build-workbench-on-mac.sh
swift run BeagleWorkbench
```

App gate: sidebar shows real projects and zellij tabs (no orange disconnected banner).

## Implementation phases (status)

| Phase | Scope | Status |
|-------|--------|--------|
| 0 | Reset honesto (no mock) | done |
| 1 | Doctor + bridge gate | done |
| 2 | Beagle.app Xcode/bundle + signing | done |
| 3 | ConnectionHealthView + CockpitClient | done |
| 4 | ExocortexClient + panel | done |
| 5 | Multimodel read/send | done |
| 6 | Agent presence + handoffs | done |
| 7 | Lease guard | done |
| 8 | Split BeagleWorkbenchApp.swift | done |
| 9 | Zellij depth + composer command deck + GraphRAG Grape | done |
| 10 | Agent PTY WS canvas + handoffs mutate | done |
| 11 | Handoff compile packet viewer (GraphRAG + thread) | done |

## Next wires (order)

1. TestFlight internal build
2. Artifact canvas (file previews from workspace git)

## Discarded (on purpose)

- `WorkbenchStore.mock()` fake agents and chat history
- Fake fallback cluster nodes and ritual zellij tabs
- “Beagle IDE” = Zed rebranding as exocortex
- Multiple half-shipped app names without Xcode targets
