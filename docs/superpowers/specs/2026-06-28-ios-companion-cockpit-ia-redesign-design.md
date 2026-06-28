# iOS App — Companion-first IA Redesign (Pessoal + Trabalho)

**Date:** 2026-06-28
**Status:** Design approved (sections Pessoal + Trabalho), pending spec review → plan
**Scope:** Information architecture of the BeagleCockpit iOS app (`beagle-ios/BeagleSuite`), grounded in a live functional audit of all screens.

## 1. Context & Problem

The shipping iOS app is the "old-style cockpit": a flat 6-tab bar (Mind / Fleet / Capture / Deep / Agents / Recall) that mixes the intimate companion with cluster-ops, and carries many screens that are out of context with the current product direction. A merge that unified two iOS branches also introduced a SwiftUI cycle (white screen) and surfaced that the situation is not "pretty fake screens" — it is **a real codebase whose backends are partly down or mis-wired**.

A live, evidence-based audit of **29 screens** (each traced to its real data source and tested against the live backend with the operator token) found:

- **10 real · 10 partial · 8 broken · 1 facade** → 11 keep, 18 fix, 0 pure-cut.
- The **Pessoal core is broken**: the companion chat (`POST /api/mobile/v1/chat`) returns **503 RUNTIME_UNAVAILABLE**, and Moshi voice hits a wrong hardcoded URL (`beagle.chiuratto.ai/api/moshi` = 404; the live backend is beagle-core, which returns 101).
- The **Trabalho side is mostly real but bloated**: 18 cockpit/cluster screens, several only needing an endpoint correction.

Audit artifact: workflow `wf_70742dd0-6dc` (full per-screen results in the session task output `wk241exbl`).

## 2. North-Star & Principles

- **Hybrid: Pessoal (intimate Personal Companion) + Trabalho (cluster/agent cockpit).**
- **Funcione de verdade.** A screen survives only if it is wired to a live backend with real data. No pretty screens with no real function. Verdicts are evidence-based (live endpoint tests), not aspirational.
- **Companion-first.** The app *is* the companion; Trabalho is a secondary mode one tap away.
- **Fewer surfaces.** Collapse 29 audited screens into a small, focused set.

## 3. Top-Level IA — "Companion-pure + Trabalho drawer"

The app opens directly into the companion. Trabalho is not a co-equal space — it lives behind a single `[Trabalho ↗]` entry.

```
COMPANION  (the whole app, opens here)
  Conversa — full-screen chat + voice, with a collapsible context header
  ↑ drawer / swipe → Pessoal sub-surfaces:
       • Capturar
       • Memória
       • Corpo
  [ Trabalho ↗ ] → opens the cockpit:
       Agentes · Cluster · Terminal · Sounio
  ⚙️ → utility: Settings · Diagnostics · Onboarding
```

## 4. Espaço PESSOAL

**Conversa = the home, full-screen.** Launch lands in the chat with the companion (cloud HERMES, memory auto-import, SwiftData history). Moshi **voice is a mic button** → full-duplex overlay (not a separate tab). The **ambient exocortex context** currently rendered by `BeagleSurface` (living-home card, memory signals, continuity delta, origin lineage, body state — all verified live, HTTP 200) **folds into a collapsible header** at the top of the chat. `BeagleSurface` stops being a "home tab" and becomes the context header of Conversa.

**Drawer/swipe → 3 Pessoal sub-surfaces:**

| Sub-surface | Merges | Audit status |
|---|---|---|
| **Capturar** | ThoughtCaptureView + ThinkingAloudSessionView | ✅ real (assisted-import + capture/sessions 200) |
| **Memória** | CognitiveRecallView + CognitiveStateView | recall ⚠️ wrong endpoint (fix); state ⚠️ partial |
| **Corpo** | *(new)* Physiome read-back view | ingest works (uploads 200); **no read view exists — build** |

**Corpo is the only net-new build in Pessoal** — the Physiome ingest pipeline works, but no iOS screen reads the body back. It is small and sits on real endpoints (`/api/physiome/correlations`, the physiome digest).

## 5. Espaço TRABALHO (cockpit, behind `[Trabalho ↗]`)

Secondary mode. Four sections collapse the 18 Trabalho screens:

| Section | Merges | Audit status | Work needed |
|---|---|---|---|
| **Agentes** | AgentsTabView + AgentsHubView + AgentConsoleView + AgentSessionView + AgentActivityView + WorkView | AgentSession ✅ real; rest ⚠️ partial | unify list→console; fix `/api/workspaces/...` endpoints |
| **Cluster** | ControlRoomView + HPCDashboardView + GPUHeatmapView/HeatmapView + ScienceJobsView + SpatialDeskMissionControlView + PlatformView | ControlRoom/SpatialDesk/Platform ✅ real; HPC ⚠️; GPUHeatmap ❌ facade; Science ❌ broken | one mission-control; GPUHeatmap must bind real data (`cockpit_cluster_truth`) or be cut |
| **Terminal** | FleetTerminalsView + TerminalContentView | ❌ broken (PTY does not connect) | same `/ws/terminal` PTY proven in the web cockpit (Fleet Terminal) |
| **Sounio** | SounioPaperWorkbenchView + DeepExplorationView + GoDeepView + TriadReviewView + VisualEvidenceCaptureView | Workbench/Evidence ✅ real; Deep/GoDeep/Triad ❌ broken | fix research-modality endpoints |

## 6. Cuts & Utility

- **CUT: `HomeView`** — the legacy 6-tab home, superseded by Conversa-as-home.
- **GPUHeatmapView** — the only pure facade; included in Cluster **only if** bound to real `cockpit_cluster_truth` data, otherwise cut.
- **Utility (behind ⚙️, outside both spaces):** ModelSettingsView + ProviderSetupView (Settings), DiagnosticsView, OnboardingView.

## 7. Full 29-Screen Disposition

**Pessoal:** ConversationView→Conversa(home); VoiceModeView→Conversa(voice overlay); BeagleSurface→Conversa(context header); ThoughtCaptureView+ThinkingAloudSessionView→Capturar; CognitiveRecallView+CognitiveStateView→Memória; *(Corpo = new Physiome read view)*.

**Trabalho:** AgentsTabView, AgentsHubView, AgentConsoleView, AgentSessionView, AgentActivityView, WorkView → Agentes; ControlRoomView, HPCDashboardView, GPUHeatmapView, HeatmapView, ScienceJobsView, SpatialDeskMissionControlView, PlatformView → Cluster; FleetTerminalsView, TerminalContentView → Terminal; SounioPaperWorkbenchView, DeepExplorationView, GoDeepView, TriadReviewView, VisualEvidenceCaptureView → Sounio.

**Utility:** ModelSettingsView, ProviderSetupView, DiagnosticsView, OnboardingView.

**Cut:** HomeView (and GPUHeatmapView if it cannot be bound to real data).

## 8. Navigation Mechanics

- Root = `ConversationView` (no TabView at the top level — removes the flat 6-tab bar that caused the duplicate-tab AttributeGraph cycle).
- Pessoal sub-surfaces via a drawer (leading-edge swipe / hamburger) — Capturar / Memória / Corpo.
- `[Trabalho ↗]` pushes/presents the cockpit; inside Trabalho a compact tab/segment bar carries Agentes / Cluster / Terminal / Sounio.
- ⚙️ Settings/Diagnostics/Onboarding reachable from the companion header menu.
- Deep-link / launch-override (`launchOverrides.selectedTab`) maps onto the new structure.

## 9. Functional Fix-List (post-IA, priority order)

These are backend/URL fixes, not UI redesign. The IA restructure is inert without them ("funcione de verdade").

- **P0 — Companion chat (503).** `POST /api/mobile/v1/chat` returns RUNTIME_UNAVAILABLE; project-cockpit's fan-out to the LLM runtime (LiteLLM router / model) is failing. iOS code is correct. Restore the serving backend. This is the single highest-leverage fix — it is the hero of the app.
- **P0 — Moshi voice URL.** iOS hardcodes `wss://beagle.chiuratto.ai/api/moshi/v1/session` (404). Either add a WS proxy route in project-cockpit forwarding `/api/moshi/*` → beagle-core, or point the client at beagle-core. Backend (moshi-server + beagle-core proxy) is healthy (101).
- **P1 — Memória recall endpoint** (CognitiveRecall wrong path), **Sounio** Deep/GoDeep/Triad modality endpoints, **Agentes** `/api/workspaces/...` endpoints.
- **P1 — Terminal PTY** for Trabalho (reuse the proven `/ws/terminal` gateway).
- **P2 — Corpo** read view (new, on real physiome endpoints), **Cluster** GPUHeatmap real-data binding or cut, **ScienceJobs**.

## 10. Non-Goals

- No visual/brand redesign in this pass (that is a separate design-system effort; see the companion design deep-research).
- No new backend capabilities beyond restoring/correcting what the screens already expect.
- Trabalho screens keep their existing real functionality; this is consolidation + endpoint repair, not rewrite.

## 11. Implementation Phasing (high level)

1. **Restructure shell** — replace the flat TabView root with Conversa-as-home + drawer + Trabalho mode; wire the disposition; delete HomeView. (No behavior change to the surviving screens.)
2. **P0 backend fixes** — chat 503, Moshi URL — so the companion actually talks.
3. **P1 endpoint repairs** — Memória / Sounio / Agentes / Terminal.
4. **Corpo** new read view; Cluster GPUHeatmap decision.

Each phase is independently shippable and verifiable on the physical device (build+install loop in [[project_mac_build_access]]).
