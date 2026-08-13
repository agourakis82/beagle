// broker.mjs — the chrome-less engine core: a session registry that speaks the protocol.
import { decodeClient, encodeServer } from "./protocol.mjs";
import { recipeFor } from "./catalog.mjs";
import { classify } from "./state.mjs";
import { LazySession } from "./lazySession.mjs";
import { fuseFleet, EXACT, INFERRED } from "./loomd.mjs";

let _seq = 0;
const nextSid = (kind) => `${kind}-${++_seq}`;

export class Broker {
  constructor({ sessionFactory, laneStates = null }) {
    this._factory = sessionFactory;      // (sid, kind) -> session
    this._sessions = new Map();          // sid -> session
    this._clients = new Set();           // sockets
    this._subs = new Map();              // socket -> Set(sid)
    this._laneStates = laneStates;       // LanePoller-like: get(sid) -> verdict | null
    // O último `usd` MEDIDO por sid, sobrevivendo à perda da fonte exata. Ver o comentário em
    // `_broadcastState`: custo é fato do passado — perder o loomd não desfaz o gasto, então o
    // ramo `inferred` congela isto em vez de reportar zero.
    this._lastUsd = new Map();
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
  /// ws ping/pong keepalive. A half-open socket (peer vanished without a FIN/RST — a laptop
  /// that slept, a NAT that dropped the mapping) never fires `close`, so nothing here relies
  /// on it: the tick itself does the same cleanup `close` would have done.
  startHeartbeat({ intervalMs = 20000 } = {}) {
    this._heartbeat = setInterval(() => this._heartbeatTick(), intervalMs);
    this._heartbeat?.unref?.();
  }
  stopHeartbeat() { clearInterval(this._heartbeat); this._heartbeat = null; }
  _heartbeatTick() {
    let reaped = 0;
    for (const sock of [...this._clients]) {
      if (sock.__vivo !== true) {
        // Missed the previous ping's pong — presumed half-open. Reap explicitly; do not
        // wait for `close` to fire, because on a half-open socket it never will.
        if (typeof sock.terminate === "function") sock.terminate();
        else sock.close?.();
        const sids = [...(this._subs.get(sock) || [])];
        this._clients.delete(sock); this._subs.delete(sock);
        for (const sid of sids) this._maybeDetach(sid);
        reaped++;
      } else {
        sock.__vivo = false;
        sock.ping?.();
      }
    }
    if (reaped) {
      console.log(`[loom] heartbeat reaped ${reaped} dead client(s) (clients=${this._clients.size})`);
    }
  }
  _wire(session) {
    session.onData((d) => this._toSubscribers(session.sid, { t: "data", sid: session.sid, bytes: d }));
    session.onExit(() => { this._broadcastState(session.sid); this._broadcastSessions(); });
  }
  /// A polled lane verdict (real screen read) beats any stream-derived guess — it is true even
  /// for lanes nobody is watching. Returns null when we have never observed the lane.
  _observed(sid) { return this._laneStates?.get?.(sid) || null; }

  /// A leitura MEDIDA no protocolo (loomd), quando existe. Map vazio = ninguém é `exact`, que é
  /// o lado seguro: um board sem a fonte boa mostra exatamente o que mostrava ontem, e diz que
  /// perdeu a fonte por `loomdTruth()` — nunca promovendo um chute a medição.
  _loomdLanes() {
    const m = this._laneStates?.loomdAll?.();
    if (!(m instanceof Map)) return new Map();
    // Toda vez que vemos um `usd` medido, ele vira o "último conhecido" daquele sid — não só
    // quando `_broadcastState` roda para ele. É deliberadamente o único lugar que grava
    // `_lastUsd`: qualquer leitura das lanes do loomd (patch OU snapshot cheio) passa por aqui.
    for (const [sid, card] of m) if (typeof card.usd === "number") this._lastUsd.set(sid, card.usd);
    return m;
  }
  _loomdTruth() {
    return this._laneStates?.loomdTruth?.()
      || { mode: "unknown", truthMode: "unknown", observedAt: null, lanes: 0, lost: [], error: "sem leitor loomd" };
  }

  _stateOf(session) {
    const obs = this._observed(session.sid);
    if (obs) return obs.state;
    if (session.lazyPending) return "unknown";   // seeded, never attached, never peeked
    const m = session.meta;
    return classify({ alive: m.alive, lastOutputAt: m.lastOutputAt, now: Date.now() });
  }
  /// O array de cards, já rotulado. `fuseFleet` é quem garante o invariante: tudo que veio de
  /// `capture-pane` sai `inferred` — literal, não derivado — e só o que o loomd serviu sai
  /// `exact`. Lanes que só o loomd conhece entram como cards ADICIONAIS, sem apagar ninguém.
  ///
  /// 🚨 `this._lastUsd` viaja como terceiro argumento para que o FRAME CHEIO também congele
  /// `usd` quando uma lane perde a contraparte no loomd — antes só o PATCH de lane única
  /// (`_broadcastState`) fazia isso, e o frame cheio (mandado a cada 20s por `startStatePump`)
  /// reintroduzia a ausência a cada sweep, apagando o congelamento na prática. A ordem dos
  /// argumentos abaixo importa: `this._loomdLanes()` é quem ATUALIZA `_lastUsd` com os valores
  /// deste sweep (ver o comentário lá), e por avaliação esquerda-para-direita ele já rodou antes
  /// de `fuseFleet` ler `this._lastUsd`.
  _sessionsSnapshot() {
    return fuseFleet(this._peekedSnapshot(), this._loomdLanes(), this._lastUsd);
  }
  _peekedSnapshot() {
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
        // Command or patch, read off the dialog's own words (laneState.approvalKindOf) — the
        // same vocabulary the loomd path speaks. `null` when the screen carries no such words.
        approvalKind: obs?.approvalKind || null,
        // `capture-pane` never sees a real diff, only the dialog text — declaring this
        // explicitly (never omitted) says "we don't have one" instead of leaving the key
        // absent, which a client could read as "keep whatever it had before".
        hasDiff: false,
        diff: null,
        // At a SHELL, not an agent's input box — the client must not draw an action that types
        // a command where an agent would read it as a request.
        atShell: obs?.atShell === true,
        // A lane não existe no tmux — DECLARADO, não inferido do texto do `detail`.
        ausente: obs?.ausente === true,
        // Truth-mode metadata: when this was actually observed (null = we are guessing).
        observedAt: obs?.observedAt || null,
        cols: m.cols, rows: m.rows,
      };
    });
  }
  _send(sock, msg) { try { sock.send(encodeServer(msg)); } catch { /* closed */ } }
  /// UM construtor para TODO frame `sessions` — o da conexão, o do `list` e o do pump. Eram três
  /// literais separados, e um campo novo em dois deles é exatamente como um cliente passa a ver
  /// o rótulo só às vezes.
  ///
  /// O frame carrega a saúde da fonte exata junto com os cards. Sem isso, o loomd cair produz um
  /// board indistinguível do de ontem — todo mundo `inferred`, nada quebrado, nenhum aviso: o
  /// falso-positivo mais provável desta fatia. `loomd.mode` é o que torna a queda visível.
  _sessionsFrame() {
    return { t: "sessions", sessions: this._sessionsSnapshot(), loomd: this._loomdTruth() };
  }
  _broadcastSessions() {
    const frame = this._sessionsFrame();
    for (const c of this._clients) this._send(c, frame);
  }
  _broadcastState(sid) {
    const s = this._sessions.get(sid); if (!s) return;
    const obs = this._observed(sid);
    const exact = this._loomdLanes().get(sid) || null;
    // O patch de lane única PRECISA carregar `confidence`: um cliente que faz `?? old` num campo
    // ausente congelaria o rótulo antigo, e uma lane que perdeu a fonte exata continuaria
    // desenhada como medida. `aceita` e `usd` têm o mesmo risco de congelamento, mas — achado da
    // review — a CURA não é a mesma para os dois, porque são afirmações de natureza oposta:
    //
    // 🚨 `aceita` é afirmação sobre CAPACIDADE ATUAL — pode ter mudado, e perder a fonte é
    // literalmente não saber mais. O ramo `inferred` manda `null`, não o último valor visto:
    // `aceita` só existe porque o loomd DECLAROU a lane num dos três conjuntos (codex/acp/tails);
    // perder a contraparte é perder a única fonte que sabia responder isso. `null` já é o
    // vocabulário do "não sei" deste campo (é o que `loomdCard` manda para uma lane ainda não
    // declarada) — reaproveitá-lo aqui empurra a tela para o lado seguro: não oferecer o gesto,
    // em vez de arriscar um botão GUIAR sobrevivendo numa lane que virou somente-leitura.
    //
    // `usd` é FATO DO PASSADO — um gasto acumulado. Perder o loomd não desfaz o que já foi
    // gasto, então mandar `0` aqui apagaria um fato em vez de admitir ignorância: uma lane com
    // US$ 12,50 acumulados que perde a fonte exata NÃO ficou de graça, e como o chip esconde
    // zero, o número sumiria da tela — a UI passaria a afirmar "não custou nada" quando só
    // perdeu quem confirmava o custo. O ramo `inferred` CONGELA o último `usd` medido
    // (`_lastUsd`, atualizado toda vez que `_loomdLanes()` vê um valor) e só cai para `0` quando
    // nunca houve leitura — aí `0` é honesto: nada foi gasto, ou nada foi observado, e o chip não
    // mostra nada nos dois casos.
    // 🚨 `loomdKind` segue a regra do `aceita`, não a do `usd`: ele diz QUAL foi o último evento
    // do protocolo, e a tela usa isso para escolher a VOZ da linha de evidência — título (um
    // nome que o agente escolheu), fala (algo dito) ou leitura (raspada da tela). Perder a
    // contraparte no loomd é perder quem sabia responder isso, e o `detail` deste ramo vem do
    // `capture-pane`: mandar o último kind conhecido casaria uma voz de protocolo com um texto
    // de tela — exatamente a mentira que `fuseFleet` recusa ao não herdar o `detail`. `null` é o
    // vocabulário de "não sei" aqui, e o cliente já cai para `leitura` por causa do `inferred`.
    const msg = exact
      ? { t: "state", sid, state: exact.state, detail: exact.detail, confidence: EXACT,
          approveKey: null, atShell: false, observedAt: exact.observedAt,
          aceita: exact.aceita ?? null, usd: Number(exact.usd) || 0,
          loomdKind: exact.loomdKind ?? null, ausente: false,
          agentTitle: exact.agentTitle ?? null,
          // Mesmo defeito do `loomdKind` (sexta vez, ver o teste): sem estas duas no PATCH de
          // lane única, o botão de aprovação e o DiffView caem no `?? antigo` do cliente e
          // congelam o pedido anterior em vez do atual — ou pior, somem em silêncio se o
          // cliente não tiver fallback nenhum.
          approvalKind: exact.approvalKind ?? null, hasDiff: exact.hasDiff === true, diff: exact.diff ?? null }
      : { t: "state", sid, state: this._stateOf(s), detail: obs?.detail || "", confidence: INFERRED,
          approveKey: obs?.approveKey || null, atShell: obs?.atShell === true, observedAt: obs?.observedAt || null,
          // Tela raspada nunca sabe um diff de verdade — só o texto do diálogo. Declarado
          // explícito (nunca ausente) pelo mesmo motivo de `_peekedSnapshot`.
          approvalKind: obs?.approvalKind || null, hasDiff: false, diff: null,
          aceita: null, usd: this._lastUsd.get(sid) ?? 0,
          // Uma lane com contraparte no loomd existe por construção; sem ela, quem sabe é a tela.
          // Sem a fonte exata não há quem saiba o nome: `null` é "não sei", e a tela cala.
          loomdKind: null, ausente: obs?.ausente === true, agentTitle: null };
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
    sock.__vivo = true;
    console.log(`[loom] client connected (clients=${this._clients.size}, sessions=${this._sessions.size})`);
    this._send(sock, this._sessionsFrame());
    sock.on("message", (raw) => this._onMessage(sock, raw));
    sock.on("pong", () => { sock.__vivo = true; });
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
      case "hello": case "list": return this._send(sock, this._sessionsFrame());
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
