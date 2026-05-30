#!/usr/bin/env node

import { appendFile, mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import WebSocket from "ws";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function cleanString(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
}

function contextFile(slug) {
  return path.join(DATA_DIR, "workbench-context", `${safeSlug(slug)}.jsonl`);
}

async function appendVerificationRecord(slug, record) {
  const file = verificationFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
}

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

async function fetchJson(url, options = {}) {
  const res = await fetch(url, {
    method: options.method || "GET",
    headers: options.body ? { "content-type": "application/json", ...(options.headers || {}) } : options.headers,
    body: options.body ? JSON.stringify(options.body) : undefined
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const error = new Error(`${res.status} ${payload?.error || res.statusText}`);
    error.detail = payload;
    throw error;
  }
  return payload;
}

async function readJsonl(file) {
  let text = "";
  try {
    text = await readFile(file, "utf8");
  } catch {
    return [];
  }
  return text
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function providerForTargetClient(targetClient) {
  const id = cleanString(targetClient).toLowerCase();
  if (id === "chatgpt") return "openai";
  if (id === "grok") return "xai";
  if (id === "claude-desktop") return "anthropic";
  return id || "subscription-client";
}

function providerForClient(client = {}) {
  if (client.id) return client.id;
  const target = cleanString(client.targetClient || client.target_client);
  if (target === "chatgpt") return "chatgpt-mcp";
  if (target === "grok") return "grok-mcp";
  if (target === "claude-desktop") return "claude-desktop";
  return target;
}

function targetAliases(targetClient) {
  const target = cleanString(targetClient).toLowerCase();
  if (target === "chatgpt") return new Set(["chatgpt", "openai", "chatgpt-mcp"]);
  if (target === "grok") return new Set(["grok", "xai", "grok-mcp"]);
  if (target === "claude-desktop") return new Set(["claude-desktop", "claude", "anthropic"]);
  return new Set([target].filter(Boolean));
}

function normalized(value) {
  return cleanString(value).toLowerCase();
}

function recordAliases(record = {}) {
  return [
    record.source,
    record.provider,
    record.client_id,
    record.metadata?.targetClient,
    record.metadata?.providerId
  ].map(normalized).filter(Boolean);
}

function isForbiddenReplyRecord(record = {}) {
  const tags = Array.isArray(record.tags) ? record.tags.map(normalized) : [];
  const meta = record.metadata || {};
  return Boolean(
    meta.verifier ||
      meta.contract_verifier ||
      meta.operator_ui ||
      meta.reply_path ||
      meta.truthMode === "observed-human-mediated-subscription-reply" ||
      meta.truthMode === "observed-subscription-client-reply" ||
      tags.includes("fixture") ||
      tags.some((tag) => tag.startsWith("fixture-")) ||
      tags.includes("mcp-realtime") ||
      ["project-cockpit-multimodel", "beagle-studio"].includes(normalized(record.client_id || record.source))
  );
}

async function findRealContextReply({ projectSlug, messageId, targetClient, expectedText }) {
  const aliases = targetAliases(targetClient);
  const records = await readJsonl(contextFile(projectSlug));
  return records
    .filter((record) => cleanString(record.metadata?.reply_to_message_id) === messageId)
    .filter((record) => cleanString(record.text || record.content).includes(expectedText))
    .filter((record) => recordAliases(record).some((alias) => aliases.has(alias)))
    .filter((record) => !isForbiddenReplyRecord(record))
    .sort((left, right) => cleanString(left.created_at).localeCompare(cleanString(right.created_at)))
    .at(0) || null;
}

async function readBringup(apiBase, projectSlug) {
  return await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/bringup`);
}

function selectClient(bringup, clientFilter) {
  const clients = bringup.clients || [];
  if (!clientFilter) return clients[0] || null;
  const filter = cleanString(clientFilter);
  return clients.find((client) => [client.id, client.targetClient, client.provider].includes(filter)) || null;
}

async function waitForPersistedTurn({ apiBase, projectSlug, turnId, provider, expectedText, timeoutMs }) {
  const deadline = Date.now() + timeoutMs;
  let lastPayload = null;
  while (Date.now() < deadline) {
    lastPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=20&includeActive=1`);
    const turn = (lastPayload.turns || []).find((item) => item.turnId === turnId);
    const response = (turn?.responses || []).find((item) => item.provider === provider);
    if (response?.status === "done" && cleanString(response.text).includes(expectedText)) {
      return { turn, response, payload: lastPayload };
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw Object.assign(new Error("persisted subscription reply turn did not finish in time"), {
    detail: { turnId, provider, expectedText, lastPayload }
  });
}

function responseHasTargetIdentity(response = {}, targetClient) {
  const aliases = targetAliases(targetClient);
  const meta = response.meta || {};
  return [
    meta.reply_client_id,
    meta.reply_source,
    meta.completed_by,
    meta.heartbeat_by,
    meta.acked_by,
    meta.claimed_by,
    meta.targetClient
  ].map(normalized).some((alias) => aliases.has(alias));
}

export async function verifyMultimodelSubscriptionReplyLive({
  projectSlug = "darwin-mfc",
  clientFilter = "chatgpt",
  provider = "",
  targetClient = "",
  apiBase = "http://127.0.0.1:4370",
  wsBase = apiBase.replace(/^http/, "ws"),
  timeoutMs = 120_000,
  marker = `sub-reply-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`
} = {}) {
  const api = apiBase.replace(/\/$/, "");
  const wsUrl = `${wsBase.replace(/\/$/, "")}/ws/projects/${encodeURIComponent(projectSlug)}/multimodel-chat`;
  const bringup = await readBringup(api, projectSlug);
  const selectedClient = selectClient(bringup, clientFilter || targetClient || provider);
  assert(selectedClient, "requested subscription client was not declared", {
    clientFilter,
    targetClient,
    provider,
    declaredClients: (bringup.clients || []).map((client) => ({ id: client.id, targetClient: client.targetClient }))
  });
  assert(bringup.ok === true, "subscription bring-up infrastructure is not ok", bringup);

  const selectedProvider = cleanString(provider, providerForClient(selectedClient));
  const selectedTargetClient = cleanString(targetClient, selectedClient.targetClient);
  const targetProvider = providerForTargetClient(selectedTargetClient);
  const turnId = `verify-subscription-reply-${marker}`;
  const expectedText = `real subscription reply ${marker}`;
  const events = [];
  const startedAt = Date.now();

  const realtime = await new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl);
    let sent = false;
    let messageId = "";
    let sawProviderDone = false;
    let sawTurnDone = false;
    let providerText = "";
    let providerMeta = {};
    let settled = false;

    function stopTurn() {
      try {
        if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: "stop", turnId }));
      } catch {
        // best-effort cleanup only
      }
    }

    function closeSocket() {
      try { socket.close(); } catch {
        // ignore close errors while settling
      }
    }

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      stopTurn();
      setTimeout(closeSocket, 200);
      reject(Object.assign(new Error(`timeout after ${timeoutMs}ms waiting for a real subscription-client reply`), {
        detail: { turnId, provider: selectedProvider, targetClient: selectedTargetClient, messageId, expectedText, events }
      }));
    }, timeoutMs);

    function finish() {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      closeSocket();
      resolve({ turnId, provider: selectedProvider, targetClient: selectedTargetClient, messageId, sawProviderDone, sawTurnDone, providerText, providerMeta, events });
    }

    function fail(error) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      stopTurn();
      setTimeout(closeSocket, 200);
      reject(error);
    }

    socket.on("message", (raw) => {
      let event;
      try {
        event = JSON.parse(raw.toString());
      } catch (error) {
        fail(Object.assign(new Error("invalid WebSocket JSON event"), { detail: { raw: raw.toString(), error: error.message } }));
        return;
      }
      const elapsedMs = Date.now() - startedAt;
      if ([
        "ready",
        "providers_snapshot",
        "turn_started",
        "turn_snapshot",
        "provider_meta",
        "delta",
        "provider_done",
        "mcp_reply_observed",
        "mcp_lifecycle_observed",
        "turn_done",
        "turn_stopped",
        "provider_error",
        "error"
      ].includes(event.type)) {
        events.push({
          type: event.type,
          provider: event.provider || "",
          turnId: event.turnId || "",
          messageId: event.messageId || event.meta?.message_id || "",
          elapsedMs,
          text: cleanString(event.text).slice(0, 180),
          state: cleanString(event.meta?.state),
          error: event.error || ""
        });
      }

      if (event.type === "ready" && !sent) {
        const providerRecord = (event.providers || []).find((item) => item.id === selectedProvider);
        if (!providerRecord || providerRecord.transport !== "workbench-context-mcp-inbox") {
          fail(Object.assign(new Error(`${selectedProvider} was not exposed as a Workbench Context inbox provider`), {
            detail: { selectedProvider, selectedTargetClient, providerRecord, providers: event.providers || [] }
          }));
          return;
        }
        sent = true;
        socket.send(JSON.stringify({
          type: "chat",
          turnId,
          message: [
            `Real subscription reply verifier ${marker}.`,
            `You are ${selectedTargetClient} connected through MCP/subscription, not an API fixture.`,
            `Reply with exactly: ${expectedText}`
          ].join(" "),
          providers: [selectedProvider],
          history: [],
          enableSynthesis: false
        }));
        return;
      }

      if (event.type === "provider_meta" && event.provider === selectedProvider && event.meta?.message_id) {
        messageId = event.meta.message_id;
        providerMeta = { ...providerMeta, ...(event.meta || {}) };
      }

      if (event.type === "provider_done" && event.provider === selectedProvider) {
        sawProviderDone = cleanString(event.text).includes(expectedText);
        providerText = cleanString(event.text);
        providerMeta = { ...providerMeta, ...(event.meta || {}) };
      }

      if (event.type === "provider_error" && event.provider === selectedProvider) {
        fail(Object.assign(new Error(`${selectedProvider} emitted error: ${event.error || "unknown"}`), { detail: { event, events } }));
      }

      if (event.type === "turn_done" && event.turnId === turnId) {
        sawTurnDone = true;
        setTimeout(finish, 300);
      }
    });
    socket.on("error", fail);
  });

  assert(realtime.messageId, "MCP handoff message id was not observed", realtime);
  assert(realtime.sawTurnDone, "WebSocket did not observe turn_done", realtime);
  assert(realtime.sawProviderDone, "WebSocket did not observe the expected subscription reply text", realtime);
  assert(responseHasTargetIdentity({ meta: realtime.providerMeta }, selectedTargetClient), "reply event did not carry the target client identity", realtime);

  const persisted = await waitForPersistedTurn({
    apiBase: api,
    projectSlug,
    turnId,
    provider: selectedProvider,
    expectedText,
    timeoutMs: 20_000
  });
  assert(responseHasTargetIdentity(persisted.response, selectedTargetClient), "persisted response did not carry the target client identity", persisted.response);

  const replyRecord = await findRealContextReply({
    projectSlug,
    messageId: realtime.messageId,
    targetClient: selectedTargetClient,
    expectedText
  });
  assert(replyRecord, "no non-fixture Workbench Context reply record was written by the target subscription client", {
    projectSlug,
    messageId: realtime.messageId,
    targetClient: selectedTargetClient,
    expectedText
  });

  const active = await fetchJson(`${api}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
  assert((active.count || 0) === 0, "active turns remained after subscription reply verification", active);

  const result = {
    ok: true,
    schema: "beagle.multimodel-subscription-reply-live-verification.v1",
    projectSlug,
    provider: selectedProvider,
    targetClient: selectedTargetClient,
    targetProvider,
    turnId,
    messageId: realtime.messageId,
    expectedText,
    replyMemoryId: cleanString(replyRecord.memory_id),
    replyClientId: cleanString(replyRecord.client_id),
    replySource: cleanString(replyRecord.source),
    replyTruthMode: cleanString(replyRecord.metadata?.truthMode),
    persistedStatus: persisted.response.status,
    persistedTextChars: cleanString(persisted.response.text).length,
    eventCount: realtime.events.length,
    activeTurns: active.count || 0,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-real-subscription-client-reply"
  };
  await appendVerificationRecord(projectSlug, {
    kind: "subscription-reply-live",
    ...result,
    generatedAt: new Date().toISOString()
  });
  return result;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const clientFilter = process.env.CLIENT || process.env.CLIENT_ID || process.argv[3] || "chatgpt";
  const provider = process.env.PROVIDER || process.argv[4] || "";
  const targetClient = process.env.TARGET_CLIENT || process.argv[5] || "";
  const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
  const wsBase = process.env.PROJECT_COCKPIT_WS_BASE || apiBase.replace(/^http/, "ws");
  const timeoutMs = Number(process.env.TIMEOUT_MS || process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 120_000);
  try {
    const result = await verifyMultimodelSubscriptionReplyLive({ projectSlug, clientFilter, provider, targetClient, apiBase, wsBase, timeoutMs });
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error(JSON.stringify({
      ok: false,
      schema: "beagle.multimodel-subscription-reply-live-verification.v1",
      projectSlug,
      clientFilter,
      provider,
      targetClient,
      error: error.message,
      detail: error.detail || null,
      truthMode: "verification-failed"
    }, null, 2));
    process.exit(1);
  }
}
