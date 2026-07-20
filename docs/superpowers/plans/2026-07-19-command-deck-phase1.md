# Command Deck — Phase 1 (drive t560 tmux from the phone) Implementation Plan

> **Execution:** controller-driven — cockpit tasks in the `beagle` repo (t560), iOS tasks via `ssh mac` on `~/dev/beagle/beagle-ios` branch `integration/ios-physiome-merge`. Steps use checkbox (`- [ ]`).

**Goal:** From the Beagle app, open and drive his live t560 tmux sessions (`beagle`, `darwin-ops`, `clops`) — shared with the laptop — replacing Termius.

**Architecture:** One t560-pinned bridge pod (debian:trixie-slim, tmux 3.5a to match t560, hostPath tmux socket dir) reached by the cockpit's existing `kubectl exec` PTY bridge. A t560-session kind resolver + a session-list/control endpoint. iOS reuses `TerminalStore` + `TerminalContentView` (no pod lifecycle) behind a new deck.

**Tech Stack:** k8s (hostPath, control-plane node), Node ESM (`node:test`), `node-pty` (existing), SwiftUI (existing `TerminalStore`/`TerminalContentView`), `xcodebuild`+`devicectl`.

## Global Constraints (INVARIANTS — every task inherits, from the spec `2026-07-19-platform-state-and-tmux-terminal-design.md`)

- **Pane content stays in the terminal** — the interactive terminal is NEVER sent to the companion grounding/memory. Phase 1 builds only the terminal + control; the state block (Phase 2) is separate and metadata-only.
- **Allowlist is the leash** — only these exact sessions are attachable/controllable, by fixed name (no free-form command, no injection): `t560-beagle → (socket default, target beagle)`, `t560-darwin-ops → (socket default, target darwin-ops)`, `t560-clops → (socket clops, target clops)`.
- The bridge pod exposes ONLY the tmux socket dir `/tmp/tmux-1000` (rw) and the sounio repo `/home/devsounio/sounio` (ro) — nothing else of t560.
- Auth: the cockpit's existing token gate on `/api/mobile/v1/*` + WS; no new auth path.
- Reuse: do NOT rebuild the terminal — reuse `TerminalStore`/`TerminalContentView` (iOS) and the `node-pty`+`kubectl exec` bridge (cockpit). Do NOT touch the intimate chat.
- t560 facts: tmux **3.5a**, Debian **trixie**; sockets `/tmp/tmux-1000/{default,clops}`, owner uid 1000; cockpit SA `project-cockpit`, ns `beagle`, execs pods already.

---

### Task 0: t560 bridge pod

**Files:**
- Create: `k8s/platform-bridge/bridge.yaml`

- [ ] **Step 1: write the manifest** (`k8s/platform-bridge/bridge.yaml`)

```yaml
# Always-on t560-pinned bridge: gives the in-cluster cockpit a `kubectl exec` handle to
# t560's tmux (attach) + the sounio repo (read-only state), without ssh. tmux 3.5a matches
# t560 (Debian trixie) so `tmux attach` protocol is compatible. Exposes ONLY those mounts.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: platform-bridge
  namespace: beagle
  labels: { app: platform-bridge }
spec:
  replicas: 1
  selector: { matchLabels: { app: platform-bridge } }
  template:
    metadata:
      labels: { app: platform-bridge }
    spec:
      nodeName: t560-proxmox
      tolerations:
        - { key: node-role.kubernetes.io/control-plane, effect: NoSchedule, operator: Exists }
        - { key: sounio.dev/compute, effect: NoSchedule, operator: Equal, value: heavy }
        - { key: sounio.dev/pool, effect: NoSchedule, operator: Equal, value: gpu-batch }
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile: { type: Unconfined }
      containers:
        - name: bridge
          image: debian:trixie-slim
          # runtime install keeps the manifest self-contained (v1); tmux 3.5a from trixie.
          command: ["sh", "-c", "apt-get update >/dev/null 2>&1 && apt-get install -y --no-install-recommends tmux git ca-certificates >/dev/null 2>&1; echo bridge-ready; exec sleep infinity"]
          env:
            - { name: HOME, value: /home/devsounio }
          volumeMounts:
            - { name: tmux, mountPath: /tmp/tmux-1000 }
            - { name: sounio, mountPath: /home/devsounio/sounio, readOnly: true }
          resources:
            requests: { cpu: "50m", memory: 64Mi }
            limits: { cpu: "1", memory: 256Mi }
      volumes:
        - name: tmux
          hostPath: { path: /tmp/tmux-1000, type: Directory }
        - name: sounio
          hostPath: { path: /home/devsounio/sounio, type: Directory }
```

- [ ] **Step 2: deploy + wait ready**

```bash
kubectl apply -f k8s/platform-bridge/bridge.yaml
kubectl -n beagle rollout status deploy/platform-bridge --timeout=180s
```
Expected: rollout succeeds (first start installs tmux, ~30-60s).

- [ ] **Step 3: verify the bridge can see + attach t560 tmux**

```bash
POD=$(kubectl -n beagle get pod -l app=platform-bridge -o jsonpath='{.items[0].metadata.name}')
kubectl -n beagle exec "$POD" -- tmux -S /tmp/tmux-1000/default list-sessions -F '#{session_name}|#{session_attached}'
kubectl -n beagle exec "$POD" -- tmux -S /tmp/tmux-1000/clops list-sessions -F '#{session_name}'
```
Expected: lists `beagle|1`, `darwin-ops|1`, `1|0` (default) and `clops` (clops). If "no server"/perm error → check socket perms (uid 1000) + hostPath.

- [ ] **Step 4: commit**

```bash
git add k8s/platform-bridge/bridge.yaml
git commit -m "platform-bridge: t560-pinned pod exposing tmux socket + sounio repo to the cockpit"
```

---

### Task 1: cockpit t560-session resolver (pure — the allowlist leash)

**Files:**
- Create: `apps/project-cockpit/server/platform-bridge.mjs`
- Test: `apps/project-cockpit/server/platform-bridge.test.mjs`

**Interfaces:**
- Produces: `SESSION_ALLOWLIST`, `isT560Kind(kind): boolean`, `tmuxAttachArgv(kind): string[]|null`, `tmuxControlArgv(kind, verb): string[]|null`, `buildSessionList(rawPerSocket): Array<{kind,name,attached,idleSeconds,window}>`.

- [ ] **Step 1: write the failing tests** (`platform-bridge.test.mjs`)

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { isT560Kind, tmuxAttachArgv, tmuxControlArgv, buildSessionList } from "./platform-bridge.mjs";

test("allowlist: only known t560 kinds; attach argv is exact, no injection", () => {
  assert.equal(isT560Kind("t560-beagle"), true);
  assert.equal(isT560Kind("t560-evil; rm -rf"), false);
  assert.equal(isT560Kind("claude-code"), false);
  assert.deepEqual(tmuxAttachArgv("t560-beagle"), ["-S", "/tmp/tmux-1000/default", "attach", "-t", "beagle"]);
  assert.deepEqual(tmuxAttachArgv("t560-clops"), ["-S", "/tmp/tmux-1000/clops", "attach", "-t", "clops"]);
  assert.equal(tmuxAttachArgv("nope"), null);
});

test("control: only list/kill verbs; exact argv; unknown refused", () => {
  assert.deepEqual(tmuxControlArgv("t560-beagle", "kill"),
    ["-S", "/tmp/tmux-1000/default", "kill-session", "-t", "beagle"]);
  assert.deepEqual(tmuxControlArgv("t560-clops", "list"),
    ["-S", "/tmp/tmux-1000/clops", "list-sessions", "-F", "#{session_name}|#{session_attached}|#{session_activity}|#{window_name}"]);
  assert.equal(tmuxControlArgv("t560-beagle", "exec"), null);
  assert.equal(tmuxControlArgv("bad", "kill"), null);
});

test("buildSessionList: parses tmux -F lines to safe shape (no pane content)", () => {
  const raw = {
    "t560-beagle":     "beagle|1|1721400000|nvim",
    "t560-darwin-ops": "darwin-ops|0|1721390000|htop",
  };
  const out = buildSessionList(raw, 1721400300);
  const b = out.find((s) => s.kind === "t560-beagle");
  assert.equal(b.name, "beagle"); assert.equal(b.attached, true);
  assert.equal(b.window, "nvim"); assert.equal(b.idleSeconds, 300);
  const d = out.find((s) => s.kind === "t560-darwin-ops");
  assert.equal(d.attached, false); assert.equal(d.idleSeconds, 10300);
});
```

- [ ] **Step 2: run — RED**

`cd apps/project-cockpit && node --test server/platform-bridge.test.mjs`
Expected: FAIL — cannot find module.

- [ ] **Step 3: implement** (`platform-bridge.mjs`)

```js
// platform-bridge.mjs — the leash. Maps allowlisted t560 session kinds to EXACT tmux argv
// against the bridge pod. No free-form command ever reaches tmux. Pure + unit-tested.
export const SESSION_ALLOWLIST = {
  "t560-beagle":     { socket: "default", target: "beagle" },
  "t560-darwin-ops": { socket: "default", target: "darwin-ops" },
  "t560-clops":      { socket: "clops",   target: "clops" },
};
const SOCK = (s) => `/tmp/tmux-1000/${s}`;
const TMUX_LIST_FORMAT = "#{session_name}|#{session_attached}|#{session_activity}|#{window_name}";

export function isT560Kind(kind) {
  return Object.prototype.hasOwnProperty.call(SESSION_ALLOWLIST, kind);
}
export function tmuxAttachArgv(kind) {
  const s = SESSION_ALLOWLIST[kind];
  return s ? ["-S", SOCK(s.socket), "attach", "-t", s.target] : null;
}
export function tmuxControlArgv(kind, verb) {
  const s = SESSION_ALLOWLIST[kind];
  if (!s) return null;
  if (verb === "kill") return ["-S", SOCK(s.socket), "kill-session", "-t", s.target];
  if (verb === "list") return ["-S", SOCK(s.socket), "list-sessions", "-F", TMUX_LIST_FORMAT];
  return null;
}
/** raw = { <kind>: "<name>|<attached>|<activity_epoch>|<window>" }. now = epoch seconds. */
export function buildSessionList(raw, now) {
  const out = [];
  for (const [kind, line] of Object.entries(raw || {})) {
    if (typeof line !== "string" || !line.trim()) continue;
    const [name, attached, activity, window] = line.trim().split("|");
    out.push({
      kind, name,
      attached: attached === "1",
      idleSeconds: Math.max(0, Math.round((Number(now) || 0) - (Number(activity) || 0))),
      window: window || "",
    });
  }
  return out;
}
```

- [ ] **Step 4: run — GREEN**

`node --test server/platform-bridge.test.mjs`
Expected: 3 tests pass.

- [ ] **Step 5: commit**

```bash
git add apps/project-cockpit/server/platform-bridge.mjs apps/project-cockpit/server/platform-bridge.test.mjs
git commit -m "cockpit: platform-bridge resolver — allowlisted t560 tmux argv (attach/list/kill), pure + tested"
```

---

### Task 2: wire the resolver into the WebSocket PTY bridge

**Files:**
- Modify: `apps/project-cockpit/server/agent-routes.mjs` (the `registerAgentWebSocket` handler, ~line 350)

**Interfaces:**
- Consumes: `isT560Kind`, `tmuxAttachArgv` (Task 1); the existing `pty`, `KUBECTL`, `AGENT_NAMESPACE`.

- [ ] **Step 1: add imports + a pod resolver + extract the pty-wiring** at the top of `agent-routes.mjs`

```js
import { isT560Kind, tmuxAttachArgv } from "./platform-bridge.mjs";
import { execFileSync } from "node:child_process";

function bridgePodName() {
  const out = execFileSync(KUBECTL, ["-n", AGENT_NAMESPACE, "get", "pod",
    "-l", "app=platform-bridge", "-o", "jsonpath={.items[0].metadata.name}"], { encoding: "utf8" });
  if (!out.trim()) throw new Error("platform-bridge pod not found");
  return out.trim();
}

// Wire a spawned pty <-> the websocket (shared by the agent-pod and t560 paths).
function wirePtyToSocket(socket, term) {
  socket.on("message", (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.type === "input") term.write(msg.data);
      else if (msg.type === "resize") term.resize(Number(msg.cols) || 120, Number(msg.rows) || 34);
    } catch { term.write(data.toString()); }
  });
  term.onData((d) => socket.send(JSON.stringify({ type: "data", data: d })));
  term.onExit(({ exitCode, signal }) => {
    if (socket.readyState === 1) {
      socket.send(JSON.stringify({ type: "exit", data: signal ? `terminal exited (${exitCode}, signal ${signal})` : `terminal exited (${exitCode})` }));
      socket.close();
    }
  });
  socket.on("close", () => term.kill());
}
```

- [ ] **Step 2: add the t560 branch** in `registerAgentWebSocket`, right after `const [, slug, kind] = match;` and the slug validation, BEFORE `normKind(kind)`:

```js
    // t560 session: attach the bridge pod's tmux instead of an agent pod.
    if (isT560Kind(kind)) {
      let pod;
      try { pod = bridgePodName(); } catch { socket.close(); return; }
      const term = pty.spawn(KUBECTL, [
        "-n", AGENT_NAMESPACE, "exec", "-it", pod, "--",
        "tmux", ...tmuxAttachArgv(kind)
      ], { name: "xterm-256color", cols: 120, rows: 34, cwd: process.cwd(), env: process.env });
      wirePtyToSocket(socket, term);
      return;
    }
```

- [ ] **Step 3: (optional DRY) replace the existing agent-pod message/data/exit block with `wirePtyToSocket(socket, kubectl)`** — the existing inline block (lines ~380-409) is identical to `wirePtyToSocket`; swap it to the helper. If risk-averse, leave the existing block and only use the helper for the t560 branch (both are correct).

- [ ] **Step 4: static check + existing tests**

```bash
cd apps/project-cockpit && node --check server/agent-routes.mjs && node --test server/platform-bridge.test.mjs
```
Expected: parses; resolver tests still pass.

- [ ] **Step 5: commit**

```bash
git add apps/project-cockpit/server/agent-routes.mjs
git commit -m "cockpit: WS PTY bridge attaches t560 tmux sessions via the bridge pod"
```

---

### Task 3: cockpit `/platform-state` (session list) + `/platform-control`

**Files:**
- Create: `apps/project-cockpit/server/platform-routes.mjs`
- Modify: the cockpit server entry that registers mobile routes — register `platform-routes` (find where `registerMobileRoutes(app, deps)` is called; call `registerPlatformRoutes(app, deps)` alongside it).

**Interfaces:**
- Consumes: `SESSION_ALLOWLIST`, `tmuxControlArgv`, `buildSessionList` (Task 1); the same auth gate as sibling `/api/mobile/v1/*` routes.
- Produces: `registerPlatformRoutes(app, deps)`; `GET /api/mobile/v1/platform-state` → `{ ok, sessions }`; `POST /api/mobile/v1/platform-control` `{ kind, verb }` → `{ ok }`.

- [ ] **Step 1: implement** (`platform-routes.mjs`)

```js
// platform-routes.mjs — the command deck's control plane (Phase 1: list + kill; attach is the WS).
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { SESSION_ALLOWLIST, tmuxControlArgv, buildSessionList } from "./platform-bridge.mjs";
const pexec = promisify(execFile);
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl";
const NS = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";

async function bridgePod() {
  const { stdout } = await pexec(KUBECTL, ["-n", NS, "get", "pod", "-l", "app=platform-bridge",
    "-o", "jsonpath={.items[0].metadata.name}"]);
  if (!stdout.trim()) throw new Error("platform-bridge pod not found");
  return stdout.trim();
}
async function tmuxExec(argv) {
  const pod = await bridgePod();
  const { stdout } = await pexec(KUBECTL, ["-n", NS, "exec", pod, "--", "tmux", ...argv], { timeout: 8000 });
  return stdout;
}

export function registerPlatformRoutes(app) {
  app.get("/api/mobile/v1/platform-state", async (_req, res) => {
    const now = Math.floor(Date.now() / 1000);
    const raw = {};
    for (const kind of Object.keys(SESSION_ALLOWLIST)) {
      try {
        const out = await tmuxExec(tmuxControlArgv(kind, "list"));
        // list returns ALL sessions on the socket; pick the allowlisted target's line.
        const target = SESSION_ALLOWLIST[kind].target;
        const line = out.split("\n").find((l) => l.startsWith(target + "|"));
        if (line) raw[kind] = line.trim();
      } catch { /* session/socket absent — omit */ }
    }
    res.json({ ok: true, sessions: buildSessionList(raw, now) });
  });

  app.post("/api/mobile/v1/platform-control", async (req, res) => {
    const kind = String(req.body?.kind || "");
    const verb = String(req.body?.verb || "");
    const argv = tmuxControlArgv(kind, verb);
    if (!argv || verb === "list") return res.status(400).json({ ok: false, error: "unsupported" });
    try { await tmuxExec(argv); res.json({ ok: true }); }
    catch (e) { res.status(500).json({ ok: false, error: String(e?.message || e) }); }
  });
}
```

- [ ] **Step 2: register it** — in the cockpit server entry (search `registerMobileRoutes(`), add:
```js
import { registerPlatformRoutes } from "./platform-routes.mjs";
// ... near registerMobileRoutes(app, deps):
registerPlatformRoutes(app);
```

- [ ] **Step 3: static check**

`cd apps/project-cockpit && node --check server/platform-routes.mjs`
Expected: parses.

- [ ] **Step 4: commit**

```bash
git add apps/project-cockpit/server/platform-routes.mjs apps/project-cockpit/server/<entry>.mjs
git commit -m "cockpit: /platform-state (session list) + /platform-control (kill), allowlist-gated"
```

---

### Task 4: iOS — `CockpitClient` methods + `SessionDeckView` + drawer entry

**Files:**
- Modify: `~/dev/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/CockpitClient.swift` (add `fetchPlatformSessions()` + `controlSession(kind:verb:)`)
- Create: `~/dev/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/SessionDeckView.swift`
- Modify: `Companion/ChatScreen.swift` (+`BeagleSurface.swift`) — a "Sessões" drawer footer entry opening the deck (mirror the synthesis wiring).

**Interfaces:**
- Consumes: `TerminalStore.connect(slug:kind:)` + `TerminalContentView(terminal:)` (existing); `BeagleClient.cockpitMobileToken`; `/platform-state`, `/platform-control` (Task 3).

- [ ] **Step 1: add CockpitClient methods** (mirror the existing `fetch`/POST pattern, x-cockpit-token, base URL fallback)
```swift
public struct PlatformSession: Decodable, Sendable, Identifiable {
    public let kind: String, name: String, window: String
    public let attached: Bool
    public let idleSeconds: Int
    public var id: String { kind }
}
extension CockpitClient {
    public func fetchPlatformSessions() async -> [PlatformSession] {
        let r: Truthful<PlatformStateEnvelope> = await fetch(PlatformStateEnvelope.self, path: "/api/mobile/v1/platform-state")
        return r.value?.sessions ?? []
    }
    public func controlSession(kind: String, verb: String) async -> Bool {
        await postOk(path: "/api/mobile/v1/platform-control", body: ["kind": kind, "verb": verb])
    }
}
struct PlatformStateEnvelope: Decodable, Sendable { let sessions: [PlatformSession] }
```
(Reuse/adjust to the file's actual `fetch`/`postOk` helpers — read them; the token+baseURL loop already exists.)

- [ ] **Step 2: create `SessionDeckView.swift`** — lists sessions, taps to attach (a `TerminalStore` + `TerminalContentView`), a kill affordance:
```swift
import SwiftUI
import BeagleCore

struct SessionDeckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [PlatformSession] = []
    @State private var active: PlatformSession?
    @State private var terminal = TerminalStore()
    private let slug = "sounio"   // the project slug the WS path uses

    var body: some View {
        NavigationStack {
            if let s = active {
                TerminalContentView(terminal: terminal)
                    .navigationTitle(s.name)
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Sessões") { terminal.disconnect(); active = nil } } }
            } else {
                List {
                    ForEach(sessions) { s in
                        Button { open(s) } label: {
                            HStack {
                                Circle().fill(s.attached ? BeagleTheme.auroraGreen : BeagleTheme.companionInk.opacity(0.3)).frame(width: 8, height: 8)
                                VStack(alignment: .leading) {
                                    Text(s.name).font(BeagleFont.headline.font).foregroundStyle(BeagleTheme.companionInk)
                                    Text("\(s.window) · idle \(s.idleSeconds/60)m").font(BeagleFont.footnote.font).foregroundStyle(BeagleTheme.companionInk.opacity(0.5))
                                }
                            }
                        }
                        .swipeActions { Button("Matar", role: .destructive) { kill(s) } }
                    }
                }
                .scrollContentBackground(.hidden).background(BeagleTheme.companionSurface)
                .navigationTitle("Sessões")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
                .task { sessions = await CockpitClient.shared.fetchPlatformSessions() }
                .refreshable { sessions = await CockpitClient.shared.fetchPlatformSessions() }
            }
        }
        .presentationBackground(BeagleTheme.companionSurface)
    }
    private func open(_ s: PlatformSession) { active = s; terminal.connect(slug: slug, kind: s.kind) }
    private func kill(_ s: PlatformSession) { Task { _ = await CockpitClient.shared.controlSession(kind: s.kind, verb: "kill"); sessions = await CockpitClient.shared.fetchPlatformSessions() } }
}
```
(Adjust to `TerminalStore`'s actual `disconnect`/`connect` API — read it; `connect(slug:kind:)` confirmed.)

- [ ] **Step 3: wire a "Sessões" drawer footer entry** — mirror the synthesis wiring exactly (a `.sessions` case in `SurfaceSheet`, `onOpenSessions: { activeSheet = .sessions }` on the ChatScreen call, a `case .sessions: SessionDeckView()` arm, an `onOpenSessions` closure through ChatScreen/ConversationDrawer + a "Sessões" footer button with `terminal` SF Symbol).

- [ ] **Step 4: build (generic iOS)** — `~/bin/xcodegen generate` then `xcodebuild ... -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bc build`. Expected: BUILD SUCCEEDED.

- [ ] **Step 5: commit** (on the Mac) — `ios(deck): SessionDeckView — attach/kill t560 tmux sessions, reusing TerminalStore`

---

### Task 5: deploy + device verify + invariant check

- [ ] **Step 1: push cockpit; build + roll the cockpit image** (kaniko `k8s/project-cockpit/build-job.yaml` with the new sha; `set image` deploy) — same pipeline as prior cockpit deploys.
- [ ] **Step 2: signed device build + install** (`ssh mac`, keychain unlock 1982, xcodebuild device, `devicectl install`).
- [ ] **Step 3: live-verify on device** — open drawer → **Sessões** → the list shows beagle/darwin-ops/clops with attached/idle → tap **beagle** → the live tmux renders → type a command → confirm it appears ON THE LAPTOP's beagle session too (shared attach). Swipe-kill a throwaway session → gone from the list.
- [ ] **Step 4: INVARIANT check** — open a chat turn → confirm NO tmux pane content appears in the companion (Phase 1 adds no grounding); confirm an un-allowlisted kind (`curl .../platform-control -d '{"kind":"t560-evil","verb":"kill"}'`) is refused (400).
- [ ] **Step 5: commit deploy manifests + push.**

---

## Self-Review

**Spec coverage (Phase 1 slice):** bridge pod → Task 0; allowlist leash → Task 1 (+ invariant checks Task 5); interactive attach (Termius supersession) → Tasks 2,4,5; session list/kill control → Tasks 3,4; iOS reuse (TerminalStore/TerminalContentView, no pod lifecycle) → Task 4; invariants (pane-not-in-companion, allowlist) → Global Constraints + Task 5 Step 4. Phase 2 (state block/proactive) and Phase 3 (acting) are deliberately OUT of this plan (separate plans). "New arbitrary session" deferred (fast-follow) — Phase 1 is attach/list/kill of the allowlisted sessions.

**Placeholder scan:** `<entry>` / `<slug>` / `<newsha>` are runtime values; the iOS steps say "read the actual TerminalStore/CockpitClient helper" where the exact method name (disconnect/postOk) must be confirmed against the file — these are named, discoverable reuse points, not logic placeholders.

**Type consistency:** `SESSION_ALLOWLIST` kinds (`t560-beagle/darwin-ops/clops`) are identical across resolver (Task 1), WS wire (Task 2), routes (Task 3), and the iOS `s.kind` passed to `TerminalStore.connect(kind:)` (Task 4). `buildSessionList` output shape `{kind,name,attached,idleSeconds,window}` matches iOS `PlatformSession`. `tmuxAttachArgv`/`tmuxControlArgv` return `string[]|null` consumed consistently.
