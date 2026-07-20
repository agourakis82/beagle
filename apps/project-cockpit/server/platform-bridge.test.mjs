import { test } from "node:test";
import assert from "node:assert/strict";
import { isT560Kind, deckExec, kubectlArgv, parseDeckSession } from "./platform-bridge.mjs";

test("allowlist: only known deck kinds; injection refused", () => {
  assert.equal(isT560Kind("t560-beagle"), true);
  assert.equal(isT560Kind("sounio-dev"), true);
  assert.equal(isT560Kind("t560-evil; rm -rf"), false);
  assert.equal(isT560Kind("claude-code"), false);
  assert.equal(deckExec("nope", "attach"), null);
});

test("tmux attach/list/kill argv is exact (t560 via @bridge)", () => {
  assert.deepEqual(deckExec("t560-beagle", "attach"),
    { pod: "@bridge", container: null, argv: ["tmux", "-S", "/tmp/tmux-1000/default", "attach", "-t", "beagle"] });
  assert.deepEqual(deckExec("t560-clops", "kill"),
    { pod: "@bridge", container: null, argv: ["tmux", "-S", "/tmp/tmux-1000/clops", "kill-session", "-t", "clops"] });
  assert.equal(deckExec("t560-beagle", "exec"), null);
});

test("zellij attach targets the workspace pod + user, no free-form input", () => {
  const a = deckExec("sounio-dev", "attach");
  assert.equal(a.pod, "sounio-workspace-control-0");
  assert.equal(a.container, "workspace-ssh");
  assert.equal(a.argv[0], "su");
  assert.match(a.argv[a.argv.length - 1], /exec zellij attach sounio-dev$/);
});

test("kubectlArgv assembles exec with optional container", () => {
  assert.deepEqual(kubectlArgv("beagle", "pod-x", { container: null, argv: ["tmux", "ls"] }, true),
    ["-n", "beagle", "exec", "-it", "pod-x", "--", "tmux", "ls"]);
  assert.deepEqual(kubectlArgv("beagle", "pod-y", { container: "c", argv: ["z"] }, false),
    ["-n", "beagle", "exec", "-i", "pod-y", "-c", "c", "--", "z"]);
});

test("parseDeckSession: tmux + zellij → safe metadata-only shape", () => {
  const tmuxOut = "beagle|1|1721400000|nvim\ndarwin-ops|0|1721390000|htop\n";
  const b = parseDeckSession("t560-beagle", tmuxOut, 1721400300);
  assert.equal(b.name, "beagle"); assert.equal(b.attached, true); assert.equal(b.window, "nvim"); assert.equal(b.idleSeconds, 300);
  const z = parseDeckSession("sounio-dev", "sounio-dev [Created 4days 13h ago] (current)\n", 1721400300);
  assert.equal(z.name, "sounio-dev"); assert.equal(z.attached, true); assert.equal(z.window, "zellij");
  assert.equal(parseDeckSession("sounio-dev", "other-session [Created ...]\n", 0), null);
});
