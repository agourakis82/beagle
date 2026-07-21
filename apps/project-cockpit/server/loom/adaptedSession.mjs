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
