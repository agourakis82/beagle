# Proactive Synthesis ("organize my head") — Design

**Date:** 2026-07-17
**Status:** approved (design), pending implementation plan
**Owner:** Demetrios (sole operator)
**Repo:** beagle · branch `reconcile/unify-beagle`

## Motivation

At the CPC26 Yale poster, anxious, the user could not articulate — in the moment —
what his research was or what he was doing. A capture-and-synthesis tool that turns
his own recorded thinking into a clear, sayable structure would have given him the
scaffold he needed. This feature is that tool: on demand, it synthesizes his
recorded self (optionally scoped to a topic) into a short, articulate map.

It builds directly on this session's work: the memory-pg **trusted-only recall**
(his real words, ranked among themselves) and the **provenance** system (his words
attributed as his; model output never laundered as truth).

## THE HARD WALL (non-negotiable — read first)

The value of Beagle is the **natural, intimate chat** — the dyadic coupling
(ACOPLAMENTO) that makes the user's daily life work. A structured "synthesis" voice
must NEVER contaminate that. These four invariants are load-bearing; any change that
weakens one is a design violation, not an optimization.

1. **`/chat` is untouched.** Synthesis is a SEPARATE endpoint (`/synthesize`). Not a
   flag on chat, not a mode chat drifts into. The chat's persona, register, warmth,
   grounding assembly, and streaming path are modified by ZERO lines. The two
   surfaces share read-only helpers (recall) but never share behavior.
2. **Never automatic — always a deliberate act by the user.** The companion never
   synthesizes unprompted, never mid-conversation. Synthesis fires only on an
   explicit request to `/synthesize`. It is a thing the user asks the relationship to
   do, in a separate room — not a lens the companion wears.
3. **Isolated register.** The synthesis voice (structured articulation) never flows
   back into the chat. Its system prompt and output live only in `/synthesize`. The
   companion does not learn to speak in headings/bullets with the user.
4. **The output is not captured as the user's memory.** A synthesis result is a
   derived artifact (`model_generated`). It is NOT written to memory-pg as the user's
   testimony, so it can never be recalled later and reshape the companion's voice.
   (The provenance system would tier it `unverified` regardless; we additionally do
   not capture it at all.)

One sentence: **the chat stays a relationship; synthesis is something the user can
ask the relationship to do, in a separate room, and it closes the door on its way
out.**

## Approach

**Chosen: a new, separate endpoint in `project-cockpit`** —
`POST /api/mobile/v1/synthesize`. It reuses read-only infrastructure (the recall
helpers in `auth-bridge.mjs`, the router client, auth) but is its own route with its
own prompt and its own streaming response. Clean boundary; honors the wall.

Rejected: a `mode: "synthesize"` flag on `/chat` — violates wall invariant #1 and
makes register isolation impossible.

## Architecture & Data Flow

```
POST /api/mobile/v1/synthesize  { topic?: string, windowDays?: number = 7 }
  │
  ├─ 1. GATHER (read-only recall; provenance-aware)
  │     topic present → fetchRecentMemories(topic, {trustedOnly:true})  [his words]
  │                   + broad/background recall (unfiltered)            [framing]
  │                   + graph facts on topic                            [his hypotheses]
  │     topic absent  → his recent captures over windowDays (recency)
  │
  ├─ 2. ASSEMBLE prompt: recalled material + synthesis system prompt
  │
  ├─ 3. SYNTHESIZE: one routerChat call (Claude), stream: true
  │
  └─ 4. STREAM markdown back (SSE text/event-stream), 5 blocks
```

## Components

Each unit is small, single-purpose, and independently testable.

### 1. `gatherSynthesisMaterial(input, deps)` — pure-ish recall assembly
- **Input:** `{ topic?, windowDays }`, plus injected `deps` (fetch impls / recall fns)
  so it is testable without the cluster.
- **Does:** builds the grounding material.
  - **topic present:** `fetchRecentMemories(topic, {k, trustedOnly:true})` (his
    trusted words) + a broad recall for background + graph facts (labelled as
    *unconfirmed hypotheses*, never as his testimony).
  - **topic absent:** his recent captures within `windowDays`, by recency.
- **Returns:** a structured object `{ trustedWords: [...], background: [...],
  hypotheses: [...], mode: "topic"|"recent" }` — NOT a prompt string, so the prompt
  builder can be tested separately.
- **Open design detail (resolve in plan):** the no-topic recency source. Options:
  (a) reuse memory-pg `/recent` if it can return recent `user_stated` records across
  surfaces; (b) add a minimal memory-pg query/endpoint for "recent trusted records by
  occurred_at". Prefer (a) if `/recent` already supports it; else (b), scoped small.

### 2. `buildSynthesisPrompt(material)` — pure
- **Input:** the object from component 1.
- **Does:** renders the system prompt + the user-content block. Encodes the
  provenance rule (see below) and the 5-block output contract.
- **Returns:** `{ system, user }` message pair. Pure → unit-tested directly.

### 3. `POST /api/mobile/v1/synthesize` handler — orchestration + streaming
- Auth (same gate as the other mobile routes).
- Calls component 1 → component 2 → `routerChat({ ..., stream: true })`.
- Streams the model's markdown to the client as SSE (`text/event-stream`), reusing
  the existing streaming plumbing pattern from `/chat` (shared transport code, not
  shared behavior).
- Fail-soft (see error handling).

## Output contract (markdown, streamed, 5 blocks)

The model writes markdown directly, in the user's register (elevated, rigorous,
"você"), streamed live:

```
## Elevator
1–2 sentences: the core in one breath.

## Espinha
Three layers: problema → abordagem → por que importa.

## O que você circula / tensões
The thread he keeps returning to; the unresolved tension.

## Perguntas abertas
What is genuinely open — where the thread is incomplete.

## Próximo movimento concreto
One small, sharp action to unstick — concrete, doable now.
```

## Provenance integrity (the other non-negotiable)

Given this session's whole arc: the synthesis **synthesizes only from the provided
recalled material.** The system prompt states, explicitly:
- Use ONLY what is in his recorded words/material below.
- Where the thread is incomplete, name it under *Perguntas abertas* — **never invent
  to fill a gap.**
- Graph facts are his *hypotheses/explorations*, phrased as "você parece explorar…",
  never asserted as established fact.
- If there is not enough material, say so plainly (see fail-soft) rather than
  confabulating a synthesis.

## Error handling (fail-soft)

- **Empty/insufficient recall:** do NOT confabulate. Stream a short, honest message —
  e.g. *"Ainda não tenho o bastante registrado sobre isso pra sintetizar com
  verdade."* — and stop.
- **Router failure / timeout:** return a clean error to the client; never emit a
  fabricated body. Log for observability.
- **Recall backend down:** synthesis degrades to "insufficient material" rather than
  erroring hard (recall calls are already fail-soft, returning `[]`).

## Testing

- **`buildSynthesisPrompt` (pure):** given a material object, asserts the system
  prompt carries the provenance rule + 5-block contract, and that hypotheses are
  labelled as unconfirmed. No network.
- **`gatherSynthesisMaterial` (injected deps):** stubbed recall fns; asserts topic
  mode requests `trustedOnly:true` for his words, recent mode uses the recency
  source, and that empty recall yields the insufficient-material path. No network.
- **Handler:** stubbed router (streaming stub) → asserts SSE shape and that a
  zero-material gather short-circuits to the honest message. Mirrors the existing
  `auth-bridge.test.mjs` fetch-stub pattern.
- **Live-verify:** curl `/synthesize` with a real topic ("redes semânticas em
  depressão") → a grounded markdown synthesis streams back, drawn from his words.

## Out of scope (v1)

- **iOS wiring.** The existing iOS #4 `DailySynthesisView` (on the Mac branch) can be
  rewired to consume this endpoint later; that is a separate Mac build, not this spec.
- **Scheduled/daily synthesis.** On-demand only. No cron.
- **Persisting synthesis results.** By wall invariant #4, results are not stored as
  memory. (A future, separate decision could store them in a *derived-artifacts*
  space that is explicitly excluded from chat grounding — not now.)

## Success criteria

1. The wall holds: `/chat` behavior is byte-identical; synthesis never fires
   unprompted; its register never appears in chat; its output is never captured as
   the user's memory.
2. `/synthesize` with a topic streams a grounded, 5-block markdown synthesis built
   only from his recalled material.
3. Insufficient material yields an honest message, never a confabulation.
4. All units unit-tested; endpoint live-verified.
