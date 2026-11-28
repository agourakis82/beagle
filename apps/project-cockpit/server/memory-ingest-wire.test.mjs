import { test } from "node:test";
import assert from "node:assert/strict";
import { ingestPersonalTurn } from "./memory-ingest.mjs";

test("fire-and-forget call shape resolves without throwing", async () => {
  // mirrors the mobile-routes call site: detached, swallowed
  await assert.doesNotReject(
    ingestPersonalTurn(
      { sessionId: "s", userText: "oi", assistantText: "olá", clientTime: "", timezone: "UTC" },
      { tokenFn: async () => ({ token: "", error: "x" }), fetchImpl: async () => ({ ok: false }) }
    )
  );
});
