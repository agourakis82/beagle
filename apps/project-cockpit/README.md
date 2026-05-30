# Project Cockpit

This app is the web-first scaffold for a project-shaped control surface that is
lighter than VS Code and more honest about where persistence really lives.

The first pilot is `Sounio`.

## Workbench mirror

The calm web mirror of the native Beagle Workbench is:

- `/workbench`
- `/workbench/:slug`

It is intentionally a focus studio, not another cockpit. The route defaults to
Code, keeps the lane rail collapsed, renders agents as presence dots, and
exposes Conversation, Artifact, Context, Terminal, and HPC as tabs only when the
user asks for them. The Code tab is the working room for the selected project:
continuity packet, RAG++ readback, open handoffs, repository facts, and the
project validation gate sit beside the composer so coding and pre-coding chat
stay in one surface. Its quick actions are wired to the same memory mesh:
Resume and Implement write turns into the workbench conversation, Review with
Kimi sends a real handoff, and Checkpoint writes a Workbench Context record.
Open handoffs can be compiled in place into an agent packet with retrieval
highlights and graph context, then acknowledged, claimed, heartbeated,
released, or completed from the same Code room.
It reads the same live contracts as the native workbench:

- `GET /api/projects/:slug/go-work-now?depth=deep`
- `GET /api/cluster/ops/summary`
- `GET /api/auth/beagle-discover`
- `GET /api/workbench/:slug/context/connect`
- `GET /api/workbench/:slug/context/status`
- `GET /api/workbench/:slug/context/doctor`
- `POST /api/workbench/:slug/context/doctor`
- `GET /api/workbench/:slug/context/clients`
- `GET /api/workbench/:slug/context/presence`
- `GET /api/workbench/:slug/context/sessions`
- `GET /api/workbench/:slug/context/audit`
- `GET /api/workbench/:slug/context/audit/events`
- `GET /api/workbench/:slug/context/recent`
- `GET /api/workbench/:slug/context/continuity`
- `GET /api/workbench/:slug/context/messages`
- `GET /api/workbench/:slug/context/messages/board`
- `GET /api/workbench/:slug/context/messages/inbox/:client_id`
- `GET /api/workbench/:slug/context/export`
- `GET /api/workbench/:slug/context/mcp/tools`
- `POST /api/workbench/:slug/context/mcp`
- `POST /api/workbench/:slug/mcp`
- `POST /api/workbench/:slug/context/ingest`
- `POST /api/workbench/:slug/context/import`
- `POST /api/workbench/:slug/context/messages/send`
- `POST /api/workbench/:slug/context/messages/:message_id/ack`
- `GET /api/workbench/:slug/context/messages/:message_id/compile`
- `POST /api/workbench/:slug/context/messages/:message_id/compile`
- `POST /api/workbench/:slug/context/messages/:message_id/claim`
- `POST /api/workbench/:slug/context/messages/:message_id/complete`
- `POST /api/workbench/:slug/context/messages/:message_id/release`
- `POST /api/workbench/:slug/context/messages/:message_id/cancel`
- `POST /api/workbench/:slug/context/messages/:message_id/reopen`
- `POST /api/workbench/:slug/context/messages/:message_id/heartbeat`
- `POST /api/workbench/:slug/context/query`
- `POST /api/workbench/:slug/context/graphrag/query`
- `POST /api/workbench/:slug/context/compiler/compile`

The Context tab is the reminder that the studio is not a private chat box:
Claude Desktop, ChatGPT, Grok, and local zellij agents are expected to share
Beagle MCP as the memory bus. RAG++ readback is shown beside the conversation
before the work becomes an agent handoff.

The Workbench context backend is implemented in this app while the currently
published Beagle Core image does not expose the deeper GraphRAG/compiler routes
yet. It stores a local append-only Workbench memory overlay, writes the same
turns through to Beagle Core `/api/memory/ingest_chat`, and queries both the
local overlay and Beagle Core `/api/memory/query`. This gives the studio real
read-after-write behavior for Claude Desktop, ChatGPT, Grok, Codex, Kimi, and
zellij-agent memory instead of waiting for the upstream memory spine to become
immediately consistent.

The GraphRAG route is intentionally bounded: it builds a small graph projection
from retrieved memories, sources, sessions, tags, providers, and detected
entities. The compiler route turns the same retrieval packet into a compact
context packet for agent handoff. These routes are operational contracts now,
not decorative UI fixtures, but the deeper long-term home is still Beagle Core.

The agent MCP server exposes the same memory bus as tools:

- `cockpit_workbench_context_status`
- `cockpit_workbench_context_doctor`
- `workbench_context_doctor` over HTTP MCP
- `cockpit_workbench_context_audit`
- `cockpit_workbench_context_presence`
- `cockpit_workbench_context_continuity`
- `cockpit_workbench_context_ingest`
- `cockpit_workbench_context_query`
- `cockpit_workbench_context_graphrag`
- `cockpit_workbench_context_compile`
- `cockpit_workbench_context_import`
- `cockpit_workbench_context_export`
- `cockpit_workbench_context_send`
- `cockpit_workbench_context_inbox`
- `cockpit_workbench_context_board`
- `cockpit_workbench_context_ack`
- `cockpit_workbench_context_handoff_compile`
- `cockpit_workbench_context_claim`
- `cockpit_workbench_context_complete`
- `cockpit_workbench_context_release`
- `cockpit_workbench_context_cancel`
- `cockpit_workbench_context_reopen`
- `cockpit_workbench_context_heartbeat`

Ingest/import are idempotent by `X-Request-ID`, `idempotencyKey`, `event_id`,
or stable turn hash, so external MCP clients can retry without duplicating the
local overlay. The status/audit endpoints expose observed clients, sessions,
sources, and tags so the UI can distinguish a declared integration from one
that has actually written memory.
The continuity packet is the anti-amnesia contract: agents should call it at
the start of a new turn to recover status, presence, open handoffs, next
actions, and recent memory before mutating work.
Handoff messages use the same append-only store instead of a separate queue:
send/inbox/ack/claim/release/complete/cancel/reopen/heartbeat records are
searchable by RAG++ and visible in audit/export. Claim is conflict-aware by
default, so two agents do not silently take the same handoff unless a caller
uses `force=true`.
`handoff_compile` turns one handoff `message_id` into an actionable packet with
the message, thread, ACKs, RAG++ highlights, graph, and plain text context for
an agent to begin work.
`claim` and `complete` add append-only ownership and outcome events, so agents
can see whether a handoff is merely acknowledged, actively owned, or finished.

External clients that can talk HTTP MCP do not need the agent-pod stdio server.
They can point at `/api/workbench/:slug/context/mcp` or the shorter
`/api/workbench/:slug/mcp` and call JSON-RPC methods `initialize`,
`tools/list`, `tools/call`, and `ping`. These tools use the same Beagle auth
bridge and Beagle Core RAG read/write paths as the REST routes, with the local
overlay kept as the read-after-write fallback while the Core image catches up.
`/api/workbench/:slug/context/connect` returns a client connection pack for
Claude Desktop, Claude Code, ChatGPT, Grok, Codex, Kimi CLI, and local zellij
agents. It includes the HTTP MCP URLs, stdio-proxy config shape, auth header
placeholder, tool list, and smoke-test JSON-RPC calls without exposing a token.
On the cluster deployment, HTTP MCP is configured to require
`Authorization: Bearer <token>`; local development leaves that switch off unless
`WORKBENCH_CONTEXT_HTTP_MCP_REQUIRE_AUTH=true` is set.
Cluster writes are also closed by default with
`WORKBENCH_CONTEXT_WRITE_REQUIRE_AUTH=true`, covering REST ingest/import and
mutating doctor probes. Read routes can be closed separately with
`WORKBENCH_CONTEXT_READ_REQUIRE_AUTH=true`; the web mirror retries context
query/ingest with the cockpit auth-bridge token when a cluster route returns
401.

`/api/workbench/:slug/context/doctor` is the operational proof route. By default
it checks storage writability, Beagle auth, Beagle RAG query, and HTTP MCP
contract without writing memory. With `write_probe=true`, it writes a sentinel
through the same ingest path, queries it back, builds the graph, and compiles
the handoff packet.

The mirror does not execute agent, zellij, cluster, or habitat mutations in this
phase. It prepares intent locally and leaves dangerous operations behind the
existing Action Ledger and lease/approval guardrails.

## Darwin control tower

The multi-project operating route is:

- `/projects/os`

Its read-only API is:

- `GET /api/project-os`
- `GET /api/project-os/actions`

That packet lists every cataloged project with posture, workspace state, branch
risk, agents, jobs, and propose-only autopilot suggestions.

The compact daily operator route is:

- `/projects/:slug/control`

It reads the existing Cockpit contracts instead of introducing a second source
of truth:

- `GET /api/projects/:slug/control-plane`
- `GET /api/projects/:slug/go-work-now`
- `GET /api/projects/:slug/agent/sessions`
- `GET /api/projects/:slug/jobs`
- `GET /api/projects/:slug/actions`

Mutations on that route still go through the existing Cockpit action endpoints
with explicit confirmation, idempotency keys, and readback refreshes.

The Darwin cluster operator route is:

- `/projects/cluster`

It is the GUI control lane for real supercomputing operations, separate from
project workspaces. Its read-only APIs are:

- `GET /api/cluster/ops/summary`
- `GET /api/cluster/ops/actions`

Its execution API is:

- `POST /api/cluster/ops/actions/:actionId/run`

Cluster execution is allowlisted only. Each run requires an Action Ledger
proposal, `confirm-intent`, `confirmed: true`, and `X-Request-ID`; then the
server writes a receipt under `BEAGLE_DATA_DIR/cluster-ops/<run_id>/` with
`run_packet.json`, `stdout.log`, `stderr.log`, and `readback.json`.

The v0 route watches Kubernetes, Cilium, Slurm, OrangeFS, GPU placement, host
freshness, and the 5860 OrangeFS thin-pool risk. Host mutations are worker-only
for `r770-proxmox`, `5860-proxmox`, and `r740-proxmox`; `t560-proxmox` remains
propose-only.

Autopilot in this phase is propose-only. It can name the next move and prepare
the route/action payload, but it does not execute cluster, agent, or job
mutations without an explicit human confirmation.

The Action Ledger is the receipt layer for those proposals:

- `POST /api/projects/:slug/actions/propose`
- `POST /api/projects/:slug/actions/:ledgerId/confirm-intent`
- `POST /api/projects/:slug/actions/:ledgerId/reject`

Action Ledger v0 records proposal, intent, and control-plane readback only. It
does not execute jobs, agents, habitats, Slurm, Kubernetes, or workspace
mutations.

## UI reset

The current UI/UX has been explicitly called out as not good enough.

The redesign handoff for a dedicated frontend lane lives here:

- [`docs/UI_HANDOFF_BRIEF.md`](./docs/UI_HANDOFF_BRIEF.md)
- [`docs/FRONTEND_BACKEND_CONTRACT.md`](./docs/FRONTEND_BACKEND_CONTRACT.md)
- [`docs/FILE_OWNERSHIP_CONTRACT.md`](./docs/FILE_OWNERSHIP_CONTRACT.md)
- [`docs/CLOUD_CODE_UI_REDESIGN_PROMPT.md`](./docs/CLOUD_CODE_UI_REDESIGN_PROMPT.md)

Those files are the current source of truth for handing the visual/system
redesign to another agent without breaking the cockpit's operational semantics.

The project route now also treats `research + supercomputing` as a first-class
lane near the top of the cockpit instead of burying operational truth inside
the memory re-entry packet. In practice that means:

- cluster lane truth stays infrastructure-shaped
- cluster lane truth is admission-scoped for the `gpuorangefs` lane and reflects only currently admitted workers
- research operations stay run-shaped
- the lane now emits an operating-posture packet with next-safe-move guidance and artifact-recovery commands for the latest observed research run
- the Vision shell remains visible as a runtime target in the same control lane
- recent observed research runs can be surfaced without reclassifying them as
  cluster state
- the supercomputing mission brief can sit beside the live lane so the cockpit
  shows both frontier intent and current operational truth

The larger direction is now explicit:

- this app is growing into a sovereign supercomputing playground shell
- not just a project dashboard
- and not just a browser-only tool

The sovereign index at `/projects` now also carries a compact operating-posture
packet per project so the multi-project surface can say, at a glance:

- what the sovereign project posture is (`always-on`, `warm`, `cold`)
- what the cluster lane posture is
- what the research lane posture is
- what the next safe move is for each layer
- and how to recover the latest observed research artifact when one exists

The sovereign index now also exposes a catalog audit lane:

- `GET /api/catalog/audit`
- duplicate project slugs are blocking failures
- catalog path/posture mismatches are blocking failures
- `ttl.sh/*:24h` image references are warnings
- warm projects that are currently live are informational operator signals

Habitat mutations from the cockpit consult this audit first. A project with a
blocking catalog failure cannot be activated or put on standby until the
catalog contract is fixed.

The sovereign index now also emits a compact `Go work now` packet per project
so the cockpit can act like an actual control surface instead of a read-only
summary. That packet is meant to answer, immediately:

- where this project lives right now
- whether the habitat should be activated or is already always-on
- how to attach to the tmux lane
- how to open mission control, the viewer, and the workspace surface
- how to return a warm project to standby when you are done

The `/projects` surface can now also execute the narrowest safe habitat actions
directly for sovereign project surfaces:

- activate a `warm` habitat
- return a `warm` habitat to standby

Those actions are project-surface operations, not cluster truth mutations.

There is now also a sovereign catalog route:

- `/projects`

That route is the beginning of the higher-order surface for several heavyweight
projects, not just the `Sounio` pilot cockpit.

It now hydrates a lightweight executive state per project from `memory/fast` so
the catalog can show project-shaped continuity before you open any individual
cockpit.

The multi-project route now also has a server-side executive aggregate:

- `GET /api/catalog/executive`
- `GET /api/catalog/project-posture-policy`
- `GET /api/research/supercomputing`
- `GET /api/public/portal`
- `GET /api/public/runtime/vision`
- `GET /api/public/vision/control-room`
- `GET /api/public/vision/apple-brief`
- `GET /api/public/vision/apple-launchpad`
- `GET /api/public/vision/operator-board`
- `GET /api/public/vision/runtime-matrix`
- `GET /api/public/vision/route-atlas`
- `GET /api/public/vision/mission-timeline`
- `GET /api/public/vision/sovereign-bridge`
- `GET /api/public/vision/sovereign-cockpit-preview`
- `GET /api/public/vision/packet-graph`
- `GET /api/public/vision/handoff`
- `GET /api/public/projects/:slug/showcase`
- `GET /api/public/projects/:slug/packet-graph`
- `GET /api/public/projects/:slug/sovereign-bridge`
- `GET /api/public/projects/:slug/sovereign-cockpit-preview`

The public Vision control-room surface now also carries an observed inference
fabric snapshot for the `Sounio` pilot, so the spatial shell can explain the
real `SGLang + Dynamo` handoff instead of treating inference as a purely
private abstraction.

The current public shell also has graph-first companion routes for both the
Vision room and the `Sounio` showcase so shells, packets, crossings, and fabric
lanes can be explained without flattening them into a single status card.

That same control model now also keeps `project posture` explicit so the
cockpit can say, clearly:

- `Sounio` is an `always-on` sovereign surface
- `Hyperbolic Semantic Networks` is a `warm` sovereign surface
- and the latest research run is not the same thing as either of those

The `/projects` route now also opens with a compact `project posture policy`
packet so the sovereign index explains the rule before any single cockpit takes
over.

There is now also a compact `Apple Vision brief` route that synthesizes the
control room, packet graph, and handoff path into one operator-facing public
surface before the sovereign cockpit takes over.

There is also an `Apple Vision launchpad` route that turns the observed
inference fabric, active Apple Developer account, packet graph, and handoff
sequence into concrete launch gates for the spatial shell.

There is also an `Apple Vision operator board` route that turns those same
observed surfaces into explicit route transitions, operator lanes, and public
to private crossing steps.

There is also an `Apple Vision runtime matrix` route that lays the public shell
targets side by side with launch gates, control-plane publication, and
sovereign crossings so the runtime story stays readable.

There is also an `Apple Vision route atlas` route that keeps the full chain of
public Vision routes visible in one place so room, briefing, launch, graph,
matrix, and handoff surfaces remain navigable as one story.

There is also an `Apple Vision mission timeline` route that turns those public
Vision surfaces into an explicit ordered sequence so the shell can be read as a
mission, not only as a map.

There is also an `Apple Vision sovereign bridge` route that turns the public
Vision shell into an explicit crossing plan toward the sovereign Sounio cockpit
and viewer routes.

There is also an `Apple Vision sovereign cockpit preview` route that makes the
private cockpit destination legible from the public shell before the final
handoff is taken.

There is also a `Sounio sovereign bridge` route that mirrors that same
crossing grammar on the showcase side so the path from public project narrative
into the sovereign cockpit and viewer stays explicit.

There is also a `Sounio sovereign cockpit preview` route that makes the private
cockpit destination legible from the showcase side before the final crossing is
taken.

And the playground/beagle-native surfaces now have dedicated project routes:

- `GET /api/projects/:slug/beagle/substrate`
- `GET /api/projects/:slug/playground/executive`
- `GET /api/projects/:slug/truth/summary`
- `GET /api/projects/:slug/mission-control`
- `GET /api/projects/:slug/cluster/lane-truth`
- `GET /api/projects/:slug/research/operations`
- `GET /api/projects/:slug/go-work-now`
- `POST /api/projects/:slug/go-work-now/actions/:actionId`
- `GET /api/projects/:slug/graph/lineage`
- `GET /api/projects/:slug/workflows/scientific`
- `GET /api/projects/:slug/workflows/scientific/checks`
- `POST /api/projects/:slug/workflows/scientific/checks/run`
- `GET /api/projects/:slug/execution/packets`
- `GET /api/projects/:slug/execution/packets/:packet`
- `GET /api/projects/:slug/resume/playground`
- `GET /api/projects/:slug/runtime/manifest`
- `GET /api/projects/:slug/datasets/catalog`
- `GET /api/projects/:slug/viewer/runtime`
- `GET /api/projects/:slug/viewer/state`
- `GET /api/projects/:slug/inference/runtime`
- `GET /api/projects/:slug/inference/models`
- `GET /api/projects/:slug/inference/workload`
- `GET /api/projects/:slug/inference/bootstrap`
- `GET /api/projects/:slug/sounio/contracts`

That endpoint consolidates per-project fast truth, mission control, and IDE
state so `/projects` does not need to fan out into one browser request per
project.

For native shells, the server now also exposes a first-cut mobile gateway under
`/api/mobile/v1` so iOS/macOS clients do not need to bind directly to the raw
Cockpit plus beagle-core route mix.

The current mobile surface includes:

- `GET /api/mobile/v1/health`
- `GET /api/mobile/v1/catalog`
- `GET /api/mobile/v1/projects/:slug/overview`
- `GET /api/mobile/v1/projects/:slug/actions`
- `POST /api/mobile/v1/projects/:slug/actions/:actionId`
- `POST /api/mobile/v1/projects/:slug/heartbeat`
- `GET /api/mobile/v1/projects/:slug/agent-sessions`
- `GET /api/mobile/v1/projects/:slug/agent-sessions/:kind`
- `POST /api/mobile/v1/projects/:slug/agent-sessions`
- `POST /api/mobile/v1/projects/:slug/agent-sessions/:kind/pause`
- `POST /api/mobile/v1/projects/:slug/agent-sessions/:kind/resume`
- `DELETE /api/mobile/v1/projects/:slug/agent-sessions/:kind`

Those routes use the contracted `{ ok, data, error, meta }` envelope and
normalize mobile-facing fields like `confirmed` and `idempotencyKey` so the
native client can evolve against one stable Cockpit-owned boundary.

It also now surfaces context drift explicitly:

- persisted sovereign context branch
- live habitat Git branch
- drift state when those diverge

The index also now carries a SOTA horizon strip so the playground can expose
its scientific north star instead of treating supercomputing research as a
separate document-only concern.

That SOTA brief is also folded back into the Beagle substrate as a `research`
packet, so the product can carry frontier context as executable guidance rather
than as documentation alone.

That matters for Sounio today because the live habitat can be ahead of the
persisted `.beagle/context` branch contract, and the cockpit should show that
as an explicit operator signal instead of flattening it away.

The branch model is now intentionally split when those truths differ:

- `branch` / `preferredPrBase`
  - the project source-of-truth branch the cockpit should treat as canonical
- `workspaceBootstrapBranch`
  - the branch the workspace bootstrap still clones by default

For Sounio today, that means the cockpit can say plainly:

- canonical/source branch: `integration/sounio-dev-ready-base`
- workspace bootstrap branch: `main`

instead of collapsing both ideas into one misleading field.

The sovereign index also now surfaces a first-class playground summary per
project:

- dataset count
- real versus observed dataset coverage
- viewer runtime state
- provenance / lineage summary
- dataset / renderer / web truth chips
- Beagle substrate routing summary
- knowledge-graph anchor count
- agent ledger truth
- routed task plan per project surface
- suggested graph queries for provenance/context recovery
- execution packets for Claude Code, Codex, and Kimi
- graph edges for project/branch/PR/dataset/artifact/lane lineage
- scientific workflow packet for dataset-to-publication handoff
- scientific playground executive summary: dataset count, multiscale count, selected axes/levels, rendering target

The broader platform direction now assumes:

- web runtime
- native Windows runtime
- native macOS runtime
- native iOS runtime
- Apple Vision / visionOS runtime
- the Vision lane is backed by a real active Apple Developer account, so the
  runtime contract is treated as concrete product direction rather than a
  placeholder

with the same sovereign continuity model across all of them.

The first playground slice now also exists inside the Sounio detail surface:

- `/projects/sounio/viewer`

That route is the first full-page proof of the supercomputing playground
direction:

- WebGPU-first viewer shell
- dataset lane
- provenance lane
- runtime capability lane
- sovereign viewer state lane
- cognitive routing lane
- knowledge graph lane
- graph edges / lineage lane
- scientific workflow packet

## What this MVP is

- a real web app scaffold
- seeded from the canonical `Sounio` workspace catalog entry
- shaped around:
  - project lane
  - terminal lane
  - planning lane
  - Git/GitHub lane
  - cluster mini-IDE lane

This is also the control shell for a broader playground direction that will add:

- dataset lane
- visualization lane
- job provenance lane
- runtime capability lane

## What this MVP is not yet

- a full Monaco IDE
- a complete GitHub client
- a mutation-heavy cluster console

Those are later layers.

## Source of truth

The cockpit should be driven by:

- [catalog/README.md](/home/devsounio/beagle/k8s/workspace-platform/catalog/README.md)
- [sounio.env](/home/devsounio/beagle/k8s/workspace-platform/catalog/always-on/sounio.env)

There is also a helper to export the workspace catalog to JSON:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/export-project-catalog-json.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog \
  /tmp/project-catalog.json
```

## Run locally

```bash
cd /home/devsounio/beagle/apps/project-cockpit
npm install
npm run dev:all
```

That starts:

- Vite on `http://127.0.0.1:4173`
- the project cockpit backend on `http://127.0.0.1:4370`

For the project-shaped route model, open:

- `http://127.0.0.1:4173/projects` for the sovereign project index in dev mode
- `http://127.0.0.1:4173/projects/sounio` in dev mode
- `http://127.0.0.1:4173/projects/sounio/viewer` in dev mode
- `http://127.0.0.1:4370/projects` after `npm run build && npm run start`
- `http://127.0.0.1:4370/projects/sounio` after `npm run build && npm run start`
- `http://127.0.0.1:4370/projects/sounio/viewer` after `npm run build && npm run start`

The backend currently assumes it runs on a machine with:

- `kubectl` access to the Darwin cluster
- permission to `exec` into the project habitat
- a live `tmux`-ready container for the project

Useful live smokes:

- public surfaces:
  - `/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_public_surfaces.sh`
- public assets via pod:
  - `/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_public_assets.sh`
- vision route semantics:
  - `/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_vision_route_semantics.sh`
- private inference:
  - `/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_private_inference.sh`
- full shell:
  - `/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_full_shell.sh`

The app now tries to load:

- `/project-catalog.json`

and falls back to the seeded `Sounio` catalog in `src/catalog.js` if that file
is not present.

To refresh the public JSON from the live workspace catalog:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/export-project-catalog-json.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog \
/home/devsounio/beagle/apps/project-cockpit/public/project-catalog.json
```

The public catalog is now also playground-aware. Additive fields include:

- `playgroundClass`
- `runtimeCapabilities`
- `datasetCatalog`
- `viewerDefaults`

For the `sounio` pilot, the dataset catalog is now hybrid in a more useful way:

- real public OME-Zarr entries from the IDR/OME stack when reachable
- explicit declared/stub entries where the playground contract exists before live data does

The viewer now also has a dedicated state surface:

- `GET /api/projects/:slug/viewer/state`
- `POST /api/projects/:slug/viewer/state`

And the playground now also exposes a single composed resume packet for shells:

- `GET /api/projects/:slug/resume/playground`

And a runtime manifest specifically for web / desktop / iOS / Vision shells:

- `GET /api/projects/:slug/runtime/manifest`

That route bundles:

- truth summary
- mission control
- beagle substrate
- playground executive
- dataset summary
- viewer runtime
- viewer state
- API routes for shell re-entry

The runtime manifest adds:

- per-runtime launch intents
- resume route
- viewer route
- selected dataset hint
- rendering target hint

The inference lane now separates:

- declared/runtime probe state
- cluster workload state
- bootstrap packet

So the platform can show the difference between:

- a configured `Dynamo` control-plane endpoint
- a configured `SGLang` engine endpoint
- a reachable live inference-fabric route
- and the underlying Kubernetes deployment/service/pod status

The scientific workflow lane now also supports on-demand Sounio checks:

- `GET /api/projects/:slug/workflows/scientific/checks`
- `POST /api/projects/:slug/workflows/scientific/checks/run`

Those checks are recorded into the remembered-state store so the workflow can
carry the latest scientific/provenance gate result without putting that work on
the cold-start path.
- Vision control-room-first contract
- Vision resume / viewer / control-room handoff fields
- SGLang engine hint for private inference
- Dynamo control-plane hint for private inference
- inference-fabric runtime probe against configurable cluster endpoints

The private cockpit now also keeps a cluster-persisted remembered workspace
state in a Kubernetes `ConfigMap` so fresh pods can boot with remembered-strong
branch / PR / IDE truth when the habitat bridge is slow.

The Beagle substrate now also exposes a `sounioScientificContract` packet so
the platform can treat Sounio as the language of the scientific/provenance lane
instead of as a replacement for the web shell.

The first concrete Sounio contract for that lane now lives in:

- `/home/devsounio/sounio/examples/playground_scientific_contract.sio`
- `/home/devsounio/sounio/examples/playground_provenance_gate.sio`
- `/home/devsounio/sounio/examples/playground_publication_gate.sio`

And the private inference lane now treats `SGLang + Dynamo` as the primary
fabric, without confusing serving with the Beagle orchestration layer itself.

That lane now also performs real probes against its configured control-plane and
engine endpoints, so the runtime can honestly report `ready`,
`partial-ready`, `prototype-unreachable`, or `unconfigured` instead of
pretending that an inference target exists.

The current steady-state semantics are now explicit:

- `runtime.status: ready`
- `runtime.truthMode: observed`
- `runtime.engine.status: published-via-control-plane`
- `runtime.engine.accessMode: published-via-control-plane`

That means the published path is the `Dynamo` frontend, while the model
inventory is still observed from the live fabric rather than treated as a
declared-only contract.

It also now exposes a bootstrap packet so the cluster path is explicit:

- setup command
- control-plane bootstrap
- engine bootstrap
- test command
- endpoint candidates

That route carries:

- current dataset selection
- scene memory
- renderer truth
- renderer diagnostics:
  - API
  - backend
  - adapter class
  - texture format
  - feature snapshot
  - limit snapshot
- provenance anchors
- Beagle substrate routing and graph hints
- routed task plan and graph-query seeds
- execution packets that turn routing into an immediate first move
- scientific viewer packet that turns dataset/provenance/runtime into a single first move

## What is real today

- terminal bridge:
  - websocket -> `kubectl exec -it` -> `tmux`
- session lane:
  - lightweight viewer identity
  - browser heartbeat
  - project presence and re-entry hints
- AI tools lane:
  - `claude`
  - `codex`
  - `kimi`
  - `agent-browser`
  - surfaced explicitly in the planning lane instead of being hidden in docs only
- git lane:
  - status
  - live guardrails
  - diff preview
  - commit all
  - push current branch
  - draft PR creation through `gh`
  - publication continuity
  - guided review flow
- cluster lane:
  - workspace pod health
  - cockpit pod health
  - project surface status over tailnet
  - preview + confirm rollout actions for the workspace habitat and cockpit

These actions are intentionally explicit in the UI.

Auth is intentionally lightweight for now:

- access is delegated to the outer tailnet/web surface
- the cockpit adds viewer presence and session awareness on top
- the native-app public boundary for beagle access is the cockpit auth bridge
  at `/api/auth/beagle-token`
- the native completion boundary is now cockpit-owned as well:
  - `POST /api/mobile/v1/chat` for the new mobile envelope
    - includes explicit provenance via `source`
    - and returns agent provenance fields when the response is agent-backed
  - `POST /api/llm/complete` for legacy compatibility with existing clients
- native apps should prefer `POST /api/mobile/v1/chat`; the legacy
  `/api/llm/complete` path is retained for compatibility only
- the mobile gateway now also has first-class write lanes for native capture:
  - `POST /api/mobile/v1/projects/:slug/ideas`
  - `POST /api/mobile/v1/projects/:slug/delegations`
  - `GET /api/mobile/v1/summary`
- those routes make the native semantics explicit:
  - `Talk` -> chat completion
  - `Save Idea` -> persisted idea with `syncState`
  - `Delegate` -> agent-backed handoff with session provenance
- `beagle-core` itself stays private and is not treated as a public hostname
  contract on `beagle.chiuratto.ai`
- the Cockpit completion routes merge an optional `system` prompt into the
  completion prompt and proxy the request to the private Dynamo control plane
  behind Cockpit

## Live endpoints worth checking

- public project route:
  - `http://sounio-cockpit.tail21cbc4.ts.net/projects/sounio`
- viewer lane:
  - `GET /api/viewer`
- toolchain lane:
  - `GET /api/projects/sounio/toolchain`
- git guardrails lane:
  - `GET /api/projects/sounio/git/guardrails`
- cluster lane:
  - `GET /api/projects/sounio/cluster/summary`
- mobile chat lane:
  - `POST /api/mobile/v1/chat`
  - `POST /api/llm/complete` (legacy compatibility alias)
- mobile capture lanes:
  - `POST /api/mobile/v1/projects/:slug/ideas`
  - `POST /api/mobile/v1/projects/:slug/delegations`
  - `GET /api/mobile/v1/summary`

The planning lane is now backed by the live toolchain endpoint and reports the
versions currently visible from the habitat for:

- `Claude Code`
- `Codex`
- `Kimi CLI`
- `agent-browser`

The Git lane is also backed by a live guardrails endpoint so the UI can show:

- remote URL
- ahead/behind against origin
- GitHub auth health
- whether commit, push, and draft PR are safe to offer

The `Memory lane` now separates:

- `fast resume`
- `deep memory`
- `publishable dirt`
- `memory-local dirt`
- `publication checkpoint`

That split is intentional:

- the first hit should get you back into the habitat quickly
- deeper hydration can land after the page is already usable
- `.beagle/` and other memory-local context should not be confused with
  publishable repo dirt
- the continuity ledger is now rendered in two layers:
  - a `Timeline by phase` executive summary
  - the detailed `Continuity timeline`
- the executive summary now classifies each phase as:
  - `active`
  - `blocked`
  - `ready`
- the browser now prefers the current cockpit origin first for `memory/fast`
  hydration and only falls back to the alternate route if needed
- the sovereign catalog route `/projects` now renders a project index that makes
  the multi-project shape explicit:
  - project slug
  - workspace
  - PR base
  - automation readiness
  - cockpit entry route
  - executive phase state per project

For the `Sounio` pilot, the public payloads now also expose the playground
slice:

- runtime capabilities
- dataset catalog
- viewer defaults
- playground class

The publication lane now also exposes a more guided review path:

- open the current PR
- open the public compare view
- open changed files
- open checks
- copy reviewer context
- copy a guided review packet

It now also records review state as part of the project activity ledger:

- last review step
- last review URL
- merge readiness
- checks pass
- comments review
- merge decision
- publication stage

That means a later browser on another machine can rehydrate not just the branch
and PR, but also where review had paused.

The cockpit is also starting to tell the truth about where each executive claim
comes from and how strong that claim is:

- `observed`
- `remembered`
- `declared`

That same truth model is the intended foundation for future:

- OME-Zarr dataset views
- WebGPU real-time visualization
- native desktop shells
- native iOS shells
comes from:

- `Live / Observed truth`
- `Cached / Remembered truth`
- `Policy fallback / Declared truth`

That truth framing now shows up across the executive surface, not just the IDE
lane. Today the multi-project route can summarize:

- startup readiness now gates on a fast sovereign warm instead of full deep hydration:
  - `/livez` means the process is alive
  - `/healthz` becomes ready after the fast truth surfaces are warmed
  - deep hydration keeps running in the background

- IDE truth
- Publication truth
- Review truth
- Cluster truth
- mission-control next move
- current PR anchor
- executive publication stage

This is the SOTA/SOTT split in practice:

- continuity should be state-of-the-art enough to survive browser and machine changes
- semantics should stay truthful enough to reveal whether the system is observing, remembering, or merely declaring state

The publication lane is now starting to behave more like a state machine than a
bag of buttons:

- `working`
- `published`
- `under-review`
- `merge-ready`
- `merged-later`

## Browser automation note

`agent-browser` is installed on the host and in the `Sounio` habitat.

The robust automation path is now:

- VIP-backed cockpit route:
  - `http://100.107.208.198/projects/sounio`

The hostname route is still fine for humans:

- `http://sounio-cockpit.tail21cbc4.ts.net/projects/sounio`

But Chrome automation still hits `net::ERR_BLOCKED_BY_CLIENT` against the
hostname, so the planning lane and the smoke helper both prefer the VIP route.

That divergence is now documented more explicitly in the app:

- `agent-browser` / Chrome automation:
  - VIP-backed route first
- humans:
  - hostname route is fine
- `Lightpanda`:
  - can read both hostname and VIP on this host, which reinforces that the
    remaining hostname problem is runtime-specific rather than app-specific

To reduce runtime spillover from the terminal lane into the sovereign catalog
route, the `xterm` stack is now lazy-loaded. That keeps `/projects` lighter and
more automation-friendly even when the full terminal lane is not opened.

Inside the habitat, the IDE image now carries the Chrome runtime dependencies
that `agent-browser` needs, so cockpit automation can be reopened from the
persistent workspace itself after reconnects.

## Why this matters

The cockpit should reduce the ritual of re-entry:

- open one project page
- attach to the canonical `tmux` session
- view planning and doctors in the same surface
- commit and integrate without re-deriving the whole environment

## VSIX direction

The platform already runs `openvscode-server` in the workspace habitat, so the
right path for `VSIX` support is:

- keep the sovereign cockpit as the continuity layer
- use the IDE lane as the extension host
- standardize project extension packs instead of letting every habitat drift

Reference documents:

- [SOVEREIGN_VSIX_ARCHITECTURE.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_ARCHITECTURE.md)
- [SOVEREIGN_VSIX_EXTENSION_MATRIX.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_EXTENSION_MATRIX.md)

Current AI IDE agent policy:

- `Codex` is tracked as `vsix-first`
- `Claude Code` is tracked as `hybrid`
- do not claim IDE-native `Codex` runtime verification until an official install
  artifact or extension identifier has been validated in `openvscode-server`

IDE executive state should now tell the truth about where that state came from:

- `Live / Observed truth`
- `Cached / Remembered truth`
- `Policy fallback / Declared truth`
