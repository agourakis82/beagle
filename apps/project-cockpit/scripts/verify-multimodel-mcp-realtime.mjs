#!/usr/bin/env node

import { appendFile, mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import WebSocket from "ws";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
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

async function callTool({ mcpUrl, name, args = {}, headers = {} }) {
  const response = await fetchJson(mcpUrl, {
    method: "POST",
    headers,
    body: {
      jsonrpc: "2.0",
      id: `${name}-${Date.now()}`,
      method: "tools/call",
      params: { name, arguments: args }
    }
  });
  if (response.error) {
    const error = new Error(response.error.message || `MCP tool failed: ${name}`);
    error.detail = response;
    throw error;
  }
  return response.result?.structuredContent || {};
}

function providerForTargetClient(targetClient) {
  const id = cleanString(targetClient).toLowerCase();
  if (id === "chatgpt") return "openai";
  if (id === "grok") return "xai";
  if (id === "claude-desktop") return "anthropic";
  return id || "subscription-client";
}

function scopedMcpUrl(api, projectSlug, targetClient, targetProvider) {
  const query = new URLSearchParams({
    client_id: targetClient,
    provider: targetProvider
  }).toString();
  return `${api}/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp?${query}`;
}

function scopedMcpHeaders(targetClient, targetProvider) {
  return {
    "x-beagle-client-id": targetClient,
    "x-beagle-provider": targetProvider
  };
}

async function readLocalMcpToken(projectSlug) {
  const envToken =
    cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
    cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
  if (envToken) return envToken;
  try {
    return cleanString(await readFile(path.join(DATA_DIR, "workbench-context", `${safeSlug(projectSlug)}.http-mcp-token`), "utf8"));
  } catch {
    return "";
  }
}

async function waitForPersistedTurn({ apiBase, projectSlug, turnId, provider, expectedText, timeoutMs }) {
  const deadline = Date.now() + timeoutMs;
  let lastPayload = null;
  while (Date.now() < deadline) {
    lastPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=12&includeActive=1`);
    const turn = (lastPayload.turns || []).find((item) => item.turnId === turnId);
    const response = (turn?.responses || []).find((item) => item.provider === provider);
    if (response?.status === "done" && String(response.text || "").includes(expectedText)) {
      return { turn, response, payload: lastPayload };
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw Object.assign(new Error("persisted MCP realtime turn did not finish in time"), {
    detail: { turnId, provider, expectedText, lastPayload }
  });
}

export async function verifyMultimodelMcpRealtime({
  projectSlug = "darwin-mfc",
  provider = "chatgpt-mcp",
  targetClient = "chatgpt",
  apiBase = "http://127.0.0.1:4370",
  wsBase = apiBase.replace(/^http/, "ws"),
  timeoutMs = 90_000,
  marker = `mcp-rt-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`
} = {}) {
  const api = apiBase.replace(/\/$/, "");
  const wsUrl = `${wsBase.replace(/\/$/, "")}/ws/projects/${encodeURIComponent(projectSlug)}/multimodel-chat`;
  const targetProvider = providerForTargetClient(targetClient);
  const mcpUrl = scopedMcpUrl(api, projectSlug, targetClient, targetProvider);
  const token = await readLocalMcpToken(projectSlug);
  const mcpHeaders = {
    ...scopedMcpHeaders(targetClient, targetProvider),
    ...(token ? { authorization: `Bearer ${token}` } : {})
  };
  const turnId = `verify-mcp-realtime-${marker}`;
  const replyText = `mcp realtime reply ${marker}`;
  const events = [];
  const startedAt = Date.now();

  const realtime = await new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl);
    let sent = false;
    let messageId = "";
    let sawSnapshotReply = false;
    let sawReplyEvent = false;
    let sawDone = false;
    let replied = false;
    const timer = setTimeout(() => {
      try { socket.close(); } catch {
        // ignore close errors while failing
      }
      reject(Object.assign(new Error(`timeout after ${timeoutMs}ms`), {
        detail: { turnId, provider, targetClient, messageId, events }
      }));
    }, timeoutMs);

    function finish() {
      clearTimeout(timer);
      try { socket.close(); } catch {
        // ignore close errors while resolving
      }
      resolve({ turnId, provider, targetClient, messageId, sawSnapshotReply, sawReplyEvent, sawDone, events });
    }

    function fail(error) {
      clearTimeout(timer);
      try { socket.close(); } catch {
        // ignore close errors while failing
      }
      reject(error);
    }

    async function replyToMessage(id) {
      if (replied || !id) return;
      replied = true;
      try {
        await fetchJson(`${api}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/mcp-inbox/${encodeURIComponent(id)}/reply`, {
          method: "POST",
          body: {
            client_id: targetClient,
            provider: targetProvider,
            text: replyText,
            metadata: {
              marker,
              verifier: "multimodel-mcp-realtime",
              reply_path: "direct-multimodel-mcp-inbox-endpoint",
              scoped_mcp_url: mcpUrl
            }
          }
        });
      } catch (error) {
        fail(error);
      }
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
        "provider_error",
        "error"
      ].includes(event.type)) {
        events.push({
          type: event.type,
          provider: event.provider || "",
          turnId: event.turnId || "",
          messageId: event.messageId || event.meta?.message_id || "",
          elapsedMs,
          text: cleanString(event.text).slice(0, 160),
          error: event.error || ""
        });
      }

      if (event.type === "ready" && !sent) {
        const providerRecord = (event.providers || []).find((item) => item.id === provider);
        if (!providerRecord?.selectable && providerRecord?.transport !== "workbench-context-mcp-inbox") {
          fail(Object.assign(new Error(`${provider} was not selectable as an MCP inbox provider`), {
            detail: { provider, targetClient, providerRecord, event }
          }));
          return;
        }
        sent = true;
        socket.send(JSON.stringify({
          type: "chat",
          turnId,
          message: `MCP realtime verifier ${marker}. Reply with ${replyText}.`,
          providers: [provider],
          history: [],
          enableSynthesis: false
        }));
        return;
      }

      if (event.type === "provider_meta" && event.provider === provider && event.meta?.message_id) {
        messageId = event.meta.message_id;
        void replyToMessage(messageId);
      }
      if (event.type === "mcp_reply_observed" && event.turnId === turnId) {
        sawReplyEvent = true;
      }
      if (event.type === "turn_snapshot" && event.turnId === turnId) {
        const response = (event.turn?.responses || []).find((item) => item.provider === provider);
        if (response?.text && String(response.text).includes(replyText)) sawSnapshotReply = true;
      }
      if (event.type === "provider_done" && event.provider === provider && String(event.text || "").includes(replyText)) {
        sawSnapshotReply = true;
      }
      if (event.type === "provider_error" && event.provider === provider) {
        fail(Object.assign(new Error(`${provider} emitted error: ${event.error || "unknown"}`), { detail: { event, events } }));
      }
      if (event.type === "turn_done" && event.turnId === turnId) {
        sawDone = true;
        setTimeout(finish, 300);
      }
    });
    socket.on("error", fail);
  });

  assert(realtime.messageId, "MCP handoff message id was not observed", realtime);
  assert(realtime.sawSnapshotReply || realtime.sawReplyEvent, "WebSocket did not observe MCP reply", realtime);
  assert(realtime.sawDone, "WebSocket did not observe turn_done", realtime);

  const persisted = await waitForPersistedTurn({
    apiBase: api,
    projectSlug,
    turnId,
    provider,
    expectedText: replyText,
    timeoutMs: 20_000
  });

  const active = await fetchJson(`${api}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
  assert((active.count || 0) === 0, "active turns remained after MCP realtime verification", active);

  const result = {
    ok: true,
    projectSlug,
    provider,
    targetClient,
    targetProvider,
    mcpUrl,
    mcpHeaders: {
      ...mcpHeaders,
      ...(mcpHeaders.authorization ? { authorization: "Bearer <redacted>" } : {})
    },
    turnId,
    messageId: realtime.messageId,
    replyText,
    replyPath: "direct-multimodel-mcp-inbox-endpoint",
    sawReplyEvent: realtime.sawReplyEvent,
    sawSnapshotReply: realtime.sawSnapshotReply,
    sawDone: realtime.sawDone,
    persistedStatus: persisted.response.status,
    persistedTextChars: cleanString(persisted.response.text).length,
    activeTurns: active.count || 0,
    eventCount: realtime.events.length,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-websocket-mcp-handoff-reply-persisted"
  };
  await appendVerificationRecord(projectSlug, {
    schema: "beagle.multimodel-mcp-realtime-verification.v1",
    kind: "mcp-realtime",
    ...result,
    generatedAt: new Date().toISOString()
  });
  return result;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const provider = process.env.PROVIDER || process.argv[3] || "chatgpt-mcp";
  const targetClient = process.env.TARGET_CLIENT || process.argv[4] || "chatgpt";
  const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
  const wsBase = process.env.PROJECT_COCKPIT_WS_BASE || apiBase.replace(/^http/, "ws");
  const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 90_000);
  try {
    const result = await verifyMultimodelMcpRealtime({ projectSlug, provider, targetClient, apiBase, wsBase, timeoutMs });
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error(JSON.stringify({
      ok: false,
      projectSlug,
      provider,
      targetClient,
      error: error.message,
      detail: error.detail || null,
      truthMode: "verification-failed"
    }, null, 2));
    process.exit(1);
  }
}
