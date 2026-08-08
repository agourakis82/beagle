import { test } from "node:test";
import assert from "node:assert/strict";
import {
  isT560Kind, deckExec, kubectlArgv, parseDeckSession,
  lanesPeekArgv, parseLanesPeek, WORKSPACE_LANES, PEEK_DELIM,
} from "./platform-bridge.mjs";

test("peek is read-only (capture-pane), su-wrapped, and never attaches a client", () => {
  const p = deckExec("claude-1", "peek");
  assert.match(p.argv[5], /exec tmux capture-pane -p -t claude-1 -S -\d+$/);
  assert.doesNotMatch(p.argv[5], /attach/, "peek must not attach — it would resize his real pane");
  assert.equal(deckExec("t560-beagle", "peek").argv.join(" ").includes("capture-pane"), true);
});

test("batched fleet peek: one exec, all 11 lanes, delimited, no request input", () => {
  const argv = lanesPeekArgv("beagle");
  assert.deepEqual(argv.slice(0, 8),
    ["-n", "beagle", "exec", "-i", "sounio-workspace-control-0", "-c", "workspace-ssh", "--"]);
  const body = argv[argv.length - 1];
  for (const lane of WORKSPACE_LANES) {
    assert.ok(body.includes(`${PEEK_DELIM}${lane}`), `missing delimiter for ${lane}`);
    assert.ok(body.includes(`capture-pane -p -t ${lane}`), `missing capture for ${lane}`);
  }
  assert.match(body, /TMUX_TMPDIR=\/workspace\/\.home\/openvscode-server\/\.tmux/);
  assert.doesNotMatch(body, /attach|kill-session|send-keys/);
});

test("parseLanesPeek splits by lane and drops unknown labels", () => {
  const out = parseLanesPeek(
    `${PEEK_DELIM}claude-1\nhello\nworld\n${PEEK_DELIM}evil-lane\nrm -rf\n${PEEK_DELIM}repo\n$ ls\n`,
  );
  assert.deepEqual(Object.keys(out).sort(), ["claude-1", "repo"]);
  assert.equal(out["claude-1"], "hello\nworld");
  assert.match(out["repo"], /\$ ls/);
});

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

test("workspace lane: tmux su-wrapped with TMUX_TMPDIR (measured socket, not /tmp/tmux-1000)", () => {
  assert.equal(isT560Kind("claude-1"), true);
  assert.equal(isT560Kind("repo"), true);
  assert.equal(isT560Kind("claude-code"), false); // family prefix alone is NOT a lane
  const a = deckExec("claude-1", "attach");
  assert.equal(a.pod, "sounio-workspace-control-0");
  assert.equal(a.container, "workspace-ssh");
  assert.deepEqual(a.argv.slice(0, 5), ["su", "-s", "/bin/bash", "openvscode-server", "-c"]);
  const body = a.argv[5];
  assert.match(body, /export TMUX_TMPDIR=\/workspace\/\.home\/openvscode-server\/\.tmux;/);
  assert.match(body, / exec tmux attach -t claude-1$/);
  assert.doesNotMatch(body, /\/tmp\/tmux-1000/); // must NOT use the wrong default socket path
  // list quotes the -F format so the pipe isn't a shell pipe
  const l = deckExec("codex-2", "list");
  assert.match(l.argv[5], /exec tmux list-sessions -F '#\{session_name\}\|#\{session_attached\}\|/);
  assert.equal(deckExec("grok-cli1", "kill").argv[5].endsWith("exec tmux kill-session -t grok-cli1"), true);
  assert.equal(deckExec("claude-1", "exec"), null); // unknown action refused
});

test("all 11 workspace lanes are allowlisted and target the workspace pod as the workspace user", () => {
  const lanes = ["claude-1","claude-2","claude-3","codex-1","codex-2","codex-3","kimi-cli1","kimi-cli2","grok-cli1","grok-cli2","repo"];
  for (const lane of lanes) {
    assert.equal(isT560Kind(lane), true, lane);
    const a = deckExec(lane, "attach");
    assert.equal(a.pod, "sounio-workspace-control-0", lane);
    assert.equal(a.argv[3], "openvscode-server", lane);
    assert.match(a.argv[5], new RegExp(`exec tmux attach -t ${lane}$`), lane);
  }
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
