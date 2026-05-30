// action-ledger-routes.mjs
//
// Durable propose/intent/readback ledger for Darwin Project OS.
// This module never executes project actions. It records proposals and human
// intent so agents can orient from receipts instead of terminal folklore.

import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { idempotent } from "./contract.mjs";

const DATA_DIR =
  process.env.ACTION_LEDGER_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  "/var/lib/cockpit";
const MAX_EVENTS = 1000;
const MAX_LIST = 200;
const KNOWN_STATUSES = new Set([
  "proposed",
  "intent-confirmed",
  "rejected",
  "superseded"
]);

function cleanValue(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  return String(value).trim();
}

function safeSlug(slug) {
  return cleanValue(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

function fileFor(slug) {
  return path.join(DATA_DIR, "action-ledger", `${safeSlug(slug)}.jsonl`);
}

function ensureDir(file) {
  const dir = path.dirname(file);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
  }
}

function parseLimit(raw, fallback = 50) {
  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value)) return fallback;
  return Math.max(1, Math.min(MAX_LIST, value));
}

function loadEvents(slug) {
  const file = fileFor(slug);
  if (!fs.existsSync(file)) return [];
  const lines = fs
    .readFileSync(file, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  const start = Math.max(0, lines.length - MAX_EVENTS);
  return lines.slice(start).flatMap((line) => {
    try {
      return [JSON.parse(line)];
    } catch {
      return [];
    }
  });
}

function appendEvent(slug, event) {
  const file = fileFor(slug);
  ensureDir(file);
  fs.appendFileSync(file, `${JSON.stringify(event)}\n`);
}

function extractProposal(body = {}) {
  const proposal = body.proposal && typeof body.proposal === "object" ? body.proposal : body;
  const actionId = cleanValue(
    body.actionId ||
      body.action_id ||
      proposal.actionId ||
      proposal.action_id ||
      proposal.id
  );
  return {
    id: cleanValue(proposal.id || body.proposalId || actionId || "proposal").slice(0, 160),
    label: cleanValue(proposal.label || body.label || actionId || "proposal").slice(0, 240),
    kind: cleanValue(proposal.kind || body.kind || "proposal").slice(0, 80),
    summary: cleanValue(proposal.summary || body.summary || "").slice(0, 4000),
    risk: cleanValue(proposal.risk || body.risk || "low").slice(0, 40),
    actionId,
    route: cleanValue(proposal.route || body.route || "").slice(0, 1000),
    command: cleanValue(proposal.command || body.command || "").slice(0, 4000),
    enabled: proposal.enabled !== false && body.enabled !== false,
    requiresConfirmation: proposal.requiresConfirmation !== false,
    mode: "propose-only"
  };
}

function requestIdentity(req, body = {}) {
  const requestId =
    cleanValue(req.header("X-Request-ID") || req.header("x-request-id")) ||
    cleanValue(body.idempotencyKey || body.idempotency_key);
  return {
    requestId,
    idempotencyKey: cleanValue(body.idempotencyKey || body.idempotency_key || requestId),
    actor: cleanValue(body.actor || req.header("X-Darwin-Actor") || "agent").slice(0, 80),
    source: cleanValue(body.source || "autopilot").slice(0, 80)
  };
}

function createProposalEvent(slug, body = {}, req) {
  const now = new Date().toISOString();
  const proposal = extractProposal(body);
  const identity = requestIdentity(req, body);
  return {
    schema: "darwin.action-ledger-event.v0",
    ledger_id: randomUUID(),
    projectSlug: slug,
    kind: "proposal",
    status: "proposed",
    source: identity.source,
    actor: identity.actor,
    actionId: proposal.actionId,
    proposal,
    risk: proposal.risk,
    route: proposal.route,
    command: proposal.command,
    requestId: identity.requestId,
    idempotencyKey: identity.idempotencyKey,
    readback: null,
    createdAt: now,
    updatedAt: now
  };
}

function foldEvents(events = []) {
  const byId = new Map();
  for (const event of events) {
    const id = cleanValue(event.ledger_id);
    if (!id) continue;
    const existing = byId.get(id) || {
      ledger_id: id,
      projectSlug: event.projectSlug,
      createdAt: event.createdAt || event.updatedAt || "",
      eventCount: 0,
      history: []
    };
    const merged = {
      ...existing,
      ...event,
      proposal: existing.proposal || event.proposal || null,
      actionId: existing.actionId || event.actionId || "",
      route: existing.route || event.route || "",
      command: existing.command || event.command || "",
      risk: existing.risk || event.risk || "",
      source: event.source || existing.source || "",
      actor: event.actor || existing.actor || "",
      createdAt: existing.createdAt || event.createdAt || event.updatedAt || "",
      updatedAt: event.updatedAt || event.createdAt || existing.updatedAt || "",
      eventCount: existing.eventCount + 1,
      history: [...existing.history, {
        kind: event.kind,
        status: event.status,
        actor: event.actor,
        source: event.source,
        requestId: event.requestId,
        createdAt: event.createdAt,
        updatedAt: event.updatedAt
      }]
    };
    byId.set(id, merged);
  }
  return [...byId.values()].sort((left, right) =>
    cleanValue(right.updatedAt || right.createdAt).localeCompare(cleanValue(left.updatedAt || left.createdAt))
  );
}

export function listActionLedgerEntries(slug, { limit = 50 } = {}) {
  return foldEvents(loadEvents(slug)).slice(0, parseLimit(limit));
}

export function appendActionProposal(slug, body = {}, req = { header: () => "" }) {
  const event = createProposalEvent(slug, body, req);
  appendEvent(slug, event);
  return event;
}

function findLedgerRecord(slug, ledgerId) {
  return listActionLedgerEntries(slug, { limit: MAX_LIST }).find(
    (entry) => entry.ledger_id === ledgerId
  );
}

function appendTransition(slug, ledgerId, status, body = {}, req, readback = null) {
  if (!KNOWN_STATUSES.has(status)) {
    const error = new Error(`unknown action ledger status: ${status}`);
    error.statusCode = 400;
    throw error;
  }
  const existing = findLedgerRecord(slug, ledgerId);
  if (!existing) {
    const error = new Error(`unknown action ledger id: ${ledgerId}`);
    error.statusCode = 404;
    throw error;
  }
  const now = new Date().toISOString();
  const identity = requestIdentity(req, body);
  const event = {
    schema: "darwin.action-ledger-event.v0",
    ledger_id: ledgerId,
    projectSlug: slug,
    kind: status === "intent-confirmed" ? "intent" : status,
    status,
    source: identity.source || existing.source || "operator",
    actor: identity.actor || "operator",
    actionId: existing.actionId || "",
    proposal: null,
    risk: existing.risk || "",
    route: existing.route || "",
    command: existing.command || "",
    requestId: identity.requestId,
    idempotencyKey: identity.idempotencyKey,
    reason: cleanValue(body.reason || "").slice(0, 2000),
    readback,
    createdAt: now,
    updatedAt: now
  };
  appendEvent(slug, event);
  return event;
}

async function safeReadback(slug, readbackFn) {
  if (typeof readbackFn !== "function") {
    return {
      projectSlug: slug,
      observedAt: new Date().toISOString(),
      truthMode: "declared",
      note: "no readback callback registered"
    };
  }
  try {
    return await readbackFn(slug);
  } catch (error) {
    return {
      projectSlug: slug,
      observedAt: new Date().toISOString(),
      truthMode: "stale",
      error: error?.message || String(error)
    };
  }
}

async function knownSlugs(options = {}) {
  if (typeof options.listProjectSlugs === "function") {
    const slugs = await options.listProjectSlugs();
    if (Array.isArray(slugs)) return slugs.map((item) => safeSlug(item));
  }
  const dir = path.join(DATA_DIR, "action-ledger");
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((name) => name.endsWith(".jsonl"))
    .map((name) => name.replace(/\.jsonl$/, ""));
}

function jsonError(res, error) {
  res.status(error.statusCode || 500).json({
    ok: false,
    error: error.message,
    truthMode: "stale"
  });
}

export function registerActionLedgerRoutes(app, options = {}) {
  app.get("/api/project-os/actions", async (req, res) => {
    try {
      const limit = parseLimit(req.query.limit, 50);
      const slugs = await knownSlugs(options);
      const actions = slugs.flatMap((slug) => listActionLedgerEntries(slug, { limit }));
      actions.sort((left, right) =>
        cleanValue(right.updatedAt || right.createdAt).localeCompare(cleanValue(left.updatedAt || left.createdAt))
      );
      res.json({
        schema: "darwin.action-ledger.v0",
        generatedAt: new Date().toISOString(),
        scope: "project-os",
        actions: actions.slice(0, limit),
        count: Math.min(actions.length, limit),
        truthMode: "observed"
      });
    } catch (error) {
      jsonError(res, error);
    }
  });

  app.get("/api/projects/:slug/actions", async (req, res) => {
    try {
      if (typeof options.getProjectOrThrow === "function") {
        await options.getProjectOrThrow(req.params.slug);
      }
      const actions = listActionLedgerEntries(req.params.slug, { limit: req.query.limit });
      res.json({
        schema: "darwin.action-ledger.v0",
        generatedAt: new Date().toISOString(),
        projectSlug: req.params.slug,
        actions,
        count: actions.length,
        truthMode: "observed"
      });
    } catch (error) {
      jsonError(res, error);
    }
  });

  app.post(
    "/api/projects/:slug/actions/propose",
    idempotent({ ttlMs: 60_000 }),
    async (req, res) => {
      try {
        if (typeof options.getProjectOrThrow === "function") {
          await options.getProjectOrThrow(req.params.slug);
        }
        const event = appendActionProposal(req.params.slug, req.body || {}, req);
        res.json({
          ok: true,
          schema: "darwin.action-ledger.v0",
          action: foldEvents([event])[0],
          event,
          truthMode: "observed"
        });
      } catch (error) {
        jsonError(res, error);
      }
    }
  );

  app.post(
    "/api/projects/:slug/actions/:ledgerId/confirm-intent",
    idempotent({ ttlMs: 60_000 }),
    async (req, res) => {
      try {
        if (typeof options.getProjectOrThrow === "function") {
          await options.getProjectOrThrow(req.params.slug);
        }
        const readback = await safeReadback(req.params.slug, options.buildReadback);
        const event = appendTransition(
          req.params.slug,
          req.params.ledgerId,
          "intent-confirmed",
          req.body || {},
          req,
          readback
        );
        const action = findLedgerRecord(req.params.slug, req.params.ledgerId);
        res.json({
          ok: true,
          schema: "darwin.action-ledger.v0",
          action,
          event,
          readback,
          executed: false,
          truthMode: "observed"
        });
      } catch (error) {
        jsonError(res, error);
      }
    }
  );

  app.post(
    "/api/projects/:slug/actions/:ledgerId/reject",
    idempotent({ ttlMs: 60_000 }),
    async (req, res) => {
      try {
        if (typeof options.getProjectOrThrow === "function") {
          await options.getProjectOrThrow(req.params.slug);
        }
        const event = appendTransition(
          req.params.slug,
          req.params.ledgerId,
          "rejected",
          req.body || {},
          req,
          null
        );
        const action = findLedgerRecord(req.params.slug, req.params.ledgerId);
        res.json({
          ok: true,
          schema: "darwin.action-ledger.v0",
          action,
          event,
          executed: false,
          truthMode: "observed"
        });
      } catch (error) {
        jsonError(res, error);
      }
    }
  );
}
