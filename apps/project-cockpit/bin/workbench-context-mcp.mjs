#!/usr/bin/env node
// Minimal STDIO MCP bridge for Beagle Workbench Context.
//
// Subscription clients can run this from Claude Desktop, Cursor, Kimi CLI, or
// any MCP client that supports JSON-RPC over stdio. It does not call model
// APIs. It proxies the real Project Cockpit HTTP MCP endpoint so clients can
// heartbeat, read inbox handoffs, reply, and write/read RAG++ memory.

import { createInterface } from "node:readline";

const API = cleanUrl(process.env.COCKPIT_API || process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370");
const PROJECT = cleanString(process.env.COCKPIT_PROJECT || process.env.PROJECT_SLUG || "darwin-mfc");
const MCP_PATH = cleanString(process.env.COCKPIT_MCP_PATH || `/api/workbench/${encodeURIComponent(PROJECT)}/context/mcp`);
const STATIC_TOKEN =
  cleanString(process.env.COCKPIT_TOKEN) ||
  cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
  cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
const FETCH_AUTH_BRIDGE = /^(1|true|yes)$/i.test(cleanString(process.env.COCKPIT_FETCH_AUTH_BRIDGE || ""));
const REQUEST_TIMEOUT_MS = Number(process.env.COCKPIT_MCP_TIMEOUT_MS || 20000);
const CLIENT_ID = cleanString(process.env.COCKPIT_CLIENT_ID || process.env.WORKBENCH_CONTEXT_CLIENT_ID || "");
const CLIENT_PROVIDER = cleanString(process.env.COCKPIT_CLIENT_PROVIDER || CLIENT_ID || "stdio-mcp");
const AUTO_HEARTBEAT = !/^(0|false|no)$/i.test(cleanString(process.env.COCKPIT_AUTO_HEARTBEAT || "1"));
const HEARTBEAT_INTERVAL_MS = Math.max(15000, Number(process.env.COCKPIT_HEARTBEAT_INTERVAL_MS || 60_000));
const SERVER_NAME = "beagle-workbench-context-stdio";
const SERVER_VERSION = "0.1.0";

let cachedToken = "";
let cachedTokenAt = 0;
let cachedTools = null;
let lastHeartbeatAt = 0;
let heartbeatTimer = null;

function cleanString(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function cleanUrl(value) {
  return cleanString(value).replace(/\/+$/, "");
}

function mcpUrl() {
  return `${API}${MCP_PATH.startsWith("/") ? MCP_PATH : `/${MCP_PATH}`}`;
}

async function fetchAuthToken() {
  if (STATIC_TOKEN) return STATIC_TOKEN;
  if (!FETCH_AUTH_BRIDGE) return "";
  if (cachedToken && Date.now() - cachedTokenAt < 4 * 60 * 1000) return cachedToken;
  const res = await fetchJson(`${API}/api/auth/beagle-token`, {
    method: "GET",
    timeoutMs: 8000,
    allowMcpError: true,
    skipAuth: true
  });
  cachedToken = cleanString(res.token);
  cachedTokenAt = Date.now();
  return cachedToken;
}

async function fetchJson(url, {
  method = "POST",
  body,
  timeoutMs = REQUEST_TIMEOUT_MS,
  allowMcpError = false,
  skipAuth = false
} = {}) {
  const ctrl = new AbortController();
  const timeout = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const headers = {};
    if (body !== undefined) headers["content-type"] = "application/json";
    const token = skipAuth ? "" : await fetchAuthToken();
    if (token) headers.authorization = `Bearer ${token}`;
    const res = await fetch(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: ctrl.signal
    });
    const payload = await res.json().catch(() => ({}));
    if (!res.ok && !allowMcpError) {
      const error = new Error(payload?.error || `HTTP ${res.status}`);
      error.statusCode = res.status;
      error.payload = payload;
      throw error;
    }
    return payload;
  } finally {
    clearTimeout(timeout);
  }
}

function writeMessage(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function writeError(id, code, message, data = undefined) {
  writeMessage({
    jsonrpc: "2.0",
    id,
    error: { code, message, ...(data === undefined ? {} : { data }) }
  });
}

function toMcpToolAlias(tool) {
  if (!tool?.name || !tool.name.startsWith("workbench_context_")) return null;
  return {
    ...tool,
    name: `cockpit_${tool.name}`,
    description: `${tool.description || ""} Alias for ${tool.name}.`.trim()
  };
}

async function httpMcp(message) {
  return await fetchJson(mcpUrl(), { body: message });
}

async function autoHeartbeat(reason = "stdio-bridge") {
  if (!AUTO_HEARTBEAT || !CLIENT_ID) return null;
  const now = Date.now();
  if (now - lastHeartbeatAt < Math.min(HEARTBEAT_INTERVAL_MS, 30_000)) return null;
  lastHeartbeatAt = now;
  try {
    const response = await httpMcp({
      jsonrpc: "2.0",
      id: `auto-heartbeat-${now}`,
      method: "tools/call",
      params: {
        name: "workbench_context_client_heartbeat",
        arguments: {
          client_id: CLIENT_ID,
          provider: CLIENT_PROVIDER,
          session_id: `stdio-mcp:${PROJECT}:${CLIENT_ID}`,
          status: "online",
          note: `STDIO MCP bridge ${reason}`,
          tags: ["stdio-mcp", "auto-heartbeat", CLIENT_ID],
          metadata: {
            bridge: SERVER_NAME,
            bridge_version: SERVER_VERSION,
            api: API,
            project: PROJECT,
            reason
          }
        }
      }
    });
    if (response.error) {
      process.stderr.write(`[${SERVER_NAME}] heartbeat failed: ${response.error.message || "unknown"}\n`);
      return null;
    }
    return response.result?.structuredContent || null;
  } catch (error) {
    process.stderr.write(`[${SERVER_NAME}] heartbeat failed: ${error.message}\n`);
    return null;
  }
}

function unaliasToolName(name) {
  const clean = cleanString(name);
  return clean.startsWith("cockpit_workbench_context_") ? clean.slice("cockpit_".length) : clean;
}

async function listTools(id) {
  if (!cachedTools) {
    const response = await httpMcp({ jsonrpc: "2.0", id: "tools-list", method: "tools/list", params: {} });
    if (response.error) {
      throw new Error(response.error.message || "HTTP MCP tools/list failed");
    }
    const tools = Array.isArray(response.result?.tools) ? response.result.tools : [];
    const aliases = tools.map(toMcpToolAlias).filter(Boolean);
    cachedTools = [...tools, ...aliases];
  }
  return { jsonrpc: "2.0", id, result: { tools: cachedTools } };
}

async function callTool(id, params = {}) {
  const name = unaliasToolName(params.name);
  return await httpMcp({
    jsonrpc: "2.0",
    id,
    method: "tools/call",
    params: {
      ...params,
      name,
      arguments: params.arguments && typeof params.arguments === "object" ? params.arguments : {}
    }
  });
}

async function handleMessage(message = {}) {
  const id = message.id ?? null;
  try {
    if (message.method === "initialize") {
      await autoHeartbeat("initialize");
      return {
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: { name: SERVER_NAME, version: SERVER_VERSION }
        }
      };
    }
    if (message.method === "notifications/initialized" || message.method === "notifications/cancelled") {
      return null;
    }
    if (message.method === "ping") {
      return { jsonrpc: "2.0", id, result: {} };
    }
    if (message.method === "tools/list") {
      await autoHeartbeat("tools-list");
      return await listTools(id);
    }
    if (message.method === "tools/call") {
      await autoHeartbeat(`tools-call:${cleanString(message.params?.name, "unknown")}`);
      return await callTool(id, message.params || {});
    }
    return {
      jsonrpc: "2.0",
      id,
      error: { code: -32601, message: `unknown method: ${message.method}` }
    };
  } catch (error) {
    return {
      jsonrpc: "2.0",
      id,
      error: {
        code: error.statusCode === 401 ? -32001 : -32000,
        message: error.message || "Workbench Context STDIO bridge failed",
        data: {
          api: API,
          project: PROJECT,
          mcpUrl: mcpUrl(),
          statusCode: error.statusCode || null,
          payload: error.payload || null
        }
      }
    };
  }
}

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });

rl.on("line", async (line) => {
  const text = line.trim();
  if (!text) return;
  let message;
  try {
    message = JSON.parse(text);
  } catch (error) {
    writeError(null, -32700, `parse error: ${error.message}`);
    return;
  }

  const messages = Array.isArray(message) ? message : [message];
  const responses = [];
  for (const item of messages) {
    const response = await handleMessage(item);
    if (response) responses.push(response);
  }
  if (Array.isArray(message)) {
    writeMessage(responses);
  } else if (responses.length) {
    writeMessage(responses[0]);
  }
});

if (AUTO_HEARTBEAT && CLIENT_ID) {
  heartbeatTimer = setInterval(() => {
    void autoHeartbeat("interval");
  }, HEARTBEAT_INTERVAL_MS);
  heartbeatTimer.unref?.();
}

rl.on("close", () => {
  if (heartbeatTimer) clearInterval(heartbeatTimer);
  process.exit(0);
});
