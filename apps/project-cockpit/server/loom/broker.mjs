// broker.mjs — the chrome-less engine core: a session registry that speaks the protocol.
import { decodeClient, encodeServer } from "./protocol.mjs";
import { recipeFor } from "./catalog.mjs";
import { classify } from "./state.mjs";
import { LazySession } from "./lazySession.mjs";

let _seq = 0;
const nextSid = (kind) => `${kind}-${++_seq}`;

export class Broker {
  constructor({ sessionFactory, laneStates = null }) {
    this._factory = sessionFactory;      // (sid, kind) -> session
    this._sessions = new Map();          // sid -> session
    this._clients = new Set();           // sockets
    this._subs = new Map();              // socket -> Set(sid)
    this._laneStates = laneStates;       // LanePoller-like: get(sid) -> verdict | null
  }
  addSeed(session) { this._sessions.set(session.sid, session); this._wire(session); }
  // Advertise an existing attachable session; it attaches (materializes) on first subscribe.
  addLazySeed(sid, kind, factory, opts = {}) {
    const ls = new LazySession(sid, kind, factory, opts);
    this._sessions.set(sid, ls); this._wire(ls);
  }
  startStatePump(intervalMs = 20000) {
    this._pump = setInterval(() => { if (this._clients.size) this._broadcastSessions(); }, intervalMs);
    this._pump?.unref?.();
  }
  stopStatePump() { clearInterval(this._pump); this._pump = null; }
  _wire(session) {
    session.onData((d) => this._toSubscribers(session.sid, { t: "data", sid: session.sid, bytes: d }));
    session.onExit(() => { this._broadcastState(session.sid); this._broadcastSessions(); });
  }
  /// A polled lane verdict (real screen read) beats any stream-derived guess — it is true even
  /// for lanes nobody is watching. Returns null when we have never observed the lane.
  _observed(sid) { return this._laneStates?.get?.(sid) || null; }

  _stateOf(session) {
    const obs = this._observed(session.sid);
    if (obs) return obs.state;
    if (session.lazyPending) return "unknown";   // seeded, never attached, never peeked
    const m = session.meta;
    return classify({ alive: m.alive, lastOutputAt: m.lastOutputAt, now: Date.now() });
  }
  _sessionsSnapshot() {
    return [...this._sessions.values()].map((s) => {
      const m = s.meta;
      const obs = this._observed(m.sid);
      return {
        sid: m.sid, title: m.title || m.sid, kind: m.kind, source: m.source,
        state: this._stateOf(s),
        // The evidence for the verdict — the UI quotes this instead of asserting a bare state.
        detail: obs?.detail || "",
        peek: obs?.peek || [],
        approveKey: obs?.approveKey || null,
        // Truth-mode metadata: when this was actually observed (null = we are guessing).
        observedAt: obs?.observedAt || null,
        cols: m.cols, rows: m.rows,
      };
    });
  }
  _send(sock, msg) { try { sock.send(encodeServer(msg)); } catch { /* closed */ } }
  _broadcastSessions() { const snap = this._sessionsSnapshot(); for (const c of this._clients) this._send(c, { t: "sessions", sessions: snap }); }
  _broadcastState(sid) {
    const s = this._sessions.get(sid); if (!s) return;
    const obs = this._observed(sid);
    const msg = { t: "state", sid, state: this._stateOf(s), detail: obs?.detail || "", observedAt: obs?.observedAt || null };
    for (const c of this._clients) this._send(c, msg);
  }
  _toSubscribers(sid, msg) { for (const c of this._clients) if (this._subs.get(c)?.has(sid)) this._send(c, msg); }
  _subscriberCount(sid) { let n = 0; for (const set of this._subs.values()) if (set.has(sid)) n++; return n; }
  // When the last viewer of a lazy (attached) session leaves, detach its real client so it
  // stops constraining other clients (e.g. a shared zellij shrinking his Mac). Seed stays.
  _maybeDetach(sid) {
    const s = this._sessions.get(sid);
    if (s && typeof s.dematerialize === "function" && this._subscriberCount(sid) === 0) {
      s.dematerialize();
      this._broadcastSessions();
    }
  }

  handleConnection(sock) {
    this._clients.add(sock); this._subs.set(sock, new Set());
    console.log(`[loom] client connected (clients=${this._clients.size}, sessions=${this._sessions.size})`);
    this._send(sock, { t: "sessions", sessions: this._sessionsSnapshot() });
    sock.on("message", (raw) => this._onMessage(sock, raw));
    sock.on("close", () => {
      const sids = [...(this._subs.get(sock) || [])];
      this._clients.delete(sock); this._subs.delete(sock);
      for (const sid of sids) this._maybeDetach(sid);   // release attaches this socket held
    });
  }
  _onMessage(sock, raw) {
    const m = decodeClient(String(raw));
    if (!m) return this._send(sock, { t: "error", message: "bad message" });
    const s = m.sid ? this._sessions.get(m.sid) : null;
    switch (m.t) {
      case "hello": case "list": return this._send(sock, { t: "sessions", sessions: this._sessionsSnapshot() });
      case "subscribe": {
        console.log(`[loom] subscribe ${m.sid} (exists=${!!s}, lazyPending=${s?.lazyPending})`);
        if (!s) return this._send(sock, { t: "error", sid: m.sid, message: "no such session" });
        this._subs.get(sock).add(m.sid);
        if (s.lazyPending) {
          try { s.materialize(); this._broadcastSessions(); }
          catch { return this._send(sock, { t: "error", sid: m.sid, message: "failed to attach" }); }
        }
        return this._send(sock, { t: "scrollback", sid: m.sid, bytes: s.snapshot() });
      }
      case "unsubscribe": this._subs.get(sock).delete(m.sid); this._maybeDetach(m.sid); return;
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
