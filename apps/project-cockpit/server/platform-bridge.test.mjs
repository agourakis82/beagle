import { test } from "node:test";
import assert from "node:assert/strict";
import { isT560Kind, tmuxAttachArgv, tmuxControlArgv, buildSessionList } from "./platform-bridge.mjs";

test("allowlist: only known t560 kinds; attach argv is exact, no injection", () => {
  assert.equal(isT560Kind("t560-beagle"), true);
  assert.equal(isT560Kind("t560-evil; rm -rf"), false);
  assert.equal(isT560Kind("claude-code"), false);
  assert.deepEqual(tmuxAttachArgv("t560-beagle"), ["-S", "/tmp/tmux-1000/default", "attach", "-t", "beagle"]);
  assert.deepEqual(tmuxAttachArgv("t560-clops"), ["-S", "/tmp/tmux-1000/clops", "attach", "-t", "clops"]);
  assert.equal(tmuxAttachArgv("nope"), null);
});
test("control: only list/kill; exact argv; unknown refused", () => {
  assert.deepEqual(tmuxControlArgv("t560-beagle", "kill"), ["-S", "/tmp/tmux-1000/default", "kill-session", "-t", "beagle"]);
  assert.deepEqual(tmuxControlArgv("t560-clops", "list"), ["-S", "/tmp/tmux-1000/clops", "list-sessions", "-F", "#{session_name}|#{session_attached}|#{session_activity}|#{window_name}"]);
  assert.equal(tmuxControlArgv("t560-beagle", "exec"), null);
  assert.equal(tmuxControlArgv("bad", "kill"), null);
});
test("buildSessionList: parses to safe shape (no pane content)", () => {
  const out = buildSessionList({ "t560-beagle": "beagle|1|1721400000|nvim", "t560-darwin-ops": "darwin-ops|0|1721390000|htop" }, 1721400300);
  const b = out.find((s) => s.kind === "t560-beagle");
  assert.equal(b.name, "beagle"); assert.equal(b.attached, true); assert.equal(b.window, "nvim"); assert.equal(b.idleSeconds, 300);
  const d = out.find((s) => s.kind === "t560-darwin-ops");
  assert.equal(d.attached, false); assert.equal(d.idleSeconds, 10300);
});
