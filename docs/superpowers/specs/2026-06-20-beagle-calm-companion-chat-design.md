# Beagle — Calm Companion Chat (Redesign Design)

**Date:** 2026-06-20
**Status:** design approved by user; spec for review → plan → build
**Surface:** iOS cockpit chat (Home), branch `feat/ios-100pct-real`

---

## North star

> Beagle must be at my side — *especially* when I'm getting anxious and want to chat a little, or have a doubt.

Beagle is not a productivity chatbot. It is a **cognitive companion that holds space** — reached in moments of anxiety or uncertainty, where the interaction itself must *steady* the person, never spike them. The prior chat did the opposite (silent waits, a composer that doesn't clear, generic answers, no felt presence → anxiety/anguish). Wellbeing is the **primary design goal**, not a side effect.

The user is a psychiatrist; emotional safety, calm pacing, and felt presence are first-class requirements.

## Evidence base (deep-research, 22/25 claims confirmed 3-0; weak ones killed)

1. **Calm Technology** (Weiser & Brown; Amber Case): an interface must demand the *least possible attention*; companion state lives in the **periphery** and moves to center only when the user recenters it. Peripheral attunement = felt "locatedness"/presence *without* anxiety, and prevents overload in a dense exocortex.
2. **Psychology of waiting** (Lallemand & Gronier DIS 2012; NN/g): opaque silent waits are the core anxiety driver — satisfaction declines *linearly*, dropping below acceptable by ~10s. **Streaming** (token-by-token) is the single most important fix: it shifts cognitive resources off the wait and restores a sense of control. *(Killed: "richer/decorated waiting feedback shortens perceived wait" — the answer is honest streaming, not fancier spinners.)*
3. **Positive Technology / Positive Computing** (Gaggioli, Riva; Calvo & Peters; 2026 MAKE & GROW): interaction quality is **co-orchestrated** through turn-taking/pacing, not delivered as a final blob; **warmth + response specificity + visible memory/provenance** ("it remembered my…") is what makes a companion feel understood, present, trustworthy. Anthropomorphism is a **tunable lever** set via role/onboarding.
4. **Warmth & tone are decisive** for emotional safety (confirmed 3-0).

## The design — "a presence that stays with you"

### 1. Ambient presence, in the periphery
Reuse the existing `BeaglePresenceState` (resting → attentive → present → holding). Render it as a quiet **breathing mark** in the header — soft, slow, never flashing for attention. It shifts state the instant you send (so there is *never* a silent void), and the "holding" state explicitly signals *I'm here through this*. Presence without demand → felt locatedness.

### 2. Streaming that breathes (and works on-device)
Token-by-token, calmly paced; the cursor *is* the thinking. Never a silent gap >~10s — sending immediately moves presence to "attentive" and tokens begin. **Fix the Cloudflare SSE buffering** so it streams on the real device (it currently buffers through `beagle.chiuratto.ai` → blob), and validate on the device from step one — no more simulator-as-proof.

### 3. A composer that respires
- **Clears on send** (the current bug — text persists).
- One calm field that grows/shrinks with content; no dead empty box.
- Explicit **Stop** during generation (control restores calm).
- Low-friction to start: opening Beagle in a hard moment lands you ready to type, with a warm, safe empty state (not a cluttered dashboard).

### 4. Memory made visible, gently
When Beagle grounds an answer in your exocortex, show a soft **peripheral** provenance cue ("recalling…", a quiet chip) — enough to feel *understood*, never loud. Specificity + memory cues = trust.

### 5. Calm visual & motion language
Sovereign Dark, soft surfaces, **slow** transitions (breathing, not flashing); reduce cognitive load; warm, specific copy. Errors are gentle and recoverable (a calm retry), never a dead-end.

### 6. "Chat a little / a doubt" is first-class
Not every turn is a heavy query. Low-stakes, quick exchanges must feel natural and light — no ceremony, no friction, no anxiety. This is the primary use, not an edge case.

## Throughline
Stop making the user wait in silence and shout for attention. Become a **calm presence that streams, remembers, and stays** — reachable and steadying exactly when anxiety rises.

## Scope (this pass)
iOS chat surface only (Home): presence mark, streaming on-device (incl. CF fix), composer (clear/stop/empty state), memory cues, calm motion. Out of scope: the deep RAG-ranking work (separate), other tabs.

## Verification doctrine
The **real device is the proof** from the first step. Backend changes verified live; iOS via on-device test (the MLX/CF paths are sim-invisible). Before/after on the device, not the simulator.
