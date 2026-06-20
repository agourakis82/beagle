# Beagle Calm-Companion Chat — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or executing-plans. Steps use `- [ ]` tracking.

**Goal:** Make the iOS chat a calm, present companion — reachable and steadying in anxious moments — per `docs/superpowers/specs/2026-06-20-beagle-calm-companion-chat-design.md`.

**Architecture:** iOS app on branch `feat/ios-100pct-real` (Mac `~/Developer/beagle/beagle-ios`, built via xcodegen → `BeagleSuite.xcodeproj`, scheme `BeagleCockpit`). Chat backend = `project-cockpit` (branch `fix/mobile-summary-timeout`) serving `/api/mobile/v1/chat[/stream]`. Edit-on-t560 (`/tmp/ios-proof/` or sparse worktree) → scp/commit → build.

**Tech stack:** SwiftUI (iOS 17+, `@Observable`/`@MainActor`), `BeagleCore` package; Node (project-cockpit); Cloudflare in front of `beagle.chiuratto.ai`.

**Verification doctrine:** UI changes verify on the **iPhone 17 Pro sim** (representative for layout/visual). Streaming/CF + on-device-only paths verify on the **real device** (TestFlight build 43) — the sim cannot prove them. Final judgment = on-device.

---

### Task 1 — Streaming actually streams on the device (the #1 anxiety fix)

**Files:** `apps/project-cockpit/server/mobile-routes.mjs` (SSE route headers), `beagle-ios/.../BeagleCore/BeagleClient.swift` (`chatStream` base-URL order), Cloudflare config (dashboard/API for `beagle.chiuratto.ai`).

- [ ] **Step 1.1 — Confirm the cause.** From the device's network path: `curl -N` the public URL `https://beagle.chiuratto.ai/api/mobile/v1/chat/stream` (POST, prompt) and observe whether tokens arrive incrementally or as one blob. Compare to the direct pod (`kubectl port-forward`, already known to stream). Expected: CF buffers → blob. Record which.
- [ ] **Step 1.2 — Fix delivery.** Two levers, apply in order until tokens arrive incrementally over the public path:
  - (a) Backend already sends `Content-Type: text/event-stream`, `Cache-Control: no-cache, no-transform`, `X-Accel-Buffering: no`. Verify these survive to the client over CF.
  - (b) Cloudflare: add a **Configuration Rule** for path `/api/mobile/v1/chat/stream` disabling buffering / setting `cache: bypass` + ensure no "Rocket Loader"/proxy transform; OR confirm CF passes `text/event-stream` unbuffered (it should when content-type is correct + response is chunked).
  - (c) If the phone is on Tailscale, make `chatStream` **prefer the tailnet cockpit URL** (`http://sounio-cockpit.tail21cbc4.ts.net`) over `beagle.chiuratto.ai` for the stream only (non-CF path), keeping CF as fallback.
- [ ] **Step 1.3 — Verify on device.** `curl -N` over the chosen path shows incremental `data:{token}` events; then in-app the bubble fills token-by-token.
- [ ] **Step 1.4 — Commit** (`fix(cockpit/ios): stream survives the public/CF path on-device`).

### Task 2 — Composer that respires (clear-on-send, Stop, calm empty state)

**Files:** `beagle-ios/.../BeagleCockpit/HomeView.swift` (`exocortexInput`, `homeInvitation`, send wiring), `beagle-ios/.../BeagleCockpit/BeagleInputBar.swift` (Stop wiring).

- [ ] **Step 2.1 — Clear the composer on send (the bug).** In HomeView's send dispatch (the `exocortexInput`/starter-prompt `onSubmit`), after handing the text to `conversation.sendMessage(_:)`, reset the bound text to `""` synchronously so the field empties immediately. Verify: type → send → field is empty, text appears only in the thread.
- [ ] **Step 2.2 — Stop control during generation.** Wire `BeagleInputBar`'s existing stop affordance: while `conversation.isStreaming`, the send button becomes **Stop** and calls `conversation.stopStreaming()`. Verify on sim: during a (mock/local) stream, Stop halts it and the bubble finalizes.
- [ ] **Step 2.3 — Warm, low-friction empty state.** In `homeInvitation`, soften the copy for the anxious-moment use (e.g. headline that invites talking/doubt without pressure, calm subtitle) and keep the teal brand badge. The field is focusable on appear so opening Beagle lands ready to type. Verify on sim (screenshot).
- [ ] **Step 2.4 — Commit** (`fix(ios): composer clears on send + Stop + calm empty state`).

### Task 3 — Ambient presence mark (presence without demand)

**Files:** `beagle-ios/.../BeagleCockpit/HomeView.swift` (nav/header), reuse `BeagleCore/Theme.swift` `BeaglePresenceState` + `bodyPresenceState`.

- [ ] **Step 3.1 — Breathing presence glyph in the header.** Replace/augment the static wordmark glyph with a slow **breathing** mark tinted by `bodyPresenceState.tint` (`BeagleMotion`-driven, ~3–4s cycle, low opacity range). It must NOT flash or pulse aggressively (Calm Tech: periphery, minimal attention).
- [ ] **Step 3.2 — State shifts on send.** On send, presence moves to `.attentive`/`.active` (so there is never a silent void); during streaming, `.active`; on a stalled/errored turn, `.holding` ("I'm here through this"). Drive from `conversation.isStreaming` + the turn lifecycle.
- [ ] **Step 3.3 — Verify on sim** (screenshot: calm breathing glyph, state change on send).
- [ ] **Step 3.4 — Commit** (`feat(ios): ambient breathing presence mark in chat header`).

### Task 4 — Memory shown gently (felt understanding)

**Files:** `apps/project-cockpit/server/mobile-routes.mjs` (stream `done` event: add `grounded` flag), `beagle-ios/.../BeagleCore/BeagleClient.swift` (`ChatStreamEvent.done` carries `grounded`), `BeagleCore/ConversationStore.swift` + `BeagleCockpit/ChatBubbleView.swift` (soft cue).

- [ ] **Step 4.1 — Backend signals grounding.** In `/api/mobile/v1/chat/stream`, when `fetchExocortexContext` returned non-empty, include `"grounded": true` (and optionally a 1-line memory label) in the `data:{done,...}` event.
- [ ] **Step 4.2 — iOS carries it.** Extend `ChatStreamEvent.done` with `grounded: Bool`; store on the message.
- [ ] **Step 4.3 — Gentle peripheral cue.** When `grounded`, show a quiet "recalling…" / memory chip on the assistant bubble (low-contrast, `truthRemembered` tint) — informing without demanding. Verify on sim.
- [ ] **Step 4.4 — Commit** (`feat(cockpit/ios): gentle memory-grounding cue on streamed replies`).

### Task 5 — Calm motion & gentle recovery

**Files:** `ChatBubbleView.swift`, `HomeView.swift` (transitions), error/retry paths in `ConversationStore.sendMessageCloud`.

- [ ] **Step 5.1 — Slow, soft transitions.** Message-in, presence, and composer transitions use `BeagleMotion.normal/slow` (no snappy/flashy); reduce abrupt layout jumps.
- [ ] **Step 5.2 — Gentle errors.** On stream error/timeout, the bubble shows a warm, non-alarming line + an obvious **Retry** (reuse `regenerateLastResponse`); never a dead-end or red shout.
- [ ] **Step 5.3 — Verify on sim** + **Commit** (`feat(ios): calm motion + gentle error/retry in chat`).

### Task 6 — Ship build 43 + on-device judgment

- [ ] **Step 6.1 — Bump build 42 → 43** in `beagle-ios/project.yml`, `xcodegen generate`, commit, push.
- [ ] **Step 6.2 — Archive (Xcode GUI, keychain) + upload** to TestFlight (`1.1 (43)`).
- [ ] **Step 6.3 — On-device acceptance.** On the real iPhone, verify against the north star: send a message → presence shifts + tokens stream calmly (no silent wait), composer clears, Stop works, memory cue appears when grounded, errors are gentle. The bar: *does it feel like a calm companion at your side?*

---

## Notes / DRY
- Backend stream pieces (`streamChatViaRouter`, `/api/mobile/v1/chat/stream`) already exist (commit `f0c6c19b`); iOS `chatStream` + streaming `sendMessageCloud` exist (`04dc0f6`). This plan **completes + calms** them, fixes CF delivery, and adds presence/memory/motion.
- Out of scope: deep RAG-ranking (separate); other tabs.
- Every iOS step that touches streaming/CF or MLX is **device-verified**, not sim.
