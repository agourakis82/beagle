#!/usr/bin/env node

import { access, appendFile, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { constants } from "node:fs";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");
const kitDir = path.resolve(
  process.env.WORKBENCH_MCP_CLIENT_KIT_DIR ||
    path.join(DATA_DIR, "mcp-client-kit", safeSlug(projectSlug))
);
const verificationPath = path.join(DATA_DIR, "multimodel-chat", `${safeSlug(projectSlug)}.verifications.jsonl`);
const tokenFile = path.join(DATA_DIR, "workbench-context", `${safeSlug(projectSlug)}.http-mcp-token`);

async function appendVerificationRecord(record) {
  await appendFile(verificationPath, `${JSON.stringify(record)}\n`, "utf8");
}

function isProjectMcpUrl(value) {
  const text = String(value || "");
  return text.includes(`/api/workbench/${projectSlug}/context/mcp`) ||
    text.includes(`/api/workbench/${projectSlug}/mcp`);
}

async function readJson(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

async function readLocalMcpToken() {
  const envToken =
    cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
    cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
  if (envToken) return envToken;
  try {
    return cleanString(await readFile(tokenFile, "utf8"));
  } catch {
    return "";
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

function queryParam(value, key) {
  try {
    return new URL(value).searchParams.get(key) || "";
  } catch {
    return "";
  }
}

function assertSubscriptionSetupText(name, text, { clientId, localToken = "" } = {}) {
  assert(text.includes("Register this MCP server"), `${name} is missing the registration instruction`, { text });
  assert(text.includes(`/api/workbench/${projectSlug}/context/mcp`), `${name} is missing the project MCP endpoint`, { text });
  assert(text.includes("Bearer <workbench-context-token>"), `${name} is missing the bearer placeholder`, { text });
  assert(text.includes("workbench_context_join"), `${name} is missing the join tool`, { text });
  assert(text.includes("workbench_context_client_heartbeat"), `${name} is missing the heartbeat tool`, { text });
  assert(text.includes("verify:multimodel:subscription-reply-live"), `${name} is missing the reply-live gate`, { text });
  if (clientId === "claude-desktop") {
    assert(text.includes("cockpit_workbench_context_reply"), `${name} is missing the Claude Desktop reply alias`, { text });
  } else {
    assert(text.includes("workbench_context_reply"), `${name} is missing the reply tool`, { text });
  }
  assert(!localToken || localToken.length < 8 || !text.includes(localToken), `${name} leaked the raw Workbench Context token`, {
    tokenFile
  });
}

class OneShotStdioClient {
  constructor(config, { clientId = "" } = {}) {
    const server = Object.values(config.mcpServers || {})[0] || {};
    this.pending = new Map();
    this.nextId = 1;
    this.stderr = "";
    this.child = spawn(server.command, server.args || [], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        ...(server.env || {}),
        ...(clientId ? {
          COCKPIT_CLIENT_ID: clientId,
          COCKPIT_CLIENT_PROVIDER: "fixture-client-kit",
          COCKPIT_HEARTBEAT_INTERVAL_MS: "15000"
        } : {})
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    this.rl = createInterface({ input: this.child.stdout, crlfDelay: Infinity });
    this.rl.on("line", (line) => this.onLine(line));
    this.child.stderr.on("data", (chunk) => {
      this.stderr += chunk.toString();
    });
    this.child.on("exit", (code, signal) => {
      for (const pending of this.pending.values()) {
        pending.reject(new Error(`kit stdio bridge exited code=${code} signal=${signal} stderr=${this.stderr}`));
      }
      this.pending.clear();
    });
  }

  onLine(line) {
    let payload;
    try {
      payload = JSON.parse(line);
    } catch {
      return;
    }
    const messages = Array.isArray(payload) ? payload : [payload];
    for (const message of messages) {
      const pending = this.pending.get(message.id);
      if (!pending) continue;
      clearTimeout(pending.timeout);
      this.pending.delete(message.id);
      if (message.error) {
        const error = new Error(message.error.message || "MCP error");
        error.detail = message.error;
        pending.reject(error);
      } else {
        pending.resolve(message);
      }
    }
  }

  rpc(method, params = {}, timeoutMs = 20000) {
    const id = `kit-${this.nextId++}`;
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`timeout waiting for ${method}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timeout });
      this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    });
  }

  close() {
    this.rl.close();
    this.child.stdin.end();
    setTimeout(() => {
      if (!this.child.killed) this.child.kill("SIGTERM");
    }, 250).unref();
  }
}

try {
  const requiredFiles = [
    "claude_desktop_config.json",
    "cursor_mcp.json",
    "kimi_mcp.json",
    "generic_stdio_mcp.json",
    "http_mcp.json",
    "http_mcp.redacted.json",
    "hosted_subscription_connection.json",
    "hosted_subscription_connection.redacted.json",
    "connection-pack.json",
    "claude_desktop_subscription_setup.txt",
    "chatgpt_subscription_setup.txt",
    "grok_subscription_setup.txt",
    "README.md"
  ];
  const stats = await stat(kitDir);
  assert(stats.isDirectory(), "client kit directory is not a directory", { kitDir });

  const files = {};
  for (const name of requiredFiles) {
    const file = path.join(kitDir, name);
    await access(file, constants.R_OK);
    files[name] = file;
  }

  const claude = await readJson(files["claude_desktop_config.json"]);
  const cursor = await readJson(files["cursor_mcp.json"]);
  const kimi = await readJson(files["kimi_mcp.json"]);
  const http = await readJson(files["http_mcp.json"]);
  const hostedPacket = await readJson(files["hosted_subscription_connection.json"]);
  const hostedPacketRedacted = await readJson(files["hosted_subscription_connection.redacted.json"]);
  const connectionPack = await readJson(files["connection-pack.json"]);
  const localToken = await readLocalMcpToken();
  const setupTexts = {
    "claude_desktop_subscription_setup.txt": await readFile(files["claude_desktop_subscription_setup.txt"], "utf8"),
    "chatgpt_subscription_setup.txt": await readFile(files["chatgpt_subscription_setup.txt"], "utf8"),
    "grok_subscription_setup.txt": await readFile(files["grok_subscription_setup.txt"], "utf8")
  };

  assertSubscriptionSetupText("claude_desktop_subscription_setup.txt", setupTexts["claude_desktop_subscription_setup.txt"], {
    clientId: "claude-desktop",
    localToken
  });
  assertSubscriptionSetupText("chatgpt_subscription_setup.txt", setupTexts["chatgpt_subscription_setup.txt"], {
    clientId: "chatgpt",
    localToken
  });
  assertSubscriptionSetupText("grok_subscription_setup.txt", setupTexts["grok_subscription_setup.txt"], {
    clientId: "grok",
    localToken
  });

  for (const [name, config] of Object.entries({ claude, cursor, kimi })) {
    const serverName = `beagle-workbench-${projectSlug}`;
    const server = config.mcpServers?.[serverName];
    assert(server?.command === "node", `${name} config is missing node command`, config);
    assert(Array.isArray(server.args) && server.args[0]?.endsWith("bin/workbench-context-mcp.mjs"), `${name} config points at wrong bridge`, config);
    assert(server.env?.COCKPIT_PROJECT === projectSlug, `${name} config has wrong project`, config);
    assert(String(server.env?.COCKPIT_MCP_PATH || "").includes(`/api/workbench/${projectSlug}/context/mcp`), `${name} config has wrong MCP path`, config);
  }

  assert(isProjectMcpUrl(http.clients?.chatgpt?.url), "ChatGPT HTTP MCP URL missing", http);
  assert(isProjectMcpUrl(http.clients?.grok?.url), "Grok HTTP MCP URL missing", http);
  assert(http.publicEndpoint && typeof http.publicEndpoint === "object", "HTTP MCP config missing public endpoint doctor output", http);
  assert(typeof http.publicEndpoint.hostedClientReachable === "boolean", "HTTP MCP config missing hosted reachability status", http);
  assert(queryParam(http.clients?.chatgpt?.url, "client_id") === "chatgpt", "ChatGPT HTTP MCP URL is not client-scoped", http);
  assert(queryParam(http.clients?.grok?.url, "client_id") === "grok", "Grok HTTP MCP URL is not client-scoped", http);
  assert(http.clients?.chatgpt?.headers?.["x-beagle-client-id"] === "chatgpt", "ChatGPT HTTP MCP headers do not identify the client", http);
  assert(http.clients?.grok?.headers?.["x-beagle-client-id"] === "grok", "Grok HTTP MCP headers do not identify the client", http);
  assert(hostedPacket.schema === "beagle.workbench-hosted-subscription-connection.v1", "hosted subscription packet missing", hostedPacket);
  assert(hostedPacketRedacted.schema === "beagle.workbench-hosted-subscription-connection.v1", "redacted hosted subscription packet missing", hostedPacketRedacted);
  assert(cleanString(hostedPacketRedacted.clients?.chatgpt?.headers?.authorization) === "Bearer <workbench-context-token>", "redacted hosted packet leaked or lost auth marker", hostedPacketRedacted);
  assert(!localToken || localToken.length < 8 || !JSON.stringify(hostedPacketRedacted).includes(localToken), "redacted hosted packet leaked the raw token", {
    tokenFile
  });
  if (connectionPack.auth?.required?.http_mcp === true) {
    assert(localToken, "HTTP MCP auth is required but no local token file/env is available", { tokenFile });
    assert(
      String(http.clients?.chatgpt?.headers?.authorization || "").startsWith("Bearer "),
      "ChatGPT HTTP MCP config missing authorization header",
      http.clients?.chatgpt
    );
    assert(
      String(http.clients?.grok?.headers?.authorization || "").startsWith("Bearer "),
      "Grok HTTP MCP config missing authorization header",
      http.clients?.grok
    );
  }
  assert(connectionPack.clients?.some((client) => client.client_id === "claude-desktop"), "connection pack missing Claude Desktop", connectionPack);
  assert(connectionPack.clients?.some((client) => client.client_id === "kimi"), "connection pack missing Kimi", connectionPack);

  const fixtureHttpClientId = `fixture-http-mcp-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`;
  const httpMcpUrl = `${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp?client_id=${encodeURIComponent(fixtureHttpClientId)}&provider=fixture-http-mcp`;
  const httpHeaders = {
    ...(http.clients?.chatgpt?.headers || {}),
    "x-beagle-client-id": fixtureHttpClientId,
    "x-beagle-provider": "fixture-http-mcp",
    ...(localToken ? { authorization: `Bearer ${localToken}` } : {})
  };
  const httpInit = await fetchJson(httpMcpUrl, {
    method: "POST",
    headers: httpHeaders,
    body: {
      jsonrpc: "2.0",
      id: "http-init",
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "workbench-http-mcp-client-kit-verifier", version: "0.1.0" }
      }
    }
  });
  assert(httpInit.result?.serverInfo?.name === "beagle-workbench-context", "HTTP MCP initialize failed", httpInit);
  const httpExport = await fetchJson(httpMcpUrl, {
    method: "POST",
    headers: httpHeaders,
    body: {
      jsonrpc: "2.0",
      id: "http-export",
      method: "tools/call",
      params: {
        name: "workbench_context_export",
        arguments: { source: fixtureHttpClientId, limit: 10 }
      }
    }
  });
  const httpHeartbeatData = httpExport.result?.structuredContent || {};
  assert((httpHeartbeatData.records || []).some((item) => (item.tags || []).includes("http-mcp") && (item.tags || []).includes("auto-heartbeat")), "HTTP MCP auto heartbeat did not write fixture presence", httpHeartbeatData);

  const fixtureClientId = `fixture-kit-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`;
  const stdio = new OneShotStdioClient(claude, { clientId: fixtureClientId });
  try {
    const init = await stdio.rpc("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "workbench-mcp-client-kit-verifier", version: "0.1.0" }
    });
    assert(init.result?.serverInfo?.name === "beagle-workbench-context-stdio", "kit stdio initialize failed", init);
    const tools = await stdio.rpc("tools/list");
    const toolNames = (tools.result?.tools || []).map((tool) => tool.name);
    assert(toolNames.includes("workbench_context_client_heartbeat"), "kit stdio missing heartbeat tool", tools);
    assert(toolNames.includes("cockpit_workbench_context_reply"), "kit stdio missing reply alias", tools);
    const heartbeatExport = await stdio.rpc("tools/call", {
      name: "workbench_context_export",
      arguments: { source: fixtureClientId, limit: 10 }
    });
    const heartbeatData = heartbeatExport.result?.structuredContent || {};
    assert((heartbeatData.records || []).some((item) => (item.tags || []).includes("auto-heartbeat")), "kit stdio auto heartbeat did not write fixture presence", heartbeatData);
  } finally {
    stdio.close();
  }

  const result = {
    ok: true,
    schema: "beagle.workbench-mcp-client-kit-verification.v1",
    kind: "mcp-client-kit",
    projectSlug,
    kitDir,
    fileCount: requiredFiles.length,
    stdioClients: ["claude-desktop", "cursor", "kimi", "generic"],
    httpClients: ["chatgpt", "grok"],
    subscriptionSetupFiles: Object.keys(setupTexts),
    publicEndpoint: http.publicEndpoint,
    hostedClientReachable: http.publicEndpoint.hostedClientReachable === true,
    authRequired: connectionPack.auth?.required?.http_mcp === true,
    authHeaderPresent: Boolean(http.clients?.chatgpt?.headers?.authorization),
    heartbeatFixtureClientId: fixtureClientId,
    httpHeartbeatFixtureClientId: fixtureHttpClientId,
    bridgePath: claude.mcpServers?.[`beagle-workbench-${projectSlug}`]?.args?.[0] || "",
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-client-kit-files-stdio-tools-and-http-mcp-auto-heartbeat"
  };
  await appendVerificationRecord({ ...result, generatedAt: new Date().toISOString() });
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    kitDir,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
