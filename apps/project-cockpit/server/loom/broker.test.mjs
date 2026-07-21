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
