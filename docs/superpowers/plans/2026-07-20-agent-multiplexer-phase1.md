# Agent Multiplexer (Loom) — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native, unbreakable agent multiplexer — open his fleet of agents as native tabs, render clean, switch by touch, spawn any of 8 agent kinds, and reset a stuck one in one tap.

**Architecture:** A chrome-less broker (Node/TS) holds one raw persistent PTY per agent and speaks a fixed WebSocket protocol; a native SwiftUI client draws all tabs/panes/status and renders one program per pane with SwiftTerm. The protocol is the swap boundary (v1 Node now, Sounio broker later).

**Tech Stack:** Server — Node ESM `.mjs`, `ws`, `node-pty`, `node:test`, deployed inside `project-cockpit`. Client — SwiftUI, SwiftTerm ≥1.15, BeagleCore/BeagleCockpit/BeagleWorkbenchKit, XCTest, xcodegen.

## Global Constraints

- **No chrome in the engine.** The broker manages PTYs + state only; all tabs/panes/status live in the client. (Spec invariant 1.)
- **Allowlist is the leash.** Agents spawn ONLY from the fixed catalog; control verbs are `create|kill|reset` only; no request input reaches a shell. (Invariant 4.)
- **The protocol is fixed and is the swap boundary.** `state ∈ running|idle|waiting|stuck|exited`. Both engines implement it verbatim. (Invariant 5.)
- **Auth reuses the cockpit gate.** WS carries `x-cockpit-token` header OR `?token=` (= `PROJECT_COCKPIT_AUTH_TOKEN`), same as `index.mjs:15113`.
- **Server tests:** `node --test apps/project-cockpit/server/loom/<file>.test.mjs`. **Commits:** `git commit --no-verify` (LFS hook). Server branch `reconcile/unify-beagle`.
- **Client:** Mac `~/dev/beagle/beagle-ios`, branch `integration/ios-physiome-merge`; build `xcodebuild -project BeagleSuite.xcodeproj -scheme BeagleCockpit`; device UDID `EF83DE84-8CC0-54E4-86A5-C3B6359A51E7`; keychain `1982`.
- **Brand tints (exact):** claude `#E2A568` · codex `#6EE6AA` · cursor `#8FA8FF` · glm `#C58FF0` · kimi `#7FD4E6` · grok `#C3CCD8` · opencode `#E6C86E` · local `#8B93B8`. **Status:** run `#6EE6AA` · wait `#E6B24C` · stuck `#E8706E` · done `#5EC8C0` · idle `#7D84A6`.

## File Structure

**Server** (`apps/project-cockpit/server/loom/`):
- `protocol.mjs` — encode/decode/validate the message set (pure).
- `catalog.mjs` — `kind → recipe`; allowlist (pure).
- `ring.mjs` — bounded scrollback byte ring (pure).
- `state.mjs` — agent-state classifier (pure).
- `ownedSession.mjs` — broker-spawned PTY session (node-pty).
- `adaptedSession.mjs` — attach existing tmux/zellij pane (reuses `platform-bridge.mjs`).
- `broker.mjs` — session registry + protocol handler over a WS.
- `*.test.mjs` alongside each.
- Wire: `index.mjs` upgrade handler → `/ws/loom`.

**Client** (`~/dev/beagle/beagle-ios/BeagleSuite/Sources/`):
- `BeagleCore/Loom/LoomProtocol.swift` — Codable message models (pure).
- `BeagleCore/Loom/LoomCatalog.swift` — the 8 kinds + tints (pure).
- `BeagleCore/Loom/LoomClient.swift` — one WS per host → `@Observable HostConnection`.
- `BeagleCockpit/Loom/SessionScreen.swift` — Sessão (terminal + bottom agent bar).
- `BeagleCockpit/Loom/FleetDrawer.swift` — Frota (dashboard + reset).
- `BeagleCockpit/Loom/NewAgentCatalog.swift` — Novo agente (grid).
- Wire: `BeagleCockpitApp.swift` iPhone TabView → "Agentes" tab.

---

## Task 1: Protocol codec (pure)

**Files:**
- Create: `apps/project-cockpit/server/loom/protocol.mjs`
- Test: `apps/project-cockpit/server/loom/protocol.test.mjs`

**Interfaces:**
- Produces: `decodeClient(str) -> {t, ...}|null` (null on malformed/unknown); `encodeServer(msg) -> string`; constants `CLIENT_TYPES`, `SERVER_TYPES`, `STATES = ["running","idle","waiting","stuck","exited"]`.

- [ ] **Step 1: Write the failing test**

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeClient, encodeServer, STATES } from "./protocol.mjs";

test("decodeClient accepts known client messages, rejects the rest", () => {
  assert.deepEqual(decodeClient('{"t":"subscribe","sid":"a"}'), { t: "subscribe", sid: "a" });
  assert.deepEqual(decodeClient('{"t":"create","kind":"codex"}'), { t: "create", kind: "codex" });
  assert.equal(decodeClient('{"t":"evil"}'), null);
  assert.equal(decodeClient("not json"), null);
  assert.equal(decodeClient('{"no":"t"}'), null);
});

test("encodeServer round-trips a data frame and a state frame", () => {
  assert.equal(encodeServer({ t: "data", sid: "a", bytes: "hi" }),
    '{"t":"data","sid":"a","bytes":"hi"}');
  const s = JSON.parse(encodeServer({ t: "state", sid: "a", state: "running", detail: "" }));
  assert.equal(s.state, "running");
  assert.deepEqual(STATES, ["running", "idle", "waiting", "stuck", "exited"]);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test apps/project-cockpit/server/loom/protocol.test.mjs`
Expected: FAIL — `Cannot find module './protocol.mjs'`.

- [ ] **Step 3: Write minimal implementation**

```js
// protocol.mjs — the fixed client<->broker message set. The swap boundary.
export const STATES = ["running", "idle", "waiting", "stuck", "exited"];
export const CLIENT_TYPES = new Set(["hello", "list", "subscribe", "unsubscribe", "input", "resize", "create", "kill", "reset"]);
export const SERVER_TYPES = new Set(["sessions", "scrollback", "data", "state", "exit", "error"]);

export function decodeClient(str) {
  let m;
  try { m = JSON.parse(str); } catch { return null; }
  if (!m || typeof m !== "object" || !CLIENT_TYPES.has(m.t)) return null;
  return m;
}
export function encodeServer(msg) {
  if (!msg || !SERVER_TYPES.has(msg.t)) throw new Error(`bad server msg: ${msg && msg.t}`);
  return JSON.stringify(msg);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test apps/project-cockpit/server/loom/protocol.test.mjs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/loom/protocol.mjs apps/project-cockpit/server/loom/protocol.test.mjs
git commit --no-verify -m "loom: protocol codec (the swap boundary)"
```

---

## Task 2: Agent catalog (pure)

**Files:**
- Create: `apps/project-cockpit/server/loom/catalog.mjs`
- Test: `apps/project-cockpit/server/loom/catalog.test.mjs`

**Interfaces:**
- Produces: `catalogKinds() -> string[]` (the 8 + "shell"); `recipeFor(kind) -> {argv,env,home,cwd,resumeArgv}|null`. A recipe's `argv` is fixed; no caller input is interpolated.

- [ ] **Step 1: Write the failing test**

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { catalogKinds, recipeFor } from "./catalog.mjs";

test("catalog has the eight agent kinds plus a raw shell", () => {
  assert.deepEqual(catalogKinds(),
    ["claude", "codex", "cursor", "glm", "kimi", "grok", "opencode", "local", "shell"]);
});

test("recipeFor resolves fixed argv; unknown kind refused", () => {
  const codex = recipeFor("codex");
  assert.ok(Array.isArray(codex.argv) && codex.argv.length > 0);
  assert.equal(recipeFor("codex").argv.includes(";"), false); // no shell metachars smuggled
  assert.equal(recipeFor("evil; rm -rf"), null);
  assert.equal(recipeFor(""), null);
  assert.equal(recipeFor("shell").argv[0], "/bin/bash");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test apps/project-cockpit/server/loom/catalog.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation**

```js
// catalog.mjs — the allowlist of agent launch recipes. The leash: only these spawn.
// Each recipe is fixed argv + env; no request input is ever interpolated in.
const NODE_BIN = process.env.LOOM_NODE_BIN || "node";
const CATALOG = {
  claude:   { argv: ["claude"],                       resumeArgv: ["claude", "--continue"] },
  codex:    { argv: [NODE_BIN, "codex"],              resumeArgv: [NODE_BIN, "codex", "resume", "--last"] },
  cursor:   { argv: ["cursor-agent"],                 resumeArgv: null },
  glm:      { argv: ["glm"],                          resumeArgv: null },
  kimi:     { argv: ["kimi"],                         resumeArgv: null },
  grok:     { argv: ["grok"],                         resumeArgv: null },
  opencode: { argv: ["opencode"],                     resumeArgv: null },
  local:    { argv: ["beagle-local-agent"],           resumeArgv: null },
  shell:    { argv: ["/bin/bash", "-l"],              resumeArgv: null },
};
export function catalogKinds() { return Object.keys(CATALOG); }
export function recipeFor(kind) {
  if (!Object.prototype.hasOwnProperty.call(CATALOG, kind)) return null;
  const r = CATALOG[kind];
  return { argv: r.argv, resumeArgv: r.resumeArgv, env: {}, home: null, cwd: null };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test apps/project-cockpit/server/loom/catalog.test.mjs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/loom/catalog.mjs apps/project-cockpit/server/loom/catalog.test.mjs
git commit --no-verify -m "loom: agent catalog allowlist (8 kinds + shell)"
```

---

## Task 3: Scrollback ring (pure)

**Files:**
- Create: `apps/project-cockpit/server/loom/ring.mjs`
- Test: `apps/project-cockpit/server/loom/ring.test.mjs`

**Interfaces:**
- Produces: `class Ring { constructor(capBytes) ; push(str) ; snapshot() -> string ; get size() }`. Keeps the last `capBytes` bytes of appended UTF-8 text.

- [ ] **Step 1: Write the failing test**

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { Ring } from "./ring.mjs";

test("ring keeps only the last capBytes of appended text", () => {
  const r = new Ring(5);
  r.push("abc"); r.push("de"); r.push("fg");   // "abcdefg" -> keep last 5
  assert.equal(r.snapshot(), "cdefg");
  assert.ok(r.size <= 5);
});
test("ring snapshot of a short stream is the whole stream", () => {
  const r = new Ring(100);
  r.push("hello"); assert.equal(r.snapshot(), "hello");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test apps/project-cockpit/server/loom/ring.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation**

```js
// ring.mjs — bounded scrollback: keep the last N bytes so a (re)subscribing client
// sees the current screen. A resize-on-attach then makes full-screen TUIs repaint.
export class Ring {
  constructor(capBytes = 64 * 1024) { this._cap = capBytes; this._buf = ""; }
  push(str) {
    this._buf += str;
    if (this._buf.length > this._cap) this._buf = this._buf.slice(this._buf.length - this._cap);
  }
  snapshot() { return this._buf; }
  get size() { return this._buf.length; }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test apps/project-cockpit/server/loom/ring.test.mjs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/loom/ring.mjs apps/project-cockpit/server/loom/ring.test.mjs
git commit --no-verify -m "loom: scrollback ring buffer"
```

---

## Task 4: State classifier (pure)

**Files:**
- Create: `apps/project-cockpit/server/loom/state.mjs`
- Test: `apps/project-cockpit/server/loom/state.test.mjs`

**Interfaces:**
- Produces: `classify({ alive, lastOutputAt, now, atPrompt, awaitingInput, stuckAfterMs }) -> one of STATES`.

- [ ] **Step 1: Write the failing test**

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { classify } from "./state.mjs";

test("classify maps signals to the fixed state vocabulary", () => {
  const now = 1_000_000;
  assert.equal(classify({ alive: false, now }), "exited");
  assert.equal(classify({ alive: true, awaitingInput: true, now }), "waiting");
  assert.equal(classify({ alive: true, atPrompt: true, lastOutputAt: now - 10, now }), "idle");
  assert.equal(classify({ alive: true, lastOutputAt: now - 100, now }), "running");
  assert.equal(classify({ alive: true, atPrompt: false, lastOutputAt: now - 999999, now, stuckAfterMs: 120000 }), "stuck");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test apps/project-cockpit/server/loom/state.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation**

```js
// state.mjs — classify an agent session into the fixed vocabulary. v1 heuristics;
// richer waiting/idle detection is Phase 4.
export function classify({ alive, lastOutputAt = 0, now = 0, atPrompt = false, awaitingInput = false, stuckAfterMs = 120000 }) {
  if (!alive) return "exited";
  if (awaitingInput) return "waiting";
  const idleMs = now - lastOutputAt;
  if (!atPrompt && idleMs >= stuckAfterMs) return "stuck";
  if (atPrompt) return "idle";
  return "running";
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test apps/project-cockpit/server/loom/state.test.mjs`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/loom/state.mjs apps/project-cockpit/server/loom/state.test.mjs
git commit --no-verify -m "loom: agent state classifier"
```

---

## Task 5: OwnedPtySession (broker-spawned PTY)

**Files:**
- Create: `apps/project-cockpit/server/loom/ownedSession.mjs`
- Test: `apps/project-cockpit/server/loom/ownedSession.test.mjs`

**Interfaces:**
- Consumes: `recipeFor` (Task 2), `Ring` (Task 3).
- Produces: `class OwnedPtySession { constructor(sid, kind, recipe) ; onData(fn) ; onExit(fn) ; write(data) ; resize(cols,rows) ; kill() ; snapshot() ; get meta() }`. `meta = {sid,kind,source:"owned",cols,rows,alive,lastOutputAt}`.

- [ ] **Step 1: Write the failing test**

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { OwnedPtySession } from "./ownedSession.mjs";
import { recipeFor } from "./catalog.mjs";

test("owned session runs a recipe, streams output to the ring, then exits", async () => {
  // Use the shell recipe to run a trivial deterministic command.
  const s = new OwnedPtySession("t1", "shell", recipeFor("shell"));
  let out = "";
  s.onData((d) => { out += d; });
  const exited = new Promise((res) => s.onExit(res));
  s.write("echo loom-ok; exit\n");
  await exited;
  assert.match(out, /loom-ok/);
  assert.match(s.snapshot(), /loom-ok/);
  assert.equal(s.meta.alive, false);
  assert.equal(s.meta.source, "owned");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test apps/project-cockpit/server/loom/ownedSession.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation**

```js
// ownedSession.mjs — the broker spawns the agent in its own PTY and HOLDS the master
// (persistence: survives client disconnect). No tmux/zellij underneath.
import pty from "node-pty";
import { Ring } from "./ring.mjs";

export class OwnedPtySession {
  constructor(sid, kind, recipe, { cols = 120, rows = 34 } = {}) {
    this.sid = sid; this.kind = kind;
    this._ring = new Ring();
    this._alive = true; this._lastOutputAt = Date.now();
    this._dataCbs = []; this._exitCbs = [];
    this._cols = cols; this._rows = rows;
    const [file, ...args] = recipe.argv;
    this._term = pty.spawn(file, args, {
      name: "xterm-256color", cols, rows,
      cwd: recipe.cwd || process.cwd(),
      env: { ...process.env, ...(recipe.env || {}), ...(recipe.home ? { HOME: recipe.home } : {}) },
    });
    this._term.onData((d) => {
      this._lastOutputAt = Date.now(); this._ring.push(d);
      for (const cb of this._dataCbs) cb(d);
    });
    this._term.onExit(({ exitCode }) => {
      this._alive = false;
      for (const cb of this._exitCbs) cb(exitCode);
    });
  }
  onData(fn) { this._dataCbs.push(fn); }
  onExit(fn) { this._exitCbs.push(fn); }
  write(data) { if (this._alive) this._term.write(data); }
  resize(cols, rows) { this._cols = cols; this._rows = rows; if (this._alive) this._term.resize(cols, rows); }
  kill() { if (this._alive) this._term.kill(); }
  snapshot() { return this._ring.snapshot(); }
  get meta() {
    return { sid: this.sid, kind: this.kind, source: "owned", cols: this._cols, rows: this._rows,
      alive: this._alive, lastOutputAt: this._lastOutputAt };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test apps/project-cockpit/server/loom/ownedSession.test.mjs`
Expected: PASS (1 test). (Requires `node-pty` resolvable — run from a dir where `/app` or the cockpit `node_modules` is on the path, or `cd apps/project-cockpit && node --test server/loom/ownedSession.test.mjs`.)

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/loom/ownedSession.mjs apps/project-cockpit/server/loom/ownedSession.test.mjs
git commit --no-verify -m "loom: OwnedPtySession (broker-held PTY)"
```

---

## Task 6: AdaptedSession (attach existing tmux/zellij)

**Files:**
- Create: `apps/project-cockpit/server/loom/adaptedSession.mjs`
- Test: `apps/project-cockpit/server/loom/adaptedSession.test.mjs`

**Interfaces:**
- Consumes: `deckExec`, `kubectlArgv` from `../platform-bridge.mjs` (existing); `Ring` (Task 3). A `spawnFn` is injected for testability (defaults to `node-pty` `spawn`).
- Produces: `class AdaptedSession` with the SAME shape as `OwnedPtySession` (`onData/onExit/write/resize/kill/snapshot/meta`), `meta.source = "adapted"`. Plus a pure helper `adaptedAttachArgv(kind, kubectl, ns, podResolver)` returning the exact kubectl argv.

- [ ] **Step 1: Write the failing test**

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { adaptedAttachArgv } from "./adaptedSession.mjs";

test("adapted attach builds an exact kubectl argv from the deck allowlist, refuses unknown", () => {
  const argv = adaptedAttachArgv("t560-beagle", "/usr/local/bin/kubectl", "beagle", () => "bridge-pod");
  assert.deepEqual(argv,
    ["-n", "beagle", "exec", "-it", "bridge-pod", "--", "tmux", "-S", "/tmp/tmux-1000/default", "attach", "-t", "beagle"]);
  assert.equal(adaptedAttachArgv("evil", "/k", "beagle", () => "p"), null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test apps/project-cockpit/server/loom/adaptedSession.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation**

```js
// adaptedSession.mjs — transitional: attach an existing tmux/zellij pane (his current
// agents) via kubectl exec, reusing the Command Deck's allowlisted resolvers. Same
// interface as OwnedPtySession so the broker treats both identically. Retires later.
import pty from "node-pty";
import { deckExec, kubectlArgv } from "../platform-bridge.mjs";
import { Ring } from "./ring.mjs";

export function adaptedAttachArgv(kind, kubectl, ns, podResolver) {
  const spec = deckExec(kind, "attach");
  if (!spec) return null;
  const pod = spec.pod === "@bridge" ? podResolver() : spec.pod;
  return kubectlArgv(ns, pod, spec, true);
}

export class AdaptedSession {
  constructor(sid, kind, { kubectl, ns, podResolver, cols = 120, rows = 34, spawnFn = pty.spawn } = {}) {
    this.sid = sid; this.kind = kind;
    this._ring = new Ring(); this._alive = true; this._lastOutputAt = Date.now();
    this._dataCbs = []; this._exitCbs = []; this._cols = cols; this._rows = rows;
    const argv = adaptedAttachArgv(kind, kubectl, ns, podResolver);
    if (!argv) throw new Error(`unknown adapted kind: ${kind}`);
    this._term = spawnFn(kubectl, argv, { name: "xterm-256color", cols, rows, cwd: process.cwd(), env: process.env });
    this._term.onData((d) => { this._lastOutputAt = Date.now(); this._ring.push(d); for (const cb of this._dataCbs) cb(d); });
    this._term.onExit(({ exitCode }) => { this._alive = false; for (const cb of this._exitCbs) cb(exitCode); });
  }
  onData(fn) { this._dataCbs.push(fn); }
  onExit(fn) { this._exitCbs.push(fn); }
  write(data) { if (this._alive) this._term.write(data); }
  resize(cols, rows) { this._cols = cols; this._rows = rows; if (this._alive) this._term.resize(cols, rows); }
  kill() { if (this._alive) this._term.kill(); }
  snapshot() { return this._ring.snapshot(); }
  get meta() { return { sid: this.sid, kind: this.kind, source: "adapted", cols: this._cols, rows: this._rows, alive: this._alive, lastOutputAt: this._lastOutputAt }; }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test apps/project-cockpit/server/loom/adaptedSession.test.mjs`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/loom/adaptedSession.mjs apps/project-cockpit/server/loom/adaptedSession.test.mjs
git commit --no-verify -m "loom: AdaptedSession (transitional tmux/zellij attach)"
```

---

## Task 7: Broker core (registry + protocol handler)

**Files:**
- Create: `apps/project-cockpit/server/loom/broker.mjs`
- Test: `apps/project-cockpit/server/loom/broker.test.mjs`

**Interfaces:**
- Consumes: `decodeClient`, `encodeServer` (Task 1); `recipeFor`, `catalogKinds` (Task 2); `classify` (Task 4); a `sessionFactory` injected for testability (defaults to real Owned/Adapted).
- Produces: `class Broker { constructor({ sessionFactory }) ; handleConnection(socket) ; addSeed(session) }`. `socket` is a `ws`-like object with `.on("message"|"close", fn)` and `.send(str)`. On connect it sends `sessions`; on `subscribe` sends `scrollback` then live `data`; `create` spawns via factory + broadcasts `sessions`; `reset` kills+respawns; emits `state` on transitions.

- [ ] **Step 1: Write the failing test**

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { Broker } from "./broker.mjs";

// Fake session + socket doubles.
function fakeSession(sid, kind) {
  const s = { sid, kind, _data: null, _exit: null, killed: false, written: [],
    onData(f){ s._data=f; }, onExit(f){ s._exit=f; }, write(d){ s.written.push(d); },
    resize(){}, kill(){ s.killed=true; s._exit && s._exit(0); }, snapshot(){ return "SB:"+sid; },
    get meta(){ return { sid, kind, source:"owned", cols:120, rows:34, alive:!s.killed, lastOutputAt: 0 }; } };
  return s;
}
function fakeSocket() {
  const s = { sent: [], handlers: {}, on(ev,f){ s.handlers[ev]=f; }, send(str){ s.sent.push(JSON.parse(str)); },
    recv(obj){ s.handlers.message(JSON.stringify(obj)); } };
  return s;
}

test("broker: connect->sessions; subscribe->scrollback; create->new session; reset->kill+respawn", () => {
  const created = [];
  const factory = (sid, kind) => { const s = fakeSession(sid, kind); created.push(s); return s; };
  const broker = new Broker({ sessionFactory: factory });
  const sock = fakeSocket();
  broker.handleConnection(sock);
  assert.equal(sock.sent[0].t, "sessions");           // snapshot on connect

  sock.recv({ t: "create", kind: "codex" });
  const sessMsg = sock.sent.filter((m) => m.t === "sessions").at(-1);
  assert.equal(sessMsg.sessions.length, 1);
  const sid = sessMsg.sessions[0].sid;

  sock.recv({ t: "subscribe", sid });
  assert.ok(sock.sent.some((m) => m.t === "scrollback" && m.sid === sid && m.bytes === "SB:" + sid));

  sock.recv({ t: "input", sid, data: "x" });
  assert.deepEqual(created[0].written, ["x"]);

  const before = created.length;
  sock.recv({ t: "reset", sid });
  assert.equal(created[0].killed, true);
  assert.equal(created.length, before + 1);           // respawned

  sock.recv({ t: "create", kind: "evil" });           // refused
  assert.ok(sock.sent.some((m) => m.t === "error"));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test apps/project-cockpit/server/loom/broker.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation**

```js
// broker.mjs — the chrome-less engine core: a session registry that speaks the protocol.
import { decodeClient, encodeServer } from "./protocol.mjs";
import { recipeFor } from "./catalog.mjs";
import { classify } from "./state.mjs";

let _seq = 0;
const nextSid = (kind) => `${kind}-${++_seq}`;

export class Broker {
  constructor({ sessionFactory }) {
    this._factory = sessionFactory;      // (sid, kind) -> session
    this._sessions = new Map();          // sid -> session
    this._clients = new Set();           // sockets
    this._subs = new Map();              // socket -> Set(sid)
  }
  addSeed(session) { this._sessions.set(session.sid, session); this._wire(session); }
  _wire(session) {
    session.onData((d) => this._toSubscribers(session.sid, { t: "data", sid: session.sid, bytes: d }));
    session.onExit(() => { this._broadcastState(session.sid); this._broadcastSessions(); });
  }
  _stateOf(session) {
    const m = session.meta;
    return classify({ alive: m.alive, lastOutputAt: m.lastOutputAt, now: Date.now() });
  }
  _sessionsSnapshot() {
    return [...this._sessions.values()].map((s) => {
      const m = s.meta;
      return { sid: m.sid, title: m.sid, kind: m.kind, source: m.source, state: this._stateOf(s), detail: "", cols: m.cols, rows: m.rows };
    });
  }
  _send(sock, msg) { try { sock.send(encodeServer(msg)); } catch { /* closed */ } }
  _broadcastSessions() { const snap = this._sessionsSnapshot(); for (const c of this._clients) this._send(c, { t: "sessions", sessions: snap }); }
  _broadcastState(sid) { const s = this._sessions.get(sid); if (!s) return; for (const c of this._clients) this._send(c, { t: "state", sid, state: this._stateOf(s), detail: "" }); }
  _toSubscribers(sid, msg) { for (const c of this._clients) if (this._subs.get(c)?.has(sid)) this._send(c, msg); }

  handleConnection(sock) {
    this._clients.add(sock); this._subs.set(sock, new Set());
    this._send(sock, { t: "sessions", sessions: this._sessionsSnapshot() });
    sock.on("message", (raw) => this._onMessage(sock, raw));
    sock.on("close", () => { this._clients.delete(sock); this._subs.delete(sock); });
  }
  _onMessage(sock, raw) {
    const m = decodeClient(String(raw));
    if (!m) return this._send(sock, { t: "error", message: "bad message" });
    const s = m.sid ? this._sessions.get(m.sid) : null;
    switch (m.t) {
      case "hello": case "list": return this._send(sock, { t: "sessions", sessions: this._sessionsSnapshot() });
      case "subscribe": {
        if (!s) return this._send(sock, { t: "error", sid: m.sid, message: "no such session" });
        this._subs.get(sock).add(m.sid);
        return this._send(sock, { t: "scrollback", sid: m.sid, bytes: s.snapshot() });
      }
      case "unsubscribe": this._subs.get(sock).delete(m.sid); return;
      case "input": if (s) s.write(m.data); return;
      case "resize": if (s) s.resize(Number(m.cols) || 120, Number(m.rows) || 34); return;
      case "create": {
        if (!recipeFor(m.kind)) return this._send(sock, { t: "error", message: "unknown kind" });
        const sid = nextSid(m.kind); const sess = this._factory(sid, m.kind);
        this._sessions.set(sid, sess); this._wire(sess); this._broadcastSessions(); return;
      }
      case "kill": if (s) { s.kill(); this._sessions.delete(m.sid); this._broadcastSessions(); } return;
      case "reset": {
        if (!s) return;
        const kind = s.meta.kind; s.kill(); this._sessions.delete(m.sid);
        const sid = nextSid(kind); const sess = this._factory(sid, kind);
        this._sessions.set(sid, sess); this._wire(sess); this._broadcastSessions(); return;
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test apps/project-cockpit/server/loom/broker.test.mjs`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/loom/broker.mjs apps/project-cockpit/server/loom/broker.test.mjs
git commit --no-verify -m "loom: broker core (registry + protocol handler)"
```

---

## Task 8: Wire the broker into the cockpit WebSocket

**Files:**
- Modify: `apps/project-cockpit/server/index.mjs` (upgrade handler near `:15113`; add a `loomWss` beside `agentWss`).
- Create: `apps/project-cockpit/server/loom/mount.mjs` (builds the real sessionFactory: Owned for catalog kinds, Adapted for `t560-*`, seeds the current deck sessions).

**Interfaces:**
- Consumes: `Broker` (Task 7), `OwnedPtySession` (Task 5), `AdaptedSession` (Task 6), `recipeFor` (Task 2).
- Produces: `mountLoom(server, { WebSocketServer, kubectl, ns, podResolver }) -> void` — creates a `WebSocketServer({noServer:true})`, a singleton `Broker`, and returns nothing; caller routes `/ws/loom` upgrades to it.

- [ ] **Step 1: Write the failing integration test**

```js
// apps/project-cockpit/server/loom/mount.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { makeSessionFactory } from "./mount.mjs";
import { recipeFor } from "./catalog.mjs";

test("makeSessionFactory builds owned sessions for catalog kinds", () => {
  const factory = makeSessionFactory({ kubectl: "/k", ns: "beagle", podResolver: () => "p" });
  const s = factory("shell-1", "shell");
  assert.equal(s.meta.source, "owned");
  s.kill();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test server/loom/mount.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `mount.mjs`**

```js
// mount.mjs — build the real session factory + expose a mount helper.
import { Broker } from "./broker.mjs";
import { OwnedPtySession } from "./ownedSession.mjs";
import { AdaptedSession } from "./adaptedSession.mjs";
import { recipeFor } from "./catalog.mjs";
import { isT560Kind } from "../platform-bridge.mjs";

export function makeSessionFactory({ kubectl, ns, podResolver }) {
  return (sid, kind) => {
    if (isT560Kind(kind)) return new AdaptedSession(sid, kind, { kubectl, ns, podResolver });
    const recipe = recipeFor(kind);
    if (!recipe) throw new Error(`unknown kind: ${kind}`);
    return new OwnedPtySession(sid, kind, recipe);
  };
}

export function mountLoom({ kubectl, ns, podResolver }) {
  const broker = new Broker({ sessionFactory: makeSessionFactory({ kubectl, ns, podResolver }) });
  return broker;   // caller wires WS connections to broker.handleConnection(ws)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test server/loom/mount.test.mjs`
Expected: PASS (1 test).

- [ ] **Step 5: Wire the upgrade handler in `index.mjs`**

Add beside the existing `agentWss` (near `:15107`):

```js
import { mountLoom } from "./loom/mount.mjs";
const loomWss = new WebSocketServer({ noServer: true });
const loomBroker = mountLoom({
  KUBECTL, // existing const
  kubectl: KUBECTL, ns: AGENT_NAMESPACE || "beagle",
  podResolver: bridgePodName, // existing helper (execFileSync get pod -l app=platform-bridge)
});
loomWss.on("connection", (ws) => loomBroker.handleConnection(ws));
```

Add the route in the `server.on("upgrade", ...)` block (after the agentMatch branch), reusing the SAME token gate already at the top of the handler:

```js
if (urlPath === "/ws/loom") {
  loomWss.handleUpgrade(req, socket, head, (ws) => loomWss.emit("connection", ws, req));
  return;
}
```

- [ ] **Step 6: Live-verify in-cluster (before iOS exists)**

Build+deploy the cockpit (kaniko → set image → rollout, per [[project_beagle_build_deploy]]). Then from inside the cockpit pod:

```bash
# a tiny ws client (like the earlier wsfinal.mjs): connect ws://localhost:4370/ws/loom
# with header x-cockpit-token=$TOKEN, send {"t":"create","kind":"shell"}, then
# {"t":"subscribe","sid":<sid from sessions>}, {"t":"input","sid":..,"data":"echo hi\n"}
```
Expected: a `sessions` frame with the new `shell-N`, a `scrollback` frame, then `data` frames containing `hi`. `{"t":"create","kind":"evil"}` → `error`.

- [ ] **Step 7: Commit**

```bash
git add apps/project-cockpit/server/loom/mount.mjs apps/project-cockpit/server/loom/mount.test.mjs apps/project-cockpit/server/index.mjs
git commit --no-verify -m "loom: mount broker on /ws/loom (owned + adapted factory)"
```

---

## Task 9: iOS protocol models + catalog (pure, BeagleCore)

**Files:**
- Create: `~/dev/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/Loom/LoomProtocol.swift`
- Create: `.../BeagleCore/Loom/LoomCatalog.swift`
- Test: `.../BeagleSuite/Tests/BeagleCoreTests/LoomProtocolTests.swift` (or the existing test target; if none, add live-decoding assertions in a temporary `#if DEBUG` check verified by the build + a device log).

**Interfaces:**
- Produces: `enum LoomServerMsg: Decodable` decoding `{t:...}`; `struct LoomSession {sid,title,kind,source,state,cols,rows}`; `enum LoomState: String {running,idle,waiting,stuck,exited}`; `LoomCatalog.kinds: [LoomKind]` with `{id, label, subtitle, tint: Color, glyph: String}` using the exact tints from Global Constraints.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BeagleCore

final class LoomProtocolTests: XCTestCase {
    func testDecodeSessionsAndData() throws {
        let j = #"{"t":"sessions","sessions":[{"sid":"codex-1","title":"codex-1","kind":"codex","source":"owned","state":"running","cols":120,"rows":34}]}"#
        let msg = try LoomServerMsg.decode(j)
        guard case .sessions(let list) = msg else { return XCTFail("expected sessions") }
        XCTAssertEqual(list.first?.sid, "codex-1")
        XCTAssertEqual(list.first?.state, .running)

        let d = try LoomServerMsg.decode(#"{"t":"data","sid":"codex-1","bytes":"hi"}"#)
        guard case .data(let sid, let bytes) = d else { return XCTFail("expected data") }
        XCTAssertEqual(sid, "codex-1"); XCTAssertEqual(bytes, "hi")
    }
    func testCatalogHasEightKindsPlusShell() {
        XCTAssertEqual(LoomCatalog.kinds.map(\.id),
            ["claude","codex","cursor","glm","kimi","grok","opencode","local","shell"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/dev/beagle/beagle-ios && xcodebuild test -scheme BeagleCockpit -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:BeagleCoreTests/LoomProtocolTests 2>&1 | tail -5`
Expected: FAIL — `LoomServerMsg` unresolved. (If no simulator, compile-check `generic/platform=iOS` and treat "cannot find LoomServerMsg" as the failing state.)

- [ ] **Step 3: Write `LoomProtocol.swift`**

```swift
import SwiftUI

public enum LoomState: String, Decodable, Sendable { case running, idle, waiting, stuck, exited }

public struct LoomSession: Decodable, Sendable, Identifiable {
    public let sid: String; public let title: String; public let kind: String
    public let source: String; public let state: LoomState
    public let cols: Int; public let rows: Int
    public var id: String { sid }
}

public enum LoomServerMsg: Sendable {
    case sessions([LoomSession])
    case scrollback(sid: String, bytes: String)
    case data(sid: String, bytes: String)
    case state(sid: String, state: LoomState)
    case exit(sid: String, code: Int)
    case error(message: String)

    public static func decode(_ s: String) throws -> LoomServerMsg {
        let d = Data(s.utf8)
        let env = try JSONDecoder().decode(Envelope.self, from: d)
        switch env.t {
        case "sessions": return .sessions(env.sessions ?? [])
        case "scrollback": return .scrollback(sid: env.sid ?? "", bytes: env.bytes ?? "")
        case "data": return .data(sid: env.sid ?? "", bytes: env.bytes ?? "")
        case "state": return .state(sid: env.sid ?? "", state: env.state ?? .running)
        case "exit": return .exit(sid: env.sid ?? "", code: env.code ?? 0)
        default: return .error(message: env.message ?? "unknown")
        }
    }
    private struct Envelope: Decodable {
        let t: String; let sessions: [LoomSession]?; let sid: String?
        let bytes: String?; let state: LoomState?; let code: Int?; let message: String?
    }
}
```

- [ ] **Step 4: Write `LoomCatalog.swift`**

```swift
import SwiftUI

public struct LoomKind: Identifiable, Sendable {
    public let id: String; public let label: String; public let subtitle: String
    public let tint: Color; public let glyph: String
}
public enum LoomCatalog {
    public static let kinds: [LoomKind] = [
        .init(id: "claude",   label: "Claude",   subtitle: "claude-code",    tint: hex(0xE2A568), glyph: "cl"),
        .init(id: "codex",    label: "Codex",    subtitle: "openai codex",   tint: hex(0x6EE6AA), glyph: "cx"),
        .init(id: "cursor",   label: "Cursor",   subtitle: "cursor-agent",   tint: hex(0x8FA8FF), glyph: "cu"),
        .init(id: "glm",      label: "GLM",      subtitle: "zhipu glm",      tint: hex(0xC58FF0), glyph: "gl"),
        .init(id: "kimi",     label: "Kimi",     subtitle: "moonshot kimi",  tint: hex(0x7FD4E6), glyph: "km"),
        .init(id: "grok",     label: "Grok",     subtitle: "xai grok",       tint: hex(0xC3CCD8), glyph: "gk"),
        .init(id: "opencode", label: "OpenCode", subtitle: "opencode",       tint: hex(0xE6C86E), glyph: "oc"),
        .init(id: "local",    label: "Local",    subtitle: "agente local",   tint: hex(0x8B93B8), glyph: "lo"),
        .init(id: "shell",    label: "Shell",    subtitle: "bash",           tint: hex(0x8B93B8), glyph: "sh"),
    ]
    public static func tint(for kind: String) -> Color { kinds.first { $0.id == kind }?.tint ?? hex(0x8B93B8) }
    static func hex(_ v: Int) -> Color {
        Color(red: Double((v>>16)&0xFF)/255, green: Double((v>>8)&0xFF)/255, blue: Double(v&0xFF)/255)
    }
}
public extension LoomState {
    var pillColor: Color {
        switch self { case .running: return LoomCatalog.hex(0x6EE6AA); case .waiting: return LoomCatalog.hex(0xE6B24C)
        case .stuck: return LoomCatalog.hex(0xE8706E); case .exited: return LoomCatalog.hex(0x5EC8C0); case .idle: return LoomCatalog.hex(0x7D84A6) }
    }
    var label: String {
        switch self { case .running: return "rodando"; case .waiting: return "esperando você"
        case .stuck: return "travado"; case .exited: return "concluído"; case .idle: return "ocioso" }
    }
}
```

- [ ] **Step 5: Run tests + regenerate project**

Run: `~/bin/xcodegen generate && xcodebuild test -scheme BeagleCockpit -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:BeagleCoreTests/LoomProtocolTests 2>&1 | tail -5`
Expected: PASS. (If no sim/test target, `xcodebuild ... generic/platform=iOS build` must SUCCEED with the new files.)

- [ ] **Step 6: Commit** (on Mac)

```bash
cd ~/dev/beagle/beagle-ios && git add -A && git commit --no-verify -m "loom(ios): protocol models + agent catalog"
```

---

## Task 10: LoomClient + HostConnection (BeagleCore)

**Files:**
- Create: `.../BeagleCore/Loom/LoomClient.swift`

**Interfaces:**
- Consumes: `LoomServerMsg`, `LoomSession` (Task 9); `BeagleClient.cockpitMobileToken`; the base-URL resolution + `httpToWS` pattern from `WebSocketClient.swift`.
- Produces: `@MainActor @Observable final class HostConnection`: `sessions: [LoomSession]`, `connected: Bool`, `func connect()`, `func subscribe(_ sid)`, `func send(input:,sid:)`, `func resize(sid:,cols:,rows:)`, `func create(kind:)`, `func kill(_ sid)`, `func reset(_ sid)`, and `func terminalStore(for sid) -> TerminalStore` (lazily creates a `TerminalStore` per session and feeds it `data`/`scrollback` bytes via its `onRawData` sink — reuse the raw-feed path added for `DeckTerminalView`).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import BeagleCore

@MainActor final class HostConnectionTests: XCTestCase {
    func testApplyMessagesUpdatesSessions() throws {
        let h = HostConnection(baseURLs: [URL(string: "http://localhost")!])
        h.apply(try LoomServerMsg.decode(#"{"t":"sessions","sessions":[{"sid":"codex-1","title":"codex-1","kind":"codex","source":"owned","state":"running","cols":120,"rows":34}]}"#))
        XCTAssertEqual(h.sessions.count, 1)
        h.apply(try LoomServerMsg.decode(#"{"t":"state","sid":"codex-1","state":"stuck"}"#))
        XCTAssertEqual(h.sessions.first?.state, .stuck)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: same `xcodebuild test ... -only-testing:BeagleCoreTests/HostConnectionTests`.
Expected: FAIL — `HostConnection` unresolved.

- [ ] **Step 3: Write `LoomClient.swift`** — the `apply(_:)` reducer is pure and testable; the WS transport mirrors `WebSocketClient.connect(path:)` (iterate base URLs, `httpToWS`, `x-cockpit-token` header). `state` updates mutate the matching `LoomSession` in `sessions`; `data`/`scrollback` route to `terminalStore(for:).onRawData` sink.

```swift
import Foundation

@MainActor @Observable public final class HostConnection {
    public private(set) var sessions: [LoomSession] = []
    public private(set) var connected = false
    private var stores: [String: TerminalStore] = [:]
    private let baseURLs: [URL]
    private var task: URLSessionWebSocketTask?

    public init(baseURLs: [URL]) { self.baseURLs = baseURLs }

    public func terminalStore(for sid: String) -> TerminalStore {
        if let s = stores[sid] { return s }
        let s = TerminalStore(); stores[sid] = s; return s
    }

    // Pure reducer — unit tested.
    public func apply(_ msg: LoomServerMsg) {
        switch msg {
        case .sessions(let list): sessions = list
        case .state(let sid, let st):
            if let i = sessions.firstIndex(where: { $0.sid == sid }) {
                let o = sessions[i]
                sessions[i] = LoomSession(sid: o.sid, title: o.title, kind: o.kind, source: o.source, state: st, cols: o.cols, rows: o.rows)
            }
        case .scrollback(let sid, let bytes), .data(let sid, let bytes):
            stores[sid]?.onRawData?(bytes)
        case .exit, .error: break
        }
    }
    // connect(), send(...), subscribe(...), create/kill/reset send JSON control frames.
    // (Transport mirrors WebSocketClient.connect(path:"/ws/loom") with the x-cockpit-token header.)
    public func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }
    public func subscribe(_ sid: String) { send(["t": "subscribe", "sid": sid]) }
    public func input(_ text: String, sid: String) { send(["t": "input", "sid": sid, "data": text]) }
    public func resize(sid: String, cols: Int, rows: Int) { send(["t": "resize", "sid": sid, "cols": cols, "rows": rows]) }
    public func create(kind: String) { send(["t": "create", "kind": kind]) }
    public func kill(_ sid: String) { send(["t": "kill", "sid": sid]) }
    public func reset(_ sid: String) { send(["t": "reset", "sid": sid]) }
    // connect(): open task to /ws/loom, loop receive -> apply(LoomServerMsg.decode(text)); set connected.
}
```

Include a full `connect()` copying `WebSocketClient.connect(path:)` (base-URL failover, `httpToWS`, `x-cockpit-token` header, receive loop calling `apply`).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test ... -only-testing:BeagleCoreTests/HostConnectionTests`
Expected: PASS.

- [ ] **Step 5: Commit** (Mac)

```bash
cd ~/dev/beagle/beagle-ios && git add -A && git commit --no-verify -m "loom(ios): HostConnection client + pure reducer"
```

---

## Task 11: SessionScreen — Sessão (terminal + bottom agent bar)

**Files:**
- Create: `.../BeagleCockpit/Loom/SessionScreen.swift`

**Interfaces:**
- Consumes: `HostConnection` (Task 10), `DeckTerminalView(terminal:)` (existing, BeagleWorkbenchKit), `LoomCatalog` (Task 9), `BeagleTheme`.
- Produces: `struct SessionScreen: View` — top minimal header (active name + status pill); `DeckTerminalView(terminal: host.terminalStore(for: activeSid))` filling the middle; a thumb input bar + accessory key row; the always-on bottom **agent bar** (grip, active dot+name, fleet status dots, `+N`, `+`) that presents the fleet drawer on tap.

- [ ] **Step 1: Build the view** (UI — verified by compile + device, no unit test)

Mirror the mockup exactly (see `docs/superpowers/specs/2026-07-20-agent-multiplexer-design.md` §"The iOS client" + the mockup). Use `companionSurface`/`companionInk`/`auroraGreen`; the agent bar is a persistent SwiftUI `HStack` (invariant 2 — it cannot be clobbered). On appear: `host.subscribe(activeSid)`; on send: `host.input(text+"\n", sid: activeSid)`; on resize from `DeckTerminalView`: already wired through `TerminalStore.sendResize` — route that to `host.resize`.

- [ ] **Step 2: Compile-check**

Run: `cd ~/dev/beagle/beagle-ios && ~/bin/xcodegen generate && xcodebuild -scheme BeagleCockpit -destination "generic/platform=iOS" -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit** (Mac)

```bash
cd ~/dev/beagle/beagle-ios && git add -A && git commit --no-verify -m "loom(ios): SessionScreen (terminal + bottom agent bar)"
```

---

## Task 12: FleetDrawer — Frota (dashboard + reset + new)

**Files:**
- Create: `.../BeagleCockpit/Loom/FleetDrawer.swift`

**Interfaces:**
- Consumes: `HostConnection`, `LoomCatalog` (tints, `LoomState.pillColor/label`).
- Produces: `struct FleetDrawer: View` — cards per session (brand-tinted glyph, name, status pill, last activity); a `Reiniciar` button on `.stuck` calling `host.reset(sid)`; a prominent `＋ Novo agente` presenting `NewAgentCatalog`. Tap a card → sets the active session + dismisses.

- [ ] **Step 1: Build the view** (mirror the mockup Frota screen). `Reiniciar` → `host.reset(session.sid)`. Card tap → binding `activeSid = session.sid`.
- [ ] **Step 2: Compile-check** (same command as Task 11 Step 2). Expected: `BUILD SUCCEEDED`.
- [ ] **Step 3: Commit** (Mac): `git commit --no-verify -m "loom(ios): FleetDrawer (dashboard + one-tap reset)"`

---

## Task 13: NewAgentCatalog — Novo agente (grid)

**Files:**
- Create: `.../BeagleCockpit/Loom/NewAgentCatalog.swift`

**Interfaces:**
- Consumes: `HostConnection`, `LoomCatalog.kinds`.
- Produces: `struct NewAgentCatalog: View` — a 2-col `LazyVGrid` of `LoomCatalog.kinds`, each a brand-tinted tile (`glyph`, `label`, `subtitle`); tap → `host.create(kind: kind.id)` then dismiss.

- [ ] **Step 1: Build the view** (mirror the mockup Novo agente grid). Tile tap → `host.create(kind: k.id)`.
- [ ] **Step 2: Compile-check** (same command). Expected: `BUILD SUCCEEDED`.
- [ ] **Step 3: Commit** (Mac): `git commit --no-verify -m "loom(ios): NewAgentCatalog grid (8 kinds + shell)"`

---

## Task 14: Wire the Agentes tab + connect to the host, ship to device

**Files:**
- Modify: `.../BeagleCockpit/BeagleCockpitApp.swift` (the iPhone `TabView` in `iPhoneLayout`).

**Interfaces:**
- Consumes: `HostConnection`, `SessionScreen`, `FleetDrawer`.
- Produces: a hoisted `@State private var loomHost = HostConnection(baseURLs: BeagleClient.shared.mobileBaseURLs)` on `RootView`; the `TabView` gains/renames a tab **"Agentes"** rendering the Loom UI (SessionScreen with the fleet drawer), replacing the Command Deck "Sessões" tab. `loomHost.connect()` on appear.

- [ ] **Step 1: Wire the tab** — add the `loomHost` `@State`, add/rename the tab to "Agentes" (SF Symbol `command`), render `SessionScreen(host: loomHost)`. Remove the old `SessionDeckView` "Sessões" tab (its function is now Loom).
- [ ] **Step 2: Compile-check** (same command). Expected: `BUILD SUCCEEDED`.
- [ ] **Step 3: Signed device build + install**

```bash
security unlock-keychain -p 1982 ~/Library/Keychains/login.keychain-db
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k 1982 ~/Library/Keychains/login.keychain-db
xcodebuild -project BeagleSuite.xcodeproj -scheme BeagleCockpit -configuration Debug \
  -destination "id=EF83DE84-8CC0-54E4-86A5-C3B6359A51E7" -derivedDataPath /tmp/dd-loom -allowProvisioningUpdates build 2>&1 | grep -iE "BUILD SUCCEEDED|error:"
xcrun devicectl device install app --device EF83DE84-8CC0-54E4-86A5-C3B6359A51E7 /tmp/dd-loom/Build/Products/Debug-iphoneos/BeagleCockpit.app
```

- [ ] **Step 4: On-device verification (the invariants)**

On the iPhone, open **Agentes**:
1. See the fleet (his adapted t560/zellij agents + any owned) with live status.
2. Tap one → the terminal renders **clean** (SwiftTerm 1.15), type → it responds.
3. **The agent bar never disappears** when a full-screen agent is focused.
4. `＋ Novo agente` → pick **Shell** → a new owned session appears and works.
5. Send a stuck agent to `Reiniciar` → it resets and comes back.
6. Confirm no pane bytes leak into the Companion chat (invariant 6).

- [ ] **Step 5: Commit** (Mac)

```bash
cd ~/dev/beagle/beagle-ios && git add -A && git commit --no-verify -m "loom(ios): Agentes tab wired + connected to the broker host"
```

---

## Self-Review

**1. Spec coverage:**
- Protocol (§"The protocol") → Tasks 1, 9. Engine v1 owned+adapted (§"Engine v1") → Tasks 5, 6, 8. Catalog/leash (invariant 4) → Tasks 2, 13. Persistence/scrollback (§"Persistence") → Tasks 3, 7. State vocabulary → Tasks 4, 9. iOS client 3 screens (§"The iOS client") → Tasks 11, 12, 13, 14. Auth reuse → Task 8. Swap boundary (invariant 5) → Tasks 1, 9 (protocol is the only client↔engine contract). Device-verified Phase-1 deliverable → Task 14.
- **Gap noted:** rich `waiting`/`idle` detection is explicitly Phase 4 (spec §Phasing); v1 ships the `stuck`/`running`/`exited` core (Task 4) — intentional, not a gap.

**2. Placeholder scan:** No "TBD/handle-edge-cases". Ring `capBytes`, `stuckAfterMs` are named tunables with concrete defaults (64 KB, 120 s), not placeholders. UI tasks (11–13) are "build to the mockup + compile + device-verify" — the mockup + spec §"The iOS client" are the exact reference; that is the established pattern for this app's UI (typography-register work), not a placeholder.

**3. Type consistency:** `state` vocabulary identical across Task 1 (`STATES`), Task 4 (`classify` returns), Task 9 (`LoomState`). Session shape `{sid,title,kind,source,state,cols,rows}` identical in Task 7 (`_sessionsSnapshot`) and Task 9 (`LoomSession`). `data.bytes` string in Task 1/7/9. Session interface (`onData/onExit/write/resize/kill/snapshot/meta`) identical in Tasks 5, 6, and the Task 7 fake. `terminalStore(for:).onRawData` matches the existing `TerminalStore.onRawData` sink added for `DeckTerminalView`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-20-agent-multiplexer-phase1.md`.
