# Beagle Command Deck — the platform in his pocket, with an acting copilot

**Date:** 2026-07-19 (bold rewrite — supersedes the timid v1 of this file)
**Status:** approved-in-spirit (bold scope), pending phased implementation plans
**Owner:** Demetrios (sole operator)
**Repos:** `beagle` (cockpit `apps/project-cockpit/`, `k8s/`), iOS `~/dev/beagle/beagle-ios` branch `integration/ios-physiome-merge`.
**Mode:** written under the standing directive to be BOLD — full vision on paper, disciplined phased delivery, invariants non-negotiable. See [[feedback_be_bold]].

## The vision

Not "attach to two tmux sessions from the phone." The whole platform — **known,
driveable, and worked-alongside — from his pocket**:
1. **Command deck** — open, drive, create, kill, switch any of his t560 sessions (and the
   cockpit fleet) from the phone. Termius not replaced — superseded.
2. **Live consciousness** — the companion always knows the platform state (Sounio, sessions,
   cluster) AND **surfaces it proactively**: "darwin-ops idle 3h, the Sounio gate went red on
   your last push — want me to look?" In his register, gentle, never spammy.
3. **Acting copilot** — with his OK, the companion **does**: fire a gate, revive a session,
   run a doctor, kick a job. Not an observer — a peer.

The whole terminal stack already exists and is proven (iOS `AgentSessionView` +
`TerminalContentView` ↔ cockpit `agent-routes.mjs` WebSocket PTY bridge via `node-pty` +
`kubectl exec`). We build the deck ON it.

## THE INVARIANTS (what makes boldness safe, not what limits it)

These are absolute; every phase inherits them. Boldness lives in scope, rigor lives here.
1. **Pane content stays in the terminal.** The live terminal (his screens, his secrets) is
   NEVER sent to the companion's grounding, NEVER written to memory, NEVER synthesized. Only
   the deliberate terminal surface he opens shows it.
2. **The companion state/awareness is METADATA ONLY** — session name/attached/idle/window,
   Sounio branch/gate/themes, cluster status. No pane dumps, no output bodies.
3. **Every action is allowlisted + confirmed.** The acting copilot can run ONLY a fixed,
   reviewed set of named actions (run gate, restart session, doctor, cancel job), each shown
   to him and executed only on explicit confirm. No arbitrary command from a model. No
   `rm -rf`. The allowlist is the leash.
4. **Provenance holds** — his words vs the companion's inferences stay distinct (the
   [[project_memory_provenance]] ethos); a proactive nudge is marked as the system's read of
   state, never as his testimony.
5. **The intimate chat's naturalness is untouched** — proactive nudges + acting are a
   SEPARATE capability/surface, not bleeding into the companion's warm conversation (the same
   wall as [[project_companion_proactive_synthesis]]).

## Architecture (one bridge, three consumers)

Measured decision (see below): the cockpit's only t560-reaching capability is `kubectl exec`
(SA `project-cockpit`, no ssh key to t560); the old Rust `pty-gateway` source is gone; tmux
sockets live at `/tmp/tmux-1000/` (`default`=beagle, `clops`=darwin-ops), uid 1000,
hostPath-mountable. So: **one t560-pinned bridge pod, reached by the cockpit's existing
`kubectl exec`, serving all three consumers** — no ssh keys, no reviving lost code.

```
iPhone (Beagle app)          cockpit (in-cluster)              t560 bridge pod (NEW)
  AgentSessionView ──WS────►  PTY bridge (reuse) ──kubectl exec──► tmux attach/new/kill
  Command deck    ──HTTP───►  /platform-control  ──kubectl exec──► allowlisted actions
  companion chat  ──HTTP───►  /platform-state    ──kubectl exec──► tmux ls + git (ro)
                                                  hostPath: /tmp/tmux-1000 (rw), ~/sounio (ro),
                                                            action scripts (ro); uid 1000
```

## Components

### 0. t560 bridge pod (`k8s/platform-bridge/`) — the shared foundation
Tiny always-on pod, `nodeName: t560-proxmox`, `runAsUser: 1000`, image with `tmux`+`git`+
coreutils. hostPath: `/tmp/tmux-1000` (rw), sounio repo (ro), and a reviewed `actions/`
script dir (ro). `sleep infinity`; exists to be `kubectl exec`-ed. Exposes ONLY these mounts
— nothing else of t560.

### Phase 1 — Command deck (the Termius supersession)
- **Cockpit interactive attach:** extend `agent-routes.mjs` PTY bridge with a t560-session
  target → `kubectl exec -i <bridge> -- tmux -S /tmp/tmux-1000/<socket> attach -t <session>`.
  Reuses node-pty framing/streaming/resize. Shared attach (phone + laptop drive the same
  screen — desired).
- **Cockpit session control:** `POST /api/mobile/v1/platform-control` (authed) with an
  allowlisted verb: `attach|new|kill|list|switch-window`, mapping to `tmux` argv against the
  allowlisted socket/session (no free-form command). New sessions get a naming convention.
- **iOS:** add t560 sessions to the `AgentKind` registry (`.t560Beagle`, `.t560DarwinOps`, +
  a "new session" affordance); the existing `AgentSessionView`/`TerminalContentView` render +
  drive them. A deck picker listing sessions (from `/platform-state`) with attach/new/kill.
- **Deliverable:** open/drive/create/kill his sessions from the phone. Live-verified on device.

### Phase 2 — Live consciousness (know + surface)
- **Cockpit read-only state:** `GET /api/mobile/v1/platform-state` → kubectl-exec the bridge
  for `tmux list-sessions -F '...'` (name|attached|idle|window) per socket + `git -C ~/sounio`
  (branch, 5 recent subjects, gate from `test-results.xml`) + reuse the cockpit's existing
  mission-control/cluster-truth summary. Pure `buildPlatformState(raw)` → safe JSON (unit-tested).
- **Companion grounding:** `fetchPlatformState()` (fail-soft) → a live `## Estado da
  plataforma agora` block beside `## Agora`. Metadata only (invariant #2).
- **Proactive nudge (bold):** a per-turn diff of a few watched signals (gate red↔green,
  session idle-crossing, a failed job) → the companion MAY raise ONE gentle nudge in its
  register when something meaningful changed, marked as the system's read (invariant #4), and
  never in the intimate flow when he's mid-emotion (respect the floor). Opt-out honored.

### Phase 3 — Acting copilot (do, with his OK)
- **Cockpit action runner:** `POST /api/mobile/v1/platform-action` (authed) with an
  allowlisted action name → kubectl-exec the bridge running the matching reviewed script in
  the ro `actions/` dir (e.g. `run-gate <name>`, `revive-session <kind>`, `doctor <target>`,
  `cancel-job <id>`). Returns a SUMMARY (exit + tail), never a raw stream to the companion.
- **Confirmation UX:** the companion proposes an action ("quer que eu rode `make madaros-full-gate`?");
  it executes ONLY on his explicit confirm (a button / an unambiguous yes). Invariant #3.
- **Deliverable:** the companion can run a gate / revive a session / doctor / cancel a job on
  his say-so, and report the result — a peer, not an observer.

## Data flow (per surface)
- Terminal: app → AgentSessionView → WS `/ws/.../agent/t560-<sess>` → PTY bridge → kubectl exec
  tmux attach → live ANSI both ways.
- Control: app deck → `/platform-control {verb, session}` → kubectl exec tmux <verb>.
- State: chat turn → `fetchPlatformState()` → `/platform-state` → kubectl exec (tmux ls + git) → block.
- Action: companion proposes → he confirms → `/platform-action {name, args}` → kubectl exec
  actions/<name> → summary → companion reports.

## Error handling (fail-soft)
Bridge down → terminal shows "sessão indisponível"; state block omitted (chat unaffected);
control/action returns a clean error, never a crash. Un-allowlisted verb/action/session →
refused. Dead session attach → tmux error surfaced in the terminal.

## Testing
- Pure, unit-tested: `buildPlatformState(raw)` (safe JSON, no pane content); the allowlist
  resolvers for control verbs + action names (un-allowlisted refused; allowlisted → exact
  argv, no injection); the proactive-nudge diff (fires only on a real watched change, respects
  the floor).
- Live-verify per phase on the device: attach+type+create+kill; the `## Estado agora` block +
  a real nudge; a confirmed action running + reporting; and the invariant checks — NO pane
  content in the companion, un-allowlisted attempts refused.

## Phasing (bold vision, provable steps)
Bridge pod (0) → **Phase 1 command deck** (the thing he most wants — ship first) → **Phase 2
consciousness** → **Phase 3 acting copilot**. Each phase is its own implementation plan; each
ends with a device-verified deliverable. The vision is committed; the delivery is disciplined.

## Out of scope (even bold)
- Actions outside the reviewed allowlist (never free-form model execution).
- Non-his sessions / other users. Persisted platform-state history (live-only, his call).
- Full desktop-terminal ergonomics beyond what TerminalContentView already renders.

## Success criteria
1. He drives beagle/darwin-ops (and creates/kills sessions) from the phone, shared with the
   laptop — Termius superseded, cockpit-token gated.
2. The companion knows the live platform state, surfaces meaningful changes proactively in his
   register, and NEVER leaks pane content or breaks the intimate chat.
3. With his explicit OK, the companion runs an allowlisted action and reports the result.
4. Every invariant holds; pure helpers unit-tested; each phase live-verified on device.
