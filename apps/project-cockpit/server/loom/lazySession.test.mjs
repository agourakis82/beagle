import { test } from "node:test";
import assert from "node:assert/strict";
import { LazySession } from "./lazySession.mjs";
import { Broker } from "./broker.mjs";

function fakeReal(sid) {
  const s = { sid, _data: null, _exit: null, written: [], killed: false,
    onData(f) { s._data = f; }, onExit(f) { s._exit = f; }, write(d) { s.written.push(d); },
    resize() {}, kill() { s.killed = true; }, snapshot() { return "REAL:" + sid; },
    get meta() { return { sid, kind: "adapted-k", source: "adapted", cols: 120, rows: 34, alive: !s.killed, lastOutputAt: 0 }; } };
  return s;
}
function fakeSocket() {
  const s = { sent: [], handlers: {}, on(ev, f) { s.handlers[ev] = f; },
    send(str) { s.sent.push(JSON.parse(str)); }, recv(o) { s.handlers.message(JSON.stringify(o)); } };
  return s;
}

test("LazySession does not attach until materialize; then delegates", () => {
  let built = 0;
  const ls = new LazySession("beagle", "t560-beagle", () => { built++; return fakeReal("beagle"); }, { title: "beagle" });
  assert.equal(ls.lazyPending, true);
  assert.equal(built, 0);                       // not attached at construction
  assert.equal(ls.snapshot(), "");
  assert.equal(ls.meta.title, "beagle");
  assert.equal(ls.meta.alive, true);
  ls.materialize();
  assert.equal(built, 1);
  assert.equal(ls.lazyPending, false);
  assert.equal(ls.snapshot(), "REAL:beagle");   // now delegates to the real session
});

test("broker: a lazy seed shows as unknown, attaches on subscribe, streams data", () => {
  let built = 0; let real;
  const broker = new Broker({ sessionFactory: () => { throw new Error("no create in this test"); } });
  broker.addLazySeed("beagle", "t560-beagle", () => { built++; real = fakeReal("beagle"); return real; }, { title: "beagle" });

  const sock = fakeSocket();
  broker.handleConnection(sock);
  const first = sock.sent[0];
  assert.equal(first.t, "sessions");
  assert.equal(first.sessions[0].title, "beagle");
  // Seeded, never attached AND never peeked → "unknown", not a comfortable-looking "idle".
  // A board that guesses "idle" for lanes it has not observed teaches the operator to distrust it.
  assert.equal(first.sessions[0].state, "unknown");
  assert.equal(first.sessions[0].observedAt, null);
  assert.equal(built, 0);

  sock.recv({ t: "subscribe", sid: "beagle" });
  assert.equal(built, 1);                            // materialized on subscribe
  assert.ok(sock.sent.some((m) => m.t === "scrollback" && m.sid === "beagle" && m.bytes === "REAL:beagle"));

  sock.recv({ t: "input", sid: "beagle", data: "ls\n" });
  assert.deepEqual(real.written, ["ls\n"]);          // input reaches the materialized session

  real._data("hello");                                // real emits -> forwarded to subscriber
  assert.ok(sock.sent.some((m) => m.t === "data" && m.sid === "beagle" && m.bytes === "hello"));
});
