// workbench-context-routes.mjs
//
// Durable context mesh for the Workbench mirror.
//
// This is intentionally not a replacement for Beagle Core memory. It is a
// write-through overlay that makes the Workbench contract operational today:
// ingest -> read-after-write query -> bounded GraphRAG projection -> compiled
// context packet. Beagle Core remains the upstream memory authority when its
// published image exposes the deeper GraphRAG/compiler routes.

import fs from "node:fs";
import path from "node:path";
import { createHash, timingSafeEqual, randomUUID } from "node:crypto";
import { fetchOperatorToken } from "./auth-bridge.mjs";
import { idempotent } from "./contract.mjs";

function cleanEnv(value) {
  return typeof value === "string" && value.trim() ? value.trim() : "";
}

const DATA_DIR =
  process.env.WORKBENCH_CONTEXT_DATA_DIR ||
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  "/var/lib/cockpit";
const MAX_LOCAL_RECORDS = Number(process.env.WORKBENCH_CONTEXT_MAX_RECORDS || 5000);
const DEFAULT_LIMIT = 8;
const HTTP_MCP_SSE_KEEPALIVE_MS = Math.max(5000, Number(process.env.WORKBENCH_CONTEXT_HTTP_MCP_SSE_KEEPALIVE_MS || 15000));
const HTTP_MCP_SESSION_TTL_MS = Math.max(60_000, Number(process.env.WORKBENCH_CONTEXT_HTTP_MCP_SESSION_TTL_MS || 10 * 60_000));
const BEAGLE_PUBLIC_URL =
  process.env.PROJECT_COCKPIT_BEAGLE_URL || "http://beagle-core.tail21cbc4.ts.net";
const BEAGLE_INTERNAL_URL =
  process.env.PROJECT_COCKPIT_BEAGLE_INTERNAL_URL ||
  "http://beagle-core.beagle.svc.cluster.local:8080";

function truthyEnv(value) {
  return /^(1|true|yes)$/i.test(cleanEnv(value));
}

const REQUIRE_HTTP_MCP_AUTH = truthyEnv(
  process.env.WORKBENCH_CONTEXT_HTTP_MCP_REQUIRE_AUTH ||
    process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_REQUIRE_AUTH ||
    ""
);
const REQUIRE_CONTEXT_WRITE_AUTH = truthyEnv(
  process.env.WORKBENCH_CONTEXT_WRITE_REQUIRE_AUTH ||
    process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_WRITE_REQUIRE_AUTH ||
    (REQUIRE_HTTP_MCP_AUTH ? "true" : "")
);
const REQUIRE_CONTEXT_READ_AUTH = truthyEnv(
  process.env.WORKBENCH_CONTEXT_READ_REQUIRE_AUTH ||
    process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_READ_REQUIRE_AUTH ||
    ""
);
const ENV_STATIC_HTTP_MCP_TOKEN =
  cleanEnv(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
  cleanEnv(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
const STATIC_HTTP_MCP_TOKEN_FILE = cleanEnv(
  process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE ||
    process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE
);
const httpMcpSessions = new Map();

function staticHttpMcpToken() {
  if (ENV_STATIC_HTTP_MCP_TOKEN) return ENV_STATIC_HTTP_MCP_TOKEN;
  if (!STATIC_HTTP_MCP_TOKEN_FILE) return "";
  try {
    return cleanEnv(fs.readFileSync(STATIC_HTTP_MCP_TOKEN_FILE, "utf8"));
  } catch {
    return "";
  }
}

const KNOWN_CONTEXT_CLIENTS = [
  {
    client_id: "claude-desktop",
    label: "Claude Desktop",
    provider: "anthropic",
    transport: "stdio-mcp",
    source_aliases: ["claude-desktop", "claude", "claude-code"]
  },
  {
    client_id: "chatgpt",
    label: "ChatGPT",
    provider: "openai",
    transport: "http-mcp",
    source_aliases: ["chatgpt", "openai", "codex"]
  },
  {
    client_id: "grok",
    label: "Grok",
    provider: "xai",
    transport: "http-mcp",
    source_aliases: ["grok", "grok-cli"]
  },
  {
    client_id: "kimi",
    label: "Kimi CLI",
    provider: "moonshot",
    transport: "cli-mcp",
    source_aliases: ["kimi", "kimi-cli"]
  },
  {
    client_id: "cursor",
    label: "Cursor",
    provider: "cursor",
    transport: "stdio-mcp",
    source_aliases: ["cursor", "cursor-agent"]
  },
  {
    client_id: "local-agents",
    label: "Local zellij agents",
    provider: "beagle",
    transport: "darwin-mcp-zellij",
    source_aliases: ["workbench", "project-cockpit-workbench", "codex-smoke", "zellij-agent"]
  }
];
let contextRouteHooks = {};

function cleanString(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  const text = String(value).trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

function contextFile(slug) {
  return path.join(DATA_DIR, "workbench-context", `${safeSlug(slug)}.jsonl`);
}

function ensureDir(file) {
  const dir = path.dirname(file);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
  }
}

function normalizeText(value) {
  return cleanString(value)
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

function tokenize(value) {
  const stop = new Set([
    "the", "and", "for", "com", "que", "uma", "uns", "das", "dos", "para",
    "por", "from", "into", "this", "that", "isso", "aqui", "agora", "mais",
    "como", "with", "sem", "mas", "ter", "tem", "não", "nao"
  ]);
  return [...new Set(
    normalizeText(value)
      .split(/[^a-z0-9_+#-]+/i)
      .map((token) => token.trim())
      .filter((token) => token.length > 2 && !stop.has(token))
  )];
}

function boundedText(value, max = 12000) {
  return cleanString(value).slice(0, max);
}

function stableHash(value) {
  return createHash("sha256")
    .update(typeof value === "string" ? value : JSON.stringify(value || {}))
    .digest("hex");
}

function requestIdFromBody(body = {}) {
  return cleanString(
    body.request_id ||
      body.requestId ||
      body.idempotency_key ||
      body.idempotencyKey ||
      body.event_id ||
      body.eventId
  );
}

function bearerToken(req) {
  const header = cleanString(req.headers?.authorization || req.headers?.Authorization);
  const match = header.match(/^Bearer\s+(.+)$/i);
  return cleanString(match?.[1]);
}

function safeTokenEqual(left, right) {
  const a = Buffer.from(cleanString(left));
  const b = Buffer.from(cleanString(right));
  if (a.length === 0 || b.length === 0 || a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

async function verifyWorkbenchContextToken(req) {
  const supplied = bearerToken(req) || cleanString(req.headers?.["x-workbench-context-token"]);
  const staticToken = staticHttpMcpToken();
  if (staticToken && safeTokenEqual(supplied, staticToken)) {
    return true;
  }
  try {
    const tokenResult = await fetchOperatorToken();
    if (!tokenResult.error && tokenResult.token && safeTokenEqual(supplied, tokenResult.token)) {
      return true;
    }
  } catch {
    // Fall through to unauthorized; routes stay closed if token lookup fails.
  }
  return false;
}

async function requireContextAuth(req, res, next, { required, label }) {
  if (!required) return next();
  if (await verifyWorkbenchContextToken(req)) return next();
  res.status(401).json({
    error: `${label} requires Authorization: Bearer <token>`,
    truthMode: "declared"
  });
}

function requireHttpMcpAuth(req, res, next) {
  return requireContextAuth(req, res, next, {
    required: REQUIRE_HTTP_MCP_AUTH,
    label: "Workbench HTTP MCP"
  });
}

function requireContextReadAuth(req, res, next) {
  return requireContextAuth(req, res, next, {
    required: REQUIRE_CONTEXT_READ_AUTH,
    label: "Workbench Context read"
  });
}

function requireContextWriteAuth(req, res, next) {
  return requireContextAuth(req, res, next, {
    required: REQUIRE_CONTEXT_WRITE_AUTH,
    label: "Workbench Context write"
  });
}

function requireDoctorProbeAuth(req, res, next) {
  const body = req.body || {};
  const wantsProbe =
    body.write_probe === true ||
    body.writeProbe === true ||
    cleanString(body.write_probe).toLowerCase() === "true" ||
    cleanString(body.writeProbe).toLowerCase() === "true";
  if (!wantsProbe) return next();
  return requireContextWriteAuth(req, res, next);
}

function lineToRecord(line) {
  try {
    return JSON.parse(line);
  } catch {
    return null;
  }
}

function readLocalRecords(slug) {
  const file = contextFile(slug);
  if (!fs.existsSync(file)) return [];
  const lines = fs.readFileSync(file, "utf8").split("\n").filter(Boolean);
  const start = Math.max(0, lines.length - MAX_LOCAL_RECORDS);
  return lines.slice(start).map(lineToRecord).filter(Boolean);
}

function recordsByExternalId(slug) {
  const index = new Map();
  for (const record of readLocalRecords(slug)) {
    const externalId = cleanString(record.external_id || record.metadata?.external_id);
    if (!externalId) continue;
    const list = index.get(externalId) || [];
    list.push(record);
    index.set(externalId, list);
  }
  return index;
}

function appendLocalRecord(slug, record) {
  const file = contextFile(slug);
  ensureDir(file);
  fs.appendFileSync(file, `${JSON.stringify(record)}\n`);
}

function appendAuditEvent(slug, event) {
  const file = path.join(DATA_DIR, "workbench-context", `${safeSlug(slug)}.audit.jsonl`);
  ensureDir(file);
  fs.appendFileSync(file, `${JSON.stringify({
    schema: "beagle.workbench-context-audit-event.v1",
    projectSlug: safeSlug(slug),
    generatedAt: new Date().toISOString(),
    ...event
  })}\n`);
}

function setContextRouteHooks(hooks = {}) {
  contextRouteHooks = hooks && typeof hooks === "object" ? hooks : {};
}

async function notifyContextRouteHook(name, payload) {
  const hook = contextRouteHooks[name];
  if (typeof hook !== "function") return null;
  try {
    return await hook(payload);
  } catch {
    return null;
  }
}

function readAuditEvents(slug, limit = 50) {
  const file = path.join(DATA_DIR, "workbench-context", `${safeSlug(slug)}.audit.jsonl`);
  if (!fs.existsSync(file)) return [];
  const lines = fs.readFileSync(file, "utf8").split("\n").filter(Boolean);
  const cap = Math.max(1, Math.min(200, Number(limit) || 50));
  return lines.slice(Math.max(0, lines.length - cap)).map(lineToRecord).filter(Boolean).reverse();
}

function normalizeTags(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((tag) => cleanString(tag)).filter(Boolean).slice(0, 24))];
}

function normalizeTurns(body = {}) {
  if (Array.isArray(body.turns) && body.turns.length > 0) {
    return body.turns.map((turn, index) => ({
      role: cleanString(turn.role || "user").toLowerCase(),
      text: boundedText(turn.content || turn.text),
      turn_index: Number.isFinite(Number(turn.turn_index)) ? Number(turn.turn_index) : index,
      model: cleanString(turn.model || body.model),
      external_id: cleanString(turn.external_id || turn.externalId || turn.id)
    })).filter((turn) => turn.text);
  }

  return [{
    role: cleanString(body.role || "user").toLowerCase(),
    text: boundedText(body.text || body.content || body.message),
    turn_index: Number.isFinite(Number(body.turn_index)) ? Number(body.turn_index) : 0,
    model: cleanString(body.model),
    external_id: cleanString(body.external_id || body.externalId || body.id)
  }].filter((turn) => turn.text);
}

function normalizeIngestBody(slug, body = {}) {
  const now = new Date().toISOString();
  const metadata = body.metadata && typeof body.metadata === "object" ? body.metadata : {};
  const requestId = requestIdFromBody(body);
  const sessionId =
    cleanString(body.session_id || body.sessionId || body.conversation_id || body.conversationId) ||
    `workbench:${slug}:${now.slice(0, 10)}`;
  const source = cleanString(body.source || metadata.source || "workbench");
  const provider = cleanString(body.provider || metadata.provider || source);
  const tags = normalizeTags([
    ...normalizeTags(body.tags),
    slug,
    "workbench-context",
    "mcp-context",
    "rag-plus-plus"
  ]);
  return normalizeTurns(body).map((turn) => {
    const role = ["user", "assistant", "system", "tool"].includes(turn.role) ? turn.role : "user";
    const externalId =
      cleanString(turn.external_id || turn.externalId || turn.id) ||
      (requestId ? `${requestId}:${turn.turn_index}` : "") ||
      stableHash({
        projectSlug: slug,
        source,
        sessionId,
        conversationId: cleanString(body.conversation_id || body.conversationId || sessionId),
        turn_index: turn.turn_index,
        role,
        text: turn.text
      });
    return {
      schema: "beagle.workbench-context-turn.v1",
      memory_id: randomUUID(),
      external_id: externalId,
      request_id: requestId,
      projectSlug: slug,
      source,
      provider,
      client_id: cleanString(body.client_id || body.clientId || metadata.client_id || source),
      session_id: sessionId,
      conversation_id: cleanString(body.conversation_id || body.conversationId || sessionId),
      turn_index: turn.turn_index,
      role,
      text: turn.text,
      tags,
      metadata: {
        ...metadata,
        external_id: externalId,
        request_id: requestId,
        model: turn.model || cleanString(body.model || metadata.model),
        domain: cleanString(body.domain || metadata.domain || "beagle-workbench"),
        workspace_id: cleanString(body.workspace_id || metadata.workspace_id || slug),
        zellij_session: cleanString(body.zellij_session || metadata.zellij_session || metadata.session_id)
      },
      created_at: now,
      searchable: true,
      truthMode: "observed"
    };
  });
}

function parseLimit(body = {}, max = 30, fallback = DEFAULT_LIMIT) {
  const raw = body.limit ?? body.max_items ?? body.top_k ?? fallback;
  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) ? Math.max(1, Math.min(max, value)) : fallback;
}

function queryText(body = {}) {
  return cleanString(body.query || body.query_text || body.text);
}

function filterRecord(record, filters = {}) {
  const tags = normalizeTags(filters.tags);
  if (tags.length > 0 && !tags.every((tag) => record.tags?.includes(tag))) return false;
  const source = cleanString(filters.source);
  if (source && record.source !== source) return false;
  const sessionId = cleanString(filters.session_id || filters.sessionId);
  if (sessionId && record.session_id !== sessionId) return false;
  return true;
}

function scoreRecord(record, query, filters = {}) {
  const qNorm = normalizeText(query);
  const textNorm = normalizeText(record.text);
  const haystack = normalizeText([
    record.text,
    record.source,
    record.session_id,
    ...(record.tags || []),
    record.metadata?.domain,
    record.metadata?.workspace_id,
    record.metadata?.zellij_session
  ].join(" "));
  const tokens = tokenize(query);
  let score = 0;

  if (qNorm && textNorm.includes(qNorm)) score += 40;
  for (const token of tokens) {
    if (haystack.includes(token)) score += 4;
    if (textNorm.includes(token)) score += 3;
    if ((record.tags || []).some((tag) => normalizeText(tag).includes(token))) score += 5;
  }
  for (const tag of normalizeTags(filters.tags)) {
    if ((record.tags || []).includes(tag)) score += 6;
  }
  const ageMs = Date.now() - Date.parse(record.created_at || 0);
  if (Number.isFinite(ageMs)) {
    score += Math.max(0, 2 - ageMs / (1000 * 60 * 60 * 24 * 14));
  }
  return score;
}

function snippet(value, max = 320) {
  const text = cleanString(value);
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

function localHighlight(record, relevance) {
  return {
    memory_id: record.memory_id,
    external_id: record.external_id || "",
    source: record.source,
    provider: record.provider,
    client_id: record.client_id || "",
    date: record.created_at,
    snippet: snippet(record.text),
    text: record.text,
    role: record.role,
    session_id: record.session_id,
    conversation_id: record.conversation_id,
    turn_index: record.turn_index,
    tags: record.tags || [],
    domain: record.metadata?.domain || "",
    relevance,
    origin: "workbench-context",
    truthMode: "observed"
  };
}

function beagleHighlight(item = {}, index = 0) {
  const text = cleanString(item.text || item.snippet || item.content || item.summary);
  return {
    memory_id: cleanString(item.memory_id || item.id || `beagle:${index}`),
    external_id: cleanString(item.external_id || item.externalId),
    source: cleanString(item.source || "beagle-memory"),
    provider: cleanString(item.provider || "beagle-core"),
    client_id: cleanString(item.client_id || item.clientId),
    date: cleanString(item.date || item.timestamp || item.created_at),
    snippet: snippet(text),
    text,
    role: cleanString(item.role),
    session_id: cleanString(item.session_id || item.conversation_id),
    conversation_id: cleanString(item.conversation_id || item.session_id),
    turn_index: item.turn_index ?? null,
    tags: Array.isArray(item.tags) ? item.tags : [],
    domain: cleanString(item.domain),
    relevance: Number(item.relevance ?? item.score ?? 0),
    origin: "beagle-core",
    truthMode: "observed"
  };
}

function extractEntities(text) {
  const dictionary = [
    "Beagle", "Sounio", "MCP", "RAG++", "GraphRAG", "HyperMemory", "Claude",
    "Claude Desktop", "ChatGPT", "Grok", "Codex", "Cursor", "Kimi", "Zellij",
    "Darwin", "Qdrant", "Neo4j", "OrangeFS", "Slurm"
  ];
  const found = new Set();
  const raw = cleanString(text);
  for (const term of dictionary) {
    if (raw.toLowerCase().includes(term.toLowerCase())) found.add(term);
  }
  for (const match of raw.matchAll(/\b[A-Z][A-Za-z0-9+_-]{2,}\b/g)) {
    found.add(match[0].slice(0, 60));
  }
  return [...found].slice(0, 16);
}

function addNode(nodes, node) {
  if (!nodes.has(node.node_id)) {
    nodes.set(node.node_id, node);
  }
}

function addEdge(edges, edge) {
  if (!edges.has(edge.edge_id)) {
    edges.set(edge.edge_id, edge);
  }
}

function nodeId(type, value) {
  return `${type}:${normalizeText(value).replace(/[^a-z0-9_+#-]+/g, "-").slice(0, 90)}`;
}

function buildGraph(highlights, { query, slug, mode = "local" } = {}) {
  const nodes = new Map();
  const edges = new Map();
  const queryNodeId = nodeId("query", query || slug);
  addNode(nodes, {
    node_version: "beagle-workbench-graphrag-node-v1",
    node_id: queryNodeId,
    node_type: "query",
    display_name: query || slug,
    support_memory_ids: highlights.map((item) => item.memory_id).filter(Boolean),
    properties: { mode, projectSlug: slug }
  });

  for (const item of highlights) {
    const memoryId = item.memory_id || randomUUID();
    const memoryNodeId = nodeId("memory", memoryId);
    addNode(nodes, {
      node_version: "beagle-workbench-graphrag-node-v1",
      node_id: memoryNodeId,
      node_type: "memory",
      display_name: item.snippet || memoryId,
      support_memory_ids: [memoryId],
      properties: {
        source: item.source,
        provider: item.provider,
        client_id: item.client_id,
        session_id: item.session_id,
        origin: item.origin,
        relevance: item.relevance,
        date: item.date
      }
    });
    addEdge(edges, {
      edge_version: "beagle-workbench-graphrag-edge-v1",
      edge_id: `${queryNodeId}->${memoryNodeId}`,
      from_node_id: queryNodeId,
      to_node_id: memoryNodeId,
      edge_type: "retrieved",
      support_memory_ids: [memoryId],
      properties: { relevance: item.relevance }
    });

    for (const tag of item.tags || []) {
      const tagNodeId = nodeId("tag", tag);
      addNode(nodes, {
        node_version: "beagle-workbench-graphrag-node-v1",
        node_id: tagNodeId,
        node_type: "tag",
        display_name: tag,
        support_memory_ids: [memoryId],
        properties: {}
      });
      addEdge(edges, {
        edge_version: "beagle-workbench-graphrag-edge-v1",
        edge_id: `${memoryNodeId}->${tagNodeId}`,
        from_node_id: memoryNodeId,
        to_node_id: tagNodeId,
        edge_type: "tagged_as",
        support_memory_ids: [memoryId],
        properties: {}
      });
    }

    for (const [type, value] of [
      ["source", item.source],
      ["session", item.session_id],
      ["provider", item.provider],
      ["client", item.client_id]
    ]) {
      if (!value) continue;
      const relationNodeId = nodeId(type, value);
      addNode(nodes, {
        node_version: "beagle-workbench-graphrag-node-v1",
        node_id: relationNodeId,
        node_type: type,
        display_name: value,
        support_memory_ids: [memoryId],
        properties: {}
      });
      addEdge(edges, {
        edge_version: "beagle-workbench-graphrag-edge-v1",
        edge_id: `${memoryNodeId}->${relationNodeId}`,
        from_node_id: memoryNodeId,
        to_node_id: relationNodeId,
        edge_type: `has_${type}`,
        support_memory_ids: [memoryId],
        properties: {}
      });
    }

    const entities = extractEntities(`${item.text || ""} ${(item.tags || []).join(" ")}`);
    for (const entity of entities) {
      const entityNodeId = nodeId("entity", entity);
      addNode(nodes, {
        node_version: "beagle-workbench-graphrag-node-v1",
        node_id: entityNodeId,
        node_type: "entity",
        display_name: entity,
        support_memory_ids: [memoryId],
        properties: {}
      });
      addEdge(edges, {
        edge_version: "beagle-workbench-graphrag-edge-v1",
        edge_id: `${memoryNodeId}->${entityNodeId}`,
        from_node_id: memoryNodeId,
        to_node_id: entityNodeId,
        edge_type: "mentions",
        support_memory_ids: [memoryId],
        properties: {}
      });
    }
  }

  return {
    result_version: "beagle-workbench-graphrag-result-v1",
    query_type: "hybrid_context",
    query_mode: mode,
    query_mode_source: "workbench-context-router",
    collection_name: "workbench-context",
    node_count: nodes.size,
    edge_count: edges.size,
    nodes: [...nodes.values()],
    edges: [...edges.values()]
  };
}

async function callBeagle(pathname, body, { method = "POST", timeoutMs = 15000 } = {}) {
  const tokenResult = await fetchOperatorToken();
  if (tokenResult.error || !tokenResult.token) {
    throw new Error(tokenResult.error || "beagle token unavailable");
  }

  async function call(baseUrl) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetch(`${baseUrl.replace(/\/+$/, "")}${pathname}`, {
        method,
        headers: {
          Accept: "application/json",
          "content-type": "application/json",
          "X-Beagle-Consumer": "beagle-operator",
          Authorization: `Bearer ${tokenResult.token}`
        },
        body: method === "POST" ? JSON.stringify(body || {}) : undefined,
        signal: ctrl.signal
      });
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) {
        const error = new Error(payload?.error || payload?.raw || `beagle ${res.status}`);
        error.statusCode = res.status;
        error.payload = payload;
        throw error;
      }
      return { payload, baseUrl };
    } finally {
      clearTimeout(timer);
    }
  }

  try {
    return await call(BEAGLE_INTERNAL_URL);
  } catch (internalError) {
    if (BEAGLE_PUBLIC_URL.replace(/\/+$/, "") === BEAGLE_INTERNAL_URL.replace(/\/+$/, "")) {
      throw internalError;
    }
    return await call(BEAGLE_PUBLIC_URL);
  }
}

async function writeThroughToBeagle(records) {
  const bySession = new Map();
  for (const record of records) {
    const key = `${record.source}::${record.session_id}`;
    const list = bySession.get(key) || [];
    list.push(record);
    bySession.set(key, list);
  }

  const writes = [];
  for (const [, group] of bySession) {
    const first = group[0];
    try {
      const { payload, baseUrl } = await callBeagle("/api/memory/ingest_chat", {
        source: first.source,
        session_id: first.session_id,
        turns: group.map((record) => ({
          role: record.role,
          content: record.text,
          model: record.metadata?.model || undefined
        })),
        tags: first.tags,
        metadata: {
          ...first.metadata,
          projectSlug: first.projectSlug,
          provider: first.provider,
          workbench_memory_ids: group.map((record) => record.memory_id)
        }
      }, { timeoutMs: 20000 });
      writes.push({ ok: true, status: payload.status || "ok", baseUrl, payload });
    } catch (error) {
      writes.push({
        ok: false,
        error: error.message,
        statusCode: error.statusCode || 503,
        payload: error.payload || null
      });
    }
  }
  return writes;
}

async function queryBeagleMemory(body = {}) {
  try {
    const { payload, baseUrl } = await callBeagle("/api/memory/query", {
      query: queryText(body),
      scope: body.scope || body.domain || "general",
      max_items: parseLimit(body),
      tags: normalizeTags(body.tags),
      include_recent_physio: body.include_recent_physio === true
    }, { timeoutMs: 15000 });
    const rawHighlights = Array.isArray(payload.highlights)
      ? payload.highlights
      : Array.isArray(payload.results)
        ? payload.results
        : [];
    return {
      ok: true,
      baseUrl,
      summary: payload.summary || "",
      highlights: rawHighlights.map(beagleHighlight),
      links: Array.isArray(payload.links) ? payload.links : [],
      raw: payload
    };
  } catch (error) {
    return {
      ok: false,
      error: error.message,
      statusCode: error.statusCode || 503,
      highlights: [],
      links: []
    };
  }
}

function queryLocalRecords(slug, body = {}) {
  const query = queryText(body);
  const filters = body.filters && typeof body.filters === "object" ? body.filters : body;
  const limit = parseLimit(body);
  const scored = readLocalRecords(slug)
    .filter((record) => record.searchable !== false)
    .filter((record) => filterRecord(record, filters))
    .map((record) => ({ record, score: scoreRecord(record, query, filters) }))
    .filter((item) => item.score > 0 || !query)
    .sort((left, right) => right.score - left.score)
    .slice(0, limit)
    .map((item) => localHighlight(item.record, Number(item.score.toFixed(4))));
  return scored;
}

function summarizeRecords(records) {
  const bySource = new Map();
  const byProvider = new Map();
  const bySession = new Map();
  const byClient = new Map();
  const byTag = new Map();
  let latestAt = "";

  function bump(map, key, record) {
    const clean = cleanString(key, "unknown");
    const item = map.get(clean) || {
      id: clean,
      count: 0,
      latest_at: "",
      sessions: new Set()
    };
    item.count += 1;
    item.latest_at = cleanString(record.created_at).localeCompare(item.latest_at) > 0
      ? cleanString(record.created_at)
      : item.latest_at;
    if (record.session_id) item.sessions.add(record.session_id);
    map.set(clean, item);
  }

  for (const record of records) {
    if (cleanString(record.created_at).localeCompare(latestAt) > 0) latestAt = cleanString(record.created_at);
    bump(bySource, record.source, record);
    bump(byProvider, record.provider, record);
    bump(byClient, record.client_id || record.source, record);
    bump(bySession, record.session_id, record);
    for (const tag of record.tags || []) bump(byTag, tag, record);
  }

  function rows(map, limit = 30) {
    return [...map.values()]
      .map((item) => ({
        ...item,
        sessions: item.sessions.size
      }))
      .sort((left, right) => right.count - left.count || cleanString(right.latest_at).localeCompare(cleanString(left.latest_at)))
      .slice(0, limit);
  }

  return {
    local_records: records.length,
    latest_at: latestAt,
    local_sessions: bySession.size,
    local_sources: bySource.size,
    local_clients: byClient.size,
    by_source: rows(bySource),
    by_provider: rows(byProvider),
    by_client: rows(byClient),
    by_session: rows(bySession),
    by_tag: rows(byTag, 50)
  };
}

function observedClients(records) {
  const summary = summarizeRecords(records);
  return KNOWN_CONTEXT_CLIENTS.map((client) => {
    const aliases = new Set(client.source_aliases.map((alias) => normalizeText(alias)));
    const matching = records.filter((record) => (
      aliases.has(normalizeText(record.source)) ||
      aliases.has(normalizeText(record.provider)) ||
      aliases.has(normalizeText(record.client_id))
    ));
    const latest = matching
      .map((record) => cleanString(record.created_at))
      .sort()
      .pop() || "";
    return {
      ...client,
      status: matching.length > 0 ? "observed" : "declared",
      memory_count: matching.length,
      session_count: new Set(matching.map((record) => record.session_id).filter(Boolean)).size,
      latest_at: latest
    };
  }).concat(
    summary.by_client
      .filter((item) => !KNOWN_CONTEXT_CLIENTS.some((client) => (
        client.client_id === item.id ||
        client.source_aliases.some((alias) => normalizeText(alias) === normalizeText(item.id))
      )))
      .sort((left, right) => cleanString(right.latest_at).localeCompare(cleanString(left.latest_at)) || (right.count || 0) - (left.count || 0))
      .slice(0, 12)
      .map((item) => ({
        client_id: item.id,
        label: item.id,
        provider: item.id,
        transport: "observed-mcp-or-http",
        source_aliases: [item.id],
        status: "observed",
        memory_count: item.count,
        session_count: item.sessions,
        latest_at: item.latest_at
      }))
  );
}

function exportRecords(slug, query = {}) {
  const filters = query.filters && typeof query.filters === "object" ? query.filters : query;
  const limit = parseLimit({ limit: query.limit || query.max_items || 100 }, 100, 100);
  const since = cleanString(query.since || query.since_at);
  const until = cleanString(query.until || query.until_at);
  return readLocalRecords(slug)
    .filter((record) => filterRecord(record, filters))
    .filter((record) => !since || cleanString(record.created_at).localeCompare(since) >= 0)
    .filter((record) => !until || cleanString(record.created_at).localeCompare(until) <= 0)
    .sort((left, right) => cleanString(right.created_at).localeCompare(cleanString(left.created_at)))
    .slice(0, limit);
}

function normalizeImportPayload(slug, body = {}) {
  const batches = [];
  if (Array.isArray(body.items)) {
    for (const item of body.items) {
      batches.push({
        ...item,
        source: cleanString(item.source || body.source),
        provider: cleanString(item.provider || body.provider),
        client_id: cleanString(item.client_id || item.clientId || body.client_id || body.clientId),
        tags: [...normalizeTags(body.tags), ...normalizeTags(item.tags)],
        metadata: {
          ...(body.metadata && typeof body.metadata === "object" ? body.metadata : {}),
          ...(item.metadata && typeof item.metadata === "object" ? item.metadata : {})
        }
      });
    }
  } else if (Array.isArray(body.conversations)) {
    for (const conversation of body.conversations) {
      batches.push({
        ...conversation,
        source: cleanString(conversation.source || body.source),
        provider: cleanString(conversation.provider || body.provider),
        client_id: cleanString(conversation.client_id || conversation.clientId || body.client_id || body.clientId),
        tags: [...normalizeTags(body.tags), ...normalizeTags(conversation.tags)],
        metadata: {
          ...(body.metadata && typeof body.metadata === "object" ? body.metadata : {}),
          ...(conversation.metadata && typeof conversation.metadata === "object" ? conversation.metadata : {})
        }
      });
    }
  } else {
    batches.push(body);
  }
  return batches.flatMap((batch) => normalizeIngestBody(slug, batch));
}

function contextEndpoints(slug) {
  return {
    connect: `/api/workbench/${slug}/context/connect`,
    mcp_http: `/api/workbench/${slug}/mcp`,
    mcp_context_http: `/api/workbench/${slug}/context/mcp`,
    mcp_sessions: `/api/workbench/${slug}/context/mcp/sessions`,
    mcp_tools: `/api/workbench/${slug}/context/mcp/tools`,
    doctor: `/api/workbench/${slug}/context/doctor`,
    clients: `/api/workbench/${slug}/context/clients`,
    client_heartbeat: `/api/workbench/${slug}/context/clients/:client_id/heartbeat`,
    presence: `/api/workbench/${slug}/context/presence`,
    sessions: `/api/workbench/${slug}/context/sessions`,
    audit: `/api/workbench/${slug}/context/audit`,
    audit_events: `/api/workbench/${slug}/context/audit/events`,
    recent: `/api/workbench/${slug}/context/recent`,
    continuity: `/api/workbench/${slug}/context/continuity`,
    export: `/api/workbench/${slug}/context/export`,
    import: `/api/workbench/${slug}/context/import`,
    ingest: `/api/workbench/${slug}/context/ingest`,
    query: `/api/workbench/${slug}/context/query`,
    graphrag: `/api/workbench/${slug}/context/graphrag/query`,
    compile: `/api/workbench/${slug}/context/compiler/compile`,
    messages: `/api/workbench/${slug}/context/messages`,
    message_board: `/api/workbench/${slug}/context/messages/board`,
    message_send: `/api/workbench/${slug}/context/messages/send`,
    message_inbox: `/api/workbench/${slug}/context/messages/inbox/:client_id`,
    message_ack: `/api/workbench/${slug}/context/messages/:message_id/ack`,
    message_reply: `/api/workbench/${slug}/context/messages/:message_id/reply`,
    message_compile: `/api/workbench/${slug}/context/messages/:message_id/compile`,
    message_claim: `/api/workbench/${slug}/context/messages/:message_id/claim`,
    message_complete: `/api/workbench/${slug}/context/messages/:message_id/complete`,
    message_release: `/api/workbench/${slug}/context/messages/:message_id/release`,
    message_cancel: `/api/workbench/${slug}/context/messages/:message_id/cancel`,
    message_reopen: `/api/workbench/${slug}/context/messages/:message_id/reopen`,
    message_heartbeat: `/api/workbench/${slug}/context/messages/:message_id/heartbeat`
  };
}

function requestBaseUrl(req) {
  const proto = cleanString(req.headers?.["x-forwarded-proto"]) || req.protocol || "http";
  const host = cleanString(req.headers?.["x-forwarded-host"]) || cleanString(req.headers?.host) || "127.0.0.1:4370";
  return `${proto}://${host}`;
}

function isLoopbackRequest(req) {
  const host = cleanString(req.headers?.host).split(":")[0].toLowerCase();
  const remote = cleanString(req.socket?.remoteAddress || req.ip).replace(/^::ffff:/, "");
  return ["127.0.0.1", "::1", "localhost"].includes(host) ||
    ["127.0.0.1", "::1"].includes(remote);
}

function buildContextConnectionPack(slug, req) {
  const baseUrl = cleanString(req.query?.base_url || req.query?.baseUrl) || requestBaseUrl(req);
  const endpoint = (route) => `${baseUrl}${route}`;
  const endpoints = contextEndpoints(slug);
  const localStdioProxyPath = path.resolve(process.cwd(), "bin/workbench-context-mcp.mjs");
  const staticToken = staticHttpMcpToken();
  const staticTokenVisible = Boolean(staticToken) && isLoopbackRequest(req);
  const authHeaders = REQUIRE_HTTP_MCP_AUTH || REQUIRE_CONTEXT_WRITE_AUTH || REQUIRE_CONTEXT_READ_AUTH
    ? { authorization: `Bearer ${staticTokenVisible ? staticToken : "<beagle-operator-token>"}` }
    : {};
  const httpMcpConfig = (clientId, provider) => {
    const query = new URLSearchParams({
      client_id: clientId,
      provider
    }).toString();
    const headers = {
      "content-type": "application/json",
      "x-beagle-client-id": clientId,
      "x-beagle-provider": provider,
      ...authHeaders
    };
    return {
      url: `${endpoint(endpoints.mcp_context_http)}?${query}`,
      streamable_http_url: `${endpoint(endpoints.mcp_context_http)}?${query}`,
      alternate_url: `${endpoint(endpoints.mcp_http)}?${query}`,
      transports: ["streamable-http", "sse-listen"],
      headers
    };
  };
  const httpMcp = {
    url: endpoint(endpoints.mcp_context_http),
    streamable_http_url: endpoint(endpoints.mcp_context_http),
    alternate_url: endpoint(endpoints.mcp_http),
    protocol: "MCP JSON-RPC 2.0 over Streamable HTTP",
    protocolVersion: "2025-06-18",
    legacyProtocolVersion: "2024-11-05",
    headers: {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      ...authHeaders
    }
  };
  const clientHeartbeat = (clientId) => endpoint(`/api/workbench/${slug}/context/clients/${encodeURIComponent(clientId)}/heartbeat`);
  const stdioEnv = {
    COCKPIT_API: baseUrl,
    COCKPIT_PROJECT: slug,
    COCKPIT_MCP_PATH: endpoints.mcp_context_http,
    COCKPIT_AUTO_HEARTBEAT: "1"
  };

  return {
    schema: "beagle.workbench-context-connection-pack.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    truthMode: "declared",
    base_url: baseUrl,
    auth: {
      token_endpoint: endpoint("/api/auth/beagle-token"),
      required: {
        http_mcp: REQUIRE_HTTP_MCP_AUTH,
        rest_write: REQUIRE_CONTEXT_WRITE_AUTH,
        rest_read: REQUIRE_CONTEXT_READ_AUTH
      },
      token_configured: Boolean(staticToken),
      static_token_visible: staticTokenVisible,
      header: Object.keys(authHeaders).length > 0
        ? `Authorization: ${authHeaders.authorization}`
        : ""
    },
    endpoints: {
      ...Object.fromEntries(Object.entries(endpoints).map(([key, route]) => [key, endpoint(route)]))
    },
    tools: workbenchMcpTools().map((tool) => ({
      name: tool.name,
      description: tool.description
    })),
    clients: [
      {
        client_id: "claude-desktop",
        label: "Claude Desktop / Claude Code",
        preferred_transport: "stdio-proxy",
        config: {
          mcpServers: {
            "beagle-workbench": {
              command: "node",
              args: [localStdioProxyPath],
              env: { ...stdioEnv, COCKPIT_CLIENT_ID: "claude-desktop", COCKPIT_CLIENT_PROVIDER: "anthropic" }
            }
          }
        },
        keepalive: {
          tool: "cockpit_workbench_context_client_heartbeat",
          every_seconds: 60,
          client_id: "claude-desktop",
          endpoint: clientHeartbeat("claude-desktop")
        },
        note: "Use the cockpit MCP stdio proxy when the client does not support HTTP MCP headers directly. The proxy fetches the Beagle token through the cockpit auth bridge."
      },
      {
        client_id: "chatgpt",
        label: "ChatGPT",
        preferred_transport: "http-mcp",
        config: httpMcpConfig("chatgpt", "openai"),
        keepalive: {
          tool: "workbench_context_client_heartbeat",
          every_seconds: 60,
          client_id: "chatgpt",
          endpoint: clientHeartbeat("chatgpt")
        }
      },
      {
        client_id: "grok",
        label: "Grok",
        preferred_transport: "http-mcp",
        config: httpMcpConfig("grok", "xai"),
        keepalive: {
          tool: "workbench_context_client_heartbeat",
          every_seconds: 60,
          client_id: "grok",
          endpoint: clientHeartbeat("grok")
        }
      },
      {
        client_id: "kimi",
        label: "Kimi CLI",
        preferred_transport: "http-mcp-or-stdio-proxy",
        config: {
          http: httpMcpConfig("kimi", "moonshot"),
          stdio: {
            command: "node",
            args: [localStdioProxyPath],
            env: { ...stdioEnv, COCKPIT_CLIENT_ID: "kimi", COCKPIT_CLIENT_PROVIDER: "moonshot" }
          }
        },
        keepalive: {
          tool: "workbench_context_client_heartbeat",
          every_seconds: 60,
          client_id: "kimi",
          endpoint: clientHeartbeat("kimi")
        }
      },
      {
        client_id: "cursor",
        label: "Cursor",
        preferred_transport: "stdio-proxy",
        config: {
          mcpServers: {
            "beagle-workbench": {
              command: "node",
              args: [localStdioProxyPath],
              env: { ...stdioEnv, COCKPIT_CLIENT_ID: "cursor", COCKPIT_CLIENT_PROVIDER: "cursor" }
            }
          }
        },
        keepalive: {
          tool: "cockpit_workbench_context_client_heartbeat",
          every_seconds: 60,
          client_id: "cursor",
          endpoint: clientHeartbeat("cursor")
        }
      },
      {
        client_id: "codex",
        label: "Codex / local zellij agents",
        preferred_transport: "stdio-proxy",
        config: {
          command: "node",
          args: ["/home/agent/.config/claude-code/cockpit-mcp-server.mjs"],
          env: { ...stdioEnv, COCKPIT_CLIENT_ID: "codex", COCKPIT_CLIENT_PROVIDER: "openai" }
        },
        keepalive: {
          tool: "cockpit_workbench_context_client_heartbeat",
          every_seconds: 60,
          client_id: "codex",
          endpoint: clientHeartbeat("codex")
        }
      }
    ],
    smoke_tests: {
      tools_list: {
        method: "POST",
        url: httpMcp.url,
        headers: httpMcp.headers,
        body: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }
      },
      doctor: {
        method: "POST",
        url: httpMcp.url,
        headers: httpMcp.headers,
        body: {
          jsonrpc: "2.0",
          id: 2,
          method: "tools/call",
          params: {
            name: "workbench_context_doctor",
            arguments: { write_probe: false }
          }
        }
      }
    }
  };
}

function buildContextStatus(slug) {
  const records = readLocalRecords(slug);
  const summary = summarizeRecords(records);
  return {
    schema: "beagle.workbench-context-status.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    status: "ok",
    truthMode: "observed",
    protocol: {
      mcp_http: true,
      json_rpc: "2.0",
      protocolVersion: "2024-11-05",
      serverInfo: {
        name: "beagle-workbench-context",
        version: "0.2.0"
      }
    },
    features: {
      mcp_memory_write_through: true,
      local_read_after_write: true,
      bounded_graphrag_projection: true,
      compiled_context_packet: true,
      upstream_beagle_memory: true,
      idempotent_ingest: true,
      mcp_client_registry: true,
      context_export: true,
      context_import: true,
      agent_handoff_messages: true,
      agent_handoff_board: true,
      agent_handoff_safe_lifecycle: true,
      agent_presence: true,
      client_presence_heartbeat: true,
      continuity_packet: true,
      audit_summary: true,
      audit_events: true,
      recent_records: true,
      connection_pack: true,
      http_jsonrpc_mcp: true,
      http_mcp_auth_required: REQUIRE_HTTP_MCP_AUTH,
      context_write_auth_required: REQUIRE_CONTEXT_WRITE_AUTH,
      context_read_auth_required: REQUIRE_CONTEXT_READ_AUTH
    },
    counts: {
      local_records: summary.local_records,
      local_sessions: summary.local_sessions,
      local_sources: summary.local_sources,
      local_clients: summary.local_clients
    },
    clients: observedClients(records),
    summary,
    endpoints: contextEndpoints(slug)
  };
}

function buildContextClients(slug) {
  return {
    schema: "beagle.workbench-context-clients.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    clients: observedClients(readLocalRecords(slug)),
    truthMode: "observed"
  };
}

function contextClientById(clientId) {
  const id = normalizeText(clientId);
  if (!id) return null;
  return KNOWN_CONTEXT_CLIENTS.find((client) => (
    normalizeText(client.client_id) === id ||
    client.source_aliases.some((alias) => normalizeText(alias) === id)
  )) || null;
}

function normalizeContextClientId(clientId) {
  const requested = cleanString(clientId);
  const known = contextClientById(requested);
  return known?.client_id || requested.replace(/[^a-zA-Z0-9_.:-]/g, "-").slice(0, 80);
}

function requestHeader(req, names = []) {
  for (const name of names) {
    const value = cleanString(req.headers?.[name.toLowerCase()] || req.headers?.[name]);
    if (value) return value;
  }
  return "";
}

function mcpSessionHeader(req) {
  return requestHeader(req, ["mcp-session-id", "Mcp-Session-Id", "x-mcp-session-id"]);
}

function httpMcpSessionKey(slug, sessionId) {
  return `${safeSlug(slug)}:${cleanString(sessionId)}`;
}

function cleanupHttpMcpSessions() {
  const now = Date.now();
  for (const [key, session] of httpMcpSessions.entries()) {
    const lastSeen = timestampMs(session.last_seen_at || session.closed_at || session.connected_at);
    if (lastSeen && now - lastSeen > HTTP_MCP_SESSION_TTL_MS) {
      httpMcpSessions.delete(key);
    }
  }
}

function upsertHttpMcpSession(slug, req, {
  stage = "request",
  transport = "streamable-http",
  sessionId = "",
  state = "active",
  message = {}
} = {}) {
  cleanupHttpMcpSessions();
  const client = inferHttpMcpClient(req, message) || {};
  const clientId = normalizeContextClientId(client.clientId || "unknown-http-mcp-client");
  const now = new Date().toISOString();
  const selectedSessionId = cleanString(sessionId || mcpSessionHeader(req)) || randomUUID();
  const key = httpMcpSessionKey(slug, selectedSessionId);
  const existing = httpMcpSessions.get(key) || {};
  const record = {
    schema: "beagle.workbench-http-mcp-session.v1",
    projectSlug: slug,
    session_id: selectedSessionId,
    client_id: clientId,
    provider: cleanString(client.provider || existing.provider || clientId),
    transport,
    stage,
    state,
    connected_at: cleanString(existing.connected_at || now),
    last_seen_at: now,
    closed_at: state === "closed" ? now : "",
    endpoint: cleanString(req?.originalUrl || req?.url || existing.endpoint),
    method: cleanString(req?.method || existing.method),
    accept: cleanString(req?.headers?.accept || existing.accept),
    protocol_version: cleanString(req?.get?.("mcp-protocol-version") || existing.protocol_version || "2025-06-18"),
    user_agent: cleanString(req?.headers?.["user-agent"] || existing.user_agent),
    truthMode: "observed-live-http-mcp-session"
  };
  httpMcpSessions.set(key, record);
  return record;
}

function closeHttpMcpSession(slug, sessionId, patch = {}) {
  const key = httpMcpSessionKey(slug, sessionId);
  const existing = httpMcpSessions.get(key);
  if (!existing) return null;
  const now = new Date().toISOString();
  const record = {
    ...existing,
    ...patch,
    state: "closed",
    stage: cleanString(patch.stage || existing.stage || "closed"),
    last_seen_at: now,
    closed_at: now,
    truthMode: "observed-live-http-mcp-session"
  };
  httpMcpSessions.set(key, record);
  return record;
}

function buildHttpMcpSessionStatus(slug) {
  cleanupHttpMcpSessions();
  const now = Date.now();
  const sessions = [...httpMcpSessions.values()]
    .filter((session) => session.projectSlug === slug)
    .map((session) => {
      const ageMs = now - timestampMs(session.last_seen_at);
      const active = session.state === "active" && ageMs >= 0 && ageMs <= HTTP_MCP_SESSION_TTL_MS;
      return {
        ...session,
        active,
        age_ms: Number.isFinite(ageMs) ? ageMs : null
      };
    })
    .sort((left, right) => timestampMs(right.last_seen_at) - timestampMs(left.last_seen_at));
  const active = sessions.filter((session) => session.active);
  return {
    schema: "beagle.workbench-http-mcp-sessions.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    keepalive_ms: HTTP_MCP_SSE_KEEPALIVE_MS,
    ttl_ms: HTTP_MCP_SESSION_TTL_MS,
    summary: {
      total: sessions.length,
      active: active.length,
      closed: sessions.filter((session) => session.state === "closed").length,
      clients_active: [...new Set(active.map((session) => session.client_id).filter(Boolean))]
    },
    sessions,
    truthMode: "observed-live-http-mcp-session-registry"
  };
}

async function recordContextClientHeartbeat(slug, clientId, body = {}) {
  const id = normalizeContextClientId(clientId || body.client_id || body.clientId);
  if (!id) {
    const error = new Error("client_id is required");
    error.statusCode = 400;
    throw error;
  }

  const now = new Date().toISOString();
  const known = contextClientById(id) || {};
  const sessionId = cleanString(body.session_id || body.sessionId || body.conversation_id || body.conversationId) ||
    `client-presence:${id}`;
  const minuteBucket = now.slice(0, 16).replace(/[-:T]/g, "");
  const externalId = cleanString(body.external_id || body.externalId || body.request_id || body.requestId) ||
    `client-presence:${id}:${sessionId}:${minuteBucket}`.replace(/[^a-zA-Z0-9:_-]/g, "_");
  const existing = recordsByExternalId(slug);
  const duplicate = existing.has(externalId);
  const record = {
    schema: "beagle.workbench-context-turn.v1",
    memory_id: randomUUID(),
    external_id: externalId,
    request_id: cleanString(body.request_id || body.requestId || externalId),
    projectSlug: slug,
    source: id,
    provider: cleanString(body.provider || known.provider || id),
    client_id: id,
    session_id: sessionId,
    conversation_id: cleanString(body.conversation_id || body.conversationId || sessionId),
    turn_index: 0,
    role: "system",
    text: boundedText(body.note || body.status || `${id} presence heartbeat`, 1000),
    tags: normalizeTags([
      ...(Array.isArray(body.tags) ? body.tags : []),
      slug,
      "workbench-context",
      "mcp-context",
      "client-presence",
      "client-heartbeat",
      id
    ]),
    metadata: {
      ...(body.metadata && typeof body.metadata === "object" ? body.metadata : {}),
      external_id: externalId,
      request_id: cleanString(body.request_id || body.requestId || externalId),
      domain: "beagle-workbench-client-presence",
      workspace_id: slug,
      client_presence_heartbeat: {
        client_id: id,
        heartbeat_at: now,
        status: cleanString(body.status || "online"),
        note: cleanString(body.note),
        session_id: sessionId
      }
    },
    created_at: now,
    searchable: false,
    truthMode: "observed"
  };

  if (!duplicate) appendLocalRecord(slug, record);
  appendAuditEvent(slug, {
    event_type: "client_heartbeat",
    source: id,
    provider: record.provider,
    client_id: id,
    session_id: sessionId,
    request_id: record.request_id,
    accepted_records: duplicate ? 0 : 1,
    duplicate_records: duplicate ? 1 : 0,
    upstream_status: "skipped"
  });

  const realtime = await notifyContextRouteHook("onClientHeartbeat", {
    slug,
    clientId: id,
    heartbeat: {
      client_id: id,
      provider: record.provider,
      session_id: sessionId,
      heartbeat_at: now,
      duplicate
    },
    result: {
      client_id: id,
      heartbeat_at: now
    },
    reason: "workbench-context-client-heartbeat"
  });

  return {
    schema: "beagle.workbench-context-client-heartbeat.v1",
    status: "ok",
    projectSlug: slug,
    client_id: id,
    provider: record.provider,
    session_id: sessionId,
    heartbeat_at: now,
    duplicate,
    stored: !duplicate,
    searchable: false,
    note: "Client presence heartbeat is local-only and excluded from RAG++ retrieval.",
    memory_id: duplicate ? existing.get(externalId)?.[0]?.memory_id || "" : record.memory_id,
    realtime: {
      ...(realtime || {}),
      truthMode: "observed"
    },
    truthMode: "observed"
  };
}

function inferHttpMcpClient(req, message = {}) {
  const params = message?.params && typeof message.params === "object" ? message.params : {};
  const args = params.arguments && typeof params.arguments === "object" ? params.arguments : {};
  const clientId = cleanString(
    req.query?.client_id ||
      req.query?.clientId ||
      req.query?.client ||
      requestHeader(req, [
        "x-beagle-client-id",
        "x-workbench-client-id",
        "x-cockpit-client-id",
        "x-mcp-client-id"
      ]) ||
      params.client_id ||
      params.clientId ||
      args.client_id ||
      args.clientId
  );
  const provider = cleanString(
    req.query?.provider ||
      req.query?.client_provider ||
      req.query?.clientProvider ||
      requestHeader(req, [
        "x-beagle-provider",
        "x-workbench-client-provider",
        "x-cockpit-client-provider",
        "x-mcp-provider"
      ]) ||
      params.provider ||
      args.provider
  );
  if (!clientId) return null;
  return { clientId, provider };
}

function httpMcpRequestMetadata(req, message = {}) {
  const clientInfo = message?.params?.clientInfo && typeof message.params.clientInfo === "object"
    ? message.params.clientInfo
    : {};
  return {
    transport: "http-mcp",
    method: cleanString(message.method),
    endpoint: cleanString(req?.originalUrl || req?.url),
    user_agent: cleanString(req?.headers?.["user-agent"]),
    client_info: {
      name: cleanString(clientInfo.name),
      version: cleanString(clientInfo.version)
    }
  };
}

function withHttpMcpRequestMetadata(args = {}, req, message = {}) {
  if (!req) return args;
  const metadata = args.metadata && typeof args.metadata === "object" ? args.metadata : {};
  return {
    ...args,
    metadata: {
      ...metadata,
      mcp_request: httpMcpRequestMetadata(req, message)
    }
  };
}

async function maybeRecordHttpMcpClientHeartbeat(slug, req, message = {}) {
  const client = inferHttpMcpClient(req, message);
  if (!client?.clientId) return null;
  const method = cleanString(message.method);
  if (!["initialize", "tools/list", "tools/call"].includes(method)) return null;
  const toolName = cleanString(message.params?.name);
  if (toolName === "workbench_context_client_heartbeat" || toolName === "cockpit_workbench_context_client_heartbeat") {
    return null;
  }
  return await recordContextClientHeartbeat(slug, client.clientId, {
    provider: client.provider,
    session_id: `http-mcp:${slug}:${normalizeContextClientId(client.clientId)}`,
    status: "online",
    note: `HTTP MCP ${method}`,
    tags: ["http-mcp", "auto-heartbeat", normalizeContextClientId(client.clientId)],
    metadata: {
      ...httpMcpRequestMetadata(req, message),
      method,
      tool_name: toolName,
    }
  });
}

async function maybeRecordHttpMcpConnectionHeartbeat(slug, req, stage = "connection") {
  const client = inferHttpMcpClient(req, {});
  if (!client?.clientId) return null;
  const normalizedClientId = normalizeContextClientId(client.clientId);
  return await recordContextClientHeartbeat(slug, client.clientId, {
    provider: client.provider,
    session_id: `http-mcp:${slug}:${normalizedClientId}`,
    status: "online",
    note: `HTTP MCP ${stage}`,
    tags: ["http-mcp", "auto-heartbeat", stage, normalizedClientId],
    metadata: {
      transport: "http-mcp",
      method: "GET",
      stage,
      endpoint: cleanString(req.originalUrl || req.url),
      accept: cleanString(req.headers?.accept),
      user_agent: cleanString(req.headers?.["user-agent"])
    }
  });
}

function buildContextSessions(slug) {
  const records = readLocalRecords(slug);
  const sessions = summarizeRecords(records).by_session.map((session) => ({
    session_id: session.id,
    memory_count: session.count,
    latest_at: session.latest_at,
    sources: [...new Set(records
      .filter((record) => record.session_id === session.id)
      .map((record) => record.source)
      .filter(Boolean))]
  }));
  return {
    schema: "beagle.workbench-context-sessions.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    sessions,
    truthMode: "observed"
  };
}

function buildContextAudit(slug) {
  const records = readLocalRecords(slug);
  return {
    schema: "beagle.workbench-context-audit.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    status: "ok",
    truthMode: "observed",
    summary: summarizeRecords(records),
    clients: observedClients(records),
    recent_events: readAuditEvents(slug, 20),
    risks: [
      ...(records.length === 0 ? [{
        severity: "warn",
        code: "NO_CONTEXT_RECORDS",
        summary: "No Workbench context records have been ingested for this project yet."
      }] : []),
      ...(new Set(records.map((record) => record.source)).size <= 1 && records.length > 0 ? [{
        severity: "info",
        code: "SINGLE_CONTEXT_SOURCE",
        summary: "Only one memory source has written to the Workbench context overlay."
      }] : [])
    ]
  };
}

function buildContextRecent(slug, query = {}) {
  const records = exportRecords(slug, {
    ...query,
    limit: query.limit || query.max_items || 20
  });
  return {
    schema: "beagle.workbench-context-recent.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    count: records.length,
    records,
    truthMode: "observed"
  };
}

async function sendContextMessage(slug, body = {}) {
  const fromClient = cleanString(body.from_client || body.fromClient || body.from || body.source || body.client_id, "operator");
  const toClient = cleanString(body.to_client || body.toClient || body.to || body.target_client || body.target, "broadcast");
  const content = boundedText(body.content || body.message || body.text);
  if (!content) {
    const error = new Error("message content is required");
    error.statusCode = 400;
    throw error;
  }
  const now = new Date().toISOString();
  const threadId = cleanString(body.thread_id || body.threadId || body.conversation_id || body.conversationId) ||
    `handoff:${slug}:${now.slice(0, 10)}`;
  const messageId = cleanString(body.message_id || body.messageId || body.external_id || body.externalId) ||
    `msg_${Date.now()}_${randomUUID().slice(0, 8)}`;
  const subject = cleanString(body.subject || body.title, "handoff");
  const priority = cleanString(body.priority, "normal");
  const ingest = await ingestContextRecords(slug, {
    source: fromClient,
    provider: cleanString(body.provider || fromClient),
    client_id: fromClient,
    session_id: threadId,
    conversation_id: threadId,
    tags: [
      "agent-message",
      "handoff",
      fromClient,
      toClient,
      ...normalizeTags(body.tags)
    ],
    metadata: {
      ...(body.metadata && typeof body.metadata === "object" ? body.metadata : {}),
      domain: "beagle-workbench-handoff",
      agent_message: {
        message_id: messageId,
        from_client: fromClient,
        to_client: toClient,
        subject,
        priority,
        status: "sent",
        thread_id: threadId,
        requires_response: body.requires_response === true || body.requiresResponse === true,
        sent_at: now
      }
    },
    turns: [{
      role: "assistant",
      external_id: messageId,
      content: `[handoff:${priority}] ${fromClient} -> ${toClient}: ${subject}\n\n${content}`
    }]
  });
  appendAuditEvent(slug, {
    event_type: "message_send",
    source: fromClient,
    client_id: fromClient,
    session_id: threadId,
    message_id: messageId,
    to_client: toClient,
    subject,
    priority
  });
  return {
    schema: "beagle.workbench-context-message-send.v1",
    status: "ok",
    projectSlug: slug,
    generatedAt: now,
    truthMode: "observed",
    message: {
      message_id: messageId,
      from_client: fromClient,
      to_client: toClient,
      subject,
      priority,
      thread_id: threadId,
      status: "sent"
    },
    ingest
  };
}

function eventMillis(value) {
  const time = Date.parse(cleanString(value));
  return Number.isFinite(time) ? time : 0;
}

function timestampMs(value) {
  return eventMillis(value);
}

function latestLifecycleEvent(items = [], timestampKey) {
  return [...items].sort((left, right) => eventMillis(left[timestampKey]) - eventMillis(right[timestampKey])).at(-1) || null;
}

function afterLifecycleEvent(items = [], timestampKey, floorMs) {
  return items
    .filter((item) => eventMillis(item[timestampKey]) > floorMs)
    .sort((left, right) => eventMillis(left[timestampKey]) - eventMillis(right[timestampKey]));
}

function collectContextMessageLifecycle(records) {
  const lifecycle = {
    acknowledgements: new Map(),
    claims: new Map(),
    releases: new Map(),
    completions: new Map(),
    cancellations: new Map(),
    reopens: new Map(),
    heartbeats: new Map()
  };

  function push(map, messageId, item) {
    const id = cleanString(messageId);
    if (!id) return;
    const list = map.get(id) || [];
    list.push(item);
    map.set(id, list);
  }

  for (const record of records) {
    const ack = record.metadata?.agent_message_ack;
    if (ack?.message_id) {
      push(lifecycle.acknowledgements, ack.message_id, {
        client_id: cleanString(ack.client_id || record.client_id || record.source),
        ack_at: cleanString(ack.ack_at || record.created_at),
        note: cleanString(ack.note),
        memory_id: record.memory_id
      });
    }
    const claim = record.metadata?.agent_message_claim;
    if (claim?.message_id) {
      push(lifecycle.claims, claim.message_id, {
        client_id: cleanString(claim.client_id || record.client_id || record.source),
        claimed_at: cleanString(claim.claimed_at || record.created_at),
        note: cleanString(claim.note),
        memory_id: record.memory_id
      });
    }
    const release = record.metadata?.agent_message_release;
    if (release?.message_id) {
      push(lifecycle.releases, release.message_id, {
        client_id: cleanString(release.client_id || record.client_id || record.source),
        released_at: cleanString(release.released_at || record.created_at),
        note: cleanString(release.note),
        previous_claimed_by: cleanString(release.previous_claimed_by),
        memory_id: record.memory_id
      });
    }
    const completion = record.metadata?.agent_message_complete;
    if (completion?.message_id) {
      push(lifecycle.completions, completion.message_id, {
        client_id: cleanString(completion.client_id || record.client_id || record.source),
        completed_at: cleanString(completion.completed_at || record.created_at),
        result: cleanString(completion.result),
        note: cleanString(completion.note),
        memory_id: record.memory_id
      });
    }
    const cancellation = record.metadata?.agent_message_cancel;
    if (cancellation?.message_id) {
      push(lifecycle.cancellations, cancellation.message_id, {
        client_id: cleanString(cancellation.client_id || record.client_id || record.source),
        canceled_at: cleanString(cancellation.canceled_at || record.created_at),
        reason: cleanString(cancellation.reason),
        note: cleanString(cancellation.note),
        memory_id: record.memory_id
      });
    }
    const reopen = record.metadata?.agent_message_reopen;
    if (reopen?.message_id) {
      push(lifecycle.reopens, reopen.message_id, {
        client_id: cleanString(reopen.client_id || record.client_id || record.source),
        reopened_at: cleanString(reopen.reopened_at || record.created_at),
        note: cleanString(reopen.note),
        memory_id: record.memory_id
      });
    }
    const heartbeat = record.metadata?.agent_message_heartbeat;
    if (heartbeat?.message_id) {
      push(lifecycle.heartbeats, heartbeat.message_id, {
        client_id: cleanString(heartbeat.client_id || record.client_id || record.source),
        heartbeat_at: cleanString(heartbeat.heartbeat_at || record.created_at),
        progress: cleanString(heartbeat.progress),
        note: cleanString(heartbeat.note),
        memory_id: record.memory_id
      });
    }
  }
  return lifecycle;
}

function deriveContextMessageState(meta = {}, lifecycle = {}) {
  const reopens = lifecycle.reopens || [];
  const lastReopen = latestLifecycleEvent(reopens, "reopened_at");
  const floorMs = eventMillis(lastReopen?.reopened_at);
  const acknowledgements = afterLifecycleEvent(lifecycle.acknowledgements || [], "ack_at", floorMs);
  const claims = afterLifecycleEvent(lifecycle.claims || [], "claimed_at", floorMs);
  const releases = afterLifecycleEvent(lifecycle.releases || [], "released_at", floorMs);
  const completions = afterLifecycleEvent(lifecycle.completions || [], "completed_at", floorMs);
  const cancellations = afterLifecycleEvent(lifecycle.cancellations || [], "canceled_at", floorMs);
  const heartbeats = afterLifecycleEvent(lifecycle.heartbeats || [], "heartbeat_at", floorMs);
  const latestClaim = latestLifecycleEvent(claims, "claimed_at");
  const latestRelease = latestLifecycleEvent(releases, "released_at");
  const latestCompletion = latestLifecycleEvent(completions, "completed_at");
  const latestCancellation = latestLifecycleEvent(cancellations, "canceled_at");
  const latestAck = latestLifecycleEvent(acknowledgements, "ack_at");
  const latestHeartbeat = latestLifecycleEvent(heartbeats, "heartbeat_at");
  const claimMs = eventMillis(latestClaim?.claimed_at);
  const releaseMs = eventMillis(latestRelease?.released_at);
  const completeMs = eventMillis(latestCompletion?.completed_at);
  const cancelMs = eventMillis(latestCancellation?.canceled_at);
  const ackMs = eventMillis(latestAck?.ack_at);

  const status = cancelMs && cancelMs >= completeMs && cancelMs >= claimMs && cancelMs >= ackMs
    ? "canceled"
    : completeMs && completeMs > cancelMs
      ? "completed"
      : claimMs && claimMs > releaseMs && claimMs > cancelMs
        ? "claimed"
        : ackMs && ackMs > cancelMs
          ? "acknowledged"
          : cleanString(meta.status, "sent");

  return {
    status,
    acknowledgements,
    claims,
    releases,
    completions,
    cancellations,
    reopens,
    heartbeats,
    claimed_by: status === "claimed" ? cleanString(latestClaim?.client_id) : "",
    completed_by: status === "completed" ? cleanString(latestCompletion?.client_id) : "",
    canceled_by: status === "canceled" ? cleanString(latestCancellation?.client_id) : "",
    released_by: latestRelease && releaseMs >= claimMs ? cleanString(latestRelease.client_id) : "",
    last_heartbeat_at: cleanString(latestHeartbeat?.heartbeat_at),
    heartbeat_by: cleanString(latestHeartbeat?.client_id),
    reopened_at: cleanString(lastReopen?.reopened_at),
    reopened_by: cleanString(lastReopen?.client_id)
  };
}

function buildContextMessageSnapshot(slug, messageId) {
  const id = cleanString(messageId);
  const records = readLocalRecords(slug);
  const messageRecord = records.find((record) => record.metadata?.agent_message?.message_id === id);
  if (!messageRecord) return null;
  const meta = messageRecord.metadata.agent_message || {};
  const lifecycle = collectContextMessageLifecycle(records);
  const state = deriveContextMessageState(meta, {
    acknowledgements: lifecycle.acknowledgements.get(id) || [],
    claims: lifecycle.claims.get(id) || [],
    releases: lifecycle.releases.get(id) || [],
    completions: lifecycle.completions.get(id) || [],
    cancellations: lifecycle.cancellations.get(id) || [],
    reopens: lifecycle.reopens.get(id) || [],
    heartbeats: lifecycle.heartbeats.get(id) || []
  });
  return {
    message_id: id,
    from_client: cleanString(meta.from_client || messageRecord.source),
    to_client: cleanString(meta.to_client || "broadcast"),
    thread_id: cleanString(meta.thread_id || messageRecord.session_id),
    sent_at: cleanString(meta.sent_at || messageRecord.created_at),
    ...state
  };
}

function buildContextMessages(slug, query = {}) {
  const clientId = cleanString(query.client_id || query.clientId || query.client);
  const statusFilter = cleanString(query.status);
  const limit = parseLimit(query, 100, 30);
  const records = readLocalRecords(slug);
  const lifecycle = collectContextMessageLifecycle(records);

  const messages = records
    .filter((record) => record.metadata?.agent_message?.message_id)
    .map((record) => {
      const meta = record.metadata.agent_message;
      const state = deriveContextMessageState(meta, {
        acknowledgements: lifecycle.acknowledgements.get(meta.message_id) || [],
        claims: lifecycle.claims.get(meta.message_id) || [],
        releases: lifecycle.releases.get(meta.message_id) || [],
        completions: lifecycle.completions.get(meta.message_id) || [],
        cancellations: lifecycle.cancellations.get(meta.message_id) || [],
        reopens: lifecycle.reopens.get(meta.message_id) || [],
        heartbeats: lifecycle.heartbeats.get(meta.message_id) || []
      });
      return {
        message_id: meta.message_id,
        from_client: cleanString(meta.from_client || record.source),
        to_client: cleanString(meta.to_client || "broadcast"),
        subject: cleanString(meta.subject || "handoff"),
        priority: cleanString(meta.priority || "normal"),
        requires_response: meta.requires_response === true,
        thread_id: cleanString(meta.thread_id || record.session_id),
        sent_at: cleanString(meta.sent_at || record.created_at),
        memory_id: record.memory_id,
        text: record.text,
        snippet: snippet(record.text),
        ...state,
        tags: record.tags || []
      };
    })
    .filter((message) => !clientId || message.to_client === clientId || message.from_client === clientId || message.to_client === "broadcast")
    .filter((message) => !statusFilter || message.status === statusFilter)
    .sort((left, right) => cleanString(right.sent_at).localeCompare(cleanString(left.sent_at)))
    .slice(0, limit);

  return {
    schema: "beagle.workbench-context-messages.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    count: messages.length,
    client_id: clientId,
    messages,
    truthMode: "observed"
  };
}

async function buildContextJoin(slug, args = {}) {
  const clientId = normalizeContextClientId(args.client_id || args.clientId || args.client);
  if (!clientId) {
    const error = new Error("client_id is required");
    error.statusCode = 400;
    throw error;
  }
  const heartbeat = await recordContextClientHeartbeat(slug, clientId, {
    ...args,
    client_id: clientId,
    status: args.status || "online",
    note: cleanString(args.note, "joined Workbench Context live room"),
    tags: ["workbench-context-join", ...(Array.isArray(args.tags) ? args.tags : [])]
  });
  const limit = parseLimit(args, 50, 10);
  const includeCompleted = args.include_completed === true || args.includeCompleted === true || cleanString(args.include_completed).toLowerCase() === "true";
  const inbox = buildContextMessages(slug, {
    client_id: clientId,
    limit: Math.max(limit, 20)
  });
  const handoffs = (inbox.messages || [])
    .filter((message) => includeCompleted || !["completed", "canceled"].includes(message.status))
    .slice(0, limit)
    .map((message) => ({
      ...message,
      reply_tool: "workbench_context_reply",
      reply_tool_stdio_proxy: "cockpit_workbench_context_reply",
      reply_args: {
        message_id: message.message_id,
        client_id: clientId,
        text: "<your response>"
      },
      reply_endpoint: `/api/workbench/${slug}/context/messages/${encodeURIComponent(message.message_id)}/reply`
    }));
  const next = handoffs.find((message) => !["completed", "canceled"].includes(message.status)) || null;
  return {
    schema: "beagle.workbench-context-join.v1",
    status: "ok",
    projectSlug: slug,
    client_id: clientId,
    provider: heartbeat.provider,
    heartbeat,
    pending_count: handoffs.filter((message) => !["completed", "canceled"].includes(message.status)).length,
    handoffs,
    next_handoff: next,
    next_reply_instruction: next
      ? `Reply with workbench_context_reply using message_id=${next.message_id}.`
      : "No pending handoff for this client right now.",
    tool_flow: [
      "workbench_context_join",
      "workbench_context_handoff_compile when context is needed",
      "workbench_context_reply"
    ],
    truthMode: "observed-client-joined-workbench-context"
  };
}

function buildContextMessageBoard(slug, query = {}) {
  const limit = parseLimit(query, 500, 200);
  const staleAfterMinutes = Math.max(5, Math.min(24 * 60, Number(query.stale_after_minutes || query.staleAfterMinutes || 90) || 90));
  const includeCompleted = query.include_completed !== false && query.includeCompleted !== false && cleanString(query.include_completed) !== "false";
  const clientFilter = cleanString(query.client_id || query.clientId || query.client);
  const now = Date.now();
  const messages = buildContextMessages(slug, { ...query, limit, client_id: clientFilter }).messages;
  const knownClients = new Map(KNOWN_CONTEXT_CLIENTS.map((client) => [client.client_id, {
    client_id: client.client_id,
    label: client.label,
    provider: client.provider,
    transport: client.transport
  }]));

  for (const message of messages) {
    for (const client of [message.from_client, message.to_client, message.claimed_by, message.completed_by]) {
      const id = cleanString(client);
      if (id && id !== "broadcast" && !knownClients.has(id)) {
        knownClients.set(id, { client_id: id, label: id, provider: "observed", transport: "context-mesh" });
      }
    }
  }

  const board = {
    waiting: [],
    active: [],
    done: [],
    canceled: [],
    stale: []
  };
  const byClient = new Map([...knownClients.values()].map((client) => [client.client_id, {
    ...client,
    waiting: 0,
    active: 0,
    done: 0,
    canceled: 0,
    stale: 0,
    last_activity_at: ""
  }]));

  function touchClient(clientId, bucket, sentAt) {
    const id = cleanString(clientId);
    if (!id || id === "broadcast") return;
    if (!byClient.has(id)) {
      byClient.set(id, { client_id: id, label: id, provider: "observed", transport: "context-mesh", waiting: 0, active: 0, done: 0, canceled: 0, stale: 0, last_activity_at: "" });
    }
    const client = byClient.get(id);
    client[bucket] = (client[bucket] || 0) + 1;
    if (sentAt && (!client.last_activity_at || sentAt > client.last_activity_at)) {
      client.last_activity_at = sentAt;
    }
  }

  for (const message of messages) {
    if (!includeCompleted && message.status === "completed") continue;
    const sentMs = Date.parse(message.sent_at || "");
    const ageMinutes = Number.isFinite(sentMs) ? Math.max(0, Math.round((now - sentMs) / 60000)) : null;
    const isStale = !["completed", "canceled"].includes(message.status) && ageMinutes !== null && ageMinutes >= staleAfterMinutes;
    const item = {
      message_id: message.message_id,
      from_client: message.from_client,
      to_client: message.to_client,
      subject: message.subject,
      priority: message.priority,
      status: message.status,
      sent_at: message.sent_at,
      age_minutes: ageMinutes,
      stale: isStale,
      claimed_by: message.claimed_by,
      completed_by: message.completed_by,
      requires_response: message.requires_response,
      snippet: message.snippet,
      thread_id: message.thread_id,
      memory_id: message.memory_id
    };
    if (isStale) board.stale.push(item);
    if (message.status === "completed") {
      board.done.push(item);
      touchClient(message.completed_by || message.to_client, "done", message.sent_at);
    } else if (message.status === "canceled") {
      board.canceled.push(item);
      touchClient(message.canceled_by || message.to_client, "canceled", message.sent_at);
    } else if (message.status === "claimed") {
      board.active.push(item);
      touchClient(message.claimed_by || message.to_client, "active", message.sent_at);
    } else {
      board.waiting.push(item);
      touchClient(message.to_client, "waiting", message.sent_at);
    }
  }

  const priorityRank = { urgent: 0, high: 1, normal: 2, low: 3 };
  const openItems = [...new Map([...board.stale, ...board.waiting, ...board.active]
    .map((item) => [item.message_id, item])).values()]
    .sort((left, right) => {
      const rank = (priorityRank[left.priority] ?? 2) - (priorityRank[right.priority] ?? 2);
      if (rank !== 0) return rank;
      return (right.age_minutes || 0) - (left.age_minutes || 0);
    })
    .slice(0, 8);

  return {
    schema: "beagle.workbench-context-message-board.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    truthMode: "observed",
    stale_after_minutes: staleAfterMinutes,
    summary: {
      total: messages.length,
      waiting: board.waiting.length,
      active: board.active.length,
      done: board.done.length,
      canceled: board.canceled.length,
      stale: board.stale.length,
      urgent: messages.filter((message) => message.priority === "urgent" || message.priority === "high").length
    },
    clients: [...byClient.values()]
      .filter((client) => !clientFilter || client.client_id === clientFilter)
      .sort((left, right) => ((right.waiting + right.active + right.stale) - (left.waiting + left.active + left.stale)) || left.client_id.localeCompare(right.client_id)),
    columns: board,
    next_actions: openItems,
    messages,
    count: messages.length
  };
}

function buildContextPresence(slug, query = {}) {
  const staleAfterMinutes = Math.max(5, Math.min(24 * 60, Number(query.stale_after_minutes || query.staleAfterMinutes || 90) || 90));
  const records = readLocalRecords(slug);
  const observed = observedClients(records);
  const board = buildContextMessageBoard(slug, {
    ...query,
    limit: query.limit || 500,
    stale_after_minutes: staleAfterMinutes,
    include_completed: query.include_completed ?? query.includeCompleted ?? true
  });
  const boardClients = new Map((board.clients || []).map((client) => [client.client_id, client]));
  const now = Date.now();
  const presence = observed.map((client) => {
    const id = cleanString(client.client_id || client.id);
    const boardClient = boardClients.get(id) || {};
    const latestAt = cleanString(boardClient.last_activity_at || client.latest_at);
    const ageMinutes = latestAt
      ? Math.max(0, Math.round((now - Date.parse(latestAt)) / 60000))
      : null;
    const waiting = boardClient.waiting || 0;
    const active = boardClient.active || 0;
    const stale = boardClient.stale || 0;
    const done = boardClient.done || 0;
    const canceled = boardClient.canceled || 0;
    const state = stale > 0
      ? "stale"
      : active > 0
        ? "active"
        : waiting > 0
          ? "waiting"
          : client.status === "observed"
            ? "idle"
            : "declared";
    return {
      client_id: id,
      label: client.label || id,
      provider: client.provider,
      transport: client.transport,
      state,
      status: state,
      memory_count: client.memory_count || 0,
      session_count: client.session_count || 0,
      latest_at: latestAt,
      age_minutes: Number.isFinite(ageMinutes) ? ageMinutes : null,
      work: { waiting, active, done, canceled, stale },
      has_work: waiting + active + stale > 0,
      declared: client.status === "declared"
    };
  });

  const summary = presence.reduce((acc, item) => {
    acc[item.state] = (acc[item.state] || 0) + 1;
    return acc;
  }, { total: presence.length, active: 0, waiting: 0, stale: 0, idle: 0, declared: 0 });

  return {
    schema: "beagle.workbench-context-presence.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    truthMode: "observed",
    stale_after_minutes: staleAfterMinutes,
    summary,
    clients: presence.sort((left, right) => {
      const rank = { stale: 0, active: 1, waiting: 2, idle: 3, declared: 4 };
      return (rank[left.state] ?? 9) - (rank[right.state] ?? 9) ||
        (right.work.active + right.work.waiting + right.work.stale) - (left.work.active + left.work.waiting + left.work.stale) ||
        left.client_id.localeCompare(right.client_id);
    }),
    board_summary: board.summary
  };
}

function buildContextContinuity(slug, query = {}) {
  const limit = parseLimit(query, 120, 40);
  const handoffLimit = parseLimit({ limit: query.handoff_limit || query.handoffLimit || 24 }, 100, 24);
  const recentLimit = parseLimit({ limit: query.recent_limit || query.recentLimit || 12 }, 100, 12);
  const board = buildContextMessageBoard(slug, { ...query, limit: handoffLimit, include_completed: true });
  const presence = buildContextPresence(slug, { ...query, limit });
  const status = buildContextStatus(slug);
  const recent = buildContextRecent(slug, { ...query, limit: recentLimit });
  const openHandoffs = (board.messages || [])
    .filter((message) => !["completed", "canceled"].includes(message.status))
    .slice(0, handoffLimit)
    .map((message) => ({
      message_id: message.message_id,
      status: message.status,
      from_client: message.from_client,
      to_client: message.to_client,
      subject: message.subject,
      priority: message.priority,
      claimed_by: message.claimed_by,
      last_heartbeat_at: message.last_heartbeat_at,
      sent_at: message.sent_at,
      snippet: message.snippet
    }));
  const stale = (board.columns?.stale || []).slice(0, 8);
  const nextActions = (board.next_actions || []).slice(0, 8);
  const activeAgents = (presence.clients || []).filter((client) => client.state === "active");
  const waitingAgents = (presence.clients || []).filter((client) => client.state === "waiting");
  const staleAgents = (presence.clients || []).filter((client) => client.state === "stale");
  const resumeLines = [
    `Project: ${slug}`,
    `Continuity generated at ${new Date().toISOString()}`,
    `Context records: ${status.counts.local_records}; sessions: ${status.counts.local_sessions}; clients: ${status.counts.local_clients}`,
    `Presence: ${presence.summary.active} active, ${presence.summary.waiting} waiting, ${presence.summary.stale} stale, ${presence.summary.idle} idle, ${presence.summary.declared} declared`,
    `Handoffs: ${board.summary.waiting} waiting, ${board.summary.active} active, ${board.summary.done} done, ${board.summary.canceled} canceled, ${board.summary.stale} stale`,
    "",
    "Open handoffs:",
    ...(openHandoffs.length
      ? openHandoffs.slice(0, 10).map((item) => `- ${item.message_id} [${item.status}] ${item.from_client} -> ${item.to_client}: ${item.subject}${item.claimed_by ? ` (claimed by ${item.claimed_by})` : ""}`)
      : ["- none"]),
    "",
    "Next actions:",
    ...(nextActions.length
      ? nextActions.map((item) => `- ${item.message_id} [${item.status}${item.stale ? ", stale" : ""}] ${item.to_client}: ${item.subject}`)
      : ["- no open handoff needs attention"]),
    "",
    "Rule: before mutating work, query this continuity packet, claim a handoff or create one, keep heartbeat while working, and complete/release/cancel explicitly."
  ];

  return {
    schema: "beagle.workbench-context-continuity-packet.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    truthMode: "observed",
    resume_brief: resumeLines.join("\n"),
    status: {
      counts: status.counts,
      features: status.features,
      endpoints: status.endpoints
    },
    presence: {
      summary: presence.summary,
      active: activeAgents,
      waiting: waitingAgents,
      stale: staleAgents,
      clients: presence.clients
    },
    handoffs: {
      summary: board.summary,
      open: openHandoffs,
      stale,
      next_actions: nextActions
    },
    recent: {
      count: recent.count,
      records: (recent.records || []).map((record) => ({
        memory_id: record.memory_id,
        source: record.source,
        client_id: record.client_id,
        session_id: record.session_id,
        role: record.role,
        created_at: record.created_at,
        tags: record.tags,
        snippet: snippet(record.text)
      }))
    },
    instructions: [
      "Call workbench_context_continuity at the start of every new agent turn.",
      "Use workbench_context_claim before starting delegated work.",
      "Use workbench_context_heartbeat for long-running work.",
      "Use workbench_context_complete, workbench_context_release, or workbench_context_cancel to close the loop.",
      "Do not rely on private chat memory when shared MCP context is available."
    ]
  };
}

function findHandoffMessageRecord(slug, messageId) {
  const id = cleanString(messageId);
  return readLocalRecords(slug).find((record) => record.metadata?.agent_message?.message_id === id) || null;
}

async function recordContextMessageLifecycle(slug, messageId, body = {}, kind = "claim") {
  const id = cleanString(messageId || body.message_id || body.messageId);
  if (!id) {
    const error = new Error("message_id is required");
    error.statusCode = 400;
    throw error;
  }
  const messageRecord = findHandoffMessageRecord(slug, id);
  if (!messageRecord) {
    const error = new Error(`handoff message not found: ${id}`);
    error.statusCode = 404;
    throw error;
  }
  const meta = messageRecord.metadata.agent_message || {};
  const clientId = cleanString(body.client_id || body.clientId || body.by || body.source, "operator");
  const now = new Date().toISOString();
  const threadId = cleanString(meta.thread_id || messageRecord.session_id || body.thread_id || body.threadId);
  const force = body.force === true || cleanString(body.force).toLowerCase() === "true";
  const current = buildContextMessageSnapshot(slug, id);
  const lifecycleShape = {
    claim: ["agent_message_claim", "claimed_at", "claimed"],
    complete: ["agent_message_complete", "completed_at", "completed"],
    release: ["agent_message_release", "released_at", "released"],
    cancel: ["agent_message_cancel", "canceled_at", "canceled"],
    reopen: ["agent_message_reopen", "reopened_at", "reopened"],
    heartbeat: ["agent_message_heartbeat", "heartbeat_at", "heartbeat"]
  };
  const shape = lifecycleShape[kind];
  if (!shape) {
    const error = new Error(`unsupported handoff lifecycle kind: ${kind}`);
    error.statusCode = 400;
    throw error;
  }
  if (!force) {
    if (kind === "claim" && current?.status === "claimed" && current.claimed_by && current.claimed_by !== clientId) {
      const error = new Error(`handoff already claimed by ${current.claimed_by}`);
      error.statusCode = 409;
      throw error;
    }
    if ((kind === "claim" || kind === "complete" || kind === "heartbeat") && ["completed", "canceled"].includes(current?.status)) {
      const error = new Error(`handoff is ${current.status}; reopen before ${kind}`);
      error.statusCode = 409;
      throw error;
    }
    if (["complete", "release", "heartbeat"].includes(kind) && current?.status === "claimed" && current.claimed_by && current.claimed_by !== clientId) {
      const error = new Error(`handoff claimed by ${current.claimed_by}; ${clientId} cannot ${kind} without force=true`);
      error.statusCode = 409;
      throw error;
    }
    if (kind === "release" && current?.status !== "claimed") {
      const error = new Error(`handoff is ${current?.status || "unknown"}; nothing to release`);
      error.statusCode = 409;
      throw error;
    }
    if (kind === "reopen" && !["completed", "canceled"].includes(current?.status)) {
      const error = new Error(`handoff is ${current?.status || "unknown"}; only completed or canceled handoffs can be reopened`);
      error.statusCode = 409;
      throw error;
    }
  }
  const [metadataKey, timestampKey, verb] = shape;
  const result = cleanString(body.result || body.summary || body.outcome);
  const note = cleanString(body.note || body.comment);
  const lifecycleMetadata = {
    message_id: id,
    client_id: clientId,
    [timestampKey]: now,
    note
  };
  if (kind === "complete") {
    lifecycleMetadata.result = result;
    lifecycleMetadata.artifact_refs = Array.isArray(body.artifact_refs || body.artifactRefs)
      ? (body.artifact_refs || body.artifactRefs).map((item) => cleanString(item)).filter(Boolean).slice(0, 16)
      : [];
  }
  if (kind === "release") {
    lifecycleMetadata.previous_claimed_by = cleanString(current?.claimed_by);
  }
  if (kind === "cancel") {
    lifecycleMetadata.reason = cleanString(body.reason || result || note);
  }
  if (kind === "heartbeat") {
    lifecycleMetadata.progress = cleanString(body.progress || result || note);
  }
  const ingest = await ingestContextRecords(slug, {
    source: clientId,
    provider: cleanString(body.provider || clientId),
    client_id: clientId,
    session_id: threadId,
    conversation_id: threadId,
    tags: ["agent-message", "handoff", kind, clientId],
    metadata: {
      ...(body.metadata && typeof body.metadata === "object" ? body.metadata : {}),
      domain: "beagle-workbench-handoff",
      [metadataKey]: lifecycleMetadata
    },
    turns: [{
      role: "tool",
      external_id: cleanString(body.external_id || body.externalId) || `${id}:${kind}:${clientId}`,
      content: `[handoff:${kind}] ${clientId} ${verb} ${id}${result ? `\n\nResult: ${result}` : ""}${lifecycleMetadata.reason ? `\n\nReason: ${lifecycleMetadata.reason}` : ""}${lifecycleMetadata.progress ? `\n\nProgress: ${lifecycleMetadata.progress}` : ""}${note ? `\n\n${note}` : ""}`
    }]
  });
  appendAuditEvent(slug, {
    event_type: `message_${kind}`,
    source: clientId,
    client_id: clientId,
    session_id: threadId,
    message_id: id,
    result,
    previous_status: current?.status || ""
  });
  const next = buildContextMessageSnapshot(slug, id);
  return {
    schema: `beagle.workbench-context-message-${kind}.v1`,
    status: "ok",
    projectSlug: slug,
    generatedAt: now,
    truthMode: "observed",
    message_id: id,
    client_id: clientId,
    previous: current,
    message: next,
    lifecycle: lifecycleMetadata,
    ingest
  };
}

async function acknowledgeContextMessage(slug, messageId, body = {}) {
  const id = cleanString(messageId || body.message_id || body.messageId);
  if (!id) {
    const error = new Error("message_id is required");
    error.statusCode = 400;
    throw error;
  }
  const clientId = cleanString(body.client_id || body.clientId || body.by || body.source, "operator");
  const now = new Date().toISOString();
  const messageRecord = findHandoffMessageRecord(slug, id);
  const threadId = cleanString(messageRecord?.metadata?.agent_message?.thread_id || messageRecord?.session_id || body.thread_id || body.threadId || `handoff:${slug}:${now.slice(0, 10)}`);
  const ingest = await ingestContextRecords(slug, {
    source: clientId,
    provider: cleanString(body.provider || clientId),
    client_id: clientId,
    session_id: threadId,
    conversation_id: threadId,
    tags: ["agent-message", "handoff", "ack", clientId],
    metadata: {
      ...(body.metadata && typeof body.metadata === "object" ? body.metadata : {}),
      domain: "beagle-workbench-handoff",
      agent_message_ack: {
        message_id: id,
        client_id: clientId,
        ack_at: now,
        note: cleanString(body.note)
      }
    },
    turns: [{
      role: "tool",
      external_id: cleanString(body.external_id || body.externalId) || `${id}:ack:${clientId}`,
      content: `[handoff:ack] ${clientId} acknowledged ${id}${body.note ? `\n\n${body.note}` : ""}`
    }]
  });
  appendAuditEvent(slug, {
    event_type: "message_ack",
    source: clientId,
    client_id: clientId,
    message_id: id
  });
  return {
    schema: "beagle.workbench-context-message-ack.v1",
    status: "ok",
    projectSlug: slug,
    generatedAt: now,
    truthMode: "observed",
    message_id: id,
    client_id: clientId,
    ingest
  };
}

async function acknowledgeContextMessageAndNotify(slug, messageId, body = {}) {
  const result = await acknowledgeContextMessage(slug, messageId, body);
  await notifyContextRouteHook("onMessageLifecycle", {
    slug,
    messageId: result.message_id,
    kind: "ack",
    result
  });
  return result;
}

async function replyContextMessage(slug, messageId, body = {}) {
  const id = cleanString(messageId || body.message_id || body.messageId);
  if (!id) {
    const error = new Error("message_id is required");
    error.statusCode = 400;
    throw error;
  }
  const text = boundedText(body.text || body.reply || body.response || body.result || body.content);
  if (!text) {
    const error = new Error("reply text is required");
    error.statusCode = 400;
    throw error;
  }
  const messageRecord = findHandoffMessageRecord(slug, id);
  if (!messageRecord) {
    const error = new Error(`handoff message not found: ${id}`);
    error.statusCode = 404;
    throw error;
  }
  const current = buildContextMessageSnapshot(slug, id);
  if (["completed", "canceled"].includes(current?.status) && body.force !== true && cleanString(body.force).toLowerCase() !== "true") {
    const error = new Error(`handoff is ${current.status}; pass force=true to append another reply`);
    error.statusCode = 409;
    throw error;
  }
  const meta = messageRecord.metadata.agent_message || {};
  const clientId = cleanString(body.client_id || body.clientId || body.by || body.source || meta.to_client, "operator");
  const provider = cleanString(body.provider || clientId);
  const threadId = cleanString(meta.thread_id || messageRecord.session_id || body.thread_id || body.threadId);
  const externalId = cleanString(body.external_id || body.externalId) ||
    `${id}:reply:${clientId}:${Date.now()}`.replace(/[^a-zA-Z0-9:_-]/g, "_");
  const replyIngest = await ingestContextRecords(slug, {
    source: clientId,
    provider,
    client_id: clientId,
    session_id: threadId,
    conversation_id: threadId,
    request_id: cleanString(body.request_id || body.requestId || id),
    tags: ["agent-message", "handoff", "reply", clientId, ...normalizeTags(body.tags)],
    metadata: {
      ...(body.metadata && typeof body.metadata === "object" ? body.metadata : {}),
      domain: "beagle-workbench-handoff",
      reply_to_message_id: id,
      truthMode: "observed-client-reply"
    },
    turns: [{
      role: "assistant",
      external_id: externalId,
      content: text,
      model: cleanString(body.model || body.metadata?.model)
    }]
  });
  const complete = await recordContextMessageLifecycle(slug, id, {
    ...body,
    client_id: clientId,
    provider,
    result: text,
    force: body.force === true || cleanString(body.force).toLowerCase() === "true",
    artifact_refs: [
      ...(Array.isArray(body.artifact_refs || body.artifactRefs) ? (body.artifact_refs || body.artifactRefs) : []),
      ...(replyIngest.memory_ids || [])
    ].map((item) => cleanString(item)).filter(Boolean),
    metadata: {
      ...(body.metadata && typeof body.metadata === "object" ? body.metadata : {}),
      reply_external_id: externalId,
      reply_memory_id: replyIngest.memory_ids?.[0] || "",
      truthMode: "observed-client-reply"
    }
  }, "complete");
  appendAuditEvent(slug, {
    event_type: "message_reply",
    source: clientId,
    client_id: clientId,
    session_id: threadId,
    message_id: id,
    reply_memory_id: replyIngest.memory_ids?.[0] || ""
  });
  return {
    schema: "beagle.workbench-context-message-reply.v1",
    status: "ok",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    truthMode: "observed",
    message_id: id,
    client_id: clientId,
    thread_id: threadId,
    text,
    reply: {
      memory_id: replyIngest.memory_ids?.[0] || "",
      external_id: externalId,
      source: clientId,
      provider
    },
    ingest: replyIngest,
    complete,
    message: buildContextMessageSnapshot(slug, id)
  };
}

async function replyContextMessageAndNotify(slug, messageId, body = {}) {
  const result = await replyContextMessage(slug, messageId, body);
  await notifyContextRouteHook("onMessageReply", {
    slug,
    messageId: result.message_id,
    kind: "reply",
    result
  });
  return result;
}

async function recordContextMessageLifecycleAndNotify(slug, messageId, body = {}, kind = "ack") {
  const result = await recordContextMessageLifecycle(slug, messageId, body, kind);
  const metadata = body.metadata && typeof body.metadata === "object" ? body.metadata : {};
  const suppressRealtimeNotify =
    body.suppress_realtime_notify === true ||
    body.suppressRealtimeNotify === true ||
    metadata.suppress_realtime_notify === true ||
    metadata.suppressRealtimeNotify === true;
  if (!suppressRealtimeNotify && ["claim", "complete", "release", "cancel", "reopen", "heartbeat"].includes(kind)) {
    await notifyContextRouteHook("onMessageLifecycle", {
      slug,
      messageId: result.message_id || cleanString(messageId),
      kind,
      result
    });
  }
  return result;
}

async function buildContextHandoffPacket(slug, messageId, body = {}) {
  const id = cleanString(messageId || body.message_id || body.messageId);
  if (!id) {
    const error = new Error("message_id is required");
    error.statusCode = 400;
    throw error;
  }
  const records = readLocalRecords(slug);
  const messageRecord = records.find((record) => record.metadata?.agent_message?.message_id === id);
  if (!messageRecord) {
    const error = new Error(`handoff message not found: ${id}`);
    error.statusCode = 404;
    throw error;
  }
  const meta = messageRecord.metadata.agent_message;
  const threadId = cleanString(meta.thread_id || messageRecord.session_id);
  const lifecycle = collectContextMessageLifecycle(records);
  const messageLifecycle = {
    acknowledgements: lifecycle.acknowledgements.get(id) || [],
    claims: lifecycle.claims.get(id) || [],
    releases: lifecycle.releases.get(id) || [],
    completions: lifecycle.completions.get(id) || [],
    cancellations: lifecycle.cancellations.get(id) || [],
    reopens: lifecycle.reopens.get(id) || [],
    heartbeats: lifecycle.heartbeats.get(id) || []
  };
  const state = deriveContextMessageState(meta, messageLifecycle);
  const thread = records
    .filter((record) => record.session_id === threadId)
    .filter((record) => record.metadata?.agent_message || record.metadata?.agent_message_ack || record.metadata?.agent_message_claim || record.metadata?.agent_message_release || record.metadata?.agent_message_complete || record.metadata?.agent_message_cancel || record.metadata?.agent_message_reopen || record.metadata?.agent_message_heartbeat || (record.tags || []).includes("handoff"))
    .sort((left, right) => cleanString(left.created_at).localeCompare(cleanString(right.created_at)))
    .map((record) => ({
      memory_id: record.memory_id,
      source: record.source,
      client_id: record.client_id,
      role: record.role,
      created_at: record.created_at,
      text: record.text,
      message_id: cleanString(record.metadata?.agent_message?.message_id || record.metadata?.agent_message_ack?.message_id)
    }));
  const query = cleanString(body.query || body.query_text) || [
    meta.subject,
    meta.from_client,
    meta.to_client,
    threadId,
    messageRecord.text
  ].filter(Boolean).join(" ");
  const retrieval = await buildContextQuery(slug, {
    query,
    max_items: body.max_items || body.limit || 8,
    query_mode: body.query_mode || body.query_mode_hint || "handoff"
  });
  return {
    schema: "beagle.workbench-context-handoff-packet.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    truthMode: "observed",
    task_profile: cleanString(body.task_profile || "handoff"),
    handoff: {
      message_id: id,
      from_client: cleanString(meta.from_client || messageRecord.source),
      to_client: cleanString(meta.to_client || "broadcast"),
      subject: cleanString(meta.subject || "handoff"),
      priority: cleanString(meta.priority || "normal"),
      status: state.status,
      requires_response: meta.requires_response === true,
      thread_id: threadId,
      reply_tool: "workbench_context_reply",
      reply_tool_stdio_proxy: "cockpit_workbench_context_reply",
      reply_endpoint: `/api/workbench/${slug}/context/messages/${encodeURIComponent(id)}/reply`,
      sent_at: cleanString(meta.sent_at || messageRecord.created_at),
      text: messageRecord.text,
      memory_id: messageRecord.memory_id,
      claimed_by: state.claimed_by,
      completed_by: state.completed_by,
      canceled_by: state.canceled_by,
      last_heartbeat_at: state.last_heartbeat_at
    },
    acknowledgements: messageLifecycle.acknowledgements,
    claims: messageLifecycle.claims,
    releases: messageLifecycle.releases,
    completions: messageLifecycle.completions,
    cancellations: messageLifecycle.cancellations,
    reopens: messageLifecycle.reopens,
    heartbeats: messageLifecycle.heartbeats,
    thread,
    retrieval: {
      query: retrieval.query,
      summary: retrieval.summary,
      node_count: retrieval.node_count,
      edge_count: retrieval.edge_count,
      top_memory_ids: retrieval.highlights.map((item) => item.memory_id).filter(Boolean)
    },
    reply_instruction: `Use workbench_context_reply with message_id=${id} to answer this handoff and close the loop. If your MCP client is connected through the cockpit stdio proxy, use cockpit_workbench_context_reply with the same arguments.`,
    compiled_context_text: compiledTextFromQuery(retrieval),
    graph: retrieval.graph,
    highlights: retrieval.highlights,
    upstream: retrieval.upstream
  };
}

async function buildContextDoctor(slug, body = {}) {
  const generatedAt = new Date().toISOString();
  const writeProbe = body.write_probe === true || body.writeProbe === true || body.probe === "write";
  const checks = [];

  function pushCheck(name, status, detail = {}) {
    checks.push({
      name,
      status,
      ...detail
    });
  }

  const statusPacket = buildContextStatus(slug);
  const contextDir = path.dirname(contextFile(slug));
  const doctorFile = path.join(contextDir, `.doctor-${process.pid}-${Date.now()}.tmp`);
  try {
    ensureDir(doctorFile);
    fs.writeFileSync(doctorFile, generatedAt);
    fs.unlinkSync(doctorFile);
    pushCheck("storage_writable", "green", {
      data_dir: DATA_DIR,
      context_file: contextFile(slug),
      local_records: statusPacket.counts.local_records
    });
  } catch (error) {
    pushCheck("storage_writable", "red", {
      data_dir: DATA_DIR,
      error: error.message
    });
  }

  try {
    const token = await fetchOperatorToken();
    pushCheck(token.error || !token.token ? "beagle_auth" : "beagle_auth", token.error || !token.token ? "red" : "green", {
      token_endpoint: "/api/auth/beagle-token",
      error: token.error || ""
    });
  } catch (error) {
    pushCheck("beagle_auth", "red", { error: error.message });
  }

  try {
    const beagle = await queryBeagleMemory({
      query: body.query || `${slug} Workbench Context doctor Beagle RAG`,
      max_items: 1
    });
    pushCheck("beagle_rag_query", beagle.ok ? "green" : "yellow", {
      beagle_url: beagle.baseUrl || "",
      highlights: beagle.highlights?.length || 0,
      error: beagle.error || ""
    });
  } catch (error) {
    pushCheck("beagle_rag_query", "red", { error: error.message });
  }

  pushCheck("http_mcp_contract", "green", {
    auth_required: REQUIRE_HTTP_MCP_AUTH,
    tool_count: workbenchMcpTools().length,
    endpoint: `/api/workbench/${slug}/mcp`
  });

  let probeResult = null;
  if (writeProbe) {
    const sentinel = cleanString(body.sentinel) || `WBCTX_DOCTOR_${Date.now()}_${slug}`;
    try {
      const ingest = await ingestContextRecords(slug, {
        source: "workbench-context-doctor",
        provider: "project-cockpit",
        client_id: "workbench-context-doctor",
        session_id: "workbench-context-doctor",
        tags: ["doctor", "read-after-write", "http-mcp", "beagle-rag"],
        turns: [{
          role: "system",
          external_id: sentinel,
          content: `${sentinel} validates Workbench Context storage, Beagle auth/write-through, RAG++ retrieval, GraphRAG, and compiler.`
        }]
      });
      const query = await buildContextQuery(slug, { query: sentinel, limit: 5 });
      const compiled = await callWorkbenchMcpTool(slug, "workbench_context_compile", {
        query: sentinel,
        max_items: 5,
        tool_id: "workbench-context-doctor"
      });
      const found = (query.results || []).some((item) => cleanString(item.text || item.snippet).includes(sentinel));
      probeResult = {
        sentinel,
        ingest,
        query: {
          summary: query.summary,
          node_count: query.node_count,
          edge_count: query.edge_count,
          found
        },
        compiler: {
          schema: compiled.schema,
          top_memory_ids: compiled.top_memory_ids?.length || 0
        }
      };
      pushCheck("write_read_compile_probe", found ? "green" : "red", {
        sentinel,
        read_after_write_found: found,
        upstream: ingest.upstream?.beagle_memory || "",
        node_count: query.node_count,
        edge_count: query.edge_count,
        compiled_top_memory_ids: compiled.top_memory_ids?.length || 0
      });
    } catch (error) {
      pushCheck("write_read_compile_probe", "red", {
        error: error.message
      });
    }
  } else {
    pushCheck("write_read_compile_probe", "skipped", {
      note: "Pass write_probe=true to run a mutating sentinel ingest/query/compiler probe."
    });
  }

  const red = checks.filter((check) => check.status === "red").length;
  const yellow = checks.filter((check) => check.status === "yellow").length;
  return {
    schema: "beagle.workbench-context-doctor.v1",
    projectSlug: slug,
    generatedAt,
    status: red > 0 ? "red" : yellow > 0 ? "yellow" : "green",
    truthMode: "observed",
    write_probe: writeProbe,
    checks,
    status_packet: statusPacket,
    probe: probeResult
  };
}

function workbenchMcpTools() {
  return [
    {
      name: "workbench_context_doctor",
      description: "Run Workbench Context operational diagnostics. Non-mutating by default; set write_probe=true to verify ingest, Beagle write-through, RAG++ readback, GraphRAG, and compiler.",
      inputSchema: {
        type: "object",
        properties: {
          write_probe: { type: "boolean", default: false },
          query: { type: "string" },
          sentinel: { type: "string" }
        }
      }
    },
    {
      name: "workbench_context_status",
      description: "Return Workbench shared MCP/RAG++ memory status, observed clients, counts, features, and endpoints.",
      inputSchema: { type: "object", properties: {} }
    },
    {
      name: "workbench_context_audit",
      description: "Audit Workbench shared memory: clients, sources, sessions, tags, risks, and recent ingest/import events.",
      inputSchema: { type: "object", properties: {} }
    },
    {
      name: "workbench_context_presence",
      description: "Return operational presence for MCP clients and agents: active, waiting, stale, idle, declared, plus handoff load.",
      inputSchema: {
        type: "object",
        properties: {
          stale_after_minutes: { type: "integer", minimum: 5, maximum: 1440, default: 90 },
          limit: { type: "integer", minimum: 1, maximum: 500, default: 200 }
        }
      }
    },
    {
      name: "workbench_context_client_heartbeat",
      description: "Mark an MCP/subscription client as live without creating a handoff reply. Use this as a keepalive from ChatGPT, Claude Desktop, Grok, Kimi, Codex, or local agents.",
      inputSchema: {
        type: "object",
        required: ["client_id"],
        properties: {
          client_id: { type: "string" },
          provider: { type: "string" },
          session_id: { type: "string" },
          status: { type: "string", default: "online" },
          note: { type: "string" },
          tags: { type: "array", items: { type: "string" } },
          metadata: { type: "object", additionalProperties: true }
        }
      }
    },
    {
      name: "workbench_context_continuity",
      description: "Compile a continuity packet so a new agent can resume without losing context: status, presence, open handoffs, next actions, recent memories, and resume brief.",
      inputSchema: {
        type: "object",
        properties: {
          limit: { type: "integer", minimum: 1, maximum: 120, default: 40 },
          handoff_limit: { type: "integer", minimum: 1, maximum: 100, default: 24 },
          recent_limit: { type: "integer", minimum: 1, maximum: 100, default: 12 },
          stale_after_minutes: { type: "integer", minimum: 5, maximum: 1440, default: 90 }
        }
      }
    },
    {
      name: "workbench_context_recent",
      description: "Return recent Workbench shared memory records, optionally filtered by source/session/tags.",
      inputSchema: {
        type: "object",
        properties: {
          limit: { type: "integer", minimum: 1, maximum: 100 },
          source: { type: "string" },
          session_id: { type: "string" },
          since: { type: "string" },
          tags: { type: "array", items: { type: "string" } }
        }
      }
    },
    {
      name: "workbench_context_ingest",
      description: "Write MCP/chat turns into shared Workbench memory with local read-after-write and Beagle Core write-through.",
      inputSchema: {
        type: "object",
        required: ["turns"],
        properties: {
          source: { type: "string" },
          provider: { type: "string" },
          client_id: { type: "string" },
          session_id: { type: "string" },
          conversation_id: { type: "string" },
          turns: {
            type: "array",
            items: {
              type: "object",
              required: ["content"],
              properties: {
                role: { type: "string", enum: ["user", "assistant", "system", "tool"] },
                content: { type: "string" },
                external_id: { type: "string" },
                model: { type: "string" }
              }
            }
          },
          tags: { type: "array", items: { type: "string" } },
          metadata: { type: "object", additionalProperties: true }
        }
      }
    },
    {
      name: "workbench_context_query",
      description: "Query shared memory with Workbench RAG++ over local overlay plus Beagle Core memory.",
      inputSchema: {
        type: "object",
        required: ["query"],
        properties: {
          query: { type: "string" },
          limit: { type: "integer", minimum: 1, maximum: 30 },
          source: { type: "string" },
          session_id: { type: "string" },
          tags: { type: "array", items: { type: "string" } }
        }
      }
    },
    {
      name: "beagle_memory_query",
      description: "Compatibility alias for legacy Beagle MCP clients. Queries the current Workbench shared memory/RAG++ overlay plus Beagle Core memory.",
      inputSchema: {
        type: "object",
        required: ["query"],
        properties: {
          query: { type: "string" },
          limit: { type: "integer", minimum: 1, maximum: 30 },
          top_k: { type: "integer", minimum: 1, maximum: 30 },
          domain: { type: "string" },
          source: { type: "string" },
          session_id: { type: "string" },
          tags: { type: "array", items: { type: "string" } },
          include_recent_physio: { type: "boolean", default: false }
        }
      }
    },
    {
      name: "beagle_memory_ingest_chat",
      description: "Compatibility alias for legacy Beagle MCP clients. Writes chat turns into Workbench shared memory with local read-after-write and Beagle Core write-through.",
      inputSchema: {
        type: "object",
        required: ["source", "conversation_id", "role", "text"],
        properties: {
          source: { type: "string" },
          conversation_id: { type: "string" },
          turn_index: { type: "integer", minimum: 0 },
          role: { type: "string", enum: ["user", "assistant", "system", "tool"] },
          text: { type: "string" },
          domain: { type: "string" },
          tags: { type: "array", items: { type: "string" } },
          provider: { type: "string" },
          model: { type: "string" },
          client_id: { type: "string" },
          metadata: { type: "object", additionalProperties: true }
        }
      }
    },
    {
      name: "workbench_context_graphrag",
      description: "Return bounded GraphRAG nodes/edges from retrieved Workbench and Beagle memory.",
      inputSchema: {
        type: "object",
        required: ["query"],
        properties: {
          query: { type: "string" },
          limit: { type: "integer", minimum: 1, maximum: 30 },
          query_mode: { type: "string" }
        }
      }
    },
    {
      name: "workbench_context_compile",
      description: "Compile shared memory retrieval and graph into an agent handoff context packet.",
      inputSchema: {
        type: "object",
        required: ["query"],
        properties: {
          query: { type: "string" },
          task_profile: { type: "string" },
          tool_id: { type: "string" },
          max_items: { type: "integer", minimum: 1, maximum: 30 }
        }
      }
    },
    {
      name: "workbench_context_import",
      description: "Bulk import external MCP/chat history into shared Workbench memory with duplicate suppression.",
      inputSchema: {
        type: "object",
        properties: {
          source: { type: "string" },
          provider: { type: "string" },
          client_id: { type: "string" },
          tags: { type: "array", items: { type: "string" } },
          items: { type: "array", items: { type: "object", additionalProperties: true } },
          conversations: { type: "array", items: { type: "object", additionalProperties: true } },
          write_through: { type: "boolean" }
        }
      }
    },
    {
      name: "workbench_context_export",
      description: "Export recent shared Workbench memory records for inspection, migration, or client sync.",
      inputSchema: {
        type: "object",
        properties: {
          limit: { type: "integer", minimum: 1, maximum: 100 },
          source: { type: "string" },
          session_id: { type: "string" },
          since: { type: "string" },
          tags: { type: "array", items: { type: "string" } }
        }
      }
    },
    {
      name: "workbench_context_send",
      description: "Send a handoff message from one agent/client to another through the shared Workbench context mesh.",
      inputSchema: {
        type: "object",
        required: ["to_client", "content"],
        properties: {
          from_client: { type: "string" },
          to_client: { type: "string" },
          subject: { type: "string" },
          content: { type: "string" },
          priority: { type: "string", enum: ["low", "normal", "high", "urgent"] },
          thread_id: { type: "string" },
          requires_response: { type: "boolean" },
          tags: { type: "array", items: { type: "string" } }
        }
      }
    },
    {
      name: "workbench_context_join",
      description: "Join the Workbench live room as a subscription client: records presence, returns pending handoffs, and provides exact reply tool arguments for the next message.",
      inputSchema: {
        type: "object",
        properties: {
          client_id: { type: "string" },
          provider: { type: "string" },
          session_id: { type: "string" },
          status: { type: "string", default: "online" },
          note: { type: "string" },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 10 },
          include_completed: { type: "boolean", default: false }
        }
      }
    },
    {
      name: "workbench_context_inbox",
      description: "List handoff messages for a client, including acknowledgements, claims, and completions.",
      inputSchema: {
        type: "object",
        properties: {
          client_id: { type: "string" },
          status: { type: "string", enum: ["sent", "acknowledged", "claimed", "completed", "canceled"] },
          limit: { type: "integer", minimum: 1, maximum: 100 }
        }
      }
    },
    {
      name: "workbench_context_board",
      description: "Return a coordination board for agent handoffs: waiting, active, done, stale, per-client counts, and next actions.",
      inputSchema: {
        type: "object",
        properties: {
          client_id: { type: "string" },
          limit: { type: "integer", minimum: 1, maximum: 500, default: 200 },
          stale_after_minutes: { type: "integer", minimum: 5, maximum: 1440, default: 90 },
          include_completed: { type: "boolean", default: true }
        }
      }
    },
    {
      name: "workbench_context_ack",
      description: "Acknowledge a handoff message from an agent/client.",
      inputSchema: {
        type: "object",
        required: ["message_id"],
        properties: {
          message_id: { type: "string" },
          client_id: { type: "string" },
          note: { type: "string" }
        }
      }
    },
    {
      name: "workbench_context_reply",
      description: "Reply to a handoff message as a client: writes the reply into the same thread and marks the handoff completed.",
      inputSchema: {
        type: "object",
        required: ["message_id", "text"],
        properties: {
          message_id: { type: "string" },
          client_id: { type: "string" },
          provider: { type: "string" },
          text: { type: "string" },
          model: { type: "string" },
          force: { type: "boolean", default: false },
          tags: { type: "array", items: { type: "string" } },
          metadata: { type: "object", additionalProperties: true }
        }
      }
    },
    {
      name: "workbench_context_handoff_compile",
      description: "Compile a specific handoff message into an actionable agent context packet with thread, acknowledgements, RAG++ highlights, graph, and plain text context.",
      inputSchema: {
        type: "object",
        required: ["message_id"],
        properties: {
          message_id: { type: "string" },
          query: { type: "string" },
          task_profile: { type: "string", default: "handoff" },
          max_items: { type: "integer", minimum: 1, maximum: 30, default: 8 },
          query_mode: { type: "string", default: "handoff" }
        }
      }
    },
    {
      name: "workbench_context_claim",
      description: "Claim a handoff message before starting work so other agents can see ownership.",
      inputSchema: {
        type: "object",
        required: ["message_id"],
        properties: {
          message_id: { type: "string" },
          client_id: { type: "string" },
          note: { type: "string" }
        }
      }
    },
    {
      name: "workbench_context_release",
      description: "Release a claimed handoff so another agent can take it.",
      inputSchema: {
        type: "object",
        required: ["message_id"],
        properties: {
          message_id: { type: "string" },
          client_id: { type: "string" },
          note: { type: "string" },
          force: { type: "boolean", default: false }
        }
      }
    },
    {
      name: "workbench_context_complete",
      description: "Mark a claimed handoff message complete with a result summary and optional artifact refs.",
      inputSchema: {
        type: "object",
        required: ["message_id"],
        properties: {
          message_id: { type: "string" },
          client_id: { type: "string" },
          result: { type: "string" },
          note: { type: "string" },
          artifact_refs: { type: "array", items: { type: "string" } }
        }
      }
    },
    {
      name: "workbench_context_cancel",
      description: "Cancel a handoff that should no longer be worked.",
      inputSchema: {
        type: "object",
        required: ["message_id"],
        properties: {
          message_id: { type: "string" },
          client_id: { type: "string" },
          reason: { type: "string" },
          note: { type: "string" },
          force: { type: "boolean", default: false }
        }
      }
    },
    {
      name: "workbench_context_reopen",
      description: "Reopen a completed or canceled handoff and return it to the waiting queue.",
      inputSchema: {
        type: "object",
        required: ["message_id"],
        properties: {
          message_id: { type: "string" },
          client_id: { type: "string" },
          note: { type: "string" },
          force: { type: "boolean", default: false }
        }
      }
    },
    {
      name: "workbench_context_heartbeat",
      description: "Record progress on a claimed handoff without completing it.",
      inputSchema: {
        type: "object",
        required: ["message_id"],
        properties: {
          message_id: { type: "string" },
          client_id: { type: "string" },
          progress: { type: "string" },
          note: { type: "string" },
          force: { type: "boolean", default: false }
        }
      }
    }
  ];
}

async function ingestContextRecords(slug, body = {}) {
  const records = normalizeIngestBody(slug, body);
  if (records.length === 0) {
    const error = new Error("at least one non-empty turn is required");
    error.statusCode = 400;
    throw error;
  }
  const existing = recordsByExternalId(slug);
  const newRecords = records.filter((record) => !existing.has(record.external_id));
  const duplicateRecords = records.filter((record) => existing.has(record.external_id));
  for (const record of newRecords) {
    appendLocalRecord(slug, record);
  }
  const upstreamWrites = newRecords.length > 0 ? await writeThroughToBeagle(newRecords) : [];
  appendAuditEvent(slug, {
    event_type: "ingest",
    source: records[0]?.source || "",
    provider: records[0]?.provider || "",
    client_id: records[0]?.client_id || "",
    session_id: records[0]?.session_id || "",
    request_id: records[0]?.request_id || "",
    accepted_records: newRecords.length,
    duplicate_records: duplicateRecords.length,
    upstream_status: upstreamWrites.some((write) => write.ok) ? "observed" : newRecords.length > 0 ? "stale" : "skipped"
  });
  return {
    schema: "beagle.workbench-context-ingest.v1",
    status: "ok",
    projectSlug: slug,
    truthMode: "observed",
    stored: true,
    searchable: true,
    read_after_write: true,
    duplicate: newRecords.length === 0,
    num_turns: newRecords.length,
    num_chunks: newRecords.length,
    duplicate_turns: duplicateRecords.length,
    memory_ids: newRecords.map((record) => record.memory_id),
    duplicate_memory_ids: duplicateRecords.flatMap((record) => (
      existing.get(record.external_id) || []
    ).map((existingRecord) => existingRecord.memory_id)),
    session_id: records[0].session_id,
    upstream: {
      beagle_memory: upstreamWrites.some((write) => write.ok) ? "observed" : newRecords.length > 0 ? "stale" : "skipped",
      writes: upstreamWrites
    }
  };
}

async function importContextRecords(slug, body = {}) {
  const records = normalizeImportPayload(slug, body);
  if (records.length === 0) {
    const error = new Error("import requires at least one non-empty item or conversation");
    error.statusCode = 400;
    throw error;
  }
  const existing = recordsByExternalId(slug);
  const newRecords = records.filter((record) => !existing.has(record.external_id));
  const duplicateRecords = records.filter((record) => existing.has(record.external_id));
  for (const record of newRecords) {
    appendLocalRecord(slug, record);
  }
  const upstreamWrites =
    body?.write_through === false || newRecords.length === 0
      ? []
      : await writeThroughToBeagle(newRecords);
  appendAuditEvent(slug, {
    event_type: "import",
    source: cleanString(body?.source || records[0]?.source),
    provider: cleanString(body?.provider || records[0]?.provider),
    client_id: cleanString(body?.client_id || body?.clientId || records[0]?.client_id),
    accepted_records: newRecords.length,
    duplicate_records: duplicateRecords.length,
    upstream_status: upstreamWrites.some((write) => write.ok) ? "observed" : newRecords.length > 0 ? "stale" : "skipped"
  });
  return {
    schema: "beagle.workbench-context-import.v1",
    status: "ok",
    projectSlug: slug,
    truthMode: "observed",
    stored: true,
    searchable: true,
    read_after_write: true,
    imported_records: newRecords.length,
    duplicate_records: duplicateRecords.length,
    memory_ids: newRecords.map((record) => record.memory_id),
    upstream: {
      beagle_memory: upstreamWrites.some((write) => write.ok) ? "observed" : newRecords.length > 0 ? "stale" : "skipped",
      writes: upstreamWrites
    }
  };
}

async function ingestLegacyBeagleMemoryChat(slug, body = {}) {
  const source = cleanString(body.source || body.provider || body.client_id || "beagle-mcp");
  const metadata = body.metadata && typeof body.metadata === "object" ? body.metadata : {};
  return ingestContextRecords(slug, {
    source,
    provider: cleanString(body.provider || metadata.provider || source),
    client_id: cleanString(body.client_id || body.clientId || metadata.client_id || source),
    conversation_id: cleanString(body.conversation_id || body.conversationId),
    session_id: cleanString(body.session_id || body.sessionId || body.conversation_id || body.conversationId),
    role: cleanString(body.role || "user"),
    text: body.text || body.content || body.message,
    turn_index: body.turn_index,
    model: cleanString(body.model || metadata.model),
    domain: cleanString(body.domain || metadata.domain || "beagle-memory-compat"),
    tags: normalizeTags([
      ...normalizeTags(body.tags),
      "beagle-memory-compat"
    ]),
    metadata: {
      ...metadata,
      domain: cleanString(body.domain || metadata.domain || "beagle-memory-compat"),
      legacy_tool: "beagle_memory_ingest_chat"
    }
  });
}

async function queryLegacyBeagleMemory(slug, body = {}) {
  const result = await buildContextQuery(slug, {
    ...body,
    limit: body.limit || body.top_k || DEFAULT_LIMIT,
    query: queryText(body),
    query_mode: cleanString(body.query_mode || body.query_mode_hint || "beagle-memory-compat")
  });
  return {
    schema: "beagle.memory-query-compat.v1",
    status: result.status,
    projectSlug: slug,
    query: result.query,
    summary: result.summary,
    retrieval_mode: result.retrieval_mode,
    read_after_write: result.read_after_write,
    upstream: result.upstream,
    results: result.highlights.map((item) => ({
      memory_id: item.memory_id,
      source: item.source || item.origin,
      conversation_id: item.conversation_id || item.session_id || "",
      turn_index: item.turn_index ?? null,
      role: item.role || "",
      text: item.text || item.snippet || "",
      snippet: item.snippet || item.text || "",
      tags: item.tags || [],
      domain: item.domain || item.metadata?.domain || "",
      timestamp: item.created_at || item.timestamp || "",
      score: item.score ?? null,
      metadata: item.metadata || {}
    })),
    graph: result.graph,
    truthMode: "observed"
  };
}

async function callWorkbenchMcpTool(slug, name, args = {}) {
  switch (name) {
    case "workbench_context_doctor":
      return buildContextDoctor(slug, args);
    case "workbench_context_status":
      return buildContextStatus(slug);
    case "workbench_context_audit":
      return buildContextAudit(slug);
    case "workbench_context_presence":
      return buildContextPresence(slug, args);
    case "workbench_context_client_heartbeat":
    case "cockpit_workbench_context_client_heartbeat":
      return await recordContextClientHeartbeat(slug, args.client_id || args.clientId, args);
    case "workbench_context_continuity":
      return buildContextContinuity(slug, args);
    case "workbench_context_recent":
      return buildContextRecent(slug, args);
    case "workbench_context_ingest":
      return ingestContextRecords(slug, args);
    case "workbench_context_import":
      return importContextRecords(slug, args);
    case "workbench_context_export":
      return {
        schema: "beagle.workbench-context-export.v1",
        projectSlug: slug,
        generatedAt: new Date().toISOString(),
        count: exportRecords(slug, args).length,
        records: exportRecords(slug, args),
        truthMode: "observed"
      };
    case "workbench_context_send":
      return sendContextMessage(slug, args);
    case "workbench_context_join":
      return buildContextJoin(slug, args);
    case "workbench_context_inbox":
      return buildContextMessages(slug, args);
    case "workbench_context_board":
      return buildContextMessageBoard(slug, args);
    case "workbench_context_ack":
      return acknowledgeContextMessageAndNotify(slug, args.message_id || args.messageId, args);
    case "workbench_context_reply":
      return replyContextMessageAndNotify(slug, args.message_id || args.messageId, args);
    case "cockpit_workbench_context_reply":
      return replyContextMessageAndNotify(slug, args.message_id || args.messageId, args);
    case "workbench_context_handoff_compile":
      return buildContextHandoffPacket(slug, args.message_id || args.messageId, args);
    case "workbench_context_claim":
      return recordContextMessageLifecycleAndNotify(slug, args.message_id || args.messageId, args, "claim");
    case "workbench_context_complete":
      return recordContextMessageLifecycleAndNotify(slug, args.message_id || args.messageId, args, "complete");
    case "workbench_context_release":
      return recordContextMessageLifecycleAndNotify(slug, args.message_id || args.messageId, args, "release");
    case "workbench_context_cancel":
      return recordContextMessageLifecycleAndNotify(slug, args.message_id || args.messageId, args, "cancel");
    case "workbench_context_reopen":
      return recordContextMessageLifecycleAndNotify(slug, args.message_id || args.messageId, args, "reopen");
    case "workbench_context_heartbeat":
      return recordContextMessageLifecycleAndNotify(slug, args.message_id || args.messageId, args, "heartbeat");
    case "workbench_context_query":
      return buildContextQuery(slug, args);
    case "beagle_memory_query":
      return queryLegacyBeagleMemory(slug, args);
    case "beagle_memory_ingest_chat":
      return ingestLegacyBeagleMemoryChat(slug, args);
    case "workbench_context_graphrag": {
      const result = await buildContextQuery(slug, {
        ...args,
        query: queryText(args) || cleanString(args.query_text),
        query_mode: args.query_mode || args.query_mode_hint || "local"
      });
      return {
        result_version: "beagle-workbench-graphrag-result-v1",
        projectSlug: slug,
        query: result.query,
        query_mode: args.query_mode || args.query_mode_hint || "local",
        retrieval_mode: result.retrieval_mode,
        support_memory_ids: result.highlights.map((item) => item.memory_id).filter(Boolean),
        node_count: result.node_count,
        edge_count: result.edge_count,
        nodes: result.graph_nodes,
        edges: result.graph_edges,
        highlights: result.highlights,
        upstream: result.upstream,
        note: "Bounded GraphRAG projection built from Workbench read-after-write memory plus Beagle memory highlights."
      };
    }
    case "workbench_context_compile": {
      const result = await buildContextQuery(slug, {
        ...args,
        query: queryText(args) || cleanString(args.query_text),
        max_items: args.max_items || args.top_k || 8
      });
      return {
        schema: "beagle.workbench-compiled-context-packet.v1",
        compiler_id: "project-cockpit-workbench-context-compiler",
        projectSlug: slug,
        generatedAt: new Date().toISOString(),
        task_profile: cleanString(args.task_profile || "analysis"),
        tool_id: cleanString(args.tool_id || "workbench-http-mcp"),
        query_text: result.query,
        top_memory_ids: result.highlights.map((item) => item.memory_id).filter(Boolean),
        graphrag_query_mode: args.query_mode || args.query_mode_hint || "local",
        compiled_context_text: compiledTextFromQuery(result),
        graph: result.graph,
        highlights: result.highlights,
        upstream: result.upstream,
        truthMode: "observed"
      };
    }
    default: {
      const error = new Error(`unknown Workbench MCP tool: ${name}`);
      error.statusCode = 404;
      throw error;
    }
  }
}

async function handleWorkbenchMcpJsonRpc(slug, message = {}, { req = null } = {}) {
  const id = message.id ?? null;
  try {
    if (req) {
      await maybeRecordHttpMcpClientHeartbeat(slug, req, message);
    }
    if (message.method === "initialize") {
      const requestedProtocol = cleanString(message.params?.protocolVersion);
      return {
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: requestedProtocol || "2025-06-18",
          capabilities: { tools: {} },
          serverInfo: { name: "beagle-workbench-context", version: "0.2.0" }
        }
      };
    }
    if (message.method === "tools/list") {
      return { jsonrpc: "2.0", id, result: { tools: workbenchMcpTools() } };
    }
    if (message.method === "tools/call") {
      const name = cleanString(message.params?.name);
      const args = message.params?.arguments && typeof message.params.arguments === "object"
        ? message.params.arguments
        : {};
      const result = await callWorkbenchMcpTool(slug, name, withHttpMcpRequestMetadata(args, req, message));
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
          structuredContent: result,
          isError: false
        }
      };
    }
    if (message.method === "notifications/initialized" || message.method === "notifications/cancelled") {
      return null;
    }
    if (message.method === "ping") {
      return { jsonrpc: "2.0", id, result: {} };
    }
    return {
      jsonrpc: "2.0",
      id,
      error: { code: -32601, message: `method not found: ${message.method}` }
    };
  } catch (error) {
    return {
      jsonrpc: "2.0",
      id,
      error: {
        code: error.statusCode === 404 ? -32601 : -32603,
        message: error.message
      }
    };
  }
}

function acceptsEventStream(req) {
  return cleanString(req.get?.("accept")).toLowerCase().includes("text/event-stream");
}

function setMcpResponseHeaders(res, req) {
  const protocolVersion = cleanString(req.get?.("mcp-protocol-version"), "2025-06-18");
  res.setHeader("MCP-Protocol-Version", protocolVersion);
  if (cleanString(req.body?.method) === "initialize") {
    res.setHeader("Mcp-Session-Id", cleanString(req._workbenchMcpSession?.session_id) || randomUUID());
  }
}

function writeSseEvent(res, event, data, { id = "" } = {}) {
  if (id) res.write(`id: ${id}\n`);
  if (event) res.write(`event: ${event}\n`);
  res.write(`data: ${typeof data === "string" ? data : JSON.stringify(data)}\n\n`);
}

function writeMcpSseResponse(res, payload, req) {
  setMcpResponseHeaders(res, req);
  res.status(200);
  res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();
  const messages = Array.isArray(payload) ? payload : [payload].filter(Boolean);
  for (const message of messages) {
    writeSseEvent(res, "message", message, { id: randomUUID() });
  }
  res.end();
}

async function handleMcpPost(slug, req, res) {
  const messages = Array.isArray(req.body) ? req.body : [req.body || {}];
  const responses = [];
  for (const message of messages) {
    const session = upsertHttpMcpSession(slug, req, {
      stage: cleanString(message.method, "post"),
      transport: acceptsEventStream(req) ? "streamable-http-sse-response" : "streamable-http-json",
      message
    });
    if (!req._workbenchMcpSession) req._workbenchMcpSession = session;
    const response = await handleWorkbenchMcpJsonRpc(slug, message, { req });
    if (response) responses.push(response);
  }
  if (responses.length === 0) {
    return res.status(202).end();
  }
  if (acceptsEventStream(req)) {
    return writeMcpSseResponse(res, Array.isArray(req.body) ? responses : responses[0], req);
  }
  setMcpResponseHeaders(res, req);
  if (Array.isArray(req.body)) {
    return res.json(responses);
  }
  return res.json(responses[0]);
}

async function handleMcpGet(slug, route, req, res) {
  if (acceptsEventStream(req)) {
    const session = upsertHttpMcpSession(slug, req, {
      stage: "sse-listen",
      transport: "streamable-http-sse-listen",
      sessionId: mcpSessionHeader(req) || randomUUID()
    });
    await maybeRecordHttpMcpConnectionHeartbeat(slug, req, "sse-listen");
    res.status(200);
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("MCP-Protocol-Version", cleanString(req.get?.("mcp-protocol-version"), "2025-06-18"));
    res.setHeader("Mcp-Session-Id", session.session_id);
    res.flushHeaders?.();
    writeSseEvent(res, "ready", {
      jsonrpc: "2.0",
      method: "notifications/message",
      params: {
        level: "info",
        logger: "beagle-workbench-context",
        data: {
          projectSlug: slug,
          endpoint: route.replace(":slug", slug),
          session_id: session.session_id,
          client_id: session.client_id,
          transport: "streamable-http-sse-listen",
          truthMode: "observed"
        }
      }
    }, { id: randomUUID() });
    const timer = setInterval(() => {
      const updated = upsertHttpMcpSession(slug, req, {
        stage: "sse-keepalive",
        transport: "streamable-http-sse-listen",
        sessionId: session.session_id
      });
      writeSseEvent(res, "keepalive", {
        session_id: updated.session_id,
        client_id: updated.client_id,
        last_seen_at: updated.last_seen_at,
        truthMode: "observed-live-http-mcp-session"
      }, { id: randomUUID() });
    }, HTTP_MCP_SSE_KEEPALIVE_MS);
    timer.unref?.();
    req.on("close", () => {
      clearInterval(timer);
      closeHttpMcpSession(slug, session.session_id, { stage: "sse-closed" });
    });
    return;
  }
  return res.json({
    schema: "beagle.workbench-context-http-mcp.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    protocolVersion: "2025-06-18",
    legacyProtocolVersion: "2024-11-05",
    serverInfo: { name: "beagle-workbench-context", version: "0.2.0" },
    auth: {
      required: REQUIRE_HTTP_MCP_AUTH,
      schemes: REQUIRE_HTTP_MCP_AUTH
        ? ["Authorization: Bearer <workbench-context-token-or-beagle-operator-token>"]
        : []
    },
    endpoint: route.replace(":slug", slug),
    transports: ["streamable-http", "sse-listen", "json-diagnostics"],
    sessions: buildHttpMcpSessionStatus(slug).summary,
    tools: workbenchMcpTools(),
    truthMode: "observed"
  });
}

async function buildContextQuery(slug, body = {}) {
  const query = queryText(body);
  if (!query) {
    const error = new Error("query required");
    error.statusCode = 400;
    throw error;
  }

  const local = queryLocalRecords(slug, body);
  const beagle = await queryBeagleMemory(body);
  const seen = new Set();
  const highlights = [...local, ...(beagle.highlights || [])].filter((item) => {
    const key = `${item.origin}:${item.memory_id}:${item.snippet}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, parseLimit(body));
  const graph = buildGraph(highlights, {
    query,
    slug,
    mode: cleanString(body.query_mode || body.query_mode_hint || "local")
  });
  const localCount = local.length;
  const beagleCount = beagle.highlights?.length || 0;

  return {
    schema: "beagle.workbench-context-query.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    query,
    truthMode: "observed",
    status: "ok",
    retrieval_mode: "local-read-after-write + beagle-memory",
    read_after_write: {
      guaranteed: true,
      local_records: readLocalRecords(slug).length,
      note: "Workbench context overlay is queried synchronously before Beagle Core memory, so newly ingested turns are immediately retrievable."
    },
    upstream: {
      beagle_memory: beagle.ok ? "observed" : "stale",
      beagle_url: beagle.baseUrl || "",
      error: beagle.error || ""
    },
    summary: highlights.length
      ? `Found ${highlights.length} Workbench RAG++ match(es): ${localCount} read-after-write local, ${beagleCount} Beagle memory.`
      : `No Workbench RAG++ matches found for '${query}'.`,
    highlights,
    results: highlights,
    links: [
      ...highlights.map((item) => item.memory_id).filter(Boolean),
      ...(beagle.links || [])
    ],
    graph,
    graph_nodes: graph.nodes,
    graph_edges: graph.edges,
    node_count: graph.node_count,
    edge_count: graph.edge_count
  };
}

function compiledTextFromQuery(result) {
  const lines = [
    `Context packet for: ${result.query}`,
    "",
    `Retrieval: ${result.summary}`,
    `Graph: ${result.node_count} node(s), ${result.edge_count} edge(s)`,
    ""
  ];
  for (const item of result.highlights.slice(0, 8)) {
    lines.push(`- [${item.origin}/${item.source}] ${item.snippet}`);
  }
  return lines.join("\n");
}

export function registerWorkbenchContextRoutes(app, hooks = {}) {
  setContextRouteHooks(hooks);
  app.get("/api/workbench/:slug/context/status", (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextStatus(slug));
  });

  app.get("/api/workbench/:slug/context/connect", (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextConnectionPack(slug, req));
  });

  app.get("/api/workbench/:slug/context/doctor", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await buildContextDoctor(slug, {
        ...req.query,
        write_probe: req.query?.write_probe === "true" || req.query?.writeProbe === "true"
      }));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/workbench/:slug/context/doctor", requireDoctorProbeAuth, async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await buildContextDoctor(slug, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/workbench/:slug/context/clients", (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextClients(slug));
  });

  app.post("/api/workbench/:slug/context/clients/:client_id/heartbeat", requireContextWriteAuth, idempotent({ ttlMs: 60_000 }), async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await recordContextClientHeartbeat(slug, req.params.client_id, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/workbench/:slug/context/presence", requireContextReadAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextPresence(slug, req.query || {}));
  });

  app.get("/api/workbench/:slug/context/continuity", requireContextReadAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextContinuity(slug, req.query || {}));
  });

  app.get("/api/workbench/:slug/context/sessions", (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextSessions(slug));
  });

  app.get("/api/workbench/:slug/context/audit", requireContextReadAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextAudit(slug));
  });

  app.get("/api/workbench/:slug/context/audit/events", requireContextReadAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json({
      schema: "beagle.workbench-context-audit-events.v1",
      projectSlug: slug,
      generatedAt: new Date().toISOString(),
      events: readAuditEvents(slug, req.query?.limit || 50),
      truthMode: "observed"
    });
  });

  app.get("/api/workbench/:slug/context/recent", requireContextReadAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextRecent(slug, req.query || {}));
  });

  app.get("/api/workbench/:slug/context/messages", requireContextReadAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextMessages(slug, req.query || {}));
  });

  app.get("/api/workbench/:slug/context/messages/board", requireContextReadAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextMessageBoard(slug, req.query || {}));
  });

  app.get("/api/workbench/:slug/context/messages/inbox/:client_id", requireContextReadAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildContextMessages(slug, {
      ...(req.query || {}),
      client_id: req.params.client_id
    }));
  });

  app.post("/api/workbench/:slug/context/messages/send", requireContextWriteAuth, idempotent({ ttlMs: 60_000 }), async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await sendContextMessage(slug, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/workbench/:slug/context/messages/:message_id/ack", requireContextWriteAuth, idempotent({ ttlMs: 60_000 }), async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await acknowledgeContextMessageAndNotify(slug, req.params.message_id, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/workbench/:slug/context/messages/:message_id/reply", requireContextWriteAuth, idempotent({ ttlMs: 60_000 }), async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await replyContextMessageAndNotify(slug, req.params.message_id, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/workbench/:slug/context/messages/:message_id/claim", requireContextWriteAuth, idempotent({ ttlMs: 60_000 }), async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await recordContextMessageLifecycleAndNotify(slug, req.params.message_id, req.body || {}, "claim"));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/workbench/:slug/context/messages/:message_id/complete", requireContextWriteAuth, idempotent({ ttlMs: 60_000 }), async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await recordContextMessageLifecycleAndNotify(slug, req.params.message_id, req.body || {}, "complete"));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  for (const kind of ["release", "cancel", "reopen", "heartbeat"]) {
    app.post(`/api/workbench/:slug/context/messages/:message_id/${kind}`, requireContextWriteAuth, idempotent({ ttlMs: 60_000 }), async (req, res) => {
      try {
        const slug = safeSlug(req.params.slug);
        res.json(await recordContextMessageLifecycleAndNotify(slug, req.params.message_id, req.body || {}, kind));
      } catch (error) {
        res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
      }
    });
  }

  app.get("/api/workbench/:slug/context/messages/:message_id/compile", requireContextReadAuth, async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await buildContextHandoffPacket(slug, req.params.message_id, req.query || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/workbench/:slug/context/messages/:message_id/compile", requireContextReadAuth, async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await buildContextHandoffPacket(slug, req.params.message_id, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/workbench/:slug/context/export", requireContextReadAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    const records = exportRecords(slug, req.query || {});
    res.json({
      schema: "beagle.workbench-context-export.v1",
      projectSlug: slug,
      generatedAt: new Date().toISOString(),
      count: records.length,
      records,
      truthMode: "observed"
    });
  });

  app.post("/api/workbench/:slug/context/ingest", requireContextWriteAuth, idempotent({ ttlMs: 60_000 }), async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await ingestContextRecords(slug, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/workbench/:slug/context/import", requireContextWriteAuth, idempotent({ ttlMs: 60_000 }), async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await importContextRecords(slug, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/workbench/:slug/context/mcp/tools", (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json({
      schema: "beagle.workbench-context-mcp-tools.v1",
      projectSlug: slug,
      generatedAt: new Date().toISOString(),
      protocolVersion: "2024-11-05",
      tools: workbenchMcpTools(),
      truthMode: "observed"
    });
  });

  app.get("/api/workbench/:slug/context/mcp/sessions", requireHttpMcpAuth, (req, res) => {
    const slug = safeSlug(req.params.slug);
    res.json(buildHttpMcpSessionStatus(slug));
  });

  for (const route of ["/api/workbench/:slug/mcp", "/api/workbench/:slug/context/mcp"]) {
    app.get(route, requireHttpMcpAuth, async (req, res) => {
      try {
        const slug = safeSlug(req.params.slug);
        return await handleMcpGet(slug, route, req, res);
      } catch (error) {
        if (res.headersSent) return res.end();
        return res.status(error.statusCode || 500).json({
          error: error.message,
          truthMode: "stale"
        });
      }
    });

    app.post(route, requireHttpMcpAuth, async (req, res) => {
      const slug = safeSlug(req.params.slug);
      return handleMcpPost(slug, req, res);
    });
  }

  app.post("/api/workbench/:slug/context/query", requireContextReadAuth, async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await buildContextQuery(slug, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/workbench/:slug/context/graphrag/query", requireContextReadAuth, async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const result = await buildContextQuery(slug, {
        ...(req.body || {}),
        query: queryText(req.body || {}) || cleanString(req.body?.query_text),
        query_mode: req.body?.query_mode || req.body?.query_mode_hint || "local"
      });
      res.json({
        result_version: "beagle-workbench-graphrag-result-v1",
        projectSlug: slug,
        query: result.query,
        query_mode: req.body?.query_mode || req.body?.query_mode_hint || "local",
        retrieval_mode: result.retrieval_mode,
        support_memory_ids: result.highlights.map((item) => item.memory_id).filter(Boolean),
        node_count: result.node_count,
        edge_count: result.edge_count,
        nodes: result.graph_nodes,
        edges: result.graph_edges,
        highlights: result.highlights,
        upstream: result.upstream,
        note: "Bounded GraphRAG projection built from Workbench read-after-write memory plus Beagle memory highlights."
      });
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/workbench/:slug/context/compiler/compile", requireContextReadAuth, async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const result = await buildContextQuery(slug, {
        ...(req.body || {}),
        query: queryText(req.body || {}) || cleanString(req.body?.query_text),
        max_items: req.body?.max_items || req.body?.top_k || 8
      });
      res.json({
        schema: "beagle.workbench-compiled-context-packet.v1",
        compiler_id: "project-cockpit-workbench-context-compiler",
        projectSlug: slug,
        generatedAt: new Date().toISOString(),
        task_profile: cleanString(req.body?.task_profile || "analysis"),
        tool_id: cleanString(req.body?.tool_id || "workbench"),
        query_text: result.query,
        top_memory_ids: result.highlights.map((item) => item.memory_id).filter(Boolean),
        graphrag_query_mode: req.body?.query_mode || req.body?.query_mode_hint || "local",
        compiled_context_text: compiledTextFromQuery(result),
        graph: result.graph,
        highlights: result.highlights,
        upstream: result.upstream,
        truthMode: "observed"
      });
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });
}
