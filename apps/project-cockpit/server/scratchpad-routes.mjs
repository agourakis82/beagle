// scratchpad-routes.mjs
//
// /api/projects/:slug/agents/scratchpad — a tiny shared notepad between
// the cockpit-resident Claude Code agent and external clients (iOS,
// cockpit web UI, ChatGPT). The agent leaves notes; iOS reads them; iOS
// posts back; agent reads on next session. Bounded JSONL append.
//
// Endpoints:
//   GET    /api/projects/:slug/agents/scratchpad           — list entries (latest first)
//   POST   /api/projects/:slug/agents/scratchpad           — append one entry
//   DELETE /api/projects/:slug/agents/scratchpad/:entry_id — remove one entry
//
// Storage: $BEAGLE_DATA_DIR (or /var/lib/cockpit) /scratchpad/<slug>.jsonl
// — same JSONL pattern used by the cognitive registries on beagle-core.

import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";

const DATA_DIR =
  process.env.SCRATCHPAD_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  "/var/lib/cockpit";
const MAX_ENTRIES = 200;

function fileFor(slug) {
  const safe = slug.replace(/[^a-zA-Z0-9_-]/g, "_");
  return path.join(DATA_DIR, "scratchpad", `${safe}.jsonl`);
}

function ensureDir(file) {
  const dir = path.dirname(file);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
  }
}

function loadAll(slug) {
  const file = fileFor(slug);
  if (!fs.existsSync(file)) return [];
  const lines = fs
    .readFileSync(file, "utf8")
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
  const start = Math.max(0, lines.length - MAX_ENTRIES);
  return lines.slice(start).flatMap((l) => {
    try {
      return [JSON.parse(l)];
    } catch {
      return [];
    }
  });
}

function appendEntry(slug, entry) {
  const file = fileFor(slug);
  ensureDir(file);
  fs.appendFileSync(file, JSON.stringify(entry) + "\n");
}

export function listScratchpadEntries(slug) {
  return loadAll(slug);
}

export function createScratchpadEntry(slug, body = {}) {
  const text = String(body.text || "").trim();
  if (!text) {
    const error = new Error("text required");
    error.statusCode = 400;
    throw error;
  }

  return {
    entry_id: randomUUID(),
    slug,
    text: text.slice(0, 8000),
    author: String(body.author || "unknown").slice(0, 64),
    tags: Array.isArray(body.tags) ? body.tags.slice(0, 8) : [],
    created_at: new Date().toISOString(),
  };
}

export function appendScratchpadEntry(slug, body = {}) {
  const entry = createScratchpadEntry(slug, body);
  appendEntry(slug, entry);
  return entry;
}

function rewriteWithout(slug, entryId) {
  const file = fileFor(slug);
  if (!fs.existsSync(file)) return false;
  const remaining = loadAll(slug).filter((e) => e.entry_id !== entryId);
  fs.writeFileSync(file, remaining.map((e) => JSON.stringify(e) + "\n").join(""));
  return true;
}

export function registerScratchpadRoutes(app) {
  app.get("/api/projects/:slug/agents/scratchpad", (req, res) => {
    try {
      const all = listScratchpadEntries(req.params.slug);
      // Latest first for the iOS list view.
      all.reverse();
      res.json({
        projectSlug: req.params.slug,
        entries: all,
        count: all.length,
        truthMode: "observed",
      });
    } catch (e) {
      res.status(500).json({ error: e.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/agents/scratchpad", (req, res) => {
    try {
      const entry = appendScratchpadEntry(req.params.slug, req.body || {});
      res.json({ ok: true, entry, truthMode: "observed" });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale" });
    }
  });

  app.delete(
    "/api/projects/:slug/agents/scratchpad/:entry_id",
    (req, res) => {
      try {
        const removed = rewriteWithout(req.params.slug, req.params.entry_id);
        res.json({ ok: true, removed, truthMode: "observed" });
      } catch (e) {
        res.status(500).json({ error: e.message, truthMode: "stale" });
      }
    }
  );
}
