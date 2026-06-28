# Companion Memory Spine — Design Spec

> Status: design approved (2026-06-27). Scope of THIS spec: the **ingestion loop** (the
> first, foundational piece). The rest of the system (sessions, diary, timeline, search) is
> captured as roadmap context but specced/built later.

**Goal:** Make the companion a *continuous presence that remembers*. Today the personal chat
never writes anything back to memory — once a turn scrolls past the model's 8-10 turn window,
it is forgotten. This spec wires the **ingestion loop** so the companion durably keeps what you
tell it (verbatim) and distills the points that matter ("falinhas") into recallable memory,
sovereignly. Continuity then comes from the exocortex, not from an ever-growing visible thread.

**Architecture (whole system, for context):** one continuous companion. Three layers, today
conflated into one infinite thread, are separated:
1. **Working memory** — what the model sees per turn: the last N turns. *Already bounded
   (`ConversationStore` sends `messages.suffix(8/10)`).* No change.
2. **The memory spine** — long-term continuity. Lives in the exocortex (memory-pg /
   beagle-core), written by the **ingestion loop** (THIS spec), recalled by the existing RAG
   grounding (`fetchRecentMemories`).
3. **Revisiting** — diary, timeline, find-a-"falinha". Browsable surfaces over the spine.
   *Roadmap, not this spec.*

**Tech stack:** project-cockpit (Node, `apps/project-cockpit/server`), beagle-core
(`/api/memory/ingest_chat`, Rust), memory-pg (Postgres+pgvector, the canonical index), the
sovereign DGX Spark fleet (qwen2.5-14b) for the distill pass.

---

## The ingestion loop

### Trigger & placement
The personal chat handler is `mobile-routes.mjs` `POST /api/mobile/v1/chat` with
`space === "personal"` (the `runMuseVoiceEnsemble` path). **After the reply is produced**, the
turn is ingested. **Fire-and-forget, best-effort** — exactly like the grounding fetches: a
failed ingest must NEVER block, delay, or fail the chat response. The response returns to the
user immediately; ingestion runs detached.

### Two layers

**A) Verbatim layer — the durable transcript (diary + raw recall).**
Call the existing canonical endpoint — beagle-core already persists raw turns as durable
conversation passages AND triggers a reindex, so recall finds them. The cockpit just has to
call it (it currently never does).

```
POST {BEAGLE_INTERNAL_URL}/api/memory/ingest_chat
Authorization: Bearer <operator token>;  X-Beagle-Consumer: beagle-operator
{
  "source": "companion-personal",
  "session_id": "<session id>",          // see Session model below
  "turns": [ {role, content}, ... ],     // the user turn + assistant reply (this exchange)
  "tags": ["companion", "personal", "verbatim"],
  "metadata": { "space": "personal", "client_time": "...", "timezone": "..." }
}
```
beagle-core dedups by `content_hash` (idempotent re-ingest is safe) and dual-writes to
memory-pg. The MemoryEngine chunks+embeds the passages → future `fetchRecentMemories` recall
surfaces them. **This layer is ~pure wiring.**

**B) Distill layer — the "falinhas" (clean recall + the points that matter).**
Raw-turn ingestion of *every* exchange pollutes memory with chitchat ("oi, tudo bem") — the
exact noise that made the prior pipeline feel like "porcaria". So a **selective sovereign
distill** extracts only genuinely memorable points: facts, commitments, feelings, decisions,
things-to-remember-about-the-user. Skip pure pleasantries.

- **Model:** the **sovereign Spark** (`qwen2.5-14b` via the router) — the content is the user's
  private conversation; it must not leave the cluster (same sovereignty rule as recall/refine).
- **Prompt:** "From this exchange, extract 0–4 atoms worth remembering long-term about the
  user. Each atom = one crisp sentence in the user's voice. Skip greetings/smalltalk. Return
  JSON `[]` if nothing is worth keeping." (Returning `[]` is the common, correct case.)
- **Write:** each atom → `ingest_chat` (or a memory write) tagged `["companion","personal",
  "distill"]` with the session_id + timestamp, so recall ranks them and the "find a falinha"
  search can target them.

### When (granularity) — debounced per session, not per turn
Per-turn ingest is noisy + costly. **Accumulate the session and ingest on a debounce**: ~30s
after the last activity, or on app background/session-roll, flush the session's new turns
(verbatim) and run ONE distill pass over the new exchanges. This batches naturally, cuts cost,
and gives the distill more context. Verbatim may also flush per-turn (cheap) if we want the
diary live; distill stays per-session.

### Session model (minimal, needed now)
A `session_id` groups turns. The iOS `ConversationStore` owns it: generate on first message;
**roll** to a new session on a new calendar day OR a gap > ~6h since the last turn (a new
"visit"). Persist it locally; send it in the chat request so the server tags ingestion. This is
the seam the diary/timeline will later read.

---

## Data flow

```
iOS ChatScreen → POST /api/mobile/v1/chat {prompt, space:"personal", session_id, clientTime,…}
      │
   cockpit: runMuseVoiceEnsemble → reply  ──────────────► returned to user (NOT blocked)
      │ (detached, best-effort, debounced per session)
      ├─ A) POST beagle-core /api/memory/ingest_chat (verbatim turns)  → passages + reindex + memory-pg
      └─ B) distill via Spark qwen2.5-14b → 0–4 atoms → ingest_chat (distill atoms)
                                                              │
   next conversation: fetchRecentMemories(prompt) recalls atoms+passages → continuity ✓
```

## Error handling
Every step fail-soft. Ingest failure → log + drop (chat already returned). A 5xx from
beagle-core, a Spark timeout, a malformed distill JSON → swallow, never surface to the user.
Idempotency via `content_hash` so a retry/duplicate is harmless.

## Sovereignty
Distill runs on the sovereign Spark; verbatim + atoms land only in the canonical in-cluster
store (memory-pg / beagle-core). Personal conversation content never touches external SaaS.
The user is the sole operator → no extra auth on the in-cluster hops beyond the operator token.

## Offline resilience & sync (added 2026-06-27)
The companion must never go mute when Wi-Fi/5G drops, and nothing said offline may be lost.
Most of the infra already exists; this adds two seams.

**Network-aware routing (online → cloud, offline → on-device).** `ConversationStore` already
has the seam: `LocalLLMEngine` (on-device MLX, Tier 0.5, 8-30 tok/s, kept warm) + `sendMessageLocal`
+ `sendMessageCloud`. Today it prefers local when `llm.isReady`; refine so the **personal
companion prefers the cloud** (rich sovereign cluster model + RAG grounding) **when online**, and
**falls back to the on-device model when offline** — including a graceful mid-request fallback if
the cloud call fails on a dropped connection. A network monitor (`NWPathMonitor`) drives the
choice. Tradeoff (surfaced to the user): offline answers come from the lighter on-device model;
full quality + memory grounding resume online. The on-device path is also the *most* sovereign —
nothing leaves the phone.

**Durability:** conversation turns are *already* persisted locally via SwiftData
(`persist(message:)` on every message), so a disconnect or app-kill loses nothing.

**Ingestion outbox (the new piece):** ingestion becomes an **outbox**, not a live call. Each
turn's pending ingestion (verbatim payload + a `content_hash`) is enqueued to a local store
(SwiftData). A sync worker flushes the outbox to beagle-core `/api/memory/ingest_chat` whenever
connectivity returns (and on app foreground). The server's `content_hash` dedup makes replays
harmless, so the worker can retry freely. **Distill defers to sync:** the sovereign Spark distill
runs server-side when the verbatim arrives — so offline turns are captured locally now and
distilled into "falinhas" the moment they sync. (An optional on-device light-distill is possible
later, but deferring keeps quality + sovereignty consistent.)

Flow with connectivity awareness:
```
turn → persist locally (SwiftData)              [always; never lost]
     → reply: online ? cloud(grounded) : on-device MLX   [never mute]
     → enqueue ingestion to outbox
outbox worker (on reconnect / foreground): flush → /api/memory/ingest_chat (idempotent) → spine
```

## Testing
- **Unit (cockpit):** after a personal reply, the ingest call is issued with the right payload
  (mock the fetch; assert source/session_id/turns/tags). A thrown ingest does not affect the
  returned reply.
- **Unit (distill):** given a chitchat exchange → `[]`; given an exchange with a fact/commitment
  → ≥1 atom; malformed model output → `[]` (no crash).
- **Integration:** ingest a turn with a distinct fact → a later `fetchRecentMemories` for that
  topic surfaces it. Idempotent re-ingest does not duplicate.
- **Offline (iOS):** with the network down, a sent message still gets a reply (on-device path)
  and is persisted; its ingestion lands in the outbox. On reconnect, the outbox worker flushes
  it to `/api/memory/ingest_chat`. A double-flush (worker retry) does not duplicate (content_hash).
- **Mid-request drop:** a cloud send whose connection dies falls back to the on-device model
  rather than erroring; the turn is still persisted + enqueued.

## Roadmap (after the loop — separate specs)
- **Sessions UI:** the visible thread shows the current session; past sessions are out of the
  live scroll (in memory + history).
- **Diary:** chronological read of past sessions (verbatim passages by day/session).
- **Timeline:** high-level dated session list, one-line summary per session.
- **Find-a-"falinha":** search across distill atoms + verbatim ("what did I say about X?").

## Open decisions (flag for the build)
1. **Distill cadence:** per-session debounce (proposed) vs per-turn. → per-session.
2. **Verbatim cadence:** per-turn (live diary) vs per-session. → per-session for v1 (simpler;
   diary still complete); revisit if we want a live diary.
3. **session_id authority:** iOS-owned (proposed) vs server-derived from gaps. → iOS-owned (the
   client knows the real "visit" boundaries; server-derive is a fallback).
4. **Distill noise guard:** the `[]`-by-default prompt is the main guard; consider a per-day
   atom cap to bound growth.
5. **Online routing preference (companion):** prefer cloud-when-online (rich + grounded) and
   fall back to on-device-when-offline (proposed) — vs the current "prefer local when ready".
   The companion wants the cluster model + memory grounding when it can reach them.
6. **Ingestion as outbox** (vs live call): always outbox + sync worker, so online and offline
   share one durable path (proposed).
