import { test } from "node:test";
import assert from "node:assert/strict";
import { parseSession, renderContent } from "../src/conversations.mjs";

const CLAUDE = [
  `{"type":"queue-operation","operation":"enqueue","timestamp":"2026-03-19T21:42:12.349Z","sessionId":"sess-c"}`,
  `{"type":"file-history-snapshot","timestamp":"2026-03-19T21:42:13.000Z"}`,
  `{"type":"user","timestamp":"2026-03-19T21:42:20.000Z","sessionId":"sess-c","message":{"role":"user","content":"oi, vamos quebrar o muro de 256 variáveis"}}`,
  `{"type":"assistant","timestamp":"2026-03-19T21:42:25.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Boa. Primeiro vejo o lexer."},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}`,
  `{"type":"ai-title","title":"x"}`,
].join("\n");

const CODEX = [
  `{"timestamp":"2026-02-27T09:36:08.667Z","type":"session_meta","payload":{"id":"sess-x","cwd":"/home/demetrios/work/sounio"}}`,
  `{"timestamp":"2026-02-27T09:36:10.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"rode os testes do compilador"}]}}`,
  `{"timestamp":"2026-02-27T09:36:40.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"127/209 passam"}]}}`,
  `{"timestamp":"2026-02-27T09:36:41.000Z","type":"response_item","payload":{"type":"function_call","name":"shell"}}`,
].join("\n");

test("parseSession detects Claude format + extracts user/assistant turns, skips noise", () => {
  const s = parseSession(CLAUDE);
  assert.equal(s.format, "claude");
  assert.equal(s.sessionId, "sess-c");
  assert.equal(s.turns.length, 2);
  assert.equal(s.turns[0].role, "user");
  assert.match(s.turns[0].content, /muro de 256/);
  assert.equal(s.turns[1].role, "assistant");
  assert.match(s.turns[1].content, /vejo o lexer/);
});

test("parseSession detects Codex format + extracts message turns, skips session_meta/function_call", () => {
  const s = parseSession(CODEX);
  assert.equal(s.format, "codex");
  assert.equal(s.sessionId, "sess-x");
  assert.equal(s.cwd, "/home/demetrios/work/sounio");
  assert.equal(s.turns.length, 2);
  assert.match(s.turns[0].content, /rode os testes/);
  assert.match(s.turns[1].content, /127\/209/);
});

test("renderContent handles string, block arrays, and compacts tool_use", () => {
  assert.equal(renderContent("plain"), "plain");
  assert.equal(renderContent([{ type: "text", text: "hi" }]), "hi");
  assert.equal(renderContent([{ type: "input_text", text: "ask" }]), "ask");
  const r = renderContent([{ type: "text", text: "ok" }, { type: "tool_use", name: "Bash", input: { command: "ls" } }]);
  assert.match(r, /ok/);
  assert.match(r, /\[tool_use Bash\]/);
});
