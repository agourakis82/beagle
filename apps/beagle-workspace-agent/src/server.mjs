import express from "express";
import http from "node:http";
import { randomUUID, createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { WebSocket, WebSocketServer } from "ws";
import {
  WORKBENCH_BRIDGE_VERSION,
  WORKBENCH_PROTOCOL,
  appendBlockEvent,
  agentRegistry,
  bridgeMetadata,
  cleanString,
  commandTitle,
  detectAgentState,
  detectWorkbenchSignals,
  findAgentRole,
  foldBlocks,
  getOrCreateSession,
  hasSecret,
  hashObject,
  normalizePane,
  nowIso,
  readBlockEvents,
  readProviderConfig,
  writeProviderConfig,
  maskProviderConfig,
  readSessions,
  routeAgentTask,
  safeId,
  shouldAutoRememberBlock,
  stripControl,
  updateSession,
} from "./workbench-core.mjs";

const app = express();
const port = Number(process.env.BEAGLE_WORKSPACE_AGENT_PORT || 4371);
const host = process.env.BEAGLE_WORKSPACE_AGENT_HOST || "0.0.0.0";
const slug = process.env.PROJECT_SLUG || process.env.BEAGLE_WORKSPACE_SLUG || "sounio";
const rootDir = process.env.BEAGLE_WORKBENCH_DIR || "/workspace/.beagle/workbench";
const workspaceRoot = process.env.BEAGLE_WORKSPACE_ROOT || process.env.PROJECT_WORKSPACE_ROOT || `/workspace/${slug}`;
const supervisorUrl = process.env.BEAGLE_PTY_SUPERVISOR_URL || "http://127.0.0.1:4372";
const beagleCoreUrl =
  process.env.BEAGLE_CORE_URL ||
  process.env.PROJECT_COCKPIT_BEAGLE_INTERNAL_URL ||
  "http://beagle-core.beagle.svc.cluster.local:8080";
const apiToken = process.env.BEAGLE_OPERATOR_API_TOKEN || process.env.BEAGLE_CORE_API_TOKEN || process.env.BEAGLE_API_TOKEN || "";
const beagleConsumerHeaderName = process.env.BEAGLE_CORE_CONSUMER_HEADER_NAME || "X-Beagle-Consumer";
const beagleConsumerHeaderValue = process.env.BEAGLE_CORE_CONSUMER_HEADER_VALUE || "beagle-operator";

// In-process view of stored provider-config slots, keyed by slot id.
// Holds only non-secret metadata so readinessForRole stays synchronous and
// gives read-your-write consistency without a file watcher. Raw apiKey is
// never kept here; the launch path reads it from the 0600 file at spawn time.
// Shape: slotId -> { role, env, baseUrl, model, apiKeyConfigured, updatedAt }
const providerConfigOverrides = new Map();

function applyProviderConfigToOverrides(cfg) {
  for (const [slotId, slot] of Object.entries(cfg?.slots || {})) {
    if (!slotId || !slot || typeof slot !== "object") continue;
    providerConfigOverrides.set(slotId, {
      role: slot.role || null,
      env: slot.env || null,
      baseUrl: slot.baseUrl || null,
      model: slot.model || null,
      apiKeyConfigured: Boolean(slot.apiKey),
      updatedAt: slot.updatedAt || null,
    });
  }
}

async function hydrateProviderConfigOverrides() {
  try {
    const cfg = await readProviderConfig(rootDir, slug);
    applyProviderConfigToOverrides(cfg);
  } catch (error) {
    // Hydration is best-effort; a missing/corrupt file just means no overrides
    // and lanes fall back to the process.env probe.
    console.warn(`provider-config hydration skipped: ${error?.message || error}`);
  }
}

// Resolve the override entry a probe.env belongs to. The stored slot records
// the probe env it satisfies (slot.env), so we match on that first, then fall
// back to a slot id equal to the env (defensive, should not normally happen).
function overrideForProbeEnv(envName) {
  if (!envName) return null;
  // A slot satisfies its probe env when it has the value that env represents:
  // an API key for *_API_KEY envs, or a base URL for *_PROVIDER_URL / *_BASE_URL
  // envs (self-hosted / local providers need no secret).
  const baseUrlOnly = /_PROVIDER_URL$/.test(envName) || /_BASE_URL$/.test(envName);
  for (const entry of providerConfigOverrides.values()) {
    if (entry.env !== envName) continue;
    if (baseUrlOnly ? Boolean(entry.baseUrl) : entry.apiKeyConfigured) return entry;
  }
  return null;
}

app.use(express.json({ limit: "2mb" }));

function jsonRoute(handler) {
  return async (req, res) => {
    try {
      res.json(await handler(req, res));
    } catch (error) {
      res.status(Number(error?.statusCode || error?.status || 500)).json({
        error: error?.message || "workspace agent request failed",
        authority: "workspace-agent",
      });
    }
  };
}

function assertSlug(projectSlug) {
  if (cleanString(projectSlug) !== slug) {
    const error = new Error(`workspace agent owns ${slug}, not ${projectSlug}`);
    error.statusCode = 404;
    throw error;
  }
}

async function supervisorJson(path, body = null, method = body ? "POST" : "GET") {
  const response = await fetch(`${supervisorUrl}${path}`, {
    method,
    headers: body ? { "content-type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let parsed = {};
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = { raw: text };
  }
  if (!response.ok) {
    const error = new Error(parsed?.error || `supervisor_http_${response.status}`);
    error.statusCode = response.status;
    throw error;
  }
  return parsed;
}

async function supervisorStatus() {
  try {
    const health = await supervisorJson("/v1/health");
    return {
      status: "healthy",
      runtime: "beagle-pty-supervisor-v1",
      panes: Number(health.panes || 0),
      url: supervisorUrl,
      updatedAt: nowIso(),
    };
  } catch (error) {
    return {
      status: "degraded",
      runtime: "beagle-pty-supervisor-v1",
      panes: 0,
      url: supervisorUrl,
      error: error?.message || "supervisor_unreachable",
      updatedAt: nowIso(),
    };
  }
}

async function authorityStatus() {
  return {
    authority: "workspace-agent",
    fallback: "cockpit-local",
    persistence: "workspace-pvc",
    workbenchDir: rootDir,
    workspaceRoot,
    protocol: WORKBENCH_PROTOCOL,
    bridgeVersion: WORKBENCH_BRIDGE_VERSION,
    supervisor: await supervisorStatus(),
    updatedAt: nowIso(),
  };
}

async function attachAuthority(session) {
  return {
    ...session,
    authorityStatus: await authorityStatus(),
  };
}

function commandExists(command) {
  const clean = cleanString(command).split(/\s+/)[0];
  if (!clean) return false;
  const quoted = `'${clean.replace(/'/g, "'\\''")}'`;
  const result = spawnSync("sh", ["-lc", `command -v ${quoted}`], {
    stdio: "ignore",
  });
  return result.status === 0;
}

function readinessForRole(entry) {
  const probe = entry?.readinessProbe || {};
  if (!entry) return { status: "unknown", reason: "agent role not found" };
  if (probe.type === "builtin") return { status: "ready", reason: "builtin workspace lane" };
  if (probe.type === "command") {
    const command = cleanString(probe.command || entry.launchCommand);
    return commandExists(command)
      ? { status: "ready", reason: `${command} is on PATH`, command }
      : { status: "needs_setup", reason: `${command || entry.kind} is not on PATH`, command };
  }
  if (probe.type === "provider_slot") {
    const envName = cleanString(probe.env);
    const override = overrideForProbeEnv(envName);
    if (override) {
      return {
        status: "ready",
        reason: `${envName} configured via workspace setup`,
        env: envName,
        source: "provider_config",
      };
    }
    return envName && process.env[envName]
      ? { status: "ready", reason: `${envName} is configured`, env: envName, source: "env" }
      : { status: "needs_setup", reason: envName ? `${envName} is not configured` : "provider credentials not configured", env: envName };
  }
  if (probe.type === "local_model") {
    return { status: "needs_setup", reason: "local model runtime must be explicitly configured", model: probe.model };
  }
  return { status: "unknown", reason: "no readiness probe" };
}

// Build the env vars a configured slot injects into a spawned pane process.
// Encodes the per-runtime mapping: the slot's own probe env (slot.env) carries
// either the API key (e.g. MINIMAX_API_KEY) or the base URL (e.g.
// QWEN_PROVIDER_URL / GLM_PROVIDER_URL), and openai-compatible tools also read
// OPENAI_API_KEY / OPENAI_BASE_URL / OPENAI_MODEL. Secrets travel only in this
// object (passed via the spawn env), never echoed into block-captured output.
function buildProviderEnv(slot) {
  if (!slot || typeof slot !== "object") return null;
  const envName = cleanString(slot.env);
  const baseUrl = cleanString(slot.baseUrl);
  const apiKey = cleanString(slot.apiKey);
  const model = cleanString(slot.model);
  // A base-URL-only slot (self-hosted / local provider) still configures the
  // lane even with no key; an API-key slot needs the key. Nothing to inject if
  // neither is present.
  if (!apiKey && !baseUrl) return null;
  const env = {};
  // The probe env is satisfied either by the key (API-key slots) or by the
  // base URL (provider-URL slots). Decide by the env name suffix.
  if (envName) {
    if (/_PROVIDER_URL$/.test(envName) || /_BASE_URL$/.test(envName)) {
      if (baseUrl) env[envName] = baseUrl;
    } else if (apiKey) {
      env[envName] = apiKey;
    }
  }
  // OpenAI-compatible fallbacks so generic CLIs/SDKs authenticate.
  if (apiKey) env.OPENAI_API_KEY = apiKey;
  if (baseUrl) env.OPENAI_BASE_URL = baseUrl;
  if (model) env.OPENAI_MODEL = model;
  return Object.keys(env).length ? env : null;
}

function registryWithReadiness() {
  return agentRegistry().map((entry) => ({
    ...entry,
    readiness: readinessForRole(entry),
  }));
}

async function rememberBlock({ sessionId, block, requestBody = {} }) {
  const at = nowIso();
  const combined = `${block.command}\n${block.outputPreview}`;
  if (block.privacyClass === "restricted_local_only" || hasSecret(combined)) {
    await appendBlockEvent(rootDir, slug, sessionId, {
      type: "memory",
      blockId: block.id,
      sessionId,
      paneId: block.paneId,
      at,
      status: "blocked",
      error: "restricted_or_secret_detected",
    });
    return { status: "blocked", privacyClass: "restricted_local_only", reason: "restricted_or_secret_detected" };
  }
  if (!apiToken) {
    await appendBlockEvent(rootDir, slug, sessionId, {
      type: "memory",
      blockId: block.id,
      sessionId,
      paneId: block.paneId,
      at,
      status: "queued",
      error: "beagle_api_token_unavailable",
    });
    return { status: "queued", reason: "beagle_api_token_unavailable" };
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
        metadata: { terminal_block_id: block.id, pane_id: block.paneId, block_kind: block.kind },
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
      remembered_from: "beagle-workspace-agent",
      authority: "workspace-agent",
    },
  };

  const response = await fetch(`${beagleCoreUrl}/api/exocortex/v1/memory/assisted-import`, {
    method: "POST",
    headers: {
      accept: "application/json",
      "content-type": "application/json",
      [beagleConsumerHeaderName]: beagleConsumerHeaderValue,
      authorization: `Bearer ${apiToken}`,
    },
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  let result = {};
  try {
    result = text ? JSON.parse(text) : {};
  } catch {
    result = { raw: text };
  }
  if (!response.ok) {
    await appendBlockEvent(rootDir, slug, sessionId, {
      type: "memory",
      blockId: block.id,
      sessionId,
      paneId: block.paneId,
      at,
      status: "failed",
      error: result?.error || `core_http_${response.status}`,
    });
    return { status: "failed", error: result?.error || `core_http_${response.status}` };
  }
  const memoryEventId = cleanString(result?.memory_event_id || result?.memoryEventId || result?.memory_event?.id);
  const auditEventId = cleanString(result?.audit_event_id || result?.auditEventId || result?.audit_event?.id);
  await appendBlockEvent(rootDir, slug, sessionId, {
    type: "memory",
    blockId: block.id,
    sessionId,
    paneId: block.paneId,
    at,
    status: "remembered",
    memoryEventId,
    auditEventId,
  });
  return { status: "remembered", memoryEventId, auditEventId };
}

app.get("/v1/health", jsonRoute(async () => ({
  status: "ok",
  authority: "workspace-agent",
  slug,
  workbenchDir: rootDir,
})));

app.get("/v1/ready", jsonRoute(async () => ({
  status: (await supervisorStatus()).status === "healthy" ? "ready" : "degraded",
  authority: await authorityStatus(),
})));

app.get("/v1/agents/registry", jsonRoute(async () => {
  const registry = registryWithReadiness();
  return {
    projectSlug: slug,
    registryVersion: "beagle-agent-ecology-v3.5",
    arousalModel: "lc-ne-adaptive-gain-metaphor",
    authority: await authorityStatus(),
    roles: registry,
    visibleRoles: registry.filter((entry) => entry.visible !== false).map((entry) => entry.role),
    scoutRoles: registry.filter((entry) => entry.visible === false).map((entry) => entry.role),
    updatedAt: nowIso(),
  };
}));

app.post("/v1/agents/route", jsonRoute(async (req) => {
  const decision = routeAgentTask({
    ...(req.body || {}),
    project_slug: slug,
  });
  return {
    projectSlug: slug,
    decision,
    authority: await authorityStatus(),
  };
}));

app.post("/v1/agents/:roleOrKind/start", jsonRoute(async (req) => {
  const role = findAgentRole(req.params.roleOrKind);
  if (!role) {
    const error = new Error(`unknown agent role: ${req.params.roleOrKind}`);
    error.statusCode = 404;
    throw error;
  }
  const decision = routeAgentTask({
    ...(req.body || {}),
    task: cleanString(req.body?.task || req.body?.prompt || role.roleSummary || role.title),
    project_slug: slug,
    arousal_mode: req.body?.arousal_mode || role.arousalRole,
  });
  const readiness = readinessForRole(role);
  const session = await getOrCreateSession(rootDir, slug, cleanString(req.body?.session_id || req.body?.sessionId), req.body || {});
  const providerSlot = cleanString(req.body?.provider_slot || req.body?.providerSlot) ||
    cleanString(role.providerSlots?.[0]?.id);
  const selectedSlot = role.providerSlots?.find((slot) => slot.id === providerSlot) || role.providerSlots?.[0] || {};
  const pane = normalizePane({
    id: cleanString(req.body?.pane_id || req.body?.paneId) || `pane-${role.kind}-${randomUUID().slice(0, 8)}`,
    kind: role.kind,
    title: cleanString(req.body?.title) || role.title,
    cwd: cleanString(req.body?.cwd),
    reconnectState: "fresh",
    agentRole: role.role,
    providerSlot: selectedSlot.id,
    modelId: selectedSlot.modelId,
    routeReason: decision.reason,
    arousalMode: decision.arousalMode,
    agentState: readiness.status === "ready" ? "idle" : "needs_setup",
  });
  const nextSession = await updateSession(rootDir, slug, session.id, (current) => {
    const panes = current.panes.some((entry) => entry.id === pane.id)
      ? current.panes.map((entry) => entry.id === pane.id ? pane : entry)
      : [...current.panes, pane];
    return { ...current, panes };
  });
  return {
    projectSlug: slug,
    pane,
    session: await attachAuthority(nextSession),
    decision,
    readiness,
    startCommand: cleanString(req.body?.command) || cleanString(selectedSlot.command || role.launchCommand),
    providerSlot: selectedSlot,
  };
}));

// Persist provider credentials for a lane's slot so the readiness probe flips
// needs_setup -> ready and the launch path injects them. Writes the per-slug
// 0600 file AND updates the in-process override map for read-your-write
// consistency (no pod restart). Never echoes the raw api_key back.
app.post("/v1/agents/:roleOrKind/provider-config", jsonRoute(async (req) => {
  const role = findAgentRole(req.params.roleOrKind);
  if (!role) {
    const error = new Error(`unknown agent role: ${req.params.roleOrKind}`);
    error.statusCode = 404;
    throw error;
  }
  const probe = role.readinessProbe || {};
  if (probe.type !== "provider_slot") {
    const error = new Error(`${role.role} is not provider-configurable (probe: ${probe.type || "none"})`);
    error.statusCode = 400;
    throw error;
  }
  const probeEnv = cleanString(probe.env);
  const baseUrlOnly = /_PROVIDER_URL$/.test(probeEnv) || /_BASE_URL$/.test(probeEnv);

  const body = req.body || {};
  const baseUrl = cleanString(body.base_url ?? body.baseUrl);
  const apiKey = cleanString(body.api_key ?? body.apiKey);
  const requestedSlot = cleanString(body.slot ?? body.providerSlot ?? body.provider_slot);
  const selectedSlot = role.providerSlots?.find((slot) => slot.id === requestedSlot)
    || role.providerSlots?.[0]
    || {};
  const slotId = selectedSlot.id || requestedSlot;
  if (!slotId) {
    const error = new Error("no provider slot to configure for this role");
    error.statusCode = 400;
    throw error;
  }
  if (!baseUrl) {
    const error = new Error("base_url is required");
    error.statusCode = 400;
    throw error;
  }
  if (!apiKey && !baseUrlOnly) {
    const error = new Error("api_key is required for this provider");
    error.statusCode = 400;
    throw error;
  }

  // Enrich the stored slot with the registry-derived role + probe env so the
  // readiness match (overrideForProbeEnv) and launch injection (buildProviderEnv)
  // key off the right variable — the form only sends {slot, base_url, api_key, model}.
  const slotEntry = {
    role: role.role,
    env: probeEnv,
    apiKey, // raw secret; the file is 0600 and the value is never returned
    baseUrl,
    model: cleanString(body.model) || cleanString(selectedSlot.modelId),
    updatedAt: nowIso(),
  };

  const cfg = await readProviderConfig(rootDir, slug);
  cfg.slots = { ...(cfg.slots || {}), [slotId]: slotEntry };
  const written = await writeProviderConfig(rootDir, slug, cfg);
  applyProviderConfigToOverrides(written);

  const masked = maskProviderConfig(written).slots?.[slotId] || {};
  return {
    projectSlug: slug,
    role: role.role,
    slot: slotId,
    status: "configured",
    providerConfig: {
      slot: slotId,
      baseUrl: slotEntry.baseUrl,
      model: slotEntry.model,
      apiKeyConfigured: Boolean(apiKey),
      updatedAt: masked.updatedAt || slotEntry.updatedAt,
    },
    readiness: readinessForRole(role),
  };
}));

app.get("/v1/sessions", jsonRoute(async () => {
  const state = await readSessions(rootDir, slug);
  return {
    projectSlug: slug,
    authority: await authorityStatus(),
    sessions: await Promise.all(state.sessions.map((entry) => attachAuthority(entry))),
  };
}));

app.post("/v1/sessions", jsonRoute(async (req) => ({
  session: await attachAuthority(await getOrCreateSession(rootDir, slug, "", req.body || {})),
})));

app.get("/v1/sessions/:sessionId", jsonRoute(async (req) => ({
  session: await attachAuthority(await getOrCreateSession(rootDir, slug, req.params.sessionId)),
})));

app.post("/v1/sessions/:sessionId/panes", jsonRoute(async (req) => {
  const session = await getOrCreateSession(rootDir, slug, req.params.sessionId);
  const pane = normalizePane({
    id: cleanString(req.body?.id) || `pane-${randomUUID().slice(0, 10)}`,
    kind: cleanString(req.body?.kind) || "human",
    title: cleanString(req.body?.title),
    cwd: cleanString(req.body?.cwd),
    agentRole: req.body?.agentRole || req.body?.agent_role,
    providerSlot: req.body?.providerSlot || req.body?.provider_slot,
    modelId: req.body?.modelId || req.body?.model_id,
    routeReason: req.body?.routeReason || req.body?.route_reason,
    arousalMode: req.body?.arousalMode || req.body?.arousal_mode,
    reconnectState: "fresh",
  });
  const nextSession = await updateSession(rootDir, slug, session.id, (current) => {
    const panes = current.panes.some((entry) => entry.id === pane.id)
      ? current.panes.map((entry) => entry.id === pane.id ? pane : entry)
      : [...current.panes, pane];
    return { ...current, panes };
  });
  return { pane, session: await attachAuthority(nextSession) };
}));

app.get("/v1/sessions/:sessionId/blocks", jsonRoute(async (req) => {
  await getOrCreateSession(rootDir, slug, req.params.sessionId);
  return {
    projectSlug: slug,
    sessionId: req.params.sessionId,
    authority: await authorityStatus(),
    blocks: foldBlocks(await readBlockEvents(rootDir, slug, req.params.sessionId)),
  };
}));

app.post("/v1/sessions/:sessionId/blocks/:blockId/remember", jsonRoute(async (req) => {
  await getOrCreateSession(rootDir, slug, req.params.sessionId);
  const blocks = foldBlocks(await readBlockEvents(rootDir, slug, req.params.sessionId));
  const block = blocks.find((entry) => entry.id === req.params.blockId);
  if (!block) {
    const error = new Error("terminal block not found");
    error.statusCode = 404;
    throw error;
  }
  const memory = await rememberBlock({ sessionId: req.params.sessionId, block, requestBody: req.body || {} });
  await updateSession(rootDir, slug, req.params.sessionId, (current) => ({
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

const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

function send(ws, payload) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(payload));
}

async function rememberBlockById(ws, sessionId, paneId, blockId, trigger = "manual") {
  const blocks = foldBlocks(await readBlockEvents(rootDir, slug, sessionId));
  const block = blocks.find((entry) => entry.id === blockId);
  if (!block) return null;
  if (trigger === "auto" && !shouldAutoRememberBlock(block)) return null;
  const memory = await rememberBlock({ sessionId, block, requestBody: { summary: trigger === "auto" ? "Auto-safe Workbench memory import." : "" } });
  await updateSession(rootDir, slug, sessionId, (current) => ({
    ...current,
    lastMemoryStatus: { blockId, status: memory.status, memoryEventId: memory.memoryEventId, auditEventId: memory.auditEventId, updatedAt: nowIso() },
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
    authority: "workspace-agent",
  };
  await appendBlockEvent(rootDir, slug, sessionId, event);
  send(ws, event);
  return memory;
}

wss.on("connection", async (ws, req, context) => {
  const { sessionId, paneId } = context;
  const supervisorPaneId = safeId(`${sessionId}:${paneId}`);
  const session = await getOrCreateSession(rootDir, slug, sessionId);
  await updateSession(rootDir, slug, session.id, (current) => ({
    ...current,
    lastAttachedAt: nowIso(),
    panes: current.panes.map((pane) =>
      pane.id === paneId ? { ...pane, status: "attached", lastAttachedAt: nowIso(), reconnectState: "attached" } : pane
    ),
  })).catch(() => {});
  const pane = session.panes.find((entry) => entry.id === paneId) || normalizePane({ id: paneId });
  let providerEnv = null;
  const paneProviderSlot = cleanString(pane.providerSlot || pane.agent?.providerSlot);
  if (paneProviderSlot) {
    try {
      const cfg = await readProviderConfig(rootDir, slug);
      providerEnv = buildProviderEnv(cfg.slots?.[paneProviderSlot]);
    } catch (error) {
      // Missing/unreadable config is non-fatal: spawn the pane without
      // injected creds (lane stays unauthenticated, never crashes the WS).
      console.warn(`provider-config load for pane ${paneId} skipped: ${error?.message || error}`);
    }
  }
  try {
    await supervisorJson("/v1/spawn", {
      sessionId,
      paneId: supervisorPaneId,
      cwd: cleanString(pane.cwd) || workspaceRoot,
      cols: Number(context.cols || 120),
      rows: Number(context.rows || 34),
      ...(providerEnv ? { providerEnv } : {}),
    });
  } catch (error) {
    send(ws, {
      type: "error",
      data: `pty supervisor spawn failed: ${error?.message || "unknown"}`,
      authority: "workspace-agent",
    });
    ws.close();
    return;
  }

  let activeBlock = null;
  let inputBuffer = "";
  const supervisorWs = new WebSocket(`${supervisorUrl.replace(/^http/, "ws")}/v1/panes/${encodeURIComponent(supervisorPaneId)}/stream`);

  async function finishActiveBlock(status = "finished", exitCode = null) {
    if (!activeBlock) return;
    const blockId = activeBlock.id;
    const event = {
      type: "block_finished",
      blockId,
      sessionId,
      paneId,
      at: nowIso(),
      finishedAt: nowIso(),
      durationMs: Date.now() - activeBlock.startedAtMs,
      exitCode,
      status,
      privacyClass: activeBlock.privacyClass,
      sourceModel: activeBlock.sourceModel,
      bridgeVersion: WORKBENCH_BRIDGE_VERSION,
      blockHash: activeBlock.blockHash,
      sessionHash: activeBlock.sessionHash,
      rendererHint: WORKBENCH_PROTOCOL,
      authority: "workspace-agent",
    };
    await appendBlockEvent(rootDir, slug, sessionId, event);
    send(ws, event);
    activeBlock = null;
    if (!["detached", "terminal_exit"].includes(status)) {
      void rememberBlockById(ws, sessionId, paneId, blockId, "auto").catch((error) => {
        send(ws, { type: "memory_imported", sessionId, paneId, blockId, at: nowIso(), trigger: "auto", status: "failed", error: error?.message || "auto_memory_failed" });
      });
    }
  }

  async function startBlock(commandText) {
    const command = stripControl(commandText);
    if (!command || command.length > 6000) return;
    await finishActiveBlock("observed_no_exit", null);
    const restricted = hasSecret(command);
    const blockId = `block-${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`;
    const agentRole = cleanString(pane.agentRole || pane.agent?.role);
    const providerSlot = cleanString(pane.providerSlot || pane.agent?.providerSlot);
    const modelId = cleanString(pane.modelId || pane.agent?.modelId || pane.kind || "beagle");
    const arousalMode = cleanString(pane.arousalMode || pane.agent?.arousalMode || "phasic_focus");
    const bridge = bridgeMetadata({ sourceModel: modelId, rendererHint: WORKBENCH_PROTOCOL, payload: { blockId, sessionId, paneId, command, agentRole, providerSlot } });
    activeBlock = {
      id: blockId,
      command: restricted ? "[restricted command redacted]" : command,
      startedAtMs: Date.now(),
      privacyClass: restricted ? "restricted_local_only" : "sensitive",
      sourceModel: modelId,
      sessionHash: hashObject({ slug, sessionId }),
      blockHash: hashObject({ blockId, sessionId, paneId, command }),
    };
    const event = {
      type: "block_started",
      blockId,
      sessionId,
      paneId,
      at: nowIso(),
      startedAt: nowIso(),
      kind: "command",
      title: restricted ? "Restricted command" : commandTitle(command),
      command: activeBlock.command,
      privacyClass: activeBlock.privacyClass,
      tags: [
        "workbench",
        "terminal-block",
        `project:${slug}`,
        `source_model:${modelId}`,
        agentRole ? `agent_role:${agentRole}` : "",
        providerSlot ? `provider_slot:${providerSlot}` : "",
        arousalMode ? `arousal:${arousalMode}` : "",
      ].filter(Boolean),
      sourceModel: modelId,
      agentRole,
      providerSlot,
      modelId,
      arousalMode,
      bridgeVersion: WORKBENCH_BRIDGE_VERSION,
      blockHash: activeBlock.blockHash,
      sessionHash: activeBlock.sessionHash,
      rendererHint: WORKBENCH_PROTOCOL,
      authority: "workspace-agent",
      provenance: {
        protocol: WORKBENCH_PROTOCOL,
        bridge_version: bridge.bridgeVersion,
        bridge_hash: bridge.bridgeHash,
        source_model: modelId,
        agent_role: agentRole,
        provider_slot: providerSlot,
        model_id: modelId,
        arousal_mode: arousalMode,
        renderer_hint: WORKBENCH_PROTOCOL,
        source_surface: "beagle-workbench",
        authority: "workspace-agent",
        supervisor_runtime: "beagle-pty-supervisor-v1",
      },
    };
    await appendBlockEvent(rootDir, slug, sessionId, event);
    send(ws, event);
    if (restricted) {
      const redacted = { type: "secret_redacted", blockId, sessionId, paneId, at: nowIso(), reason: "input_secret_detected" };
      await appendBlockEvent(rootDir, slug, sessionId, redacted);
      send(ws, redacted);
    }
  }

  supervisorWs.on("message", async (payload) => {
    let message = {};
    try {
      message = JSON.parse(String(payload));
    } catch {
      return;
    }
    if (message.type === "raw_output") {
      const data = String(message.data || "");
      send(ws, { type: "data", data });
      send(ws, { ...message, sourceModel: "beagle", bridgeVersion: WORKBENCH_BRIDGE_VERSION, authority: "workspace-agent" });
      if (activeBlock) {
        if (hasSecret(data)) {
          activeBlock.privacyClass = "restricted_local_only";
          const redacted = { type: "secret_redacted", blockId: activeBlock.id, sessionId, paneId, at: nowIso(), reason: "output_secret_detected" };
          await appendBlockEvent(rootDir, slug, sessionId, redacted);
          send(ws, redacted);
        }
        const blockEvent = {
          type: "block_output",
          blockId: activeBlock.id,
          sessionId,
          paneId,
          at: nowIso(),
          data: activeBlock.privacyClass === "restricted_local_only" && hasSecret(data) ? "[restricted output redacted]" : data,
          sourceModel: activeBlock.sourceModel,
          bridgeVersion: WORKBENCH_BRIDGE_VERSION,
          authority: "workspace-agent",
        };
        await appendBlockEvent(rootDir, slug, sessionId, blockEvent);
        send(ws, blockEvent);
      }
      const agentState = detectAgentState(data);
      if (agentState) {
        const event = { type: "agent_state", sessionId, paneId, at: nowIso(), state: agentState, sourceModel: "beagle", bridgeVersion: WORKBENCH_BRIDGE_VERSION, authority: "workspace-agent" };
        await appendBlockEvent(rootDir, slug, sessionId, event);
        send(ws, event);
      }
      for (const signal of detectWorkbenchSignals(data)) {
        const event = { ...signal, sessionId, paneId, at: nowIso(), sourceModel: "beagle", bridgeVersion: WORKBENCH_BRIDGE_VERSION, authority: "workspace-agent" };
        await appendBlockEvent(rootDir, slug, sessionId, event);
        send(ws, event);
      }
    }
    if (message.type === "ready") {
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
          authority: await authorityStatus(),
          reconnectState: cleanString(message.snapshot) ? "replayed_snapshot" : "attached",
        },
      });
      if (message.snapshot) send(ws, { type: "data", data: String(message.snapshot) });
    }
    if (message.type === "exit") {
      await finishActiveBlock("terminal_exit", Number(message.exitCode || 0));
      send(ws, { type: "exit", data: message.detail || "pty exited" });
    }
  });

  supervisorWs.on("close", () => {
    send(ws, { type: "exit", data: "pty supervisor stream closed" });
    ws.close();
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
          await startBlock(command);
        }
        await supervisorJson(`/v1/panes/${encodeURIComponent(supervisorPaneId)}/input`, { data: text });
        return;
      }
      if (message.type === "resize") {
        await supervisorJson(`/v1/panes/${encodeURIComponent(supervisorPaneId)}/resize`, { cols: Number(message.cols || 120), rows: Number(message.rows || 34) });
        return;
      }
      if (message.type === "signal") {
        await supervisorJson(`/v1/panes/${encodeURIComponent(supervisorPaneId)}/signal`, { signal: cleanString(message.signal || "SIGINT") });
        return;
      }
      if (message.type === "stop_process") {
        await supervisorJson(`/v1/panes/${encodeURIComponent(supervisorPaneId)}/terminate`, {});
        return;
      }
      if (message.type === "approve") {
        await appendBlockEvent(rootDir, slug, sessionId, { type: "approval_requested", sessionId, paneId, at: nowIso(), status: "approved", sourceModel: "beagle", bridgeVersion: WORKBENCH_BRIDGE_VERSION, authority: "workspace-agent" });
        await supervisorJson(`/v1/panes/${encodeURIComponent(supervisorPaneId)}/input`, { data: String(message.data || "y\n") });
        return;
      }
      if (message.type === "start_process") {
        const command = cleanString(message.command);
        if (command) {
          await startBlock(command);
          await supervisorJson(`/v1/panes/${encodeURIComponent(supervisorPaneId)}/input`, { data: `${command}\n` });
        }
        return;
      }
      if (message.type === "mark_block") {
        await finishActiveBlock("marked", null);
        return;
      }
      if (message.type === "attach_block_to_memory") {
        const blockId = cleanString(message.blockId || message.block_id);
        if (blockId) await rememberBlockById(ws, sessionId, paneId, blockId, "manual");
        return;
      }
      if (message.type === "focus") {
        send(ws, { type: "warp_bridge_event", sessionId, paneId, at: nowIso(), event: "focus", sourceModel: "beagle", bridgeVersion: WORKBENCH_BRIDGE_VERSION, authority: "workspace-agent" });
        return;
      }
    } catch {
      await supervisorJson(`/v1/panes/${encodeURIComponent(supervisorPaneId)}/input`, { data: String(payload) }).catch(() => {});
    }
  });

  ws.on("close", async () => {
    await finishActiveBlock("detached", null).catch(() => {});
    supervisorWs.close();
  });
});

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  const match = url.pathname.match(/^\/v1\/sessions\/([^/]+)\/panes\/([^/]+)\/stream$/);
  if (!match) {
    socket.destroy();
    return;
  }
  const sessionId = decodeURIComponent(match[1]);
  const paneId = decodeURIComponent(match[2]);
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit("connection", ws, req, { sessionId, paneId });
  });
});

server.listen(port, host, () => {
  console.log(`[beagle-workspace-agent] ${slug} listening on http://${host}:${port}`);
  void hydrateProviderConfigOverrides().then(() => {
    if (providerConfigOverrides.size > 0) {
      console.log(`[beagle-workspace-agent] provider-config hydrated ${providerConfigOverrides.size} slot(s)`);
    }
  });
});
