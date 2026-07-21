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
