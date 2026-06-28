// pull.mjs — Phase B: pull dyadic sessions from the exocortex conversation source.
// Each ConversationPassage is a session: ordered role-tagged turns (role=user→self=0,
// role=assistant→other=1). Restricted passages are excluded (sovereign + privacy).
// A trajectory needs >=2 turns (turn 1 already yields lr+zd; >=3 adds coherence).

import { readFile } from "node:fs/promises";

/**
 * @param {Array<{id?:string, session_id?:string, occurred_at?:string, source_platform?:string,
 *                privacy_class?:string, turns?:Array<{role?:string,content?:string}>}>} passages
 * @returns {Array<{session_id:string, occurred_at:(string|null), platform:string,
 *                  turns:Array<{speaker:number, content:string}>}>}
 */
export function sessionsFromPassages(passages) {
  const out = [];
  for (const p of passages || []) {
    if (String(p.privacy_class || "").toLowerCase() === "restricted") continue;
    const turns = (p.turns || [])
      .map((t) => ({
        speaker: String(t.role || "user").toLowerCase() === "assistant" ? 1 : 0,
        content: String(t.content || ""),
      }))
      .filter((t) => t.content.trim().length > 0);
    if (turns.length < 2) continue;
    out.push({
      session_id: String(p.id || p.session_id || ""),
      occurred_at: p.occurred_at || null,
      platform: p.source_platform || "",
      turns,
    });
  }
  return out;
}

/** Read a conversation_passages JSONL file (one passage per line) into sessions. */
export async function sessionsFromJsonl(file) {
  const raw = await readFile(file, "utf8");
  const passages = [];
  for (const line of raw.split("\n")) {
    const s = line.trim();
    if (!s) continue;
    try {
      passages.push(JSON.parse(s));
    } catch {
      /* skip malformed */
    }
  }
  return sessionsFromPassages(passages);
}

export default sessionsFromPassages;
