// lazySession.mjs — a seeded session that attaches its real (Adapted) session LAZILY, on
// first subscribe. Lets the broker advertise his existing attachable sessions (tmux/zellij)
// without attaching N PTYs at boot (each attach is a kubectl exec + a client on the real
// multiplexer). Conforms to the same session interface the broker consumes.
export class LazySession {
  constructor(sid, kind, factory, { title = null } = {}) {
    this.sid = sid; this.kind = kind; this._title = title || sid;
    this._factory = factory; this._real = null;
    this._dataCbs = []; this._exitCbs = [];
  }
  get lazyPending() { return this._real === null; }
  materialize() {
    if (this._real) return;
    this._real = this._factory();                 // constructs + attaches the real session
    this._real.onData((d) => { for (const cb of this._dataCbs) cb(d); });
    this._real.onExit((c) => { for (const cb of this._exitCbs) cb(c); });
  }
  onData(fn) { this._dataCbs.push(fn); }
  onExit(fn) { this._exitCbs.push(fn); }
  write(data) { this._real?.write(data); }
  resize(cols, rows) { this._real?.resize(cols, rows); }
  kill() { this._real?.kill(); this._real = null; }
  snapshot() { return this._real ? this._real.snapshot() : ""; }
  get meta() {
    if (this._real) return { ...this._real.meta, title: this._title };
    // unattached seed: advertise as a ready, idle session (fresh lastOutputAt so the state
    // pump never mislabels a not-yet-opened seed as stuck).
    return { sid: this.sid, kind: this.kind, title: this._title, source: "adapted",
      cols: 120, rows: 34, alive: true, lastOutputAt: Date.now() };
  }
}
