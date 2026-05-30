#!/usr/bin/env node

import { appendFile, mkdir, readFile } from "node:fs/promises";
import path from "node:path";

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "default").replace(/[^a-zA-Z0-9._-]+/g, "-");
}

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");
const tokenFile = path.join(DATA_DIR, "workbench-context", `${safeSlug(projectSlug)}.http-mcp-token`);
const verificationPath = path.join(DATA_DIR, "multimodel-chat", `${safeSlug(projectSlug)}.verifications.jsonl`);

async function appendVerificationRecord(record) {
  await mkdir(path.dirname(verificationPath), { recursive: true });
  await appendFile(verificationPath, `${JSON.stringify(record)}\n`, "utf8");
}

async function token() {
  return cleanString(await readFile(tokenFile, "utf8"));
}

function authHeaders(value, extra = {}) {
  return {
    authorization: `Bearer ${value}`,
    ...extra
  };
}

function parseSseEvents(text) {
  return cleanString(text)
    .split(/\n\n+/)
    .map((chunk) => {
      const event = {};
      for (const line of chunk.split(/\r?\n/)) {
        if (line.startsWith("event:")) event.event = cleanString(line.slice("event:".length));
        if (line.startsWith("data:")) {
          const raw = cleanString(line.slice("data:".length));
          try {
            event.data = JSON.parse(raw);
          } catch {
            event.data = raw;
          }
        }
      }
      return event;
    })
    .filter((event) => event.event || event.data);
}

async function openSseUntil(url, options = {}, { timeoutMs = 7000, predicate } = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  let reader = null;
  let text = "";
  try {
    const res = await fetch(url, {
      ...options,
      signal: ctrl.signal
    });
    reader = res.body?.getReader?.() || null;
    assert(reader, "SSE response body was not readable", {
      status: res.status,
      contentType: res.headers.get("content-type") || ""
    });
    const decoder = new TextDecoder();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      text += decoder.decode(value, { stream: true });
      const events = parseSseEvents(text);
      if (typeof predicate === "function" && predicate(events)) {
        clearTimeout(timer);
        return {
          status: res.status,
          ok: res.ok,
          contentType: res.headers.get("content-type") || "",
          protocolVersion: res.headers.get("mcp-protocol-version") || "",
          sessionId: res.headers.get("mcp-session-id") || "",
          text,
          events,
          close: async () => {
            await reader.cancel().catch(() => {});
            ctrl.abort();
          }
        };
      }
    }
    return {
      status: res.status,
      ok: res.ok,
      contentType: res.headers.get("content-type") || "",
      protocolVersion: res.headers.get("mcp-protocol-version") || "",
      sessionId: res.headers.get("mcp-session-id") || "",
      text,
      events: parseSseEvents(text),
      close: async () => {
        await reader?.cancel?.().catch(() => {});
        ctrl.abort();
      }
    };
  } finally {
    clearTimeout(timer);
  }
}

async function fetchText(url, options = {}) {
  const res = await fetch(url, options);
  const text = await res.text();
  return {
    status: res.status,
    ok: res.ok,
    contentType: res.headers.get("content-type") || "",
    protocolVersion: res.headers.get("mcp-protocol-version") || "",
    sessionId: res.headers.get("mcp-session-id") || "",
    text
  };
}

async function fetchJson(url, options = {}) {
  const response = await fetchText(url, options);
  let payload = {};
  try {
    payload = response.text ? JSON.parse(response.text) : {};
  } catch {
    payload = {};
  }
  return { ...response, payload };
}

try {
  const bearer = await token();
  assert(bearer.length >= 32, "HTTP MCP token is missing or too short", { tokenFile });
  const verifierClientId = "remote-transport-verifier";
  const endpoint = `${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp?client_id=remote-transport-verifier&provider=fixture-http-mcp`;
  const legacyEndpoint = `${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/mcp?client_id=remote-transport-verifier&provider=fixture-http-mcp`;
  const sessionsEndpoint = `${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp/sessions`;
  const presenceEndpoint = `${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/presence?stale_after_minutes=5&limit=200`;

  const diagnostics = await fetchJson(endpoint, {
    headers: authHeaders(bearer, { accept: "application/json" })
  });
  assert(diagnostics.status === 200, "remote MCP diagnostics GET failed", diagnostics);
  assert(diagnostics.payload?.transports?.includes("streamable-http"), "diagnostics did not report streamable HTTP", diagnostics.payload);

  const sseListen = await openSseUntil(endpoint, {
    headers: authHeaders(bearer, {
      accept: "text/event-stream",
      "mcp-protocol-version": "2025-06-18"
    })
  }, {
    predicate: (events) => events.some((event) => event.event === "ready")
  });
  assert(sseListen.status === 200, "SSE listen GET failed", sseListen);
  assert(sseListen.contentType.includes("text/event-stream"), "SSE listen did not return event-stream", sseListen);
  assert(sseListen.sessionId, "SSE listen did not expose Mcp-Session-Id", sseListen);
  assert(sseListen.events.some((event) => event.event === "ready"), "SSE listen did not emit a ready event", {
    sseListen,
    listenEvents: sseListen.events
  });

  const sessionRegistry = await fetchJson(sessionsEndpoint, {
    headers: authHeaders(bearer, { accept: "application/json" })
  });
  const verifierSession = (sessionRegistry.payload?.sessions || []).find((session) => (
    session.session_id === sseListen.sessionId ||
    session.client_id === verifierClientId
  ));
  assert(sessionRegistry.status === 200, "SSE session registry check failed", sessionRegistry);
  assert(verifierSession?.active === true, "SSE listen did not create an active HTTP MCP session", {
    sseSessionId: sseListen.sessionId,
    verifierSession,
    sessionSummary: sessionRegistry.payload?.summary || null
  });

  const presence = await fetchJson(presenceEndpoint, {
    headers: authHeaders(bearer, { accept: "application/json" })
  });
  const verifierPresence = (presence.payload?.clients || []).find((client) => client.client_id === verifierClientId);
  assert(presence.status === 200, "presence check after SSE listen failed", presence);
  assert(verifierPresence?.state === "idle", "SSE listen did not record a fresh MCP client heartbeat", {
    verifierPresence,
    presenceSummary: presence.payload?.summary || null
  });
  await sseListen.close();

  const initializeJson = await fetchJson(endpoint, {
    method: "POST",
    headers: authHeaders(bearer, {
      "content-type": "application/json",
      accept: "application/json",
      "mcp-protocol-version": "2025-06-18"
    }),
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: "init-json",
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "remote-mcp-transport-verifier", version: "0.1.0" }
      }
    })
  });
  assert(initializeJson.status === 200, "JSON initialize failed", initializeJson);
  assert(initializeJson.payload?.result?.serverInfo?.name === "beagle-workbench-context", "JSON initialize returned wrong server", initializeJson.payload);
  assert(initializeJson.payload?.result?.protocolVersion === "2025-06-18", "JSON initialize did not preserve protocol version", initializeJson.payload);

  const initializeSse = await fetchText(endpoint, {
    method: "POST",
    headers: authHeaders(bearer, {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      "mcp-protocol-version": "2025-06-18"
    }),
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: "init-sse",
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "remote-mcp-transport-verifier", version: "0.1.0" }
      }
    })
  });
  const initEvents = parseSseEvents(initializeSse.text);
  assert(initializeSse.status === 200, "SSE initialize failed", initializeSse);
  assert(initializeSse.contentType.includes("text/event-stream"), "SSE initialize did not return event-stream", initializeSse);
  assert(initEvents.some((event) => event.event === "message" && event.data?.result?.serverInfo?.name === "beagle-workbench-context"), "SSE initialize missing JSON-RPC response event", { initializeSse, initEvents });

  const tools = await fetchJson(legacyEndpoint, {
    method: "POST",
    headers: authHeaders(bearer, {
      "content-type": "application/json",
      accept: "application/json"
    }),
    body: JSON.stringify({ jsonrpc: "2.0", id: "tools", method: "tools/list", params: {} })
  });
  assert(tools.status === 200, "legacy /mcp tools/list failed", tools);
  assert((tools.payload?.result?.tools || []).some((item) => item.name === "workbench_context_reply"), "tools/list missing reply tool", tools.payload);

  const notification = await fetchText(endpoint, {
    method: "POST",
    headers: authHeaders(bearer, {
      "content-type": "application/json",
      accept: "application/json, text/event-stream"
    }),
    body: JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized", params: {} })
  });
  assert(notification.status === 202, "notification should return HTTP 202", notification);

  const result = {
    ok: true,
    schema: "beagle.workbench-remote-mcp-transport-verification.v1",
    kind: "remote-mcp-transport",
    projectSlug,
    endpoint,
    checks: {
      diagnostics: true,
      sseListen: true,
      sseHeartbeat: true,
      sseSessionRegistry: true,
      jsonInitialize: true,
      sseInitialize: true,
      legacyAlias: true,
      notificationAccepted: true
    },
    presence: {
      client_id: verifierPresence.client_id,
      state: verifierPresence.state,
      latest_at: verifierPresence.latest_at,
      age_minutes: verifierPresence.age_minutes,
      transport: verifierPresence.transport
    },
    session: {
      session_id: verifierSession.session_id,
      client_id: verifierSession.client_id,
      active: verifierSession.active,
      transport: verifierSession.transport,
      latest_at: verifierSession.last_seen_at
    },
    protocolVersion: "2025-06-18",
    transports: ["streamable-http", "sse-listen"],
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-streamable-http-and-sse-mcp-transport"
  };
  await appendVerificationRecord(result);
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
