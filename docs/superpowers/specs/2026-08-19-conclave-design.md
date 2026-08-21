# Conclave — Design Spec

**Date:** 2026-08-19
**Status:** Approved for implementation (design phase; implementation plan pending)
**Platform:** SwiftUI, macOS 26 + iOS 26/27 multiplatform
**Coexists with:** `apps/gpu-chat` (web) and Scriptorium — three separate frontends, one shared backend

## Purpose

A native, dedicated chat app for talking to the LLMs served on the user's
own GPUs, built to two interaction patterns the user picked after reviewing
the current state of the art (BoltAI, Enchanted, LiquidChat, Msty): a single
conversation where the responding model can switch turn to turn without
losing history ("thread mode"), and a mode where one prompt fans out to
several models in parallel and a designated model reads all the responses
and synthesizes a final answer ("chairman mode"). This is a new,
purpose-built replacement for the general chat use case gpu-chat's web app
originally covered — gpu-chat stays up as a fallback/browser-based option,
Scriptorium stays focused on citable editorial writing, Conclave is where
the user actually talks to models day to day.

## Relationship to gpu-chat and Scriptorium

Conclave is a new, independent Xcode project (own `.xcodeproj`/Swift
Package, following the same structure Scriptorium already established) —
not a merge into either existing frontend. It talks to gpu-chat's existing
Fastify backend over the tailnet, the same way Scriptorium does:

- Reuses as-is: `GET/POST /api/conversations`, `GET/POST
  /api/conversations/:id/messages` (SSE streaming), `GET /api/models`,
  `PATCH /api/conversations/:id`.
- New backend route (added to the same Fastify server, shared by all three
  frontends going forward): `POST /api/conversations/:id/chairman-messages`
  — accepts a prompt and a list of participant model IDs plus one chairman
  model ID, fans the prompt out to each participant in parallel, streams
  each participant's response as it arrives, then streams the chairman
  model's synthesis once all participants have finished (or timed out).
- Schema extension to `messages` (`apps/gpu-chat/server/src/db.ts`): the
  table already has a nullable `model` column (per-message model,
  already sufficient for thread-mode model switching — no change needed
  there). Chairman mode needs two additions: a nullable `chairman_group_id`
  column (a UUID grouping one user prompt's N participant responses plus
  its synthesis response together) and a `is_synthesis INTEGER NOT NULL
  DEFAULT 0` column (marks which of the group's assistant messages is the
  chairman's synthesis, as opposed to a raw participant response). Exact
  migration approach (in-place `ALTER TABLE` vs. rebuild) is an
  implementation-plan decision, not fixed here — the existing `openDb`
  function already uses `CREATE TABLE IF NOT EXISTS`, so new columns need
  a compatible migration path for existing databases.

No new backend service — one backend, three frontends.

## Visual direction

Figma-first, using the official Apple "OS 27" / "iOS 27" UI Kit (the
user's Figma Business Pro plan) rather than hand-drawn approximations of
Liquid Glass — this reverses the approach taken for Scriptorium's chat
pane, where gradients and shadows were built by hand before switching to
the real `glassEffect`/`GlassEffectContainer` APIs mid-implementation.
For Conclave, every screen is composed in Figma from real component
instances (buttons, list rows, segmented controls, glass panels) pulled
from the official kit via Code Connect / component search, so the SwiftUI
port maps directly to system components instead of reconstructing their
appearance. `figma-swiftui`'s design-to-code workflow governs the
Figma → SwiftUI translation once mockups exist.

## Layout

Platform-appropriate, not a single shared layout forced onto both:

- **macOS**: sidebar (conversation list, each conversation tagged with its
  mode — thread or chairman) + a main pane that renders differently by
  mode.
- **iOS**: `NavigationSplitView`/stack equivalent — conversation list as
  the root, thread/chairman view pushed on selection.

**Thread mode view**: a normal scrolling message list; each assistant
turn carries a small model badge (which model produced it); the composer
has a model picker so the next message's responder can be changed without
starting a new conversation or losing prior turns.

**Chairman mode view**: composer plus a model-configuration control
(pick N participant models + 1 chairman model, persisted per conversation
at creation — not re-configurable per turn, to keep the data model and UI
simple for Phase 1). Each user prompt renders as: an expandable card per
participant model (its individual response, collapsed by default after
the synthesis arrives) and one prominent synthesis card (the chairman
model's answer), visually distinct from the raw participant cards.

## Data flow

1. **Thread mode**: identical flow to gpu-chat's existing SSE
   conversation contract — `GPUChatStreamClient`'s wire format (JSON `data:`
   payloads, literal `[DONE]`/`error` sentinels) is reused as-is. The only
   addition is the client sending a `model` override per message instead of
   relying solely on the conversation's stored default model.
2. **Chairman mode**: the client calls the new
   `POST /api/conversations/:id/chairman-messages` endpoint once per user
   prompt. The server persists the user message, then fans the prompt out
   to each participant model concurrently, streaming each one's tokens
   back over a single SSE connection multiplexed by a per-event `model`
   field (event framing is an implementation-plan decision — e.g. a
   `data: {"model": "...", "token": "..."}` shape distinguishing streams).
   Once all participants finish (or time out), the server sends the
   accumulated participant responses plus the original prompt to the
   chairman model and streams its synthesis as a final segment, then
   `[DONE]`.
3. Conversation list, model list, and template reuse the same endpoints
   Scriptorium and gpu-chat web already share.

## Error handling

- **Thread mode**: identical to gpu-chat's existing behavior — a
  surfaced `event: error`, never a permanently stuck "streaming" state.
- **Chairman mode partial failure**: if one or more participant models
  error or time out, the chairman still synthesizes from whichever
  participants succeeded, and the UI marks the failed participant's card
  as failed (not silently dropped) rather than pretending only the
  successful ones were ever asked. If *all* participants fail, the
  chairman step is skipped and the failure is surfaced directly — no
  synthesis attempted over zero responses.
- **No network**: same explicit "couldn't reach the backend" state
  pattern already established in Scriptorium's clinical-base/ATS work —
  never a silently empty conversation list.

## Testing

- New backend route follows the same TDD pattern already established in
  `apps/gpu-chat/server` (Vitest, mocked upstream HTTP) — including a test
  for the partial-participant-failure path.
- The Swift app uses XCTest for logic (networking/parsing, chairman
  fan-out/synthesis client state machine, conversation/message models) and
  the `figma-swiftui` design-to-code workflow for visual fidelity, the same
  split already working for Scriptorium. Visual/interactive verification
  ultimately requires the user's own eyes on their Mac — accessibility-tree
  inspection over SSH is a fallback for catching layout bugs (as it was for
  Scriptorium's glassEffect-overflow bug), not a substitute for it.

## Phasing (design now, implementation later — each phase gets its own plan)

1. **Phase 1** (first implementation plan): macOS only. Thread mode
   (conversation list, model-switching composer, message list with model
   badges) fully working against the existing backend, no schema changes
   needed for this part. Chairman mode's backend route and schema
   extension, plus a basic chairman-mode UI (participant cards +
   synthesis card, no advanced retry/partial-failure polish beyond the
   spec's baseline behavior above).
2. **Phase 2**: iOS port of both modes.
3. **Phase 3**: polish pass against final Figma designs, chairman-mode
   refinements (e.g. re-running a single failed participant without
   re-running the whole group).

Explicitly deferred, not part of any phase above unless requested later:
the global-hotkey quick-access overlay pattern from the research (the user
did not select it when choosing the interaction pattern).

## Open questions carried into implementation

- Exact SSE event framing for chairman mode's multiplexed participant
  streams — Phase 1 implementation-plan decision.
- Exact schema-migration approach for the two new `messages` columns
  (`chairman_group_id`, `is_synthesis`) against existing production data —
  Phase 1 implementation-plan decision.
- Exact repo location for the new Xcode project (likely alongside
  `Scriptorium/` in the same parent directory on the Mac,
  `~/Developer/Conclave`) — finalized when Phase 1's implementation plan is
  written.
