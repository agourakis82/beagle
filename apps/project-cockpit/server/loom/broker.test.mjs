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
