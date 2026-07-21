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
  startStatePump(intervalMs = 20000) {
    this._pump = setInterval(() => { if (this._clients.size) this._broadcastSessions(); }, intervalMs);
    this._pump?.unref?.();
  }
  stopStatePump() { clearInterval(this._pump); this._pump = null; }
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
        const sid = nextSid(m.kind);
        try {
          const sess = this._factory(sid, m.kind);
          this._sessions.set(sid, sess); this._wire(sess); this._broadcastSessions();
        } catch {
          return this._send(sock, { t: "error", message: "failed to start session" });
        }
        return;
      }
      case "kill": if (s) { s.kill(); this._sessions.delete(m.sid); this._broadcastSessions(); } return;
      case "reset": {
        if (!s) return;
        const kind = s.meta.kind; s.kill(); this._sessions.delete(m.sid);
        const sid = nextSid(kind);
        try {
          const sess = this._factory(sid, kind);
          this._sessions.set(sid, sess); this._wire(sess); this._broadcastSessions();
        } catch {
          return this._send(sock, { t: "error", message: "failed to start session" });
        }
        return;
      }
    }
  }
}
