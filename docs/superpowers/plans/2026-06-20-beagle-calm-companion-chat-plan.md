# Beagle Calm-Companion Chat — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or executing-plans. Steps use `- [ ]` tracking.

**Goal:** Make the iOS chat a calm, present companion — reachable and steadying in anxious moments — per `docs/superpowers/specs/2026-06-20-beagle-calm-companion-chat-design.md`.

**Architecture:** iOS app on branch `feat/ios-100pct-real` (Mac `~/Developer/beagle/beagle-ios`, built via xcodegen → `BeagleSuite.xcodeproj`, scheme `BeagleCockpit`). Chat backend = `project-cockpit` (branch `fix/mobile-summary-timeout`) serving `/api/mobile/v1/chat[/stream]`. Edit-on-t560 (`/tmp/ios-proof/` or sparse worktree) → scp/commit → build.

**Tech stack:** SwiftUI (iOS 17+, `@Observable`/`@MainActor`), `BeagleCore` package; Node (project-cockpit); Cloudflare in front of `beagle.chiuratto.ai`.

**Verification doctrine:** UI changes verify on the **iPhone 17 Pro sim** (representative for layout/visual). Streaming/CF + on-device-only paths verify on the **real device** (TestFlight build 43) — the sim cannot prove them. Final judgment = on-device.

---

### Task 1 — Streaming actually streams on the device (the #1 anxiety fix)

> **RESOLVED IN CODE — measured + read 2026-06-20. This task needs SHIPPING, not coding.**
> 1. **Cloudflare is fine.** `curl -N` over `https://beagle.chiuratto.ai/api/mobile/v1/chat/stream` streams token-by-token, unbuffered (distinct per-token timestamps +1.36s→+1.90s; `cf-cache-status: DYNAMIC`). Direct pod identical.
> 2. **The iOS streaming code already exists and is correct at the build-42 tip (`8dc39633`).** `BeagleClient.chatStream()` (+ `enum ChatStreamEvent`) POSTs the SSE endpoint, reads `bytes.lines`, yields `.token`/`.done`, CF-first base order. `ConversationStore.sendMessageCloud` consumes it and appends tokens live on `@MainActor`, with a gentle error path. The old blocking `client.chat` + fake `revealText` typewriter is **gone**. Landed in commit `04dc0f6c` (01:00) → build bump 41→42 (01:02) → **build 42 archived 01:19 same day** (`04dc0f6c` is ancestor of HEAD ✓).
> 3. **Cost-me-time trap:** the t560 local/origin `feat/ios-100pct-real` ref was **stale at `64a2e653`** (pre-streaming); reading `git show <stale-ref>:file` showed the OLD blocking+fake code → a false "iOS fakes streaming" conclusion. Always `git fetch` and read the real tip (Mac is freshest).
>
> **Therefore the only open question is shipping/installation:** was **build 42 uploaded to TestFlight** and **installed** on the device? If the phone still runs ≤41, it has the old fake. Archive ≠ upload (upload is Xcode-GUI only, no headless ASC key).

- [x] **Step 1.1 — Cause confirmed (measured + read).** CF + pod + iOS code all correct at build 42. Not a code bug.
- [ ] **Step 1.2 — Verify build 42 is uploaded to TestFlight.** Confirm the 01:19 build-42 archive was distributed (not just archived) and finished processing.
- [ ] **Step 1.3 — Install build 42 on the device and re-test streaming on-device.** Expected: long reply begins filling within ~1–2s and flows token-by-token; no silent wait, no fake typewriter.
- [ ] **Step 1.4 — Only if build 42 on-device still fails:** real device-runtime bug. Capture the `[BeagleClient]` console prints + which base URL won, and debug from there (systematic-debugging).

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

- [ ] **Step 6.1 — Bump the build number.** First **read the current `CURRENT_PROJECT_VERSION` in `beagle-ios/project.yml`** (do not assume 42 — verify on the Mac), then bump to the next integer, `xcodegen generate`, commit, push.
- [ ] **Step 6.2 — Archive (Xcode GUI, keychain) + upload** to TestFlight (`1.1 (43)`).
- [ ] **Step 6.3 — On-device acceptance.** On the real iPhone, verify against the north star: send a message → presence shifts + tokens stream calmly (no silent wait), composer clears, Stop works, memory cue appears when grounded, errors are gentle. The bar: *does it feel like a calm companion at your side?*

---

## Notes / DRY
- Backend stream pieces (`streamChatViaRouter`, `/api/mobile/v1/chat/stream`) already exist (commit `f0c6c19b`); iOS `chatStream` + streaming `sendMessageCloud` exist (`04dc0f6`). This plan **completes + calms** them, fixes CF delivery, and adds presence/memory/motion.
- Out of scope: deep RAG-ranking (separate); other tabs.
- Every iOS step that touches streaming/CF or MLX is **device-verified**, not sim.
