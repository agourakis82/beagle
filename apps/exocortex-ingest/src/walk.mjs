import { readdir, stat } from "node:fs/promises";
import path from "node:path";

const EXCLUDE_DIRS = new Set([
  "node_modules", "target", ".git", ".cache", "dist", "build",
  ".venv", "venv", "__pycache__", ".next", ".turbo", "DerivedData",
]);
const INCLUDE_EXT = new Set([
  ".md", ".txt", ".tex", ".pdf", ".org", ".rtf", ".docx", ".csv",
  ".sio", ".rs", ".swift", ".py", ".ts", ".mjs", ".js",
]);
// Biographical signal: his own writing/thinking > project docs > generated/code.
const HIGH = [/journal/i, /diary/i, /notes?/i, /research/i, /paper/i, /\.tex$/i, /thoughts?/i, /CURRENT_THREAD/i];
const LOW = [/README/i, /CHANGELOG/i, /LICENSE/i, /node_modules/i, /\.lock$/i];

export function classifyPath(p) {
  const parts = p.split("/");
  if (parts.some((seg) => EXCLUDE_DIRS.has(seg))) return "exclude";
  const ext = path.extname(p).toLowerCase();
  if (!INCLUDE_EXT.has(ext)) return "exclude";
  return "include";
}

export function signalWeight(p) {
  let w = 1.0;
  const ext = path.extname(p).toLowerCase();
  if ([".md", ".txt", ".tex", ".org", ".rtf"].includes(ext)) w += 1.5; // prose
  if ([".rs", ".swift", ".py", ".ts", ".js", ".mjs", ".sio"].includes(ext)) w += 0.3; // code
  for (const re of HIGH) if (re.test(p)) w += 2.0;
  for (const re of LOW) if (re.test(p)) w -= 1.5;
  return w;
}

export async function* walk(root) {
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try { entries = await readdir(dir, { withFileTypes: true }); } catch { continue; }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (!EXCLUDE_DIRS.has(e.name)) stack.push(full);
      } else if (e.isFile() && classifyPath(full) === "include") {
        let size = 0;
        try { size = (await stat(full)).size; } catch {}
        if (size > 0 && size < 2_000_000) yield { path: full, weight: signalWeight(full), size };
      }
    }
  }
}
