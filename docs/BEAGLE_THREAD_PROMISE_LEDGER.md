# Beagle Thread Promise Ledger

This ledger is the repo-local contract for the long Beagle planning thread. It
does not claim "100%" unless there is code, a test, and a runnable acceptance
path. Cluster-private data, truthsets, memories, videos, PDFs, and generated
assets remain outside Git.

## Current Reality

- **Canonical memory authority:** cluster/PVC/JSONL/Merkle/Chronoself.
- **MacBook/GitHub role:** client code, schemas, scripts, UI, tests, sanitized
  documentation, and derived metrics only.
- **Primary MVP:** Sounio Workday daily driver.
- **Current hot path:** Beagle Terminal Protocol v1 + workspace-agent.
- **Warp status:** AGPL boundary + bridge/probe/bake-off only; renderer is not
  promoted.

## Promise Matrix

| Thread scope | Promised outcome | Repo evidence | Current status | Remaining acceptance |
| --- | --- | --- | --- | --- |
| v1.7 Work Memory Autopilot | Codex/Claude/app work creates cluster memory with audit trail | `scripts/beagle-work-memory-capture`, `scripts/beagle-work-memory-daemon`, `AGENTS.md` | **Implemented foundation** | Keep capturing every meaningful implementation slice; verify query recovery after each real work block. |
| v1.8-v2.3 Memory Bench, HyperMemory, Context Compiler, DreamCycle | Evaluation-first memory loop with truthsets, bench, context packs, policy/dream candidates | `apps/beagle-memory-engine/src/main.rs`, `apps/beagle-monorepo/src/http_exocortex.rs` | **Implemented scaffolds and APIs** | Run cluster-private truthset/MemoryArena jobs and record 3 passing runs before promoting any advisory policy. |
| v2.4-v2.5 Sounio PaperRun + `Claim<T>` | Beagle observes, Sounio types claims/evidence; PaperRun is traceable | `apps/beagle-monorepo/src/http_exocortex.rs` PaperRun, claims, theatre handlers | **Implemented scaffolds** | Generate a reviewed paper section and public digest from a real Sounio claim graph. |
| v2.6-v3.0 Apple Living Home/Lens/Composer | Apple-first living memory UI and multimodal capture models | `beagle-ios/BeagleSuite/Sources` | **Partially implemented** | Device-level UX pass on iPhone/iPad/macOS, plus voice/image capture acceptance with restricted filtering. |
| v3.1-v3.5 Sounio Workbench + Agent Fabric | Workspace-agent, durable PTY, role lanes, memory-curated blocks | `apps/beagle-workspace-agent`, `apps/project-cockpit`, `scripts/sounio-workday-mvp-smoke` | **Implemented MVP path** | Use for a real 60-90 minute Sounio block without Termius/Zellij; query recovered decision with provenance. |
| v3.6-v3.7 Spatial Control Room/Mind Palace | Spatial APIs, world-console, mind palace, portals, focus coach | `apps/world-console`, spatial/mind-palace routes in core | **Implemented service/API scaffolds** | Vision Pro/native RealityKit acceptance remains future physical-device work. |
| v3.8-v3.9 Warp Bake-Off | AGPL boundary, Warp bridge, renderer probe, Apple A/B sheet, Cockpit scorecard | `apps/warp-workbench`, `/projects/:slug/warp`, `BeagleWorkbenchKit/RendererBakeOff.swift` | **Implemented spike path** | Run `renderer:probe:block` on real Sounio blocks, inspect `/projects/sounio/warp`, collect Apple A/B human judgments. |
| MVP-0 Sounio Workday | Real daily-driver loop: block -> memory -> SounioMoment -> query recovery | `scripts/sounio-workday-mvp-smoke`, workspace-agent remember flow | **Ready for cluster smoke** | Execute real Sounio work session and pass the mandatory queries: "o que aconteceu hoje no Sounio?" and "qual foi a última decisão do Codex?". |

## Non-Negotiables

- `restricted` and `restricted_local_only` never enter active Home/search, public
  digest, renderer previews, or external generation prompts.
- Missing CLIs/providers show `needs_setup`; Beagle does not auto-install them.
- AGPL-derived Warp code remains under `apps/warp-workbench` or the Apple
  Workbench boundary. Core, MCP, memory engine, and Project Cockpit consume only
  protocol/JSON outputs.
- Renderer bake-off never writes canonical memory by itself.
- Any "promotion" from advisory to hot path requires test evidence, provenance,
  zero restricted leak, and an explicit decision memo.

## Required Next Proofs

1. Run `scripts/beagle-promise-ledger` locally and keep it green for repo-level
   artifacts.
2. Run `scripts/sounio-workday-mvp-smoke` against the cluster.
3. Run `npm --prefix apps/warp-workbench run renderer:probe:block -- ...` on a
   real Sounio Workbench block and confirm `/projects/sounio/warp` shows the
   derived result.
4. Use the Apple Renderer Bake-off sheet on the same block and record a human
   judgment.
5. Execute a real Sounio Workday block and prove retrieval through GraphRAG++.
