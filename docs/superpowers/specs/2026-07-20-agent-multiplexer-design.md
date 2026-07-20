# Agent Multiplexer — our own, native, unbreakable, unified (working codename: **Loom**)

**Date:** 2026-07-20
**Status:** design approved (shape + protocol + engine v1 + iOS client via mockup); pending spec review → writing-plans
**Owner:** Demetrios (sole operator)
**Repos:** `beagle` (broker + protocol under `apps/`/`k8s/`), iOS `~/dev/beagle/beagle-ios` branch `integration/ios-physiome-merge`.
**Supersedes for the deck surface:** the tmux/zellij attach of the Command Deck ([2026-07-19-platform-state-and-tmux-terminal-design.md]) becomes a *transitional adapter* here, then retires.
**Mockup:** the approved iOS client — three screens (Sessão / Frota / Novo agente).

## The vision

Not "a tmux clone." An **agent workspace** — pleasant on the MacBook *and* the phone —
where his fleet of AI agents (codex, claude, cursor, glm, kimi, grok, opencode, local)
each lives in a persistent session, and the whole thing is **native, unbreakable, and
unified across devices**. Four goals, all first-class (his call):

1. **Native mobile UX** — switch/add agents by touch; a tab/agent bar that *cannot*
   disappear (it is app chrome, not terminal text); real keyboard; no Ctrl-t gymnastics.
2. **Never breaks** — never garbles, never freezes without recovery; sessions auto-recover;
   a stuck agent is visible and resettable in one tap.
3. **Mac + phone unified** — the same sessions on both, live; each rendered at its own size.
4. **Built for agents** — status per agent (running / waiting-for-you / stuck / done / idle),
   a fleet dashboard, one-tap reset — not generic shells.

### The core insight (why this is tractable, not a moonshot)

Today's pain is **not** the multiplexer logic (tmux/zellij work) — it is their *chrome*
(tab bar, pane borders, status line) drawn as **terminal text** on a small screen. So:
**our engine has no chrome.** Each agent = one raw persistent PTY. The **native client
draws all tabs/panes/status in SwiftUI**, and the terminal emulator (SwiftTerm) only ever
renders *one program's* output per pane — never a nested multiplexer's UI. The rendering
class of bug we fought all day **disappears by construction.**

## The invariants (what makes boldness safe)

Absolute; every phase inherits them.
1. **No chrome in the engine.** The engine manages PTYs + state only. All layout, tabs,
   panes, and status live in the client. The emulator renders one program per pane.
2. **The agent bar is native and cannot be clobbered.** A focused/fullscreen program can
   never erase the switcher, because the switcher is SwiftUI, not bytes in the terminal.
3. **Persistence is the engine's job.** A session survives client disconnect and (for owned
   sessions) is held by a daemon that owns the PTY master. Leaving a view only detaches.
4. **Every spawn/kill/reset is allowlisted.** Agents launch only from a fixed, reviewed
   catalog of launch recipes; control verbs are `create|kill|reset` only. No free-form
   command from a model or a request. The catalog + verb set is the leash.
5. **The engine is swappable.** The client talks *only* the protocol below. v1 (pragmatic)
   and v2 (Sounio broker) are interchangeable behind it. No client change to swap engines.
6. **Sensitive content stays where it is shown.** Live pane bytes are never sent to the
   companion grounding, memory, or synthesis (the same wall as
   [[project_companion_proactive_synthesis]]).

## Architecture (three layers, one swap boundary)

```
 iPhone + Mac (native clients, SwiftUI + SwiftTerm)
        │  one WebSocket per HOST (tailnet, x-cockpit-token gated)
        │  ── the PROTOCOL (the swap boundary) ──
        ▼
 Broker / engine (NO chrome) — runs on any host: cluster pod AND Mac-local
   session sources:
     • OwnedPtySession   — broker spawns the agent, holds the PTY master (the future)
     • AdaptedSession    — attaches an existing tmux/zellij pane (transitional; retires)
   holds: scrollback ring per session · agent state · resize · lifecycle
        ▼
 v1 = Node/TypeScript broker (reuse cockpit stack)   →   v2 = Sounio broker (sovereign endgame)
```

## The protocol (the swap boundary) — carefully fixed

**One WebSocket per host.** The client opens one connection, receives **state (metadata)
for all** sessions (cheap → the dashboard), and **byte streams only for subscribed** panes
(the active pane + one prefetch → light on cellular). Transport: WebSocket over tailnet,
the existing `x-cockpit-token` gate. Framing v1: JSON control + base64 data (a `data`/binary
frame optimization is a later, non-breaking change).

**Client → engine**

| msg | fields | meaning |
|-----|--------|---------|
| `hello` | `token`, `client`, `proto` | auth + version handshake |
| `list` | — | request the session snapshot |
| `subscribe` | `sid` | start receiving `data` for `sid`; triggers a `scrollback` replay |
| `unsubscribe` | `sid` | stop receiving `data` for `sid` |
| `input` | `sid`, `data` | keystrokes/bytes → the PTY stdin |
| `resize` | `sid`, `cols`, `rows` | set the PTY winsize for `sid` |
| `create` | `kind`, `title?` | spawn a new agent from the catalog (owned session) |
| `kill` | `sid` | terminate the session |
| `reset` | `sid` | kill + re-spawn the same recipe (resume where supported) |

**Engine → client**

| msg | fields | meaning |
|-----|--------|---------|
| `sessions` | `[{sid,title,kind,source,state,detail,cols,rows}]` | full snapshot (sent on change) |
| `scrollback` | `sid`, `bytes` | replay of the recent ring buffer on subscribe |
| `data` | `sid`, `bytes` | live output for a subscribed session |
| `state` | `sid`, `state`, `detail` | agent state change for ANY session (drives the dashboard) |
| `exit` | `sid`, `code` | the session's process exited |
| `error` | `sid?`, `message` | fail-soft error surface |

`state` ∈ `running | idle | waiting | stuck | exited`. Both engines implement exactly this.

## Engine v1 (the pragmatic broker)

**Language:** Node/TypeScript, reusing the cockpit stack (`ws`, `node-pty`, the auth gate,
tailnet exposure) — the fastest path already proven with SwiftTerm. Deployed in the cluster
(its own small pod, or extending `project-cockpit`). Swappable for Sounio later.

**Session-source abstraction** — a session is anything the broker can
`(spawn|attach) + (read/write/resize) + reportState`. Two implementations day 1:

- **`OwnedPtySession`** — the broker `node-pty`-spawns the agent from a **catalog recipe**
  and **holds the master fd** (persists across client disconnect). No tmux/zellij underneath.
  This is the sovereign future; new agents are owned.
- **`AdaptedSession`** — attaches an existing tmux/zellij pane via `kubectl exec` (reuses the
  Command Deck's `deckExec`/`kubectlArgv`). Covers today's running agents (the compiler
  `codex-2` etc.) on day 1. **Transitional** — retires once owned sessions carry his work.

The client sees both uniformly (invariant #1).

**The agent catalog** (invariant #4) — a reviewed map `kind → launch recipe`
`{ argv, env, home, cwd, resumeArgv? }`, e.g.:
`claude → claude-code`, `codex → codex resume --last (HOME=.agents/<n>)`,
`cursor → cursor-agent`, `glm`, `kimi`, `grok`, `opencode`, `local → local GPU agent`,
plus `shell` (raw). `create{kind}` spawns the recipe; `reset` re-runs it (resume where the
tool supports it, per the codex-2 recovery pattern). No request input reaches a shell.

**Persistence + redraw:** a per-session scrollback **ring buffer** (last N KB) replayed on
`subscribe`; plus the proven **resize-on-attach redraw kick** (a fresh client's first layout
resize makes full-screen TUIs repaint). Owned sessions survive client disconnect because the
daemon holds the master fd; adapted sessions survive because tmux/zellij do.

**State detection (v1, minimal):** `running` (recent output / process busy), `exited`
(process gone), `stuck` (no output for T *and* not at an idle prompt). `waiting` / `idle`
are best-effort in v1 from output patterns; rich detection is Phase 4.

## The iOS client (Section 3 — the approved mockup, in words)

Native SwiftUI + SwiftTerm (≥1.15, the render fix from today). Dark cockpit by choice
(the app is dark-forced). Ergonomics pushed to the thumb.

**Screen — Sessão:** minimal top (active agent name + status pill + detach icon); the
**terminal takes the room** (SwiftTerm, one program, faithful); a thumb input bar + a
scrollable accessory key row (esc/ctrl/tab/arrows). At the very bottom, the **always-on
agent bar** — a grip handle, the active agent (green dot), the fleet's status dots, `+N`,
and a `+`. Swipe up → the fleet drawer. **It cannot disappear.**

**Screen — Frota (fleet dashboard):** every session as a card with a brand-tinted glyph,
name, **status pill** (rodando / esperando você / travado / concluído / ocioso), and last
activity. The stuck one shows **Reiniciar** (one-tap `reset` — the codex-2 fix as a button).
A prominent **＋ Novo agente** at the top. Lives as an app tab (Companion | Agentes | Dados)
*and* is reachable by the swipe-up from Sessão.

**Screen — Novo agente (catalog):** a 2-col grid of agent kinds, each brand-tinted:
**Claude · Codex · Cursor · GLM · Kimi · Grok · OpenCode · Local** (+ raw shell), with the
real `kind` as subtitle. Tap → `create{kind}` → a new owned session, no zellij involved.

**Brand tints:** claude âmbar `#E2A568` · codex verde `#6EE6AA` · cursor azul `#8FA8FF` ·
glm violeta `#C58FF0` · kimi ciano `#7FD4E6` · grok aço `#C3CCD8` · opencode ouro `#E6C86E` ·
local ardósia `#8B93B8`. **Status colors (separate from accent):** run `#6EE6AA` · wait
`#E6B24C` · stuck `#E8706E` · done `#5EC8C0` · idle `#7D84A6`.

**Client state model:** one `HostConnection` per host holds the session list + all states
(from `state`/`sessions`), and per-visible-pane a `TerminalStore` fed by `data` into a
SwiftTerm `DeckTerminalView`. Switching tabs = show another pane; no reconnect.

## Data flow (per action)
- **Open:** app → 1 WS per host → `hello`+`list` → native fleet + states → tap agent →
  `subscribe` → `scrollback`+`data` → SwiftTerm → type → `input`.
- **New agent:** catalog tap → `create{kind}` → engine spawns owned recipe → `sessions`
  update → new native tab.
- **Reset stuck:** dashboard `Reiniciar` → `reset{sid}` → engine kill+respawn recipe →
  `state` running.
- **Resize:** SwiftTerm layout → `resize{sid,cols,rows}` → engine winsize → program repaints.

## Error handling (fail-soft)
Host down → "host indisponível", client auto-reconnects, other hosts unaffected. Session
gone → clean `exit`; `reset` revives. Un-allowlisted `kind`/verb → refused. Bridge/adapter
failure → that session errors, the fleet stays. No action ever crashes the client.

## Testing
- **Pure, unit-tested:** the protocol codec (encode/decode every message); the catalog
  recipe resolver + `AdaptedSession` argv (exact argv, injection refused); the state
  classifier (running/exited/stuck from fixtures); the scrollback ring.
- **Live-verify per phase on device:** open/switch/create/reset agents; a stuck agent reset;
  faithful full-screen render (tmux + zellij + a bare agent); the invariants (agent bar never
  disappears; no pane bytes in the companion).

## Phasing (bold vision, provable steps)
- **Phase 1 — Protocol + broker v1 (cluster) + iOS client.** Open his agents as native tabs
  (owned + adapted), render clean (SwiftTerm ≥1.15), switch by touch, never freeze, catalog
  to spawn new agents, one-tap reset. *Proves the whole architecture. Device-verified.*
- **Phase 2 — Mac client + Mac-local host.** The same client on macOS; the broker binary also
  runs on the Mac → local + cluster sessions unified in one app, each host a WS.
- **Phase 3 — Sovereign engine (Sounio v2).** Gated by a **1-day FFI spike**: call
  `ioctl(fd, TIOCSWINSZ, &winsize)` from Sounio via `extern "C"` (struct-by-pointer). If it
  passes, write the broker in Sounio (bind `forkpty`/`ioctl`/`termios`/`poll`/`socket` on the
  live `stdlib/ffi` + `net`/`async`), swap it behind the protocol. A Sounio production milestone.
- **Phase 4 — Rich agent awareness.** Precise `waiting`/`idle`/`stuck` detection, proactive
  fleet nudges (in his register, the wall intact), per-agent history. Seed ships in Phase 1.

## Out of scope (even bold)
- Free-form spawn outside the catalog. Copy-mode / scrollback search parity with tmux in v1
  (ring replay only). Splitting one agent's terminal into sub-panes in v1 (one program per
  session; layout is the client's tabs). Non-his sessions / multi-user.

## Success criteria
1. He drives his whole fleet — switch, add (any of 8 kinds), reset — from the phone, native,
   thumb-reachable, and the agent bar never disappears.
2. tmux, zellij, and bare agents all render faithfully; nothing garbles; a stuck agent is
   visible and reset in one tap; sessions auto-recover.
3. Phase 2: the same sessions live on Mac + phone, each at its own size.
4. Phase 3: the engine is the Sounio broker, swapped with zero client change.
5. Every invariant holds; pure helpers unit-tested; each phase device-verified.
