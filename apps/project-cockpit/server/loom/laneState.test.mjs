import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyLane, normalizeLines, lastContentLine, peekLines } from "./laneState.mjs";

// Every fixture below is REAL output captured from the live lanes on
// sounio-workspace-control-0 (2026-08-08), trimmed to the tail the classifier sees.

const CLAUDE_WORKING = `
● Idêntico — mesmo módulo, mesma função, mesma instrução. A conversão foi inerte.
────────────────────────────── madaros-fixed-point-verification ──
❯
──────────────────────────────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle) · PR #1580 · esc to interrupt · ctrl+t to show tasks · ← 1 agent
`;

const CLAUDE_IDLE = `
● 11 de 11 verdes, zero falhas. Os dois vermelhos do main ficaram verdes.
──────────────────────────────────────────────
❯ avise o claude 1 sobre o gate desligado
──────────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle) · PR #1684 · ← for agents
`;

const CODEX_WORKING = `
    47 +\`\`\`
• Waiting for background terminal (2m 20s • esc to interrupt) · 2 background terminals running
  └ bin/llm-offload --raw scripts/research/cs6_chain41_staged_checkpoint_review_prompt.txt xai zai
› Explain this codebase
  gpt-5.6-luna medium · /workspace/sounio
`;

const CODEX_DONE = `
  Resultado: 182.
─ Worked for 5m 33s ────────────────────────────────
› Find and fix a bug in @filename
  gpt-5.6-luna medium · /workspace/sounio                    Goal achieved (2h 46m)
`;

// kimi-cli1 measured LIVE in the waiting case: the agent asked the operator a question and
// parked at an empty input box with nothing running.
const KIMI_ASKING = `
   • H2: σ_min(sedenion embedding) correlaciona com anedonia
   A pergunta: quer que eu baixe LEMON/MODMA e execute o pré-registro, ou prefere explorar a conexão DDI triplo com dados farmacológicos reais?
 ╭──────────────────────────────────────────╮
 │ >                                        │
 ╰──────────────────────────────────────────╯
 yolo  GLM-5.2 thinking: high  /workspace/sounio  research/zd-fiber-antisymmetry-lemma [+85 -68 ↑52↓11]     /web: use the Web UI for a better experience
                                                                                        context: 46% (444k/977k)
`;

// kimi-cli2: also parked at an empty box, but a task IS running and the last line is a todo,
// not a question → working, NOT waiting. This is the false-positive the shelf must not show.
const KIMI_WORKING = `
   ○ Rescore julgado + tabela comparativa + commit
 ╭──────────────────────────────────────────╮
 │ >                                        │
 ╰──────────────────────────────────────────╯
 yolo swarm  Kimi K3 thinking: high  [1 task running]  /workspace/sounio  research/zd-fiber [+176 -68 ↑51↓11]
`;

const SHELL_IDLE = `
Sounio lane: repo
HOME: /workspace/.home/openvscode-server
[2]  + done       setsid nohup sh /workspace/.watchdog/souc-watchdog.sh
sounio-workspace-control-0%
`;

const CLAUDE_APPROVAL = `
● I'll update the deployment manifest.
╭──────────────────────────────────────────────────╮
│ Do you want to proceed?                          │
│ ❯ 1. Yes                                         │
│   2. No, and tell Claude what to do differently   │
╰──────────────────────────────────────────────────╯
`;

const SHELL_YN = `
Removing 3 stale worktrees. Continue? (y/n)
`;

// Claude Code's edit-permission dialog: the descriptive line sits ABOVE the button prompt.
const CLAUDE_EDIT_APPROVAL = `
● I'll update the deployment manifest.
╭──────────────────────────────────────────────────╮
│ Do you want to make this edit to k8s/deploy.yaml? │
│ ❯ 1. Yes                                          │
│   2. No, and tell Claude what to do differently   │
╰──────────────────────────────────────────────────╯
`;

const CLAUDE_COMMAND_APPROVAL = `
● I'll run the test suite.
╭──────────────────────────────────────────────────╮
│ Allow this command?                               │
│   npm test                                        │
│ ❯ 1. Yes                                          │
│   2. No, and tell Claude what to do differently   │
╰──────────────────────────────────────────────────╯
`;

test("working: `esc to interrupt` is the cross-family in-flight signal", () => {
  assert.equal(classifyLane({ text: CLAUDE_WORKING }).state, "running");
  assert.equal(classifyLane({ text: CODEX_WORKING }).state, "running");
});

test("idle: at a prompt with nothing in flight", () => {
  assert.equal(classifyLane({ text: CLAUDE_IDLE }).state, "idle");
  assert.equal(classifyLane({ text: CODEX_DONE }).state, "idle");
  assert.equal(classifyLane({ text: SHELL_IDLE }).state, "idle");
});

test("waiting: an explicit approval dialog, quoted, approvable by Enter", () => {
  const r = classifyLane({ text: CLAUDE_APPROVAL });
  assert.equal(r.state, "waiting");
  assert.equal(r.awaitingInput, true);
  assert.equal(r.approveKey, "enter");
  assert.match(r.detail, /Do you want to proceed\?|1\. Yes/);
});

test("waiting: a (y/n) gate is approved with `y`, not Enter", () => {
  const r = classifyLane({ text: SHELL_YN });
  assert.equal(r.state, "waiting");
  assert.equal(r.approveKey, "y");
});

test("approvalKind: an edit dialog reads as `patch` — quoted from the dialog's own words", () => {
  const r = classifyLane({ text: CLAUDE_EDIT_APPROVAL });
  assert.equal(r.state, "waiting");
  assert.equal(r.approvalKind, "patch");
});

test("approvalKind: a run-this-command dialog reads as `command`", () => {
  const r = classifyLane({ text: CLAUDE_COMMAND_APPROVAL });
  assert.equal(r.state, "waiting");
  assert.equal(r.approvalKind, "command");
});

test("approvalKind: a bare numbered menu with no descriptive text stays null — never guessed", () => {
  const r = classifyLane({ text: "❯ 1. minimax-m3\n  2. glm-5.2\n" });
  assert.equal(r.approvalKind, null);
});

test("approvalKind: an open operator question is not an approval dialog — stays null", () => {
  const r = classifyLane({ text: KIMI_ASKING });
  assert.equal(r.approvalKind, null);
});

test("waiting: an agent QUESTION parked at an empty box needs the operator (measured: kimi-cli1)", () => {
  const r = classifyLane({ text: KIMI_ASKING });
  assert.equal(r.state, "waiting");
  assert.equal(r.approveKey, null, "an open question needs a real answer, not a keystroke");
  assert.match(r.detail, /quer que eu baixe LEMON\/MODMA/);
  assert.match(r.detail, /\?$/, "the card quotes the question itself");
});

test("NOT waiting: empty box but a task is running and the last line is not a question", () => {
  const r = classifyLane({ text: KIMI_WORKING });
  assert.equal(r.state, "running");
  assert.equal(r.awaitingInput, false);
});

test("stuck only when silent AND not working AND not at a prompt", () => {
  const mid = "● building the IR lowering pass\n  ... emitting\n";
  const now = 1_000_000_000;
  assert.equal(classifyLane({ text: mid, lastOutputAt: now - 700_000, now }).state, "stuck");
  assert.equal(classifyLane({ text: mid, lastOutputAt: now - 5_000, now }).state, "running");
  // A long build is NOT stuck: `esc to interrupt` proves the agent is alive and working.
  assert.equal(
    classifyLane({ text: CLAUDE_WORKING, lastOutputAt: now - 900_000, now }).state,
    "running",
  );
  // Nor is an idle prompt: silence at a prompt is rest, not a hang.
  assert.equal(
    classifyLane({ text: SHELL_IDLE, lastOutputAt: now - 900_000, now }).state,
    "idle",
  );
});

test("a rule with a label inside it is a separator, not evidence (seen on the Frota card)", () => {
  // Real: Claude Code draws `──── <branch> ────`. Stripping the box characters used to leave the
  // bare branch name, which the card then quoted as if the agent had said it.
  const text = [
    "● Mergeado. origin/main é agora 43e4e76f7f Merge pull request #1681.",
    "✻ Cogitated for 15m 50s",
    "─────────────────────────────────────────── ir-instruction-struct-arrays ──",
    "❯ mergeie o 1685",
    "───────────────────────────────────────────────────────────────────────────",
    "  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents",
  ].join("\n");
  const lines = normalizeLines(text);
  assert.equal(lines.some((l) => l.trim() === "ir-instruction-struct-arrays"), false,
    "the separator must not survive as a content line");
  assert.equal(lastContentLine(lines), "❯ mergeie o 1685");
  assert.equal(classifyLane({ text }).detail, "❯ mergeie o 1685");
});

test("a real bordered line survives — only MOSTLY-frame rows are dropped", () => {
  const lines = normalizeLines("│ A pergunta: rodo o pré-registro? │\n╰──────────────────────────────────╯");
  assert.equal(lines.length, 1);
  assert.match(lines[0], /A pergunta: rodo o pré-registro\?/);
});

test("braille art and launcher chrome are not evidence (grok splash)", () => {
  const text = [
    "   ⠀⠀⠀⠀⠀⠀⣀⣀⡀⠀⠀⠀⢀⠄   Grok Build Beta  0.2.11",
    "   ⠀⠀⣼⡟⠁⠀⠀⠀⢀⡴⠻⣿⡀⠀   New worktree",
    "   Resume session",
    "   Quit",
    "● o divisor de zero aparece no nível 4 da torre",
    "  Sounio-Language    [stable]",
  ].join("\n");
  assert.equal(classifyLane({ text }).detail, "● o divisor de zero aparece no nível 4 da torre");
});

test("a rotating usage tip is chrome, not the agent's last word", () => {
  const text = [
    "● Compus a prova em seis linhas; falta o passo indutivo.",
    "  Tip: Double-tap esc to rewind the code and/or conversation",
    "  ⏵⏵ auto mode on · esc to interrupt",
  ].join("\n");
  const r = classifyLane({ text });
  assert.equal(r.state, "running");
  assert.equal(r.detail, "● Compus a prova em seis linhas; falta o passo indutivo.");
});

test("a blank screen is unknown, never a confident running (found live on codex-3)", () => {
  for (const blank of ["", "\n\n", "   \n  \n", "────────\n────────"]) {
    const r = classifyLane({ text: blank });
    assert.equal(r.state, "unknown", `blank=${JSON.stringify(blank)}`);
    assert.equal(r.detail, "");
  }
});

test("exited when the session is gone", () => {
  assert.equal(classifyLane({ text: SHELL_IDLE, alive: false }).state, "exited");
});

test("normalize strips ANSI + frame chrome; peek returns opaque content lines", () => {
  assert.deepEqual(normalizeLines("[31mred[0m\n────\n  \n ok "), ["red", " ok"]);
  assert.equal(lastContentLine(normalizeLines(KIMI_ASKING)).endsWith("?"), true);
  const peek = peekLines(KIMI_ASKING, 2);
  assert.equal(peek.length, 2);
  assert.equal(peek.some((l) => /LEMON\/MODMA/.test(l)), true);
});

test("every verdict carries its evidence (never a bare state)", () => {
  for (const text of [CLAUDE_WORKING, CLAUDE_IDLE, KIMI_ASKING, CLAUDE_APPROVAL, SHELL_IDLE]) {
    const r = classifyLane({ text });
    assert.ok(r.detail.length > 0, `no evidence for state=${r.state}`);
  }
});

test("quote the last MESSAGE, not the last line (fragments read like noise)", () => {
  // Real shapes seen live: the tail of a wrapped paragraph gave "local." and
  // "ultracode or ask Claude to use a workflow directly." — true text, useless as evidence.
  const claude = [
    "● Reescrevi o lowering do IR e o gate passou; falta medir o custo em",
    "  memória, que hoje estoura em máquinas sem 64G e por isso não roda",
    "  local.",
    "  ⏵⏵ auto mode on · esc to interrupt",
  ].join("\n");
  assert.equal(classifyLane({ text: claude }).detail,
    "● Reescrevi o lowering do IR e o gate passou; falta medir o custo em");

  // A tip under a tree glyph is still a tip.
  const tip = "● A prova fecha por indução.\n  ⎿  Tip: Connect Claude to your IDE · /ide\n  ⏵⏵ esc to interrupt";
  assert.equal(classifyLane({ text: tip }).detail, "● A prova fecha por indução.");

  // His own typed prompt still wins when it is the newest thing on screen.
  const typed = "● Terminei o merge.\n❯ mergeie o 1685\n  ⏵⏵ auto mode on · ← for agents";
  assert.equal(classifyLane({ text: typed }).detail, "❯ mergeie o 1685");

  // A plain shell has no message markers at all — fall back, don't return nothing.
  assert.match(classifyLane({ text: "$ make test\nok 12 passed\nuser@host%" }).detail, /ok 12 passed/);
});

test("um shell e a caixa de entrada de um agente NÃO são a mesma coisa", () => {
  // Ambos são "idle". A diferença decide se digitar `cd ...` executa um comando ou vira um
  // PEDIDO ao agente — achado ao ir mover a codex-1 pela primeira vez (09-ago-2026).
  const shell = classifyLane({ text: "sounio-workspace-control-0%\n" });
  assert.equal(shell.state, "idle");
  assert.equal(shell.atShell, true);

  const agent = classifyLane({ text: "● terminei a análise\n╭────╮\n│ ❯  │\n╰────╯\n" });
  assert.equal(agent.state, "idle");
  assert.equal(agent.atShell, false, "a caixa do agente não executa comando");

  // Forma real da codex-1: placeholder do Codex + marcador de turno concluído.
  const codexRest = classifyLane({ text: "• Goal achieved (2h 46m)\n› Explain this codebase\n" });
  assert.equal(codexRest.atShell, false);

  // Trabalhando nunca é shell, mesmo com um % na tela.
  assert.equal(classifyLane({ text: "$ make\n· esc to interrupt\nhost%\n" }).atShell, false);

  // E os dois casos degenerados não inventam um shell.
  assert.equal(classifyLane({ text: "", alive: false }).atShell, false);
  assert.equal(classifyLane({ text: "" }).atShell, false);
});
