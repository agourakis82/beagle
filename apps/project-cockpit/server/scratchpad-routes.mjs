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

export function loadScratchpadEntries(slug) {
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

function cleanString(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "boolean") return String(value).trim();
  return "";
}

function normalizeConsciousnessState(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const hrv = Number(raw.hrv_ms ?? raw.hrvMs);
  const readiness = Number(raw.readiness);
  const intensity = cleanString(raw.intensity);
  const circadianPhase = cleanString(raw.circadian_phase ?? raw.circadianPhase);
  if (!Number.isFinite(hrv) && !Number.isFinite(readiness) && !intensity && !circadianPhase) {
    return null;
  }
  return {
    hrv_ms: Number.isFinite(hrv) ? hrv : null,
    readiness: Number.isFinite(readiness) ? readiness : null,
    intensity: intensity || null,
    circadian_phase: circadianPhase || null,
    captured_at: new Date().toISOString()
  };
}

export function buildScratchpadEntry(slug, body = {}) {
  const text = String(body.text || "").trim();
  if (!text) {
    throw new Error("text required");
  }
  return {
    entry_id: randomUUID(),
    slug,
    text: text.slice(0, 8000),
    author: String(body.author || "unknown").slice(0, 64),
    tags: Array.isArray(body.tags) ? body.tags.slice(0, 8) : [],
    project_family: String(body.project_family || body.projectFamily || "").slice(0, 32),
    publication_scope: String(body.publication_scope || body.publicationScope || "").slice(0, 32),
    promotion_state: String(body.promotion_state || body.promotionState || "").slice(0, 32),
    consciousness_state: normalizeConsciousnessState(
      body.consciousness_state || body.consciousnessState
    ),
    created_at: new Date().toISOString()
  };
}

export function appendScratchpadEntry(slug, entry) {
  const file = fileFor(slug);
  ensureDir(file);
  fs.appendFileSync(file, JSON.stringify(entry) + "\n");

  // Trim file to MAX_ENTRIES if it has grown too large
  try {
    const content = fs.readFileSync(file, "utf8");
    const lines = content.split("\n").filter(Boolean);
    if (lines.length > MAX_ENTRIES * 2) {
      fs.writeFileSync(file, lines.slice(-MAX_ENTRIES).join("\n") + "\n");
    }
  } catch { /* best effort */ }
}

export function deleteScratchpadEntry(slug, entryId) {
  const file = fileFor(slug);
  if (!fs.existsSync(file)) return false;
  const remaining = loadScratchpadEntries(slug).filter((e) => e.entry_id !== entryId);
  fs.writeFileSync(file, remaining.map((e) => JSON.stringify(e) + "\n").join(""));
  return true;
}

export function registerScratchpadRoutes(app) {
  app.get("/api/projects/:slug/agents/scratchpad", (req, res) => {
    try {
      const all = loadScratchpadEntries(req.params.slug);
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
      const entry = buildScratchpadEntry(req.params.slug, req.body || {});
      appendScratchpadEntry(req.params.slug, entry);
      res.json({ ok: true, entry, truthMode: "observed" });
    } catch (e) {
      const statusCode = e.message === "text required" ? 400 : 500;
      res.status(statusCode).json({ error: e.message, truthMode: statusCode === 400 ? "declared" : "stale" });
    }
  });

  app.delete(
    "/api/projects/:slug/agents/scratchpad/:entry_id",
    (req, res) => {
      try {
        const removed = deleteScratchpadEntry(req.params.slug, req.params.entry_id);
        res.json({ ok: true, removed, truthMode: "observed" });
      } catch (e) {
        res.status(500).json({ error: e.message, truthMode: "stale" });
      }
    }
  );
}
