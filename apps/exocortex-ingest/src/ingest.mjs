import { readFile } from "node:fs/promises";
import path from "node:path";
import { walk } from "./walk.mjs";
import { isSensitivePath, scanContent } from "./secrets.mjs";
import { assistedImport } from "./contracts.mjs";

const CHUNK_SIZE = 1200;
const TURNS_PER_IMPORT = 40; // keep request bodies bounded

function chunk(text, size = CHUNK_SIZE) {
  const out = [];
  for (let i = 0; i < text.length; i += size) out.push(text.slice(i, i + size));
  return out;
}

function batch(arr, n) {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
}

// One assisted-import per file (split into bounded batches of turns). beagle-core
// embeds server-side, so we send text only — no client-side vectors.
export async function ingestRoot(root, { limit = Infinity, dryRun = false, minSignalWeight = 0 } = {}) {
  const stats = { scanned: 0, skippedSensitive: 0, files: 0, chunks: 0, imports: 0, ingested: 0, errors: 0 };
  for await (const f of walk(root)) {
    if (stats.scanned >= limit) break;
    stats.scanned++;
    if (minSignalWeight > 0 && f.weight < minSignalWeight) { stats.skippedLowSignal = (stats.skippedLowSignal || 0) + 1; continue; }
    if (isSensitivePath(f.path)) { stats.skippedSensitive++; continue; }
    let text;
    try { text = await readFile(f.path, "utf8"); } catch { continue; }
    if (scanContent(text).flagged) { stats.skippedSensitive++; continue; }

    const chunks = chunk(text).filter((c) => c.trim());
    if (!chunks.length) continue;
    stats.files++;
    stats.chunks += chunks.length;
    if (dryRun) continue;

    const ts = new Date().toISOString();
    const title = path.basename(f.path);
    for (const group of batch(chunks, TURNS_PER_IMPORT)) {
      const turns = group.map((content, idx) => ({
        role: "user",
        content,
        timestamp: ts,
        metadata: { path: f.path, chunk_index: idx },
      }));
      stats.imports++;
      try {
        await assistedImport({
          title,
          sessionId: `disk:${f.path}`,
          turns,
          tags: ["exocortex", "tier1", "disk", `signal:${f.weight.toFixed(1)}`],
          metadata: { path: f.path, weight: f.weight, size: f.size },
        });
        stats.ingested += turns.length;
      } catch (e) {
        stats.errors++; // never throw the whole run
      }
    }
  }
  return stats;
}
