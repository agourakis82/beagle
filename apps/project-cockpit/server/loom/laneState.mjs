// laneState.mjs — read an agent lane's terminal tail and answer the one operational question
// the Mission Control exists to answer: **who needs you?**
//
// Pure + unit-tested against REAL captured output from the 11 live lanes (Claude Code, Codex,
// Kimi/GLM, Grok, plain shell). Heuristics only — so every verdict carries the evidence line
// that produced it (`detail`), and the UI must quote that instead of asserting a bare state.
// Nothing here is a substitute for the agent telling us; it is the best honest read of a TTY.

const ANSI = /\[[0-9;?]*[A-Za-z]|\][^]*(|\\)/g;
// Box-drawing + block chrome the TUIs paint their frames with.
const BOX = /[─-╿▀-▟]/g;

/// Footer/status lines: real chrome, never content. Measured across the four CLI families.
const CHROME = [
  /esc to interrupt/i,
  /shift\+tab to cycle/i,
  /ctrl\+[a-z] to /i,
  /auto mode on|bypass permissions on|always-approve|\byolo\b/i,
  /context: ?\d+%/i,
  /^\s*(gpt|claude|grok|kimi|glm)[\w.\- ]*(medium|high|low|thinking)/i,
  /for agents\s*$/i,
  /to show tasks/i,
  /press ctrl\+u to restart|Update: v?[\d.]+ available/i,
  /^\s*\/\w+: /,                       // "/web: use the Web UI ..."
  /Goal achieved/i,
  /^\s*[›❯>]\s*(Explain this codebase|Find and fix a bug)/i,   // CLI placeholder hints
  /^[\s⎿└├│─]*Tip: /i,                           // rotating usage tips (often under a tree glyph)
  /\[(stable|beta|alpha|dev)\]\s*$/i,            // grok's host/status footer
  /^\s*(Grok Build|Select '|New worktree|Resume session|Changelog|Quit)\b/i,  // grok launcher menu
];

/// The agent is actively burning tokens/CPU. `esc to interrupt` is the strongest cross-family
/// signal (Claude Code + Codex both print it only while a turn is in flight).
/// Deliberately NOT here: the spinner verbs ("Cooked for", "Worked for"). They are ambiguous
/// ACROSS families — Claude paints "Cooked for 2m" as a live spinner while Codex prints
/// "─ Worked for 5m 33s ─" as a *finished-turn* separator. Measured; cost a failing test.
const WORKING = [
  /esc to interrupt/i,
  /\[\s*\d+ tasks? running\s*\]/i,
  /\d+ (background )?(terminals?|shells?) (still )?running/i,
  /Waiting for background terminal/i,
];

/// Explicit at-rest markers: the turn finished and the agent is not mid-flight.
const AT_REST = [
  /Goal achieved/i,
  /^\s*Worked for .*$/im,   // NOTE: /m is load-bearing — matched against the joined tail.
];

/// Explicit "may I?" gates — the classic approval the FAROL shelf materializes a button for.
const APPROVAL = [
  /Do you want to (proceed|continue|make this edit|create)/i,
  /^\s*[❯>]?\s*1\.\s*Yes\b/im,          // Claude Code's numbered permission dialog
  /\(y\/n\)|\[y\/N\]|\[Y\/n\]/i,
  /Allow (this|the) (command|edit|tool)/i,
  /Approve\?|Press enter to (approve|confirm)/i,
  /Waiting for your (approval|confirmation)/i,
];

/// A highlighted selectable option (permission dialog or an open modal menu) = a choice is owed.
const SELECTION = /^\s*[❯>]\s*\d+\.\s+\S/m;

/// Command or patch — decides the button's label because it decides the risk (same vocabulary
/// the loomd path already speaks, see `pending_kind` in loomd.mjs). Read directly off the
/// dialog's own words, never guessed from the lane's family or history: Claude Code's and
/// Codex's permission prompts already say which one it is ("make this edit" vs "run this
/// command"), so this is a quote, not an inference. No match = we do not know → `null`, the same
/// "not deduced" discipline the rest of this module holds to.
const APPROVAL_KIND = [
  { kind: "patch", re: /make this edit|Allow the edit|\bcreate\b/i },
  { kind: "command", re: /run this command|Allow (this|the) command|Do you want to (proceed|continue)/i },
];

function approvalKindOf(text) {
  for (const { kind, re } of APPROVAL_KIND) if (re.test(text)) return kind;
  return null;
}

/// An empty input box (`>` / `❯` with nothing typed) or a bare shell prompt.
const EMPTY_PROMPT = /^\s*[❯>]\s*$/;
const SHELL_PROMPT = /[%$#]\s*$/;
/// An input box that is ACCEPTING input — empty or with text already typed. Its presence means
/// the agent is not mid-turn: the box only renders between turns.
const PROMPT_LINE = /^\s*[❯>›]\s/;

function isChrome(line) {
  return CHROME.some((re) => re.test(line));
}

/// Braille blocks — CLIs draw spinners and ASCII-art logos with these. Never content.
const BRAILLE = /[⠀-⣿]/g;

/// A row that is MOSTLY frame is a separator, not a line of text. This matters because CLIs
/// embed labels inside their rules (`──── ir-instruction-struct-arrays ────`), and stripping the
/// box characters used to leave a bare branch name that looked exactly like agent output — it
/// was being quoted as "evidence" on the Frota card. Measured: that separator is ~75% box
/// characters, while a real bordered line (`│ text │`) is under 10%.
function isFrameRow(raw) {
  const trimmed = String(raw).trim();
  if (!trimmed) return true;
  const box = (trimmed.match(BOX) || []).length;
  const braille = (trimmed.match(BRAILLE) || []).length;
  return (box + braille) / trimmed.length > 0.4;
}

/// Strip escapes + frame chrome, keep the visible text of each row.
export function normalizeLines(text) {
  return String(text || "")
    .replace(ANSI, "")
    .split("\n")
    .filter((l) => !isFrameRow(l))
    .map((l) => l.replace(BOX, "").replace(BRAILLE, "").replace(/\s+$/, ""))
    .filter((l) => l.trim().length > 0);
}

/// Every CLI marks where a MESSAGE begins: Claude uses ●/✻, Codex ›/•, kimi ○. Quoting the last
/// LINE lands mid-paragraph and yields fragments like "local." or "ultracode or ask Claude to…",
/// which read like noise on a card. Quoting the last message start gives the topic sentence.
const MESSAGE_START = /^\s*[●○•✻✽▸›]\s+\S/;

/// The last thing the agent (or he) actually SAID: the most recent message, preferred over the
/// most recent line. Falls back to the last content line when no message marker is present
/// (plain shells have none).
export function lastMessage(lines) {
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i];
    if (isChrome(l)) continue;
    if (MESSAGE_START.test(l)) return l.trim();
    if (/^\s*[❯>]\s+\S/.test(l) && !isChrome(l)) return l.trim();   // his own typed prompt
  }
  return lastContentLine(lines);
}

/// The last line that is actual agent/user content (not a frame or status footer).
export function lastContentLine(lines) {
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i];
    if (isChrome(l)) continue;
    if (EMPTY_PROMPT.test(l)) continue;
    if (SHELL_PROMPT.test(l) && l.trim().length < 40) continue;   // bare shell prompt
    if (l.trim().length < 2) continue;
    return l.trim();
  }
  return "";
}

/// Classify one lane from its terminal tail.
/// Returns { state, detail, question, working, atPrompt, awaitingInput, approveKey, approvalKind }.
/// `detail` is ALWAYS the evidence for the verdict — the UI quotes it rather than asserting.
export function classifyLane({
  text = "",
  lastOutputAt = 0,
  now = 0,
  alive = true,
  stuckAfterMs = 600000,   // 10min of silence while NOT working and NOT at a prompt
} = {}) {
  const lines = normalizeLines(text);
  const tail = lines.slice(-14);
  const tailText = tail.join("\n");
  const footer = lines.slice(-6).join("\n");

  const working = WORKING.some((re) => re.test(footer)) || WORKING.some((re) => re.test(tailText));
  const approvalHit = APPROVAL.find((re) => re.test(tailText)) ? tailText.match(APPROVAL.find((re) => re.test(tailText))) : null;
  const selectionHit = SELECTION.test(tailText);
  const awaitingInput = Boolean(approvalHit) || selectionHit;

  const atRest = AT_REST.some((re) => re.test(tailText));
  // A bare SHELL prompt and an AGENT's input box are both "at rest", and the difference is not
  // cosmetic: a shell will run what you type, an agent CLI will treat it as a REQUEST. Anything
  // that types a command (moving a lane into its worktree) may only aim at a shell — otherwise
  // `cd /workspace/.wt/codex-1` becomes a prompt asking the agent to change directory.
  const agentBox = tail.some((l) => EMPTY_PROMPT.test(l))
    || (!working && tail.some((l) => PROMPT_LINE.test(l) && !isChrome(l) && !/^\s*[❯>]\s*\d+\./.test(l)));
  const atShell = !working && !agentBox
    && tail.some((l) => SHELL_PROMPT.test(l) && l.trim().length < 40);

  const atPrompt = agentBox || atRest || atShell;

  // Two different reads, on purpose:
  //  * evidence = the last MESSAGE (topic sentence), so a card never quotes a fragment;
  //  * question = the last LINE, because an agent's closing question is usually the tail of a
  //    wrapped paragraph and carries no message marker of its own. Using the message read here
  //    made the shelf quote the bullet above the question instead of the question.
  const last = lastMessage(lines);
  const lastLine = lastContentLine(lines);
  const question = /\?\s*$/.test(lastLine) ? lastLine : "";

  // Not alive covers two cases the operator must be able to tell apart from `unknown`: the lane
  // died, or it was never created at all. Both have no screen to quote, so when there is no last
  // message we state the observation itself instead of showing an empty card.
  if (!alive) {
    return {
      state: "exited", detail: last || "sessão não existe no tmux",
      // 🚨 A ausência é FATO aqui, e é aqui que ela se sabe — `!alive` sem nada para citar só
      // acontece com lane que NUNCA foi criada. Antes o cliente Swift deduzia isso lendo a PROSA
      // acima (`detail.contains("não existe no tmux")`), o que amarrava a capacidade da tela à
      // redação de uma string em português: traduzir a frase quebrava a Frota em silêncio.
      // `last` presente = a lane rodou e morreu, que é coisa diferente e tem tela para citar.
      ausente: !last,
      question: "", working: false, atPrompt: false, atShell: false, awaitingInput: false, approveKey: null,
      approvalKind: null,
    };
  }
  // A blank screen tells us nothing. Found live on codex-3, which reported "running" with no
  // evidence at all — exactly the confident-but-empty verdict this vocabulary exists to avoid.
  if (lines.length === 0) {
    return { state: "unknown", detail: "", question: "", working: false, atPrompt: false, atShell: false, awaitingInput: false, approveKey: null, approvalKind: null, ausente: false };
  }

  let state, detail, approveKey = null, approvalKind = null;
  if (awaitingInput) {
    state = "waiting";
    // Quote the dialog line itself so the card shows exactly what is being asked.
    const dialogLine = tail.slice().reverse().find((l) => APPROVAL.some((re) => re.test(l)) || /^\s*[❯>]\s*\d+\./.test(l));
    detail = (dialogLine || last).trim().slice(0, 240);
    approveKey = /\(y\/n\)|\[y\/N\]|\[Y\/n\]/i.test(tailText) ? "y" : "enter";
    // Read over the whole tail, not just the matched dialog line: the descriptive phrase
    // ("I'll update the deployment manifest") often sits one line above the button prompt.
    approvalKind = approvalKindOf(tailText);
  } else if (!working && question && atPrompt) {
    state = "waiting";
    detail = question.slice(0, 240);   // quote the question itself, never the line above it
    approveKey = null;              // an open question — needs a real answer, not a keystroke
  } else if (working) {
    state = "running";
    detail = last.slice(0, 240);
  } else if (atPrompt) {
    state = "idle";
    detail = last.slice(0, 240);
  } else if (now && lastOutputAt && now - lastOutputAt >= stuckAfterMs) {
    state = "stuck";
    detail = last.slice(0, 240);
  } else {
    state = "running";
    detail = last.slice(0, 240);
  }

  return { state, detail, question, working, atPrompt, atShell, awaitingInput, approveKey, approvalKind, ausente: false };
}

/// The last N content lines — the opaque 2-line terminal peek on a Frota card.
export function peekLines(text, n = 2) {
  const lines = normalizeLines(text).filter((l) => !isChrome(l) && !EMPTY_PROMPT.test(l));
  return lines.slice(-n).map((l) => l.trim().slice(0, 160));
}
