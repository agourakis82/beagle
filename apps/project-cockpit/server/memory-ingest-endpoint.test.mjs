import { test } from "node:test";
import assert from "node:assert/strict";
import { handleIngestRequest } from "./memory-ingest.mjs";

test("handleIngestRequest calls ingestPersonalTurn with the body fields", async () => {
  let got = null;
  const fakeIngest = async (turn, deps) => { got = { turn, deps }; };
  const body = {
    session_id: "s9", userText: "guarda X", assistantText: "ok",
    clientTime: "2026-06-27T10:00:00Z", timezone: "UTC",
  };
  const res = await handleIngestRequest(body, { ingestFn: fakeIngest, tokenFn: async () => ({ token: "t" }) });
  assert.equal(res.status, 202);
  assert.equal(got.turn.sessionId, "s9");
  assert.equal(got.turn.userText, "guarda X");
  assert.equal(got.turn.assistantText, "ok");
  assert.equal(typeof got.deps.tokenFn, "function");
});

test("handleIngestRequest 400 when both sides empty", async () => {
  const res = await handleIngestRequest({ userText: "", assistantText: "" },
    { ingestFn: async () => {}, tokenFn: async () => ({ token: "t" }) });
  assert.equal(res.status, 400);
});
