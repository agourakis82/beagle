# Beagle Companion — Real-Time Awareness (Temporal Presence)

**Date:** 2026-06-26
**Status:** Approved design — ready for implementation plan
**Scope:** Personal-space companion (the beagle). v1 = *presence of time* + *dated recall*.

## Problem

The Personal-space beagle is **time-blind**. The data layer already records time
(`memory-pg` stores `occurred_at` + `decay_class`; the temporal graph is deployed), but the
companion's *voice* never receives it: the server prompt (`mobile-routes.mjs`) injects no
"now", no elapsed time, no dates on recalled memories. The only temporal touch is the iOS
opening greeting reading `hour`.

A personal friend cannot ignore time. A companion that responds but does not know it is late,
that three days passed, or *when* a remembered thing happened, feels like a stateless oracle —
present in words, absent in time.

## Goal

Every turn, the beagle is grounded in **real wall-clock time**:
1. **Presence of time** — it knows the user's local *now* (date, day-of-week, part-of-day) and
   **how long since they last talked**, and references this naturally.
2. **Dated recall** — memories surfaced via RAG carry their `occurred_at` and are situated in
   time ("ontem", "semana passada").

It references time **when it matters** (deep night, a long absence, anchoring a memory) — never
recites the clock mechanically.

## Non-goals (YAGNI — separate future specs)

- **Recency-weighted retrieval ranking** (decay in the RAG ranker) — future, *measured*.
- **Tool-calling for time** — self-hosted small models call tools unreliably; overkill for
  something the companion should *always* know.
- **Proactive cross-day follow-up / trend detection** (the "continuity" facet) — builds on this.
- **Rhythm / anticipation modeling** (circadian/weekly patterns) — separate spec.

## Approach: prompt-layer temporal context (Approach A)

All temporal awareness is assembled server-side into the Personal-space prompt each turn. No
model training, no storage change, no retrieval-ranking change. The companion "knows" time
because we tell it every turn, and the persona teaches it to *use* that naturally.

Chosen over (B) tool-calling and (C) recency-weighted ranking because it delivers both required
layers (presence + dated recall) with the least risk: stamping a snippet with its date does not
require reordering retrieval — only returning and formatting `occurred_at`.

## Components

### 1. Client (iOS) — sends "now"

With each `POST /api/mobile/v1/chat`, include in the body:
- `clientTime`: ISO8601 with offset, e.g. `2026-06-26T23:47:00-03:00`
- `timezone`: IANA id, e.g. `America/Sao_Paulo`

Source: `Date()` + `TimeZone.current.identifier` at send time, in `ConversationStore.sendMessage`
→ request body. The "now" is genuinely the user's (knows it's late *for them*; follows them
across timezones when travelling).

### 2. Server — temporal-context builder (`temporal-context.mjs`, pure module)

Two pure functions, unit-testable in isolation:

- `relativeTime(from, to, tz) → string` — pt-BR relative phrasing:
  `"agora há pouco" · "hoje de manhã/à tarde/à noite" · "ontem" · "há N dias" ·
   "semana passada" · "há algumas semanas" · "faz meses"`. Coarsens as distance grows
  (never "há 87 dias").
- `buildTemporalContext({ now, timezone, lastContactAt }) →
   { nowLabel, diaDaSemana, parteDoDia, desdeUltimo }`
  - `parteDoDia` ∈ {madrugada, manhã, tarde, noite} by local-hour boundaries.

The chat handler (`mobile-routes.mjs`, Personal-space path):
1. `now = parse(clientTime) || serverNow`; `tz = clientTimezone || "UTC"` (deterministic default).
2. `lastContactAt` = timestamp of the previous message in the thread (`home:<slug>`); none →
   first contact.
3. Build the `TEMPO AGORA` block and **insert it right after `PERSONAL_PERSONA`** (top of the
   system, before physiome + biography), so the persona reads its time-guidance then its time-facts.

Injected block (example of what the model sees):
```
TEMPO AGORA: sábado, 26/jun, 23h47 (madrugada chegando, fuso dele).
Última vez que se falaram: há 3 dias.
```
First contact omits the second line and frames it as a first meeting.

### 3. Dated recall — stamp grounding snippets

In the grounding path (`fetchExocortexContext` → memory-pg `retrieve`):
- Ensure `occurred_at` is **returned** per snippet.
- Prefix each snippet with its relative date via `relativeTime(occurred_at, now, tz)`:
  `[ontem] <snippet>` / `[há 3 dias] <snippet>`.
- A snippet missing `occurred_at` is left unstamped (never guess a date).

### 4. Persona (`PERSONAL_PERSONA`)

Append a short clause, in the beagle's scent-hound spirit (feel time, don't announce it):

> *Você vive no tempo com ele. Sente a hora — madrugada pesa diferente de meio-dia. Nota o
> intervalo: se sumiu dias, isso conta; se foi agora há pouco, retoma o fio. Situa o que lembra
> no tempo ("ontem", "semana passada"). Mas você não é relógio: só traz o tempo quando ele tem
> peso — tarde da noite, uma ausência longa, ancorar uma lembrança. Na dúvida, sente o tempo sem
> anunciá-lo.*

## Data flow (per turn)

```
iOS  sendMessage(text) → body += {clientTime, timezone} → POST /api/mobile/v1/chat
SRV  now           = parse(clientTime) || serverNow
     tz            = clientTimezone || default
     lastContactAt = thread.lastMessage.ts            // first contact → null
     temporal      = buildTemporalContext({now, tz, lastContactAt})
     grounding     = fetchExocortexContext(...)        // snippets carry occurred_at
                     → each prefixed [relativeTime(occurred_at, now, tz)]
     system        = PERSONAL_PERSONA
                     + TEMPO_AGORA(temporal)
                     + physiome + biography
                     + groundingStamped
     → muse → voice(system) → response
```

## Error handling / edge cases

- `clientTime` missing/invalid → fall back to server clock (degraded, never crash).
- `timezone` missing → default `"UTC"`; relative phrasing still works (only absolute-hour feel degrades).
- First contact (no `lastContactAt`) → "primeira vez" framing, no Δt line.
- Clock skew / future timestamp → clamp Δt ≥ 0.
- Snippet `occurred_at` missing → omit that stamp.
- Very large Δt (months) → coarse phrasing ("faz meses").
- Timezone change between turns (travel) → use the current turn's tz; the companion *may* notice
  it emergently, never forced.

## Testing (pure, deterministic — mirrors `CompanionMotion` tests)

`temporal-context.mjs` is pure → no network, no LLM:
- `relativeTime`: every boundary (just-now, today AM/PM/eve, yesterday, N days, last week,
  weeks, months) in a fixed tz.
- `buildTemporalContext`: `parteDoDia` boundaries (madrugada/manhã/tarde/noite), `diaDaSemana`,
  `desdeUltimo` phrasing, first-contact, skew clamp.
- Cross-timezone case (late-night-for-user while server is UTC).

## Dependencies to confirm during implementation

1. The thread store (`home:<slug>`) exposes a per-message timestamp for `lastContactAt`.
2. The memory-pg `retrieve` path returns `occurred_at` per snippet (capture stores it; confirm
   the read surfaces it).

If (1) or (2) is missing, that surfacing is the first task of the plan (small; data exists).
