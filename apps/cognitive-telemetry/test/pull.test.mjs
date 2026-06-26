import { test } from "node:test";
import assert from "node:assert/strict";
import { sessionsFromPassages } from "../src/pull.mjs";

test("sessionsFromPassages: role→speaker, drops restricted + <2-turn + empty turns", () => {
  const sessions = sessionsFromPassages([
    {
      id: "p1", occurred_at: "2026-02-02", source_platform: "claude", privacy_class: "sensitive",
      turns: [
        { role: "user", content: "what is the plan" },
        { role: "assistant", content: "ship it" },
        { role: "user", content: "" }, // empty dropped
      ],
    },
    { id: "p2", privacy_class: "restricted", turns: [{ role: "user", content: "secret" }, { role: "assistant", content: "x" }] },
    { id: "p3", privacy_class: "sensitive", turns: [{ role: "user", content: "only one turn" }] }, // <2 dropped
  ]);
  assert.equal(sessions.length, 1, "only p1 survives");
  const s = sessions[0];
  assert.equal(s.session_id, "p1");
  assert.equal(s.turns.length, 2, "empty turn dropped");
  assert.equal(s.turns[0].speaker, 0, "user → self/0");
  assert.equal(s.turns[1].speaker, 1, "assistant → other/1");
});
