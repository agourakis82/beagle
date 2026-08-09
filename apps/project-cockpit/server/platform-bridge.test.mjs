import { test } from "node:test";
import assert from "node:assert/strict";
import {
  isT560Kind, deckExec, kubectlArgv, parseDeckSession,
  lanesPeekArgv, parseLanesPeek, WORKSPACE_LANES, PEEK_DELIM,
  parseLanesAlive, ALIVE_DELIM, LANE_KEYS,
  laneSendKeyArgv, laneIsolateArgv, laneWorktreeCheckArgv, LANE_WT_ROOT,
  parseLoomdState, hasLoomdBlock, LOOMD_DELIM, LOOMD_STATE_URL,
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

test("the same peek reports which lanes tmux actually HAS", () => {
  const body = lanesPeekArgv("beagle").at(-1);
  assert.match(body, /echo "@@ALIVE:"; tmux ls -F "#\{session_name\}"/);
  // The liveness block must come FIRST, so parseLanesPeek (which ignores anything before the
  // first @@LANE:) keeps dropping it and the two parsers stay independent.
  assert.ok(body.indexOf(ALIVE_DELIM) < body.indexOf(PEEK_DELIM));
});

test("parseLanesAlive: absent block is null, not an empty set", () => {
  // "did not ask" must never be read as "nothing is alive" — that would blank the whole board.
  assert.equal(parseLanesAlive("some unrelated output"), null);
  assert.equal(parseLanesAlive(""), null);
  const alive = parseLanesAlive(`${ALIVE_DELIM}\nclaude-1\nrepo\nnot-a-lane\n${PEEK_DELIM}claude-1\nhi\n`);
  assert.deepEqual([...alive].sort(), ["claude-1", "repo"]);
  assert.equal(alive.has("grok-cli1"), false, "a lane tmux does not list is NOT alive");
  // An empty tmux (no sessions) is a real, distinguishable answer.
  assert.equal(parseLanesAlive(`${ALIVE_DELIM}\n`).size, 0);
});

test("parseLanesPeek still ignores the liveness block that now precedes it", () => {
  const out = parseLanesPeek(`${ALIVE_DELIM}\nclaude-1\nrepo\n${PEEK_DELIM}repo\n$ ls\n`);
  assert.deepEqual(Object.keys(out), ["repo"]);
});

// ─── one-touch actions ───────────────────────────────────────────────────────────────────

test("send-keys carries a NAMED key from a closed set — never text from a request", () => {
  const a = laneSendKeyArgv("beagle", "codex-2", "y");
  assert.deepEqual(a.slice(0, 8),
    ["-n", "beagle", "exec", "-i", "sounio-workspace-control-0", "-c", "workspace-ssh", "--"]);
  assert.deepEqual(a.slice(8, 13), ["su", "-s", "/bin/bash", "openvscode-server", "-c"]);
  assert.match(a.at(-1), /export TMUX_TMPDIR=\/workspace\/\.home\/openvscode-server\/\.tmux;/);
  assert.match(a.at(-1), / exec tmux send-keys -t codex-2 y$/);
  assert.match(laneSendKeyArgv("beagle", "repo", "enter").at(-1), / exec tmux send-keys -t repo Enter$/);
  assert.match(laneSendKeyArgv("beagle", "repo", "esc").at(-1), / exec tmux send-keys -t repo Escape$/);
});

test("send-keys refuses anything outside the two allowlists", () => {
  assert.equal(laneSendKeyArgv("beagle", "repo", "rm -rf /"), null, "free text is not a key");
  assert.equal(laneSendKeyArgv("beagle", "repo", "C-c"), null, "not in the closed set");
  assert.equal(laneSendKeyArgv("beagle", "repo", ""), null);
  assert.equal(laneSendKeyArgv("beagle", "repo; whoami", "y"), null, "lane must be allowlisted");
  assert.equal(laneSendKeyArgv("beagle", "t560-beagle", "y"), null, "only workspace lanes, not deck sessions");
  assert.equal(laneSendKeyArgv("beagle", "sounio-dev", "y"), null, "zellij is not a lane");
  // The key set is small and named on purpose: it is the whole security argument.
  assert.deepEqual(Object.keys(LANE_KEYS).sort(), ["enter", "esc", "y"]);
  for (const v of Object.values(LANE_KEYS)) {
    assert.match(v, /^[A-Za-z]{1,10}$/, "a key name must never contain a shell metacharacter");
  }
});

test("isolate types a cd whose path comes from the lane NAME, and can be pre-checked", () => {
  assert.match(laneIsolateArgv("beagle", "codex-1").at(-1),
    new RegExp(` exec tmux send-keys -t codex-1 "cd ${LANE_WT_ROOT}/codex-1" Enter$`));
  assert.equal(laneIsolateArgv("beagle", "../etc"), null);
  assert.equal(laneIsolateArgv("beagle", "t560-beagle"), null);
  assert.match(laneWorktreeCheckArgv("beagle", "codex-1").at(-1),
    new RegExp(`test -d ${LANE_WT_ROOT}/codex-1 && echo yes \\|\\| echo no`));
  assert.equal(laneWorktreeCheckArgv("beagle", "nope"), null);
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

// ─── loomd: o bloco medido no protocolo, de carona no MESMO exec ─────────────────────────────

test("o bloco @@LOOMD vem ANTES do @@ALIVE e dos 11 peeks, com teto de 3s", () => {
  const body = lanesPeekArgv("beagle").at(-1);
  const iLoomd = body.indexOf(LOOMD_DELIM);
  const iAlive = body.indexOf(ALIVE_DELIM);
  const iPeek = body.indexOf(`${PEEK_DELIM}${WORKSPACE_LANES[0]}`);
  assert.ok(iLoomd >= 0, "o exec precisa perguntar ao loomd");
  assert.ok(iLoomd < iAlive && iAlive < iPeek, "ordem: loomd → alive → peeks");
  assert.ok(body.includes(`curl -fsS --max-time 3 ${LOOMD_STATE_URL}`),
    "--max-time 3 é obrigatório: o curl roda em série dentro do timeout de 20s do sweep");
  assert.ok(body.includes("127.0.0.1:4400"), "o loomd fica em loopback — nada exposto ao cluster");
  // O script inteiro roda dentro de `sh -c '…'`: uma aspa simples no trecho novo trunca tudo
  // silenciosamente (foi assim que a query git-head foi mutilada em produção).
  assert.doesNotMatch(body.slice(iLoomd, iAlive), /'/, "o trecho do loomd não pode conter aspa simples");
});

test("o curl termina em newline — sem ele o @@ALIVE gruda no JSON e as duas leituras caem juntas", () => {
  // A resposta do axum não termina em newline. Sem o `echo`, o stdout real seria
  // `…}@@ALIVE:` numa linha só: o JSON não parseia E parseLanesAlive devolve null (o que faz
  // as 11 lanes serem assumidas vivas). Uma regressão de um caractere que derruba duas coisas.
  const body = lanesPeekArgv("beagle").at(-1);
  assert.match(body, /--max-time 3 http:\/\/127\.0\.0\.1:4400\/v2\/state 2>\/dev\/null; echo/);
});

test("parseLoomdState lê o bloco e para no delimitador seguinte", () => {
  const stdout = `${LOOMD_DELIM}\n{"ok":true,"observed_at_ms":7,"lanes":[{"lane":"loom-1","kind":"idle","confidence":"exact","observed_at_ms":7,"turns":2}]}\n`
    + `${ALIVE_DELIM}\nclaude-1\n${PEEK_DELIM}claude-1\ntela\n`;
  const j = parseLoomdState(stdout);
  assert.equal(j.lanes.length, 1);
  assert.equal(j.lanes[0].lane, "loom-1");
  assert.equal(j.observed_at_ms, 7);
  // E o bloco novo não engoliu o resto do sweep.
  assert.deepEqual([...parseLanesAlive(stdout)], ["claude-1"]);
  assert.match(parseLanesPeek(stdout)["claude-1"], /^tela/);
});

test("loomd calado é null — NUNCA objeto vazio", () => {
  // Objeto vazio faria o chamador ler "o loomd disse que não há lane"; null diz "não respondeu".
  // Confundir os dois é exatamente como uma fonte morta vira `inferred` em silêncio.
  assert.equal(parseLoomdState(`${LOOMD_DELIM}\n${ALIVE_DELIM}\nclaude-1\n`), null, "bloco vazio (curl -f falhou)");
  assert.equal(parseLoomdState(`${ALIVE_DELIM}\nclaude-1\n`), null, "bloco ausente");
  assert.equal(parseLoomdState(`${LOOMD_DELIM}\n{"ok":true,"lanes":[{"lane":"loo\n`), null, "JSON truncado");
  assert.equal(parseLoomdState(`${LOOMD_DELIM}\n<html>502</html>\n`), null, "corpo que não é o contrato");
  assert.equal(parseLoomdState(`${LOOMD_DELIM}\n{"ok":true}\n`), null, "200 sem `lanes` é tão inútil quanto silêncio");
});

test("hasLoomdBlock separa `não perguntamos` de `perguntamos e ele não respondeu`", () => {
  assert.equal(hasLoomdBlock(`${LOOMD_DELIM}\n${ALIVE_DELIM}\n`), true);
  assert.equal(hasLoomdBlock(`${ALIVE_DELIM}\nclaude-1\n`), false);
});
