// Tier-2 connector: parse Claude Code + Codex session transcripts into a unified
// { format, sessionId, cwd, startedAt, turns: [{role, content, timestamp}] } shape,
// for VERBATIM ingest into the exocortex. See docs/exocortex/CONTRACTS.md.

// Render a message `content` (string | array of blocks, either Claude or Codex
// flavor) to a flat text transcript. Verbatim: keep text + thinking; compact
// tool calls/results so the conversation stays coherent without dumping payloads.
export function renderContent(content, { trimTools = false } = {}) {
  if (content == null) return "";
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  const parts = [];
  for (const b of content) {
    if (!b || typeof b !== "object") continue;
    switch (b.type) {
      case "text":
      case "input_text":
      case "output_text":
        if (b.text) parts.push(b.text);
        break;
      case "thinking":
        if (b.thinking) parts.push(b.thinking);
        break;
      case "tool_use":
        if (!trimTools) parts.push(`[tool_use ${b.name || "?"}] ${safeJson(b.input)}`);
        break;
      case "tool_result":
        if (!trimTools) parts.push(`[tool_result] ${typeof b.content === "string" ? b.content : renderContent(b.content)}`);
        break;
      case "image":
        if (!trimTools) parts.push("[image]");
        break;
      default:
        if (b.text) parts.push(b.text);
    }
  }
  return parts.filter(Boolean).join("\n");
}

function safeJson(v) {
  try { return JSON.stringify(v); } catch { return String(v); }
}

function parseLines(text) {
  const out = [];
  for (const line of text.split("\n")) {
    const t = line.trim();
    if (!t) continue;
    try { out.push(JSON.parse(t)); } catch { /* skip malformed line */ }
  }
  return out;
}

function detectFormat(objs) {
  for (const o of objs) {
    if (o && o.payload && (o.type === "session_meta" || o.type === "response_item")) return "codex";
    if (o && o.message && (o.type === "user" || o.type === "assistant")) return "claude";
  }
  return "unknown";
}

function parseClaude(objs, opts) {
  let sessionId = null;
  let startedAt = null;
  const turns = [];
  for (const o of objs) {
    if (!sessionId && o.sessionId) sessionId = o.sessionId;
    if (o.type !== "user" && o.type !== "assistant") continue;
    const msg = o.message || {};
    const content = renderContent(msg.content, opts);
    if (!content.trim()) continue;
    if (!startedAt && o.timestamp) startedAt = o.timestamp;
    turns.push({ role: msg.role || o.type, content, timestamp: o.timestamp || null });
  }
  return { format: "claude", sessionId, cwd: null, startedAt, turns };
}

function parseCodex(objs, opts) {
  let sessionId = null;
  let cwd = null;
  let startedAt = null;
  const turns = [];
  for (const o of objs) {
    if (o.type === "session_meta") {
      const p = o.payload || {};
      sessionId = sessionId || p.id || null;
      cwd = cwd || p.cwd || null;
      startedAt = startedAt || p.timestamp || o.timestamp || null;
      continue;
    }
    if (o.type !== "response_item") continue;
    const p = o.payload || {};
    if (p.type !== "message") continue;
    const content = renderContent(p.content, opts);
    if (!content.trim()) continue;
    if (!startedAt && o.timestamp) startedAt = o.timestamp;
    turns.push({ role: p.role || "assistant", content, timestamp: o.timestamp || null });
  }
  return { format: "codex", sessionId, cwd, startedAt, turns };
}

// High-signal filter: keep substantive turns (real questions/decisions/conclusions),
// drop short/procedural chatter + harness noise. Used to cap a backfill to the
// signal-bearing units instead of every raw turn (which is too granular + too large).
const SIGNAL_NOISE_RE = [
  /<local-command/i,
  /<command-(name|message|args)/i,
  /<\/?system-reminder/i,
  /^\s*\/[a-z][\w-]*\s*$/i, // bare slash command
];
export function isHighSignalTurn(turn, { minChars = 200 } = {}) {
  const c = (turn?.content || "").trim();
  if (c.length < minChars) return false;
  for (const re of SIGNAL_NOISE_RE) if (re.test(c)) return false;
  return true;
}

export function parseSession(text, opts = {}) {
  const objs = parseLines(text);
  const format = detectFormat(objs);
  if (format === "codex") return parseCodex(objs, opts);
  if (format === "claude") return parseClaude(objs, opts);
  return { format: "unknown", sessionId: null, cwd: null, startedAt: null, turns: [] };
}
