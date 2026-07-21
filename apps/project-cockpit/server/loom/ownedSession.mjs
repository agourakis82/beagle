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
