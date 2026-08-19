# Scriptorium — Design Spec

**Date:** 2026-08-19
**Status:** Approved for implementation (design phase; first implementation plan pending)
**Platform:** SwiftUI, macOS + iOS (multiplatform)
**Coexists with:** `apps/gpu-chat` (web), sharing the same backend

## Purpose

A native macOS/iOS app for scientific and medical editorial writing — drafting
manuscripts and clinical documents with an AI assistant and literature search
built directly into the writing surface, not a separate chat window. Where
`gpu-chat` (web) is a general-purpose chat client for the user's GPU-served
models, Scriptorium is a purpose-built editorial tool: a document editor with
citation search, formula rendering, and export, backed by the model
conversation as a first-class collaborator in the margin.

## Relationship to gpu-chat

Scriptorium is a new, independent Xcode project (own `.xcodeproj`) — not a
third lane inside the existing BeagleSuite multi-target project, to avoid
entangling with BeagleSuite's known branch-reconciliation fragility. It talks
to gpu-chat's existing Fastify backend over the tailnet:

- Reuses as-is: `GET/POST /api/conversations`, `GET/POST
  /api/conversations/:id/messages` (SSE streaming), `GET /api/models`,
  `PATCH /api/conversations/:id`, `GET/POST/DELETE /api/templates`.
- New backend routes (added to the same Fastify server, in a later
  implementation slice): `GET /api/literature/search?source=pubmed|biorxiv|alphaxiv&query=...`,
  proxying each source's public API and normalizing results to a common
  shape. Keeps API-key/attribution logic server-side, shared by both
  gpu-chat web and Scriptorium.

No new backend service — one backend, two frontends.

## Visual direction

"Lab Notebook Dark" — a direct evolution of gpu-chat web's existing
instrumentation palette (ink-dark surfaces, Space Grotesk/IBM Plex type
system), adapted for long-form editorial work: the ember/coolant duo (tied to
GPU heat/coolant, appropriate for a chat-only tool) is replaced by a single
verified/cited accent — a muted green — since the defining state in an
editorial tool is "is this claim sourced," not "is a GPU actively computing."
Citation chips, reference-manager entries, and clinical-base results all use
this green consistently. The document pane keeps the dark ink background
rather than switching to a light "paper" surface — validated with the user
via the visual companion (option B chosen over a light-manuscript and a
dual-light/dark-split alternative).

## Layout

A two-pane, user-resizable split view (validated via the visual companion —
chosen over a fixed three-column layout and a document-only-with-drawer
layout):

- **Document pane** (left, wider by default) — the manuscript being written.
- **Assistant pane** (right) — chat + literature search + reference manager,
  in tabs or a segmented control within the same pane.

The divider is draggable; the user controls the balance between writing and
tool space rather than the app imposing a fixed ratio.

## Components

**Document pane**
- Native rich-text editor built on `AttributedString`/platform text views
  (not an embedded web view) — SwiftUI's native text editing on macOS/iOS,
  extended for this app's needs.
- Citations render as inline "chips" — a compact, tappable token bound to a
  real reference entry, not a raw bracketed number typed as text.
- LaTeX/formula and chemical-notation blocks render inline (rendering
  approach — a Swift LaTeX renderer vs. a math-typesetting library — is an
  implementation-time decision, not fixed by this spec).
- Backed by a document-based app architecture (`DocumentGroup` /
  `FileDocument`): each manuscript is a local file/package
  (text + citation registry + metadata), not a server-side record. Documents
  live on-device; only the model conversation persists server-side (in
  gpu-chat's existing SQLite, via the reused API), so chat history is
  naturally shared between the web app and Scriptorium for conversations
  visited from either.

**Assistant pane**
- Chat/streaming reuses the SSE conversation flow from gpu-chat's backend
  (`event: error` frames included) — the Swift networking layer parses the
  same wire format already fixed for the web client (JSON-encoded `data:`
  payloads, literal `[DONE]`/`error` event sentinels).
- Literature search: queries the backend's new `/api/literature/search`
  route across PubMed, bioRxiv, and alphaXiv; results show inline with an
  "Insert citation" action that drops a chip into the document at the
  current cursor position and adds the reference to the manager.
- Clinical base search: on-device, no network round-trip — the 211-entry
  drug-monograph corpus is bundled/synced locally (mirroring how the
  Companion app already caches its offline clinical grounding), included
  from the first implementation phase per the user's explicit choice.
- Retraction/correction awareness: literature results flag retracted or
  corrected entries (mirroring the `editorialNotices` check convention
  already used with the scite tool) before the user inserts them.

**Reference manager**
- Lists every reference currently cited in the open document, formatted
  (APA by default) and deduplicated.
- Backs the export step directly — it's the source of truth for the
  document's bibliography, not a derived/regenerated list.

**Export**
- Local operation: reads the document model + reference registry, produces
  Markdown, LaTeX, or DOCX, and hands the user the platform's native
  save/share flow (save panel on macOS, share sheet on iOS).

## Data flow

1. User writes in the document pane; the assistant pane runs alongside as an
   independent, always-available panel — not a modal or a separate app mode.
2. A literature or clinical-base search is triggered explicitly (from the
   assistant pane) or offered by the model inline in a chat response; either
   path surfaces results the same way.
3. Inserting a citation writes a chip into the document at the cursor and
   upserts an entry into the reference manager's registry — one write path,
   not two.
4. Chat messages persist server-side exactly as gpu-chat web already does;
   documents persist on-device only.
5. Export reads document + registry synchronously; no network needed unless
   the document also references something not yet fully fetched (should not
   occur, since insertion always writes the full formatted reference at
   insert time).

## Error handling

- No network: clinical-base search still works (on-device); PubMed/bioRxiv/
  alphaXiv search surfaces an explicit "couldn't reach literature search"
  state — never a silently empty result list.
- Chat/streaming failures: identical contract to gpu-chat web's fixed
  behavior — a surfaced `event: error` message, and the UI never gets stuck
  in a permanent "streaming" state on failure.
- Retracted/corrected sources: flagged before insertion, not after.

## Testing

- New backend routes (`/api/literature/search`) follow the same TDD pattern
  already established in `apps/gpu-chat/server` (Vitest, mocked upstream
  HTTP).
- The Swift app uses XCTest for logic (networking/parsing, document model,
  citation registry) and manual verification in Xcode Previews/Simulator —
  this requires Xcode tooling on macOS hardware, not available from this
  Linux development box. Visual fidelity to the Figma design is verified via
  the `figma-swiftui` design-to-code skill once mockups exist, rather than
  approximated from the spec text alone.

## Phasing (design now, implementation later — each phase gets its own plan)

1. **Phase 1** (first implementation plan): document editor shell, chat pane
   wired to the existing gpu-chat conversation API, clinical-base search
   (on-device, bundled corpus), citation insertion + reference manager,
   basic export (Markdown at minimum).
2. **Phase 2**: PubMed/bioRxiv/alphaXiv search (new backend routes +
   Swift client), retraction awareness.
3. **Phase 3**: LaTeX/chemical notation rendering in the document.
4. **Phase 4**: DOCX/LaTeX export (beyond Markdown), polish pass against the
   Figma designs.

Phase boundaries may shift once implementation starts — this ordering
reflects what's needed to have a genuinely usable tool soonest (write +
chat + cite from a local corpus) versus what can follow once that core loop
is proven.

## Open questions carried into implementation

- Exact LaTeX/chemical-notation rendering approach (native Swift library vs.
  other) — Phase 3 decision, not blocking Phases 1-2.
- Exact repo location for the new Xcode project (likely a new directory
  alongside `beagle-ios/`, finalized when Phase 1's implementation plan is
  written, since project scaffolding needs Xcode on macOS).
