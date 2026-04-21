/**
 * Command Registry — action catalog for the command palette.
 *
 * Every navigable route, every mutation, every query
 * is a command. The palette is the spine of the cockpit.
 */
import { createSignal } from "solid-js";

const [commands, setCommands] = createSignal([]);

/**
 * Register a command in the global registry.
 * @param {{ id: string, label: string, description?: string, category?: string, action: Function, shortcut?: string }} cmd
 */
export function registerCommand(cmd) {
  setCommands(prev => {
    const filtered = prev.filter(c => c.id !== cmd.id);
    return [...filtered, cmd];
  });
}

/**
 * Register multiple commands at once.
 */
export function registerCommands(cmds) {
  setCommands(prev => {
    const ids = new Set(cmds.map(c => c.id));
    const filtered = prev.filter(c => !ids.has(c.id));
    return [...filtered, ...cmds];
  });
}

/**
 * Fuzzy match score (simplified fzf algorithm).
 * Returns 0 for no match, higher = better match.
 */
function fuzzyScore(query, text) {
  const q = query.toLowerCase();
  const t = text.toLowerCase();

  // Exact substring match gets highest score
  if (t.includes(q)) return 1000 + (100 - t.indexOf(q));

  // Character-by-character fuzzy
  let qi = 0;
  let score = 0;
  let lastMatchIdx = -1;

  for (let ti = 0; ti < t.length && qi < q.length; ti++) {
    if (t[ti] === q[qi]) {
      score += 10;
      // Bonus for consecutive matches
      if (lastMatchIdx === ti - 1) score += 15;
      // Bonus for word boundary matches
      if (ti === 0 || t[ti - 1] === " " || t[ti - 1] === "-" || t[ti - 1] === "/") score += 20;
      lastMatchIdx = ti;
      qi++;
    }
  }

  // All query chars must match
  return qi === q.length ? score : 0;
}

/**
 * Search commands with fuzzy matching.
 * @param {string} query
 * @returns {Array<{cmd: object, score: number}>}
 */
export function searchCommands(query) {
  if (!query || !query.trim()) {
    return commands().slice(0, 12).map(cmd => ({ cmd, score: 100 }));
  }

  const results = [];
  for (const cmd of commands()) {
    const labelScore = fuzzyScore(query, cmd.label);
    const descScore = cmd.description ? fuzzyScore(query, cmd.description) * 0.6 : 0;
    const catScore = cmd.category ? fuzzyScore(query, cmd.category) * 0.4 : 0;
    const idScore = fuzzyScore(query, cmd.id) * 0.5;
    const score = Math.max(labelScore, descScore, catScore, idScore);
    if (score > 0) results.push({ cmd, score });
  }

  return results.sort((a, b) => b.score - a.score).slice(0, 12);
}

export { commands };
