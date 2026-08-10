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
  const s = { sent: [], handlers: {}, pinged: 0, terminated: false,
    on(ev,f){ s.handlers[ev]=f; }, send(str){ s.sent.push(JSON.parse(str)); },
    recv(obj){ s.handlers.message(JSON.stringify(obj)); },
    ping(){ s.pinged++; }, terminate(){ s.terminated = true; } };
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

test("broker: factory throw on create sends error frame, does not crash, does not add session", () => {
  // "codex" is a valid catalog kind (passes recipeFor gating) but the factory itself
  // throws (e.g. node-pty spawn error), mirroring a real makeSessionFactory failure mode.
  const factory = (sid, kind) => { throw new Error("spawn failed"); };
  const broker = new Broker({ sessionFactory: factory });
  const sock = fakeSocket();
  broker.handleConnection(sock);

  assert.doesNotThrow(() => sock.recv({ t: "create", kind: "codex" }));
  assert.ok(sock.sent.some((m) => m.t === "error" && m.message === "failed to start session"));
  const sessMsg = sock.sent.filter((m) => m.t === "sessions").at(-1);
  assert.equal(sessMsg.sessions.length, 0);           // no broken session registered
});

test("broker: factory throw on reset sends error frame, does not crash, old session gone", () => {
  let calls = 0;
  const factory = (sid, kind) => {
    calls += 1;
    if (calls > 1) throw new Error("respawn failed");   // first call (create) ok, respawn on reset throws
    return fakeSession(sid, kind);
  };
  const broker = new Broker({ sessionFactory: factory });
  const sock = fakeSocket();
  broker.handleConnection(sock);

  sock.recv({ t: "create", kind: "codex" });
  const sessMsg = sock.sent.filter((m) => m.t === "sessions").at(-1);
  const sid = sessMsg.sessions[0].sid;

  assert.doesNotThrow(() => sock.recv({ t: "reset", sid }));
  assert.ok(sock.sent.some((m) => m.t === "error" && m.message === "failed to start session"));

  sock.recv({ t: "list" });                             // next snapshot: old session is gone
  const finalSessMsg = sock.sent.filter((m) => m.t === "sessions").at(-1);
  assert.equal(finalSessMsg.sessions.length, 0);        // old session killed+deleted, respawn failed
});

// ─── O CONTRASTE: medido no protocolo vs. lido da tela, no MESMO frame ───────────────────────

// Um LanePoller de mentira com as DUAS fontes: `get` é a tela raspada, `loomdAll/loomdTruth` é
// o supervisor. Mesma interface do LanePoller real.
function fakeLaneStates({ peeked = {}, loomd = new Map(), truth = null } = {}) {
  return {
    get: (sid) => peeked[sid] || null,
    loomdAll: () => loomd,
    loomdTruth: () => truth || { mode: loomd.size ? "observed" : "down", truthMode: loomd.size ? "observed" : "unknown",
      observedAt: 1000, readAt: 1000, lanes: loomd.size, lost: [], error: loomd.size ? null : "loomd não respondeu" },
  };
}
const exactCard = (sid, over = {}) => ({
  sid, title: sid, kind: sid, source: "loomd", truthSource: "loomd", confidence: "exact",
  state: "waiting", loomdKind: "awaiting_approval", detail: "posso escrever em src/main.rs?",
  peek: [], approveKey: null, pendingApproval: { id: "7", method: "item/fileChange/requestApproval" },
  hasDiff: false, turns: 3, session: "t1", atShell: false, observedAt: 1000, cols: null, rows: null, ...over,
});

test("um único frame mostra loom-1 `exact` ao lado das lanes de tela `inferred`", () => {
  // Este é o produto da fatia, e a exigência é de UM frame só: duas capturas em momentos
  // diferentes provariam que as duas coisas existem, não que o operador as vê lado a lado.
  const broker = new Broker({
    sessionFactory: fakeSession,
    laneStates: fakeLaneStates({
      peeked: { "claude-1": { state: "running", detail: "● lowering the IR", peek: ["● lowering the IR"], observedAt: 999 } },
      loomd: new Map([["loom-1", exactCard("loom-1")]]),
    }),
  });
  broker.addSeed(fakeSession("claude-1", "claude-1"));
  broker.addSeed(fakeSession("codex-1", "codex-1"));
  const sock = fakeSocket();
  broker.handleConnection(sock);

  const frame = sock.sent.find((m) => m.t === "sessions");
  const byId = Object.fromEntries(frame.sessions.map((s) => [s.sid, s]));
  assert.equal(byId["loom-1"].confidence, "exact");
  assert.equal(byId["loom-1"].state, "waiting");
  assert.equal(frame.sessions.filter((s) => s.confidence === "inferred").length, 2);
  assert.equal(byId["claude-1"].truthSource, "capture-pane");
  assert.equal(frame.loomd.mode, "observed");
});

test("sem loomd, NINGUÉM é exact, nenhum card some, e o frame diz que a fonte boa caiu", () => {
  // A degradação tem de ser visível: todo mundo inferred sem aviso é indistinguível do sucesso.
  const broker = new Broker({
    sessionFactory: fakeSession,
    laneStates: fakeLaneStates({ loomd: new Map(), truth: { mode: "down", truthMode: "unknown", observedAt: 1000,
      readAt: 1000, lanes: 0, lost: ["loom-1"], error: "loomd não respondeu em 127.0.0.1:4400" } }),
  });
  broker.addSeed(fakeSession("claude-1", "claude-1"));
  broker.addSeed(fakeSession("codex-1", "codex-1"));
  const sock = fakeSocket();
  broker.handleConnection(sock);

  const frame = sock.sent.find((m) => m.t === "sessions");
  assert.equal(frame.sessions.filter((s) => s.confidence === "exact").length, 0);
  assert.equal(frame.sessions.length, 2, "o board não encolhe abaixo das lanes de tela");
  assert.equal(frame.loomd.mode, "down");
  assert.deepEqual(frame.loomd.lost, ["loom-1"], "a lane perdida é nomeada no frame");
});

test("um broker sem leitor loomd nenhum é o board de ontem mais o rótulo `inferred`", () => {
  // Degradação para o lado seguro: quem nunca ouviu falar de loomd não ganha nenhum exact.
  const broker = new Broker({ sessionFactory: fakeSession });
  broker.addSeed(fakeSession("claude-1", "claude-1"));
  const sock = fakeSocket();
  broker.handleConnection(sock);
  const frame = sock.sent.find((m) => m.t === "sessions");
  assert.equal(frame.sessions[0].confidence, "inferred");
  assert.equal(frame.loomd.mode, "unknown");
});

test("o patch de lane única também carrega `confidence` — senão o rótulo congela no cliente", () => {
  const loomd = new Map([["codex-1", exactCard("codex-1", { state: "idle", loomdKind: "idle" })]]);
  const broker = new Broker({ sessionFactory: fakeSession, laneStates: fakeLaneStates({ loomd }) });
  broker.addSeed(fakeSession("claude-1", "claude-1"));
  broker.addSeed(fakeSession("codex-1", "codex-1"));
  const sock = fakeSocket();
  broker.handleConnection(sock);

  sock.recv({ t: "kill", sid: "claude-1" });        // onExit → _broadcastState
  sock.recv({ t: "kill", sid: "codex-1" });
  const patches = sock.sent.filter((m) => m.t === "state");
  assert.equal(patches.find((m) => m.sid === "claude-1").confidence, "inferred");
  const exact = patches.find((m) => m.sid === "codex-1");
  assert.equal(exact.confidence, "exact");
  assert.equal(exact.state, "idle", "o veredito do protocolo, não o do stream");
});

// ─── Heartbeat: sockets meio-abertos não disparam `close` — o tick tem de reapar sozinho ────

test("heartbeat: tick on a live socket sends a ping and marks it awaiting pong", () => {
  const broker = new Broker({ sessionFactory: fakeSession });
  const sock = fakeSocket();
  broker.handleConnection(sock);

  broker._heartbeatTick();
  assert.equal(sock.pinged, 1);
  assert.equal(sock.__vivo, false);
});

test("heartbeat: two ticks without a pong reaps the socket and frees its subscription", () => {
  let dematerialized = 0;
  const factory = (sid, kind) => {
    const s = fakeSession(sid, kind);
    s.dematerialize = () => { dematerialized++; };
    return s;
  };
  const broker = new Broker({ sessionFactory: factory });
  const sock = fakeSocket();
  broker.handleConnection(sock);
  sock.recv({ t: "create", kind: "codex" });
  const sessMsg = sock.sent.filter((m) => m.t === "sessions").at(-1);
  const sid = sessMsg.sessions[0].sid;
  sock.recv({ t: "subscribe", sid });

  broker._heartbeatTick();   // 1st tick: ping sent, no pong yet — not reaped yet
  assert.equal(sock.terminated, false);
  broker._heartbeatTick();   // 2nd tick: still no pong since last ping — reaped

  assert.equal(sock.terminated, true, "meio-aberto tem de ser derrubado explicitamente");
  assert.equal(broker._clients.has(sock), false, "removido de _clients sem esperar por `close`");
  assert.equal(dematerialized, 1, "a sessão que ele assinava é liberada, não fica presa");
});

test("heartbeat: a pong between ticks keeps the socket alive", () => {
  const broker = new Broker({ sessionFactory: fakeSession });
  const sock = fakeSocket();
  broker.handleConnection(sock);

  broker._heartbeatTick();       // ping sent, __vivo=false
  sock.handlers.pong();          // client answers before the next tick
  broker._heartbeatTick();       // should ping again, not reap

  assert.equal(sock.terminated, false);
  assert.equal(sock.pinged, 2);
  assert.equal(broker._clients.has(sock), true);
});
