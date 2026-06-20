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

> **AUDIT (2026-06-20, read against the real build-42 tip `8dc39633` — not stale).** Far more is already built than the original plan assumed (it was written against a stale ref). Per-step status folded in below. Genuinely-remaining iOS work is small + concentrated: **2.2, 2.3, 3, 4.** Tasks 2.1 and 5 are already done.

### Task 2 — Composer that respires (clear-on-send, Stop, calm empty state)

**Files:** `beagle-ios/.../BeagleCockpit/HomeView.swift` (`exocortexInput`, `homeInvitation`, send wiring), `beagle-ios/.../BeagleCockpit/BeagleInputBar.swift` (Stop wiring).

- [x] **Step 2.1 — Clear the composer on send.** ALREADY DONE: `BeagleInputBar.performSubmit()` calls `onSubmit(trimmed)` then `text = ""` (BeagleInputBar.swift:361-362) for typed sends. The plan's "current bug" was a false read off stale code. *(Optional nit: the `homeInvitation` starter-prompt buttons set `inputText = prompt` and don't clear it — but the invitation disappears after the first send, so it's not user-visible. Skip unless it resurfaces.)*
- [ ] **Step 2.2 — Stop control during generation.** PARTIAL → wire in Home. `conversation.stopStreaming()` exists (ConversationStore.swift:188) and `onStop` IS wired in `ConversationView.swift:65`, but **HomeView's `exocortexInput` does not pass `onStop`** — so the Home composer shows no Stop button while streaming (it only disables via `isEnabled: !isStreaming`). Fix = add `onStop: { conversation.stopStreaming() }` to the `BeagleInputBar(...)` call in `exocortexInput`. BeagleInputBar already renders the `stop.fill` button when `!isEnabled && onStop != nil` (BeagleInputBar.swift:258-267). Verify on sim: during a stream, Stop halts it and the bubble finalizes.
- [ ] **Step 2.3 — Warm, low-friction empty state.** PARTIAL → copy + focus. The warm state exists (teal brain badge + starter prompts, HomeView.swift:757+), but the copy is productivity-framed ("What are you working on?" / "Type a thought below — Beagle stays with it."). Soften for the anxious-moment companion use (invite talking/doubt without pressure). Also wire focus-on-appear (bump `inputFocusRequest` in the home `.onAppear` so opening Beagle lands ready to type). Verify on sim (screenshot).
- [ ] **Step 2.4 — Commit** (`fix(ios): wire Stop in home composer + companion empty-state copy + focus-on-appear`).

### Task 3 — Ambient presence mark (presence without demand)

**Files:** `beagle-ios/.../BeagleCockpit/HomeView.swift` (header/nav), `BeagleCore/Theme.swift` `BeaglePresenceState`.

> **AUDIT:** MOSTLY MISSING for the chat-turn intent. Presence states exist and render tinted in the header, BUT `shellPresenceState` is driven by cognitive/job signals (HomeView.swift:431) and `bodyPresenceState` by physio/HRV readiness (HomeView.swift:2408) — **neither reacts to `conversation.isStreaming` or the chat turn.** There is no slow breathing glyph tied to the conversation. **Enum-name correction:** the real `BeaglePresenceState` cases are `.attentive/.active/.strained/.dormant` (Theme.swift:193+) — there is **no `.holding`/`.resting`/`.present`**. Either add a `.holding` case or repurpose `.strained` for the stalled-turn signal.

- [ ] **Step 3.1 — Breathing presence glyph in the header.** Add a slow **breathing** mark (≈3–4s cycle, low opacity range, `BeagleMotion`-driven) tinted by the conversation presence; must not flash/pulse aggressively (Calm Tech: periphery).
- [ ] **Step 3.2 — Presence reacts to the chat turn.** Introduce a conversation-derived presence (driven by `conversation.isStreaming` + turn lifecycle): on send → `.attentive`; during stream → `.active`; on stall/error → `.strained` (or a new `.holding`). This is the "never a silent void / I'm here through this" signal — distinct from the existing cognitive/physio states.
- [ ] **Step 3.3 — Verify on sim** (screenshot: calm breathing glyph + state change on send).
- [ ] **Step 3.4 — Commit** (`feat(ios): chat-turn presence — breathe on stream, hold on stall`).

### Task 4 — Memory shown gently (felt understanding)

**Files:** `apps/project-cockpit/server/mobile-routes.mjs` (stream `done` event), `beagle-ios/.../BeagleCore/BeagleClient.swift` (`ChatStreamEvent.done`), `ConversationStore.swift` + `BeagleCockpit/ChatBubbleView.swift`.

> **AUDIT:** MISSING (not started). Backend computes `memoryContext` (mobile-routes.mjs:1521) but the `done` event omits it — it only sends `{done, model, source, tokens_used}` (line 1542). iOS `ChatStreamEvent.done` carries `(model, tokensUsed, source)` — no `grounded`. Raw materials exist: `BeagleTheme.truthRemembered` tint + a "Composing from memory…" string already in ChatBubbleView (≈line 363).

- [ ] **Step 4.1 — Backend signals grounding.** In `/api/mobile/v1/chat/stream`, when `memoryContext` is non-empty, add `"grounded": true` (optionally a 1-line memory label) to the `data:{done,...}` event.
- [ ] **Step 4.2 — iOS carries it.** Extend `ChatStreamEvent.done` with `grounded: Bool` (parse `obj["grounded"]` in `chatStream`); store on the message; thread through `sendMessageCloud`.
- [ ] **Step 4.3 — Gentle peripheral cue.** When `grounded`, show a quiet "recalling…" / memory chip on the assistant bubble (low-contrast, `truthRemembered` tint) — informing without demanding. Verify on sim.
- [ ] **Step 4.4 — Commit** (`feat(cockpit/ios): gentle memory-grounding cue on streamed replies`).

### Task 5 — Calm motion & gentle recovery

**Files:** `ChatBubbleView.swift`, `HomeView.swift` (transitions), error/retry paths in `ConversationStore.sendMessageCloud`.

- [x] **Step 5.1 — Slow, soft transitions.** LARGELY DONE: `ChatBubbleView` uses `BeagleMotion.normal` (line 377) + `.opacity` transitions (99/102); HomeView uses `BeagleMotion.slow` for surfaces. *(Optional polish: one `.snappy` at HomeView.swift:1697 — leave unless it reads as flashy on-device.)*
- [x] **Step 5.2 — Gentle errors + Retry.** ALREADY DONE: stream-fail path shows "The cluster didn't respond — tap ↺ to try again" (ConversationStore `sendMessageCloud`); Retry wired via `regenerateLastResponse` (HomeView.swift:964).
- [ ] **Step 5.3 — Confirm on device** (no separate commit expected unless the optional polish above is taken).

### Task 6 — Ship build ≥44 + on-device judgment

> **AUDIT correction:** the installed TestFlight build is **43 (old code, runs the blocking + fake-reveal path)**. Today's streaming work was archived as build **42** — a *lower* number — so it never superseded 43 on the device. The next build **must exceed 43** (→ 44+), built from current HEAD (which has the streaming fix). Verified: Mac `project.yml` is at 42, HEAD `8dc39633` contains streaming commit `04dc0f6c`.

- [ ] **Step 6.1 — Apply the remaining iOS edits** (2.2, 2.3, 3, 4) on `feat/ios-100pct-real`, commit, push.
- [ ] **Step 6.2 — Bump build to 44** (must exceed installed 43) in `beagle-ios/project.yml`, `xcodegen generate`, commit, push.
- [ ] **Step 6.3 — Archive (Xcode GUI, keychain) + upload** to TestFlight as `1.1 (44)`. (No headless ASC key — upload via Xcode Organizer GUI.)
- [ ] **Step 6.4 — On-device acceptance.** On the real iPhone (build 44): send a message → **tokens stream calmly, no silent wait**; presence shifts on send; composer clears; Stop works; memory cue appears when grounded; errors are gentle. The bar: *does it feel like a calm companion at your side?*

---

## Notes / DRY
- Backend stream (`streamChatViaRouter`, `/api/mobile/v1/chat/stream`, `f0c6c19b`) **and** iOS streaming (`chatStream` + live `sendMessageCloud`, `04dc0f6`) are **both complete and correct** at the build-42 tip. CF delivery is **fine** (measured — not buffering). So the streaming half of this plan is DONE in code; the gap was purely that build 42 (the streaming build) carries a *lower* number than the installed build 43 and never shipped over it. Remaining net-new work = presence/memory + the two small composer gaps (Stop in Home, empty-state copy) + ship build ≥44.
- **Lesson banked:** the original plan was written against a stale `feat/ios-100pct-real` ref (`64a2e653`). Always `git fetch` and read the real tip before planning iOS work. See memory `project_ios_chat_fake_streaming`.
- Out of scope: deep RAG-ranking (separate); other tabs.
- Every iOS step that touches streaming/CF or MLX is **device-verified**, not sim.
