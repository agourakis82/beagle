import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeClient, encodeServer, STATES } from "./protocol.mjs";

test("decodeClient accepts known client messages, rejects the rest", () => {
  assert.deepEqual(decodeClient('{"t":"subscribe","sid":"a"}'), { t: "subscribe", sid: "a" });
  assert.deepEqual(decodeClient('{"t":"create","kind":"codex"}'), { t: "create", kind: "codex" });
  assert.equal(decodeClient('{"t":"evil"}'), null);
  assert.equal(decodeClient("not json"), null);
  assert.equal(decodeClient('{"no":"t"}'), null);
});

test("encodeServer round-trips a data frame and a state frame", () => {
  assert.equal(encodeServer({ t: "data", sid: "a", bytes: "hi" }),
    '{"t":"data","sid":"a","bytes":"hi"}');
  const s = JSON.parse(encodeServer({ t: "state", sid: "a", state: "running", detail: "" }));
  assert.equal(s.state, "running");
  assert.deepEqual(STATES, ["running", "idle", "waiting", "stuck", "exited", "unknown"]);
});
