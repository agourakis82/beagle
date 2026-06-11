// Workspace routes — Beagle Notebook Terminal v1.
//
// This service is intentionally workspace-scoped. It persists sessions, panes,
// and enriched terminal block logs in cluster storage, while canonical memory
// still lives in beagle-core via assisted-import.

import fs from "node:fs/promises";
import path from "node:path";
import { createHash, randomUUID } from "node:crypto";
import pty from "node-pty";
import { WebSocket } from "ws";
import { fetchOperatorToken } from "./auth-bridge.mjs";

const WORKBENCH_DIR =
  process.env.PROJECT_COCKPIT_WORKBENCH_DIR || "/var/lib/beagle/workbench";
const WORKBENCH_AUTHORITY =
  process.env.PROJECT_COCKPIT_WORKBENCH_AUTHORITY || "cockpit-local";
const WORKSPACE_AGENT_PORT = Number(process.env.PROJECT_COCKPIT_WORKSPACE_AGENT_PORT || 4371);
const WORKSPACE_AGENT_TIMEOUT_MS = Number(process.env.PROJECT_COCKPIT_WORKSPACE_AGENT_TIMEOUT_MS || 2500);
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl";
const BEAGLE_INTERNAL_URL =
  process.env.PROJECT_COCKPIT_BEAGLE_INTERNAL_URL ||
  "http://beagle-core.beagle.svc.cluster.local:8080";
const WORKBENCH_PROTOCOL = "beagle-terminal-v1";
const WORKBENCH_BRIDGE_VERSION = "beagle-warp-bridge-v0.2";

const AGENT_KINDS = new Set([
  "human",
  "claude-code",
  "codex",
  "cursor",
  "opencode",
  "kimi",
  "minimax",
  "qwen-coder",
  "glm-air",
  "palmyra-x5",
  "jamba",
  "pegasus",
  "lfm2",
  "custom",
]);

const SECRET_PATTERNS = [
  /(?:api[_-]?key|client[_-]?secret|refresh[_-]?token|access[_-]?token|password|passwd)\s*[:=]/i,
  /bearer\s+[a-z0-9._~+/=-]{16,}/i,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /\bsk-[a-zA-Z0-9]{20,}/,
  /\bghp_[a-zA-Z0-9]{20,}/,
  /\bxox[baprs]-[a-zA-Z0-9-]{20,}/,
];

const AUTO_MEMORY_COMMAND_PATTERNS = [
  /\b(codex|claude|claude-code|cursor|opencode|kimi)\b/i,
  /\b(swift test|xcodebuild|cargo test|npm test|pytest|pnpm test|bun test|build)\b/i,
  /\b(git diff|git show|git commit|git status|git log|diffstat)\b/i,
  /\b(kubectl|helm|terraform|rollout|deploy|apply)\b/i,
  /\b(plan|decision|summary|next action|sounio|beagle|paperrun)\b/i,
];

const AUTO_MEMORY_OUTPUT_PATTERNS = [
  /\b(BUILD SUCCEEDED|BUILD FAILED|tests? passed|tests? failed|FAILED|error|warning)\b/i,
  /\bdiff --git\b/i,
  /\b(decision|next action|summary|approval|approved|rejected)\b/i,
];

function cleanString(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "boolean") return String(value).trim();
  return "";
}

function safeId(value, fallback = "default") {
  const cleaned = cleanString(value)
    .toLowerCase()
    .replace(/[^a-z0-9_.:-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return cleaned || fallback;
}

function nowIso() {
  return new Date().toISOString();
}

function hashObject(payload) {
  return `sha256:${createHash("sha256").update(JSON.stringify(payload)).digest("hex")}`;
}

function bridgeMetadata({ sourceModel = "beagle", rendererHint = WORKBENCH_PROTOCOL, payload = {} } = {}) {
  const cleanSource = safeId(sourceModel, "beagle");
  return {
    sourceModel: cleanSource,
    source_model: cleanSource,
    bridgeVersion: WORKBENCH_BRIDGE_VERSION,
    bridge_version: WORKBENCH_BRIDGE_VERSION,
    rendererHint,
    renderer_hint: rendererHint,
    bridgeHash: hashObject({
      sourceModel: cleanSource,
      rendererHint,
      payload,
    }),
  };
}

function jsonResponse(handler) {
  return async (req, res) => {
    try {
      const payload = await handler(req, res);
      if (!res.headersSent) res.json(payload);
    } catch (error) {
      const status = Number(error?.statusCode || error?.status || 500);
      if (!res.headersSent) {
        res.status(status).json({
          error: error?.message || "workspace request failed",
          truthMode: "stale",
        });
      }
    }
  };
}

function workspaceDir(slug) {
  return path.join(WORKBENCH_DIR, safeId(slug));
}

function sessionsPath(slug) {
  return path.join(workspaceDir(slug), "sessions.json");
}

function blockLogPath(slug, sessionId) {
  return path.join(workspaceDir(slug), "sessions", safeId(sessionId), "blocks.ndjson");
}

async function ensureWorkspaceDir(slug, sessionId = "") {
  await fs.mkdir(workspaceDir(slug), { recursive: true, mode: 0o700 });
  if (sessionId) {
    await fs.mkdir(path.dirname(blockLogPath(slug, sessionId)), { recursive: true, mode: 0o700 });
  }
}

async function readJsonFile(filePath, fallback) {
  try {
    return JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return fallback;
    throw error;
  }
}

async function writeJsonFile(filePath, payload) {
  await fs.mkdir(path.dirname(filePath), { recursive: true, mode: 0o700 });
  await fs.writeFile(filePath, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
}

async function readSessions(slug) {
  return await readJsonFile(sessionsPath(slug), { sessions: [] });
}

async function writeSessions(slug, state) {
  await writeJsonFile(sessionsPath(slug), {
    ...state,
    updatedAt: nowIso(),
  });
}

function normalizePane(pane = {}, index = 0) {
  const kind = AGENT_KINDS.has(cleanString(pane.kind)) ? cleanString(pane.kind) : "human";
  return {
    id: cleanString(pane.id) || (index === 0 ? "pane-main" : `pane-${randomUUID()}`),
    title: cleanString(pane.title) || (kind === "human" ? "Shell" : kind),
    kind,
    status: cleanString(pane.status) || "idle",
    createdAt: cleanString(pane.createdAt) || nowIso(),
    lastAttachedAt: cleanString(pane.lastAttachedAt),
    cwd: cleanString(pane.cwd),
    agent: pane.agent || null,
  };
}

function normalizeSession(slug, session = {}) {
  const panes = Array.isArray(session.panes) && session.panes.length > 0
    ? session.panes.map(normalizePane)
    : [normalizePane({ id: "pane-main", kind: "human", title: "Shell" }, 0)];
  const base = {
    id: cleanString(session.id) || `wb-${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`,
    projectSlug: cleanString(session.projectSlug) || slug,
    title: cleanString(session.title) || "Sounio Workbench",
    status: cleanString(session.status) || "active",
    layout: cleanString(session.layout) || "notebook",
    createdAt: cleanString(session.createdAt) || nowIso(),
    updatedAt: cleanString(session.updatedAt) || nowIso(),
    lastAttachedAt: cleanString(session.lastAttachedAt),
    lastMemoryStatus: session.lastMemoryStatus || null,
    panes,
  };
  const bridge = bridgeMetadata({
    sourceModel: cleanString(session.sourceModel || session.source_model || "beagle"),
    rendererHint: cleanString(session.rendererHint || session.renderer_hint || WORKBENCH_PROTOCOL),
    payload: {
      id: base.id,
      projectSlug: base.projectSlug,
      panes: base.panes.map((pane) => pane.id),
    },
  });
  return {
    ...base,
    sourceModel: bridge.sourceModel,
    bridgeVersion: bridge.bridgeVersion,
    sessionHash: cleanString(session.sessionHash || session.session_hash) || bridge.bridgeHash,
    rendererHint: bridge.rendererHint,
  };
}

async function getOrCreateSession(slug, sessionId = "", body = {}) {
  await ensureWorkspaceDir(slug);
  const state = await readSessions(slug);
  const requestedId = cleanString(sessionId || body.session_id || body.sessionId);
  const found = state.sessions.find((entry) => cleanString(entry.id) === requestedId);
  if (found) return normalizeSession(slug, found);

  const session = normalizeSession(slug, {
    id: requestedId,
    title: cleanString(body.title),
    layout: cleanString(body.layout),
  });
  state.sessions = [session, ...state.sessions].slice(0, 80);
  await writeSessions(slug, state);
  await ensureWorkspaceDir(slug, session.id);
  return session;
}

async function updateSession(slug, sessionId, mutate) {
  const state = await readSessions(slug);
  const index = state.sessions.findIndex((entry) => cleanString(entry.id) === cleanString(sessionId));
  if (index < 0) {
    const error = new Error("workspace session not found");
    error.statusCode = 404;
    throw error;
  }
  const next = normalizeSession(slug, mutate(normalizeSession(slug, state.sessions[index])));
  next.updatedAt = nowIso();
  state.sessions[index] = next;
  await writeSessions(slug, state);
  return next;
}

function hasSecret(text) {
  const value = cleanString(text);
  if (!value) return false;
  return SECRET_PATTERNS.some((pattern) => pattern.test(value));
}

function stripControl(text) {
  return cleanString(text)
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "");
}

function detectAgentState(text) {
  const value = stripControl(text).toLowerCase();
  if (!value) return "";
  if (value.includes("running tests") || value.includes("test failed") || value.includes("test passed")) {
    return "running_tests";
  }
  if (value.includes("approval") || value.includes("allow this") || value.includes("proceed?")) {
    return "approval_wait";
  }
  if (value.includes("thinking") || value.includes("planning")) return "thinking";
  if (value.includes("done") || value.includes("complete")) return "done";
  return "";
}

function detectWorkbenchSignals(text) {
  const value = stripControl(text);
  const signals = [];
  if (/\b(swift test|xcodebuild|cargo test|npm test|pytest|tests? passed|tests? failed|BUILD SUCCEEDED|BUILD FAILED)\b/i.test(value)) {
    signals.push({ type: "test_detected", status: /fail|failed|BUILD FAILED/i.test(value) ? "failed" : "observed" });
  }
  if (/\bdiff --git\b|\bfiles? changed\b|\bdiffstat\b/i.test(value)) {
    signals.push({ type: "diff_detected", status: "observed" });
  }
  if (/\b(approval|approve|allow this|proceed\?|confirm)\b/i.test(value)) {
    signals.push({ type: "approval_requested", status: "pending" });
  }
  return signals;
}

function shouldAutoRememberBlock(block) {
  if (!block || block.privacyClass === "restricted_local_only") return false;
  const command = cleanString(block.command);
  const output = cleanString(block.outputPreview);
  if (!command && !output) return false;
  if (hasSecret(`${command}\n${output}`)) return false;
  if (/\bcommand not found\b/i.test(output)) return false;
  return AUTO_MEMORY_COMMAND_PATTERNS.some((pattern) => pattern.test(command)) ||
    AUTO_MEMORY_OUTPUT_PATTERNS.some((pattern) => pattern.test(output));
}

async function appendBlockEvent(slug, sessionId, event) {
  await ensureWorkspaceDir(slug, sessionId);
  await fs.appendFile(blockLogPath(slug, sessionId), `${JSON.stringify(event)}\n`, { mode: 0o600 });
}

async function readBlockEvents(slug, sessionId) {
  try {
    const raw = await fs.readFile(blockLogPath(slug, sessionId), "utf8");
    return raw
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => JSON.parse(line));
  } catch (error) {
    if (error?.code === "ENOENT") return [];
    throw error;
  }
}

function foldBlocks(events) {
  const byId = new Map();
  for (const event of events) {
    const blockId = cleanString(event.blockId || event.block_id);
    if (!blockId) continue;
    if (!byId.has(blockId)) {
      byId.set(blockId, {
        id: blockId,
        sessionId: cleanString(event.sessionId),
        paneId: cleanString(event.paneId),
        kind: "command",
        title: "",
        command: "",
        outputPreview: "",
        outputByteCount: 0,
        startedAt: cleanString(event.at) || nowIso(),
        finishedAt: "",
        durationMs: null,
        exitCode: null,
        status: "running",
        privacyClass: "sensitive",
        memoryStatus: "not_saved",
        tags: [],
        provenance: {},
        sourceModel: cleanString(event.sourceModel || event.source_model || "beagle"),
        bridgeVersion: cleanString(event.bridgeVersion || event.bridge_version || WORKBENCH_BRIDGE_VERSION),
        blockHash: "",
        sessionHash: cleanString(event.sessionHash || event.session_hash),
        rendererHint: cleanString(event.rendererHint || event.renderer_hint || WORKBENCH_PROTOCOL),
      });
    }
    const block = byId.get(blockId);
    if (event.type === "block_started") {
      block.kind = cleanString(event.kind) || block.kind;
      block.title = cleanString(event.title) || block.title;
      block.command = cleanString(event.command) || block.command;
      block.startedAt = cleanString(event.startedAt || event.at) || block.startedAt;
      block.status = "running";
      block.privacyClass = cleanString(event.privacyClass) || block.privacyClass;
      block.tags = Array.isArray(event.tags) ? event.tags : block.tags;
      block.provenance = event.provenance || block.provenance;
      block.sourceModel = cleanString(event.sourceModel || event.source_model) || block.sourceModel;
      block.bridgeVersion = cleanString(event.bridgeVersion || event.bridge_version) || block.bridgeVersion;
      block.blockHash = cleanString(event.blockHash || event.block_hash) || block.blockHash;
      block.sessionHash = cleanString(event.sessionHash || event.session_hash) || block.sessionHash;
      block.rendererHint = cleanString(event.rendererHint || event.renderer_hint) || block.rendererHint;
    }
    if (event.type === "block_output") {
      const chunk = String(event.data || "");
      block.outputByteCount += Buffer.byteLength(chunk);
      if (block.outputPreview.length < 12000) {
        block.outputPreview = `${block.outputPreview}${chunk}`.slice(0, 12000);
      }
    }
    if (event.type === "block_finished") {
      block.finishedAt = cleanString(event.finishedAt || event.at) || nowIso();
      block.durationMs = Number.isFinite(Number(event.durationMs)) ? Number(event.durationMs) : block.durationMs;
      block.exitCode = Number.isFinite(Number(event.exitCode)) ? Number(event.exitCode) : block.exitCode;
      block.status = cleanString(event.status) || "finished";
      block.privacyClass = cleanString(event.privacyClass) || block.privacyClass;
    }
    if (event.type === "memory") {
      block.memoryStatus = cleanString(event.status) || block.memoryStatus;
      block.memoryEventId = cleanString(event.memoryEventId);
      block.auditEventId = cleanString(event.auditEventId);
      block.memoryError = cleanString(event.error);
    }
    if (event.type === "secret_redacted") {
      block.privacyClass = "restricted_local_only";
      block.status = "blocked";
      block.memoryStatus = "blocked";
    }
  }
  for (const block of byId.values()) {
    if (!block.blockHash) {
      block.blockHash = hashObject({
        id: block.id,
        command: block.command,
        outputByteCount: block.outputByteCount,
        startedAt: block.startedAt,
      });
    }
  }
  return Array.from(byId.values()).sort((left, right) =>
    cleanString(right.startedAt).localeCompare(cleanString(left.startedAt))
  );
}

function workspaceSummaryFromProject(project = {}) {
  return {
    slug: cleanString(project.projectSlug || project.slug),
    title: cleanString(project.displayName || project.title || project.projectSlug || project.slug),
    namespace: cleanString(project.namespace || "beagle"),
    workspaceRoot: cleanString(project.workspaceRoot || "/workspace"),
    workspacePod: cleanString(project.workspacePod),
    workspaceContainer: cleanString(project.workspaceContainer || "workspace-ide"),
    branch: cleanString(project.branch),
    truthMode: cleanString(project.truthMode || "observed"),
  };
}

function resolveWorkspaceTarget(project = {}) {
  const slug = cleanString(project.projectSlug || project.slug || "sounio");
  const pod =
    cleanString(project.workspacePod) ||
    cleanString(project.workspaceWorkloadName) ||
    `${slug}-workspace-0`;
  return {
    namespace: cleanString(project.namespace || "beagle"),
    pod,
    container: cleanString(project.workspaceContainer || "workspace-ide"),
    workspaceRoot: cleanString(project.workspaceRoot || "/workspace"),
  };
}

function workspaceAgentServiceName(project = {}, slug = "sounio") {
  const explicit =
    cleanString(project.workspaceAgentService) ||
    cleanString(project.workspaceAgentServiceName) ||
    cleanString(project.workspaceService);
  if (explicit) return explicit;
  const pod = cleanString(project.workspacePod);
  if (pod) return pod.replace(/-\d+$/, "");
  const workload = cleanString(project.workspaceWorkloadName);
  if (workload) return workload;
  return `${safeId(slug)}-workspace`;
}

function workspaceAgentBaseUrl(project = {}, slug = "sounio") {
  const explicit = cleanString(project.workspaceAgentUrl || project.workspace_agent_url);
  if (explicit) return explicit.replace(/\/+$/, "");
  const namespace = cleanString(project.namespace || "beagle");
  const service = workspaceAgentServiceName(project, slug);
  const port = Number(project.workspaceAgentPort || project.workspace_agent_port || WORKSPACE_AGENT_PORT);
  return `http://${service}.${namespace}.svc.cluster.local:${port}`;
}

async function proxyWorkspaceAgentJson(req, res, project, agentPath) {
  if (WORKBENCH_AUTHORITY !== "workspace-agent") return false;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), WORKSPACE_AGENT_TIMEOUT_MS);
  try {
    const response = await fetch(`${workspaceAgentBaseUrl(project, req.params.slug)}${agentPath}`, {
      method: req.method,
      headers: {
        "accept": "application/json",
        "content-type": "application/json",
        "x-beagle-workbench-gateway": "project-cockpit",
      },
      body: ["GET", "HEAD"].includes(req.method) ? undefined : JSON.stringify(req.body || {}),
      signal: controller.signal,
    });
    const text = await response.text();
    let payload = {};
    try {
      payload = text ? JSON.parse(text) : {};
    } catch {
      payload = { raw: text };
    }
    if (!response.ok) {
      if (response.status === 404) return false;
      const error = new Error(payload?.error || `workspace_agent_http_${response.status}`);
      error.statusCode = response.status;
      throw error;
    }
    if (!res.headersSent) res.status(response.status).json(payload);
    return true;
  } catch (error) {
    console.warn(
      `[workbench] workspace-agent proxy ${agentPath} -> ${workspaceAgentBaseUrl(project, req.params.slug)} failed: ` +
      `${error?.name || "?"}/${error?.code || "?"}: ${error?.message || error} (cause: ${error?.cause?.code || error?.cause?.message || "n/a"})`
    );
    if (error?.name === "AbortError" || error?.code === "ECONNREFUSED" || error?.code === "ENOTFOUND") {
      return false;
    }
    if (String(error?.message || "").includes("fetch failed")) return false;
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

async function tryProxyWorkspaceAgentWebSocket(clientWs, project, { slug, sessionId, paneId }) {
  if (WORKBENCH_AUTHORITY !== "workspace-agent") return false;
  const base = workspaceAgentBaseUrl(project, slug).replace(/^http/, "ws");
  const upstreamUrl = `${base}/v1/sessions/${encodeURIComponent(sessionId)}/panes/${encodeURIComponent(paneId)}/stream`;
  return await new Promise((resolve) => {
    let settled = false;
    let opened = false;
    const upstream = new WebSocket(upstreamUrl, {
      handshakeTimeout: WORKSPACE_AGENT_TIMEOUT_MS,
      headers: {
        "x-beagle-workbench-gateway": "project-cockpit",
      },
    });
    const settle = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };
    const timer = setTimeout(() => {
      if (!opened) {
        upstream.terminate();
        settle(false);
      }
    }, WORKSPACE_AGENT_TIMEOUT_MS);
    upstream.on("open", () => {
      opened = true;
      clearTimeout(timer);
      upstream.on("message", (data, isBinary) => {
        if (clientWs.readyState === clientWs.OPEN) clientWs.send(data, { binary: isBinary });
      });
      clientWs.on("message", (data, isBinary) => {
        if (upstream.readyState === upstream.OPEN) upstream.send(data, { binary: isBinary });
      });
      upstream.on("close", () => {
        if (clientWs.readyState === clientWs.OPEN) clientWs.close();
      });
      clientWs.on("close", () => {
        if (upstream.readyState === upstream.OPEN) upstream.close();
      });
      upstream.on("error", (error) => {
        if (clientWs.readyState === clientWs.OPEN) {
          send(clientWs, {
            type: "exit",
            data: `workspace-agent stream error: ${error?.message || "unknown"}`,
          });
          clientWs.close();
        }
      });
      settle(true);
    });
    upstream.on("error", () => {
      clearTimeout(timer);
      if (!opened) settle(false);
    });
  });
}

function kubectlExecArgs(project, command, { tty = true } = {}) {
  const target = resolveWorkspaceTarget(project);
  const args = ["-n", target.namespace, "exec"];
  if (tty) args.push("-it");
  args.push(target.pod, "-c", target.container, "--", ...command);
  return args;
}

function commandTitle(command) {
  const stripped = stripControl(command).replace(/\s+/g, " ").trim();
  if (!stripped) return "Command";
  return stripped.length > 72 ? `${stripped.slice(0, 69)}...` : stripped;
}

function send(ws, payload) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}

async function rememberBlock({ slug, sessionId, block, requestBody = {} }) {
  const combined = `${block.command}\n${block.outputPreview}`;
  const at = nowIso();
  if (block.privacyClass === "restricted_local_only" || hasSecret(combined)) {
    await appendBlockEvent(slug, sessionId, {
      type: "memory",
      blockId: block.id,
      sessionId,
      paneId: block.paneId,
      at,
      status: "blocked",
      error: "restricted_or_secret_detected",
    });
    return {
      status: "blocked",
      privacyClass: "restricted_local_only",
      reason: "restricted_or_secret_detected",
    };
  }

  const output = cleanString(block.outputPreview).slice(0, 8000);
  const summary = cleanString(requestBody.summary) || [
    `Workbench terminal block: ${commandTitle(block.command)}`,
    output ? `Output preview: ${output.slice(0, 1400)}` : "No output captured.",
  ].join("\n\n");
  const payload = {
    source_platform: "beagle-apple",
    source_surface: "beagle-workbench",
    import_scope: "workbench_terminal_block",
    session_id: sessionId,
    project_ref: slug,
    privacy_class: "sensitive",
    title: commandTitle(block.command),
    confidence_score: 0.82,
    create_chronoself_commit: false,
    turns: [
      {
        role: "user",
        content: block.command || commandTitle(block.title),
        timestamp: block.startedAt,
        metadata: {
          terminal_block_id: block.id,
          pane_id: block.paneId,
          block_kind: block.kind,
        },
      },
      {
        role: "assistant",
        content: summary,
        timestamp: block.finishedAt || at,
        metadata: {
          terminal_block_id: block.id,
          output_byte_count: block.outputByteCount,
          exit_code: block.exitCode,
          duration_ms: block.durationMs,
        },
      },
    ],
    tags: [
      "workbench",
      "terminal-block",
      `project:${slug}`,
      `source_model:${block.sourceModel || "beagle"}`,
      block.kind ? `block:${block.kind}` : "block:command",
      ...(Array.isArray(block.tags) ? block.tags : []),
    ],
    metadata: {
      workspace_session_id: sessionId,
      terminal_block_id: block.id,
      pane_id: block.paneId,
      command_hash: createHash("sha256").update(block.command || "").digest("hex"),
      source_runtime: WORKBENCH_PROTOCOL,
      source_model: block.sourceModel || "beagle",
      bridge_version: block.bridgeVersion || WORKBENCH_BRIDGE_VERSION,
      block_hash: block.blockHash || hashObject({ id: block.id, command: block.command }),
      session_hash: block.sessionHash || hashObject({ sessionId }),
      renderer_hint: block.rendererHint || WORKBENCH_PROTOCOL,
      restricted_leak_check: "passed",
      remembered_from: "project-cockpit",
    },
  };

  const tokenResult = await fetchOperatorToken().catch((error) => ({ error: error.message }));
  if (tokenResult.error || !tokenResult.token) {
    await appendBlockEvent(slug, sessionId, {
      type: "memory",
      blockId: block.id,
      sessionId,
      paneId: block.paneId,
      at,
      status: "queued",
      error: tokenResult.error || "operator_token_unavailable",
    });
    return {
      status: "queued",
      reason: tokenResult.error || "operator_token_unavailable",
    };
  }

  const response = await fetch(`${BEAGLE_INTERNAL_URL}/api/exocortex/v1/memory/assisted-import`, {
    method: "POST",
    headers: {
      "accept": "application/json",
      "content-type": "application/json",
      "x-beagle-consumer": "beagle-operator",
      "authorization": `Bearer ${tokenResult.token}`,
    },
    body: JSON.stringify(payload),
  });

  const resultText = await response.text();
  let result = {};
  try {
    result = resultText ? JSON.parse(resultText) : {};
  } catch {
    result = { raw: resultText };
  }

  if (!response.ok) {
    await appendBlockEvent(slug, sessionId, {
      type: "memory",
      blockId: block.id,
      sessionId,
      paneId: block.paneId,
      at,
      status: "failed",
      error: result?.error || `core_http_${response.status}`,
    });
    return {
      status: "failed",
      error: result?.error || `core_http_${response.status}`,
    };
  }

  const memoryEventId = cleanString(
    result?.memory_event_id ||
    result?.memoryEventId ||
    result?.memory_event?.id ||
    result?.memoryEvent?.id
  );
  const auditEventId = cleanString(
    result?.audit_event_id ||
    result?.auditEventId ||
    result?.audit_event?.id ||
    result?.auditEvent?.id
  );

  await appendBlockEvent(slug, sessionId, {
    type: "memory",
    blockId: block.id,
    sessionId,
    paneId: block.paneId,
    at,
    status: "remembered",
    memoryEventId,
    auditEventId,
  });
  return {
    status: "remembered",
    memoryEventId,
    auditEventId,
  };
}

export function registerWorkspaceRoutes(app, deps = {}) {
  const getProjectOrThrow = deps.getProjectOrThrow || (async () => ({}));
  const readCatalog = deps.readCatalog || (async () => ({ projects: [] }));

  app.get("/api/workspaces", jsonResponse(async () => {
    const catalog = await readCatalog();
    const projects = Array.isArray(catalog?.projects) ? catalog.projects : [];
    return {
      workspaces: projects.map(workspaceSummaryFromProject).filter((entry) => entry.slug),
      truthMode: projects.length > 0 ? "observed" : "declared",
    };
  }));

  app.get("/api/workspaces/:slug/sessions", jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    if (await proxyWorkspaceAgentJson(req, res, project, "/v1/sessions")) return undefined;
    await ensureWorkspaceDir(req.params.slug);
    const state = await readSessions(req.params.slug);
    return {
      projectSlug: req.params.slug,
      sessions: state.sessions.map((entry) => normalizeSession(req.params.slug, entry)),
    };
  }));

  app.post("/api/workspaces/:slug/sessions", jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    if (await proxyWorkspaceAgentJson(req, res, project, "/v1/sessions")) return undefined;
    const session = await getOrCreateSession(req.params.slug, "", req.body || {});
    return { session };
  }));

  app.get("/api/workspaces/:slug/agents/registry", jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    if (await proxyWorkspaceAgentJson(req, res, project, "/v1/agents/registry")) return undefined;
    return {
      projectSlug: req.params.slug,
      registryVersion: "beagle-agent-ecology-v3.5",
      truthMode: "stale",
      roles: [],
      visibleRoles: [],
      scoutRoles: [],
      error: "workspace-agent registry unavailable; cockpit-local fallback does not own Agent Fabric",
    };
  }));

  app.post("/api/workspaces/:slug/agents/route", jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    if (await proxyWorkspaceAgentJson(req, res, project, "/v1/agents/route")) return undefined;
    return {
      projectSlug: req.params.slug,
      truthMode: "stale",
      error: "workspace-agent router unavailable; cockpit-local fallback does not route model ecology lanes",
    };
  }));

  app.post("/api/workspaces/:slug/agents/:roleOrKind/start", jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    if (await proxyWorkspaceAgentJson(req, res, project, `/v1/agents/${encodeURIComponent(req.params.roleOrKind)}/start`)) return undefined;
    const error = new Error("workspace-agent start unavailable; cockpit-local fallback cannot start Agent Fabric lanes");
    error.statusCode = 503;
    throw error;
  }));

  // POST /api/workspaces/:slug/agents/:roleOrKind/provider-config
  // Receives {slot?, base_url, api_key, model?} from the iOS set-up form and proxies
  // the write to the workspace-agent, which is the only pod that owns the PVC.
  // api_key is NEVER logged or echoed back; the proxy forwards it in the request body
  // to the agent over the cluster-internal HTTP path only.
  // On proxy success the agent returns a MASKED view (apiKeyConfigured:true, no raw key).
  // On proxy-false (agent unreachable or cockpit-local mode) we return 503 — never a
  // stale 200 that the iOS client would silently misinterpret as success.
  app.post("/api/workspaces/:slug/agents/:roleOrKind/provider-config", jsonResponse(async (req, res) => {
    const slug = safeId(req.params.slug, "default");
    const roleOrKind = cleanString(req.params.roleOrKind);

    // Require only base_url here; the workspace-agent decides whether api_key is
    // mandatory (it is for *_API_KEY slots, optional for self-hosted *_PROVIDER_URL
    // slots). Keeping that authority in the agent avoids blocking base-URL-only
    // (qwen/glm local) lanes that need no secret. api_key is never logged.
    const baseUrl = cleanString(req.body?.base_url || req.body?.baseUrl);
    if (!baseUrl) {
      const error = new Error("provider-config missing required field: base_url");
      error.statusCode = 400;
      throw error;
    }

    // Proxy the write to the workspace-agent — it owns the PVC and the in-process
    // override map. The proxy helper adds x-beagle-workbench-gateway: project-cockpit
    // and forwards method + body verbatim.
    const project = await getProjectOrThrow(slug);
    const proxied = await proxyWorkspaceAgentJson(
      req,
      res,
      project,
      `/v1/agents/${encodeURIComponent(roleOrKind)}/provider-config`
    );
    if (proxied) return undefined; // agent responded; proxy already sent the reply.

    // Proxy returned false: WORKBENCH_AUTHORITY !== "workspace-agent" or agent
    // is unreachable.  Never return a fake 200 — the iOS form must not appear to
    // succeed when nothing was persisted.
    const error = new Error(
      "workspace-agent provider-config unavailable; cannot persist credentials without a live workspace-agent"
    );
    error.statusCode = 503;
    throw error;
  }));

  app.get("/api/workspaces/:slug/sessions/:sessionId", jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    if (await proxyWorkspaceAgentJson(req, res, project, `/v1/sessions/${encodeURIComponent(req.params.sessionId)}`)) return undefined;
    const session = await getOrCreateSession(req.params.slug, req.params.sessionId);
    return { session };
  }));

  app.post("/api/workspaces/:slug/sessions/:sessionId/panes", jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    if (await proxyWorkspaceAgentJson(req, res, project, `/v1/sessions/${encodeURIComponent(req.params.sessionId)}/panes`)) return undefined;
    await getOrCreateSession(req.params.slug, req.params.sessionId);
    const pane = normalizePane({
      id: cleanString(req.body?.id) || `pane-${randomUUID().slice(0, 10)}`,
      kind: cleanString(req.body?.kind) || "human",
      title: cleanString(req.body?.title),
      cwd: cleanString(req.body?.cwd),
    });
    const session = await updateSession(req.params.slug, req.params.sessionId, (current) => {
      const panes = current.panes.some((entry) => entry.id === pane.id)
        ? current.panes.map((entry) => entry.id === pane.id ? pane : entry)
        : [...current.panes, pane];
      return { ...current, panes };
    });
    return { pane, session };
  }));

  app.get("/api/workspaces/:slug/sessions/:sessionId/blocks", jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    if (await proxyWorkspaceAgentJson(req, res, project, `/v1/sessions/${encodeURIComponent(req.params.sessionId)}/blocks`)) return undefined;
    await getOrCreateSession(req.params.slug, req.params.sessionId);
    const events = await readBlockEvents(req.params.slug, req.params.sessionId);
    return {
      projectSlug: req.params.slug,
      sessionId: req.params.sessionId,
      blocks: foldBlocks(events),
    };
  }));

  app.post("/api/workspaces/:slug/sessions/:sessionId/blocks/:blockId/remember", jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    if (await proxyWorkspaceAgentJson(req, res, project, `/v1/sessions/${encodeURIComponent(req.params.sessionId)}/blocks/${encodeURIComponent(req.params.blockId)}/remember`)) return undefined;
    await getOrCreateSession(req.params.slug, req.params.sessionId);
    const blocks = foldBlocks(await readBlockEvents(req.params.slug, req.params.sessionId));
    const block = blocks.find((entry) => entry.id === req.params.blockId);
    if (!block) {
      const error = new Error("terminal block not found");
      error.statusCode = 404;
      throw error;
    }
    const memory = await rememberBlock({
      slug: req.params.slug,
      sessionId: req.params.sessionId,
      block,
      requestBody: req.body || {},
    });
    await updateSession(req.params.slug, req.params.sessionId, (current) => ({
      ...current,
      lastMemoryStatus: {
        blockId: block.id,
        status: memory.status,
        privacyClass: memory.privacyClass,
        reason: memory.reason,
        error: memory.error,
        memoryEventId: memory.memoryEventId,
        auditEventId: memory.auditEventId,
        sourceModel: block.sourceModel || "beagle",
        bridgeVersion: block.bridgeVersion || WORKBENCH_BRIDGE_VERSION,
        updatedAt: nowIso(),
      },
    }));
    return { blockId: block.id, memory };
  }));
}

export function registerWorkspaceWebSocket(wss, deps = {}) {
  const getProjectOrThrow = deps.getProjectOrThrow || (async () => ({}));

  wss.on("connection", async (ws, req) => {
    const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
    const match = url.pathname.match(/^\/ws\/workspaces\/([^/]+)\/sessions\/([^/]+)\/panes\/([^/]+)$/);
    if (!match) {
      send(ws, { type: "error", data: "invalid workspace websocket path" });
      ws.close();
      return;
    }
    const [, slug, sessionId, paneId] = match.map(decodeURIComponent);
    let project;
    try {
      project = await getProjectOrThrow(slug);
      if (await tryProxyWorkspaceAgentWebSocket(ws, project, { slug, sessionId, paneId })) {
        return;
      }
      const session = await getOrCreateSession(slug, sessionId);
      await updateSession(slug, session.id, (current) => ({
        ...current,
        lastAttachedAt: nowIso(),
        panes: current.panes.map((pane) =>
          pane.id === paneId ? { ...pane, status: "attached", lastAttachedAt: nowIso() } : pane
        ),
      }));
    } catch (error) {
      send(ws, { type: "error", data: error?.message || "workspace attach failed" });
      ws.close();
      return;
    }

    const target = resolveWorkspaceTarget(project);
    const shellCommand =
      'cd "$WORKSPACE_ROOT" && export TERM="${TERM:-xterm-256color}" && export BEAGLE_WORKBENCH=1 && exec "${SHELL:-/bin/bash}" -l';
    const proc = pty.spawn(
      KUBECTL,
      kubectlExecArgs(
        project,
        [
          "env",
          `WORKSPACE_ROOT=${target.workspaceRoot}`,
          `TERM=xterm-256color`,
          "sh",
          "-lc",
          shellCommand,
        ],
        { tty: true }
      ),
      {
        name: "xterm-256color",
        cols: 120,
        rows: 34,
        cwd: process.cwd(),
        env: process.env,
      }
    );

    let inputBuffer = "";
    let activeBlock = null;

    async function rememberBlockById(blockId, trigger = "manual") {
      const blocks = foldBlocks(await readBlockEvents(slug, sessionId));
      const block = blocks.find((entry) => entry.id === blockId);
      if (!block) return null;
      if (trigger === "auto" && !shouldAutoRememberBlock(block)) return null;
      const memory = await rememberBlock({
        slug,
        sessionId,
        block,
        requestBody: { summary: trigger === "auto" ? "Auto-safe Workbench memory import." : "" },
      });
      await updateSession(slug, sessionId, (current) => ({
        ...current,
        lastMemoryStatus: {
          blockId,
          status: memory.status,
          privacyClass: memory.privacyClass,
          reason: memory.reason,
          error: memory.error,
          memoryEventId: memory.memoryEventId,
          auditEventId: memory.auditEventId,
          updatedAt: nowIso(),
        },
      })).catch(() => {});
      const event = {
        type: "memory_imported",
        sessionId,
        paneId,
        blockId,
        at: nowIso(),
        trigger,
        status: memory.status,
        memoryEventId: memory.memoryEventId,
        auditEventId: memory.auditEventId,
        sourceModel: block.sourceModel || "beagle",
        bridgeVersion: block.bridgeVersion || WORKBENCH_BRIDGE_VERSION,
      };
      await appendBlockEvent(slug, sessionId, event);
      send(ws, event);
      return memory;
    }

    async function finishActiveBlock(status = "finished", exitCode = null) {
      if (!activeBlock) return;
      const finishedBlockId = activeBlock.id;
      const finishedAt = nowIso();
      const event = {
        type: "block_finished",
        blockId: finishedBlockId,
        sessionId,
        paneId,
        at: finishedAt,
        finishedAt,
        durationMs: Date.now() - activeBlock.startedAtMs,
        exitCode,
        status,
        privacyClass: activeBlock.privacyClass,
        sourceModel: activeBlock.sourceModel,
        bridgeVersion: WORKBENCH_BRIDGE_VERSION,
        blockHash: activeBlock.blockHash,
        sessionHash: activeBlock.sessionHash,
        rendererHint: WORKBENCH_PROTOCOL,
      };
      await appendBlockEvent(slug, sessionId, event);
      send(ws, event);
      activeBlock = null;
      if (!["detached", "terminal_exit"].includes(status)) {
        void rememberBlockById(finishedBlockId, "auto").catch((error) => {
          send(ws, {
            type: "memory_imported",
            sessionId,
            paneId,
            blockId: finishedBlockId,
            at: nowIso(),
            trigger: "auto",
            status: "failed",
            error: error?.message || "auto_memory_failed",
          });
        });
      }
    }

    async function startBlockFromInput(commandText) {
      const command = stripControl(commandText);
      if (!command || command.length > 6000) return;
      await finishActiveBlock("observed_no_exit", null);
      const restricted = hasSecret(command);
      const blockId = `block-${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`;
      const startedAt = nowIso();
      activeBlock = {
        id: blockId,
        command: restricted ? "[restricted command redacted]" : command,
        startedAtMs: Date.now(),
        privacyClass: restricted ? "restricted_local_only" : "sensitive",
        sourceModel: "beagle",
        sessionHash: hashObject({ slug, sessionId }),
        blockHash: hashObject({ blockId, sessionId, paneId, command }),
      };
      const bridge = bridgeMetadata({
        sourceModel: "beagle",
        rendererHint: WORKBENCH_PROTOCOL,
        payload: { blockId, sessionId, paneId, command },
      });
      const event = {
        type: "block_started",
        blockId,
        sessionId,
        paneId,
        at: startedAt,
        startedAt,
        kind: "command",
        title: restricted ? "Restricted command" : commandTitle(command),
        command: activeBlock.command,
        privacyClass: activeBlock.privacyClass,
        tags: ["workbench", "terminal-block", `project:${slug}`, "source_model:beagle"],
        sourceModel: "beagle",
        bridgeVersion: WORKBENCH_BRIDGE_VERSION,
        blockHash: activeBlock.blockHash,
        sessionHash: activeBlock.sessionHash,
        rendererHint: WORKBENCH_PROTOCOL,
        provenance: {
          protocol: WORKBENCH_PROTOCOL,
          bridge_version: bridge.bridgeVersion,
          bridge_hash: bridge.bridgeHash,
          source_model: "beagle",
          renderer_hint: WORKBENCH_PROTOCOL,
          source_surface: "beagle-workbench",
          workspace_pod: target.pod,
        },
      };
      await appendBlockEvent(slug, sessionId, event);
      send(ws, event);
      if (restricted) {
        const redacted = {
          type: "secret_redacted",
          blockId,
          sessionId,
          paneId,
          at: nowIso(),
          reason: "input_secret_detected",
        };
        await appendBlockEvent(slug, sessionId, redacted);
        send(ws, redacted);
      }
    }

    proc.onData(async (data) => {
      send(ws, { type: "data", data });
      const rawEvent = {
        type: "raw_output",
        sessionId,
        paneId,
        at: nowIso(),
        data,
        sourceModel: "beagle",
        bridgeVersion: WORKBENCH_BRIDGE_VERSION,
      };
      send(ws, rawEvent);
      if (activeBlock) {
        if (hasSecret(data)) {
          activeBlock.privacyClass = "restricted_local_only";
          const redacted = {
            type: "secret_redacted",
            blockId: activeBlock.id,
            sessionId,
            paneId,
            at: nowIso(),
            reason: "output_secret_detected",
          };
          await appendBlockEvent(slug, sessionId, redacted);
          send(ws, redacted);
        }
        const blockEvent = {
          type: "block_output",
          blockId: activeBlock.id,
          sessionId,
          paneId,
          at: nowIso(),
          data: activeBlock.privacyClass === "restricted_local_only" && hasSecret(data)
            ? "[restricted output redacted]"
            : data,
          sourceModel: activeBlock.sourceModel,
          bridgeVersion: WORKBENCH_BRIDGE_VERSION,
        };
        await appendBlockEvent(slug, sessionId, blockEvent);
        send(ws, blockEvent);
      }
      const agentState = detectAgentState(data);
      if (agentState) {
        const event = {
          type: "agent_state",
          sessionId,
          paneId,
          at: nowIso(),
          state: agentState,
          sourceModel: "beagle",
          bridgeVersion: WORKBENCH_BRIDGE_VERSION,
        };
        await appendBlockEvent(slug, sessionId, event);
        send(ws, event);
      }
      for (const signal of detectWorkbenchSignals(data)) {
        const event = {
          ...signal,
          sessionId,
          paneId,
          at: nowIso(),
          sourceModel: "beagle",
          bridgeVersion: WORKBENCH_BRIDGE_VERSION,
        };
        await appendBlockEvent(slug, sessionId, event);
        send(ws, event);
      }
    });

    proc.onExit(async ({ exitCode, signal }) => {
      await finishActiveBlock("terminal_exit", exitCode);
      send(ws, {
        type: "exit",
        data: signal ? `terminal exited (${exitCode}, signal ${signal})` : `terminal exited (${exitCode})`,
      });
      ws.close();
    });

    send(ws, {
      type: "ready",
      data: {
        projectSlug: slug,
        sessionId,
        paneId,
        protocol: WORKBENCH_PROTOCOL,
        sourceModel: "beagle",
        bridgeVersion: WORKBENCH_BRIDGE_VERSION,
        rendererHint: WORKBENCH_PROTOCOL,
      },
    });

    ws.on("message", async (payload) => {
      try {
        const message = JSON.parse(String(payload));
        if (message.type === "input" || message.type === "paste") {
          const text = String(message.data || "");
          inputBuffer += text;
          if (text.includes("\n") || text.includes("\r")) {
            const command = inputBuffer.split(/\r?\n/)[0];
            inputBuffer = "";
            await startBlockFromInput(command);
          }
          proc.write(text);
          return;
        }
        if (message.type === "resize") {
          proc.resize(Number(message.cols || 120), Number(message.rows || 34));
          return;
        }
        if (message.type === "signal") {
          const signal = cleanString(message.signal || "SIGINT");
          if (signal === "SIGINT") proc.write("\u0003");
          if (signal === "SIGTERM") proc.kill();
          return;
        }
        if (message.type === "stop_process") {
          proc.kill();
          return;
        }
        if (message.type === "focus") {
          send(ws, {
            type: "warp_bridge_event",
            sessionId,
            paneId,
            at: nowIso(),
            event: "focus",
            sourceModel: "beagle",
            bridgeVersion: WORKBENCH_BRIDGE_VERSION,
          });
          return;
        }
        if (message.type === "approve") {
          await appendBlockEvent(slug, sessionId, {
            type: "approval_requested",
            sessionId,
            paneId,
            at: nowIso(),
            status: "approved",
            sourceModel: "beagle",
            bridgeVersion: WORKBENCH_BRIDGE_VERSION,
          });
          proc.write(String(message.data || "y\n"));
          return;
        }
        if (message.type === "start_process") {
          const command = cleanString(message.command);
          if (command) {
            await startBlockFromInput(command);
            proc.write(`${command}\n`);
          }
          return;
        }
        if (message.type === "mark_block") {
          await finishActiveBlock("marked", null);
          return;
        }
        if (message.type === "attach_block_to_memory") {
          const blockId = cleanString(message.blockId || message.block_id);
          if (blockId) await rememberBlockById(blockId, "manual");
          return;
        }
      } catch {
        const text = String(payload);
        proc.write(text);
      }
    });

    ws.on("close", async () => {
      await finishActiveBlock("detached", null).catch(() => {});
      proc.kill();
    });
  });
}
