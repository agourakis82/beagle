#!/usr/bin/env node

import { access, appendFile, readFile } from "node:fs/promises";
import { constants } from "node:fs";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import path from "node:path";
import os from "node:os";

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

async function readJson(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const home = os.homedir();
const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");
const tokenFile = path.join(DATA_DIR, "workbench-context", `${safeSlug(projectSlug)}.http-mcp-token`);
const installDir = path.resolve(
  process.env.WORKBENCH_MCP_INSTALL_DIR ||
    path.join(home, ".config", "beagle-workbench", "mcp", safeSlug(projectSlug))
);
const manifestPath = path.join(installDir, "install-manifest.json");
const verificationPath = path.join(DATA_DIR, "multimodel-chat", `${safeSlug(projectSlug)}.verifications.jsonl`);
const serverName = `beagle-workbench-${projectSlug}`;

async function appendVerificationRecord(record) {
  await appendFile(verificationPath, `${JSON.stringify(record)}\n`, "utf8");
}

async function readLocalMcpToken() {
  const envToken =
    cleanString(process.env.COCKPIT_TOKEN) ||
    cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
    cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
  if (envToken) return envToken;
  try {
    return cleanString(await readFile(tokenFile, "utf8"));
  } catch {
    return "";
  }
}

class LauncherClient {
  constructor({ launcher, clientId, token = "" }) {
    this.nextId = 1;
    this.pending = new Map();
    this.stderr = "";
    this.child = spawn(launcher, [], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        COCKPIT_API: process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370",
        COCKPIT_PROJECT: projectSlug,
        COCKPIT_CLIENT_ID: clientId,
        COCKPIT_CLIENT_PROVIDER: "fixture-install",
        COCKPIT_HEARTBEAT_INTERVAL_MS: "15000",
        PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE: tokenFile,
        ...(token ? { COCKPIT_TOKEN: token } : {})
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
        pending.reject(new Error(`installed launcher exited code=${code} signal=${signal} stderr=${this.stderr}`));
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
    const id = `install-${this.nextId++}`;
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
  const manifest = await readJson(manifestPath);
  assert(manifest.schema === "beagle.workbench-mcp-client-install.v1", "unexpected install manifest schema", manifest);
  assert(manifest.projectSlug === projectSlug, "install manifest project mismatch", manifest);
  assert(manifest.launcher && manifest.launcher.includes(`beagle-workbench-${projectSlug}-mcp`), "install manifest launcher missing", manifest);
  await access(manifest.launcher, constants.X_OK);

  for (const file of manifest.copied || []) {
    await access(file, constants.R_OK);
  }
  const installedHttpMcp = await readJson(path.join(installDir, "http_mcp.json"));
  assert(installedHttpMcp.publicEndpoint && typeof installedHttpMcp.publicEndpoint === "object", "installed HTTP MCP config missing public endpoint doctor output", installedHttpMcp);
  assert(typeof installedHttpMcp.publicEndpoint.hostedClientReachable === "boolean", "installed HTTP MCP config missing hosted reachability status", installedHttpMcp);
  const hostedPacket = await readJson(path.join(installDir, "hosted_subscription_connection.json"));
  const hostedPacketRedacted = await readJson(path.join(installDir, "hosted_subscription_connection.redacted.json"));
  assert(hostedPacket.schema === "beagle.workbench-hosted-subscription-connection.v1", "installed hosted subscription packet missing", hostedPacket);
  assert(hostedPacketRedacted.schema === "beagle.workbench-hosted-subscription-connection.v1", "installed redacted hosted subscription packet missing", hostedPacketRedacted);
  assert(/^Bearer \S{16,}$/.test(cleanString(hostedPacket.clients?.chatgpt?.headers?.authorization)), "installed hosted packet is missing real bearer auth", hostedPacket);
  assert(cleanString(hostedPacketRedacted.clients?.chatgpt?.headers?.authorization) === "Bearer <workbench-context-token>", "installed redacted hosted packet leaked or lost auth marker", hostedPacketRedacted);

  const targetFiles = (manifest.clientTargets || []).length
    ? (manifest.clientTargets || []).map((target) => target.file)
    : [
        path.join(home, ".claude", "settings.json"),
        path.join(home, ".config", "Claude", "claude_desktop_config.json"),
        path.join(home, ".cursor", "mcp.json")
      ];
  const configuredTargets = [];
  for (const file of targetFiles) {
    let config = {};
    try {
      config = await readJson(file);
    } catch {
      continue;
    }
    if (config.mcpServers?.[serverName]) configuredTargets.push(file);
  }
  assert(configuredTargets.length > 0, `no installed client config mentions ${serverName}`, { targetFiles });

  const localToken = await readLocalMcpToken();
  const fixtureClientId = `fixture-install-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`;
  const client = new LauncherClient({ launcher: manifest.launcher, clientId: fixtureClientId, token: localToken });
  try {
    const init = await client.rpc("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "workbench-mcp-install-verifier", version: "0.1.0" }
    });
    assert(init.result?.serverInfo?.name === "beagle-workbench-context-stdio", "installed launcher initialize failed", init);
    const tools = await client.rpc("tools/list");
    const toolNames = (tools.result?.tools || []).map((tool) => tool.name);
    assert(toolNames.includes("workbench_context_inbox"), "installed launcher missing inbox tool", tools);
    assert(toolNames.includes("cockpit_workbench_context_reply"), "installed launcher missing stdio reply alias", tools);
    const heartbeatExport = await client.rpc("tools/call", {
      name: "workbench_context_export",
      arguments: { source: fixtureClientId, limit: 10 }
    });
    const heartbeatData = heartbeatExport.result?.structuredContent || {};
    assert((heartbeatData.records || []).some((item) => (item.tags || []).includes("auto-heartbeat")), "installed launcher did not write auto heartbeat", heartbeatData);
  } finally {
    client.close();
  }

  const result = {
    ok: true,
    schema: "beagle.workbench-mcp-client-install-verification.v1",
    kind: "mcp-client-install",
    projectSlug,
    installDir,
    launcher: manifest.launcher,
    copiedCount: (manifest.copied || []).length,
    hostedSubscriptionPacket: path.join(installDir, "hosted_subscription_connection.json"),
    hostedSubscriptionPacketRedacted: path.join(installDir, "hosted_subscription_connection.redacted.json"),
    publicEndpoint: installedHttpMcp.publicEndpoint,
    hostedClientReachable: installedHttpMcp.publicEndpoint.hostedClientReachable === true,
    configuredTargets,
    heartbeatFixtureClientId: fixtureClientId,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-installed-launcher-and-client-configs"
  };
  await appendVerificationRecord({ ...result, generatedAt: new Date().toISOString() });
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    installDir,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
