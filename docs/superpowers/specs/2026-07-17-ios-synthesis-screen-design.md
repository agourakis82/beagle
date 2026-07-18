# iOS Synthesis Screen ("organize my head", on the phone) — Design

**Date:** 2026-07-17
**Status:** approved (design), pending implementation plan
**Owner:** Demetrios (sole operator)
**Implementation target:** the iOS app — `~/dev/beagle/beagle-ios` on the Mac
(`Sounio-Language-MacBook`, M5 Max), branch **`integration/ios-physiome-merge`** (the
live companion branch — AuroraPresence, no dog). Build+install via `ssh mac`.
**Server dependency (already shipped + live):** `POST /api/mobile/v1/synthesize` —
see `docs/superpowers/specs/2026-07-17-proactive-synthesis-design.md`.

## Motivation

The phone-side of the proactive-synthesis tool. The server endpoint is live and
proven; this gives Demetrios a deliberate place ON HIS PHONE to open when he wants to
organize his head (the CPC26 poster wound) — a topic (or the last few days) turns his
own recorded thinking into a streamed, sayable 5-block map.

## THE HARD WALL (client-side — non-negotiable, mirrors the server spec)

The intimate chat's naturalness is the value; a structured synthesis surface must
never contaminate it. Client-side invariants:

1. **Separate surface.** Synthesis is its OWN view (`SynthesisView.swift`), presented
   as a dedicated sheet — never inline in the conversation, never a chat message.
2. **Deliberate, never automatic.** It opens only when the user taps "Sintetizar" in
   the drawer footer. Nothing auto-triggers it.
3. **Result never enters the chat.** The streamed synthesis lives ONLY in the sheet's
   local view state. It is NEVER appended to `ConversationStore` / the message list,
   and is NEVER persisted (no SwiftData write, no capture). Dismissing the sheet
   discards it.
4. **Register isolation is inherited from the server** — the client only renders what
   the endpoint streams; it adds no synthesis voice of its own to the chat.

## Placement

The app's `ChatScreen` already uses ONE enum-driven sheet (`.sheet(item: $activeSheet)`)
whose drawer footer opens the dedicated Data screen (Agora/physiome) and
`ThoughtCaptureView`. Add synthesis the same way:
- A new case `.synthesize` in the `activeSheet` enum.
- A **"Sintetizar"** entry in the drawer footer, next to Data + Capture, that sets
  `activeSheet = .synthesize`.
This keeps synthesis out of the chat flow while making it reachable on purpose —
consistent with the existing information architecture and the wall.

## The screen (`SynthesisView.swift`)

A single self-contained SwiftUI view with three visual states:

```
Síntese                         ✕
┌───────────────────────────────┐
│ sobre o quê?  (vazio = últimos │   ← topic TextField
│               dias)            │
└───────────────────────────────┘
            [ Sintetizar ]           ← primary action

## Elevator                          ← result area: streamed markdown
Você quer falar sobre…                 (block-aware renderer, reused)
## Espinha
…
```

- **idle:** topic field + "Sintetizar" button; empty result area.
- **streaming:** button shows "sintetizando…" (disabled); the result area fills live
  as tokens arrive; an unobtrusive stop/cancel is available.
- **done:** full synthesis shown; a "nova síntese" affordance resets to idle; a
  copy/share action on the rendered text.
- **insufficient / error:** the honest server message (or a local network-error line)
  rendered plainly, with a retry.

**Rendering:** reuse the chat's existing block-aware markdown renderer (the one in
`Companion/MessageBubble.swift` / `MarkdownMessage`) so typography matches and the 5
`##` blocks render as headings — do NOT write a second markdown renderer.

**Input contract:** the topic field maps to the request `topic`; empty → omit topic
(server falls back to recent mode, default 7-day window). No window control in v1.

## Networking (`SynthesisClient`)

A small streaming client, isolated in its own type so it is unit-testable:
- `POST {baseURL}/api/mobile/v1/synthesize` with JSON body `{ "topic": <string?> }`.
- Auth + base URL: **reuse** whatever the chat already uses (the cockpit base URL +
  `x-cockpit-token` header — see how `ConversationStore` / the existing exocortex
  client, `ExocortexQuery.swift`, obtains them; do not introduce a new config path).
- Response is SSE (`text/event-stream`): read `URLSession.bytes(for:)` line by line,
  parse `data: {json}` lines, extract `.token` (append to the running text) and stop
  on `{"done": true}` (surfacing `insufficient`/`error` fields).
- Expose the stream to the view as an `AsyncThrowingStream<String, Error>` (token
  deltas) or an `@Observable` accumulator — the view appends deltas to its state.

## Data flow

```
tap "Sintetizar" in drawer footer → activeSheet = .synthesize
  → SynthesisView(topic field + button)
    → tap Sintetizar → SynthesisClient.stream(topic:)
      → POST /api/mobile/v1/synthesize (SSE)
      → for-await token deltas → append to @State markdown string → render live
      → done/insufficient/error → terminal state
  → dismiss sheet → local state discarded (nothing written anywhere)
```

## Error handling

- **Network failure / non-2xx:** stop, show an inline error line + retry; never fake a
  synthesis.
- **Insufficient material:** the server streams the honest "Ainda não tenho o
  bastante…" token then `done:{insufficient:true}` — render it as-is (no special UI
  beyond showing it's not a full synthesis).
- **Cancel:** cancelling the task stops the stream and returns to idle; partial text
  discarded.

## Testing

- **`SynthesisClient` SSE parsing (unit-testable, no network):** feed a canned byte
  sequence of `data:` lines (tokens + a `done`) through the line parser and assert the
  emitted token sequence + terminal signal. This is the one genuinely unit-testable
  unit; iOS view code is verified by build + on-device.
- **Build + on-device live-verify:** build `BeagleCockpit` for the device, install via
  `devicectl`, open the drawer → Sintetizar → enter a real topic ("redes semânticas em
  depressão") → confirm the 5-block markdown streams in and is grounded; enter a
  nonsense topic → confirm the honest insufficient message; confirm the result does NOT
  appear in the chat after dismissing.

## Out of scope (v1)

- **History of past syntheses.** v1 is ephemeral: open, synthesize, read, dismiss. A
  persisted synthesis archive (in a derived-artifacts space, explicitly excluded from
  chat grounding) is a possible later feature — not now.
- **Window control / advanced options** (the no-topic window is fixed at the server
  default). No streaming-vs-block toggle (always streams).
- **Deep-think mode** (the server v1 is fast-recall only).

## Success criteria

1. The wall holds on the client: synthesis is a separate sheet; its result never
   enters `ConversationStore`, never persists, and never appears in the chat.
2. Opening the drawer → Sintetizar → a topic streams a grounded 5-block markdown
   synthesis, rendered with the chat's markdown typography.
3. A nonsense topic shows the honest insufficient message, never a fabrication.
4. `SynthesisClient` SSE parsing is unit-tested; the screen is built + live-verified on
   his iPhone.
