import { readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";
import { parseSession } from "./conversations.mjs";
import { scanContent } from "./secrets.mjs";
import { assistedImport } from "./contracts.mjs";

const TURNS_PER_IMPORT = 40;
// Roles that are real conversation. The system/developer envelope (Codex
// permissions boilerplate, identical across sessions) is excluded unless
// INCLUDE_SYSTEM=1, so it doesn't drown the biographical signal in recall.
const CONVO_ROLES = new Set(["user", "assistant"]);

async function* findSessionFiles(root) {
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try { entries = await readdir(dir, { withFileTypes: true }); } catch { continue; }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) { stack.push(full); continue; }
      if (!e.isFile() || !full.endsWith(".jsonl")) continue;
      // Only true session transcripts: under claude/projects/ or codex/sessions/.
      if (!/\/claude\/projects\//.test(full) && !/\/codex\/sessions\//.test(full)) continue;
      yield full;
    }
  }
}

function batch(arr, n) {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
}

export async function ingestConversations(root, { limit = Infinity, dryRun = false, includeSystem = false, trimTools = true } = {}) {
  const stats = { sessions: 0, parsed: 0, turnsKept: 0, turnsSkippedRole: 0, turnsSkippedSecret: 0, imports: 0, ingested: 0, errors: 0 };
  for await (const file of findSessionFiles(root)) {
    if (stats.sessions >= limit) break;
    stats.sessions++;
    let text;
    try { text = await readFile(file, "utf8"); } catch { continue; }
    const s = parseSession(text, { trimTools });
    if (s.format === "unknown" || !s.turns.length) continue;
    stats.parsed++;

    const kept = [];
    for (const t of s.turns) {
      if (!includeSystem && !CONVO_ROLES.has(t.role)) { stats.turnsSkippedRole++; continue; }
      if (scanContent(t.content).flagged) { stats.turnsSkippedSecret++; continue; } // hard guardrail
      kept.push(t);
    }
    if (!kept.length) continue;
    stats.turnsKept += kept.length;
    if (dryRun) continue;

    const label = path.basename(path.dirname(file)).replace(/^-/, "").replace(/-/g, "/");
    const ts = s.startedAt || new Date().toISOString();
    for (const group of batch(kept, TURNS_PER_IMPORT)) {
      const turns = group.map((t) => ({
        role: t.role === "user" ? "user" : "assistant",
        content: t.content,
        timestamp: t.timestamp || ts,
        metadata: { orig_role: t.role },
      }));
      stats.imports++;
      try {
        await assistedImport({
          title: `${s.format} session — ${label}`,
          sessionId: `${s.format}:${s.sessionId || path.basename(file)}`,
          sourcePlatform: `agent-${s.format}`,
          sourceSurface: "agent-conversation",
          importScope: "agent_conversation",
          confidenceScore: 0.85,
          turns,
          tags: ["exocortex", "tier2", "agent-convo", s.format, label ? `project:${label}` : "project:unknown"],
          metadata: { path: file, format: s.format, cwd: s.cwd, session_id: s.sessionId },
        });
        stats.ingested += turns.length;
      } catch (e) { stats.errors++; }
    }
  }
  return stats;
}
