# Platform State + Phone tmux Terminal (replace Termius) — Design

**Date:** 2026-07-19
**Status:** approved (design), pending implementation plan
**Owner:** Demetrios (sole operator)
**Repos:** `beagle` (cockpit server `apps/project-cockpit/`, k8s `k8s/`), iOS `~/dev/beagle/beagle-ios` branch `integration/ios-physiome-merge` (Mac).

## Motivation

Two joined needs, one root:
1. **Drive the t560 tmux from the phone, away from the laptop, without Termius.** The
   user runs his real work in t560 tmux sessions (`beagle` = the persistent Claude
   session, `darwin-ops` = cluster operator). He wants to open and TYPE INTO them from
   the Beagle app.
2. **The companion knows the platform state live** — Sounio (branch/gates/themes), his
   sessions (who's alive, on what), cluster — fresh in-conversation (a `## Estado da
   plataforma agora` block, like `## Agora` for body/sky).

The key discovery: **the whole terminal stack already exists and is proven** — iOS
`AgentSessionView` + `TerminalContentView` (live WebSocket ANSI terminal) ↔ cockpit
`agent-routes.mjs` WebSocket **PTY bridge** (`node-pty` + `kubectl exec`). Today it
shells into workspace pods. The work is to point it at his t560 tmux, and add the
read-only state block. **Reuse, don't rebuild.**

## Architecture (measured decision)

Measured facts that drove it: the cockpit's only t560-reaching capability is
**`kubectl exec`** (RBAC via SA `project-cockpit`; no ssh key to t560); the old Rust
`pty-gateway` source is gone (only `target/` remains); the tmux sockets live at
`/tmp/tmux-1000/` (`default` = beagle, `clops` = darwin-ops), uid 1000, hostPath-mountable.

**Chosen: one t560-pinned "bridge" pod, reached by the cockpit's existing `kubectl exec`.**
It serves BOTH the interactive attach AND the read-only state — one access point, no ssh
keys, no reviving lost code.

```
                       ┌──────────────── t560 (control-plane node) ───────────────┐
iPhone (Beagle app)    │  bridge pod (NEW, small):                                │
  AgentSessionView ──WS──►  cockpit PTY bridge ──kubectl exec──►  tmux -S /tmp/... │
  (reuse terminal)     │     (agent-routes.mjs, reuse)              attach -t <s>  │
                       │                                          ▲ shared attach  │
  companion chat ──HTTP──► cockpit state endpoint ─kubectl exec─► tmux ls + git    │
  "## Estado agora"    │     (NEW, read-only)                     (~sounio, ro)    │
                       │  hostPath: /tmp/tmux-1000 (rw), ~/sounio (ro); uid 1000   │
                       └──────────────────────────────────────────────────────────┘
```

## THE WALL / privacy (non-negotiable)

- **Pane content (the live terminal) is shown ONLY in the deliberate terminal surface**
  the user opens (like Termius) — it is NEVER sent to the companion's grounding, never
  written to memory, never synthesized. His terminals hold secrets.
- **The companion state block is METADATA ONLY** — session name, attached?, idle time,
  window title / last command; Sounio branch/gate/themes; cluster status. NO pane
  dumps, NO command output bodies.
- The bridge pod exposes **only** the tmux sockets (rw) + the sounio repo (ro) — nothing
  else of t560. Reached only through the cockpit's authenticated routes (cockpit token).

## Components

### 1. t560 bridge pod (`k8s/platform-bridge/`)
- **What:** a tiny always-on pod, `nodeName: t560-proxmox`, `runAsUser: 1000` (devsounio),
  image with `tmux` + `git` + a coreutils base. hostPath volumes: `/tmp/tmux-1000` (rw,
  for tmux client socket access) and the sounio repo `/home/devsounio/sounio` (ro).
  Idle `sleep infinity` command; it exists to be `kubectl exec`-ed.
- **Why:** gives the in-cluster cockpit a `kubectl exec` handle to t560's tmux + repo
  without ssh. One pod, both interactive + read-only uses.
- **Depends on:** nothing new; standard k8s + hostPath + the tmux socket perms (uid 1000).

### 2. Cockpit — interactive attach (extend `agent-routes.mjs`)
- **What:** register a t560-session target in the PTY bridge. The WS handler, for a
  t560-kind session, execs `kubectl exec -i <bridge-pod> -- tmux -S /tmp/tmux-1000/<socket> attach -t <session>`
  instead of the agent-pod shell. Everything else (node-pty framing, WS streaming,
  resize) is reused unchanged.
- **Session registry:** a small allowlist of exposed sessions → `{kind, socket, target}`
  (e.g. `t560-beagle → {default, beagle}`, `t560-darwin-ops → {clops, darwin-ops}`). Only
  allowlisted sessions are attachable (no arbitrary command injection).
- **Shared attach:** attaching a live session (beagle is attached on the laptop) yields a
  shared tmux client — phone + laptop see/drive the same screen. Desired.

### 3. Cockpit — read-only state endpoint (NEW, `apps/project-cockpit/server/`)
- **What:** `GET /api/mobile/v1/platform-state` (authed). It `kubectl exec`s the bridge
  pod for safe read-only commands and returns JSON:
  - `sessions`: from `tmux -S <socket> list-sessions -F '#{session_name}|#{session_attached}|#{session_activity}|#{window_name}'` per socket → `[{name, attached, idleSeconds, window}]`.
  - `sounio`: `git -C ~/sounio symbolic-ref --short HEAD` (branch); recent 5 commit subjects; gate status from `test-results.xml` if present (green/red counts). Best-effort per probe.
  - `cluster`: reuse the cockpit's existing mission-control / cluster-truth summary (already in-cluster).
- Pure helpers (`buildPlatformState(raw)`) unit-tested; the kubectl-exec + parse is the shell.

### 4. iOS — expose t560 sessions (reuse `AgentSessionView`)
- **What:** add t560 sessions to the `AgentKind` registry (e.g. `.t560Beagle`, `.t560DarwinOps`),
  each mapping to the WS path `/ws/projects/<slug>/agent/<kind>`. The existing
  `AgentSessionView` + `TerminalContentView` render + drive them unchanged — a new entry in
  the agent picker, nothing else.

### 5. Companion — the live state block (`mobile-routes.mjs`)
- **What:** `fetchPlatformState()` (best-effort, fail-soft, like the other `fetch*`) calls
  the cockpit `/platform-state`, and assembles a `## Estado da plataforma agora` grounding
  section (Sounio: branch/gate/themes · sessões: beagle ativa / darwin-ops idle 3h ·
  cluster: OK) placed with the dynamic `## Agora` block. If the fetch fails → the block is
  omitted; the chat never blocks.
- **Wall:** this block carries ONLY the metadata from #3 — never pane content.

## Data flow

- **Terminal:** app → open t560 session in AgentSessionView → WS `/ws/.../agent/t560-beagle`
  → cockpit PTY bridge → `kubectl exec bridge-pod -- tmux attach -t beagle` → live ANSI both ways.
- **State:** chat turn → `fetchPlatformState()` → cockpit `/platform-state` → kubectl exec
  bridge-pod (tmux ls + git) → JSON → `## Estado da plataforma agora` in the grounding.

## Error handling (fail-soft everywhere)
- Bridge pod down / kubectl-exec fails → terminal shows a clean "sessão indisponível";
  the state block is omitted from grounding (chat unaffected).
- A session not in the allowlist → refused (no arbitrary attach).
- Attaching a non-existent/dead session → tmux errors surfaced in the terminal, not a crash.

## Testing
- **`buildPlatformState` (pure):** raw tmux-ls + git strings → the safe JSON shape; asserts
  NO pane content, correct session/branch/gate parsing. No cluster.
- **Session allowlist (pure):** an un-allowlisted kind is refused; an allowlisted one maps to
  the right `tmux -S <socket> attach -t <target>` argv (no injection).
- **Live-verify:** deploy the bridge pod → `kubectl exec` it manually to confirm `tmux ls`
  + attach work → open a t560 session in the app terminal and type → confirm shared attach
  (laptop sees it) → open a chat and confirm the `## Estado agora` block shows the sessions,
  and that NO pane content appears in the companion.

## Scope note (decomposition)
Two consumers share the bridge pod and can ship independently:
- **A — the terminal** (bridge pod + cockpit attach + iOS AgentKind): the primary Termius
  replacement.
- **B — the state block** (cockpit `/platform-state` + companion grounding): the read-side.
The plan builds the bridge pod first (shared foundation), then A, then B.

## Out of scope (v1)
- Non-t560 sessions / the cockpit workspace fleet (already exists) / the coord board.
- Persisted history of platform state (the user chose live-only).
- Session lifecycle control from the phone (start/kill sessions) — attach/read only.
- Full mobile keyboard ergonomics (arrow/ctrl keys) beyond what TerminalContentView already has.

## Success criteria
1. From the phone, the user opens `beagle`/`darwin-ops` and types into them — shared with
   the laptop — replacing Termius, gated by the cockpit token.
2. The companion's `## Estado da plataforma agora` shows live Sounio + session + cluster
   state, refreshed each turn, and NEVER leaks pane content.
3. The bridge pod exposes only tmux + sounio; un-allowlisted attach is refused.
4. Pure helpers unit-tested; the flow live-verified on the device.
