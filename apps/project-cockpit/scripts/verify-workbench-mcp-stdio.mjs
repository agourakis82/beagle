#!/usr/bin/env node

import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { appendFile, mkdir, readFile } from "node:fs/promises";
import path from "node:path";

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
const bridgePath = path.resolve(process.cwd(), "bin/workbench-context-mcp.mjs");
const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
}

async function appendVerificationRecord(slug, record) {
  const file = verificationFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
}

async function readLocalMcpToken() {
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

class StdioMcpClient {
  constructor({ clientId, token = "" }) {
    this.nextId = 1;
    this.pending = new Map();
    this.stderr = "";
    this.child = spawn(process.execPath, [bridgePath], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        COCKPIT_API: apiBase,
        COCKPIT_PROJECT: projectSlug,
        COCKPIT_MCP_PATH: `/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp`,
        COCKPIT_CLIENT_ID: clientId,
        COCKPIT_CLIENT_PROVIDER: "fixture-stdio",
        COCKPIT_HEARTBEAT_INTERVAL_MS: "15000",
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
        pending.reject(new Error(`stdio bridge exited code=${code} signal=${signal} stderr=${this.stderr}`));
      }
      this.pending.clear();
    });
  }

  onLine(line) {
    let payload;
    try {
      payload = JSON.parse(line);
    } catch (error) {
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

  rpc(method, params = {}, { timeoutMs = 20000 } = {}) {
    const id = `stdio-${this.nextId++}`;
    const body = { jsonrpc: "2.0", id, method, params };
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`timeout waiting for ${method}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timeout });
      this.child.stdin.write(`${JSON.stringify(body)}\n`);
    });
  }

  notify(method, params = {}) {
    this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, params })}\n`);
  }

  async callTool(name, args = {}) {
    const response = await this.rpc("tools/call", { name, arguments: args });
    return response.result?.structuredContent || {};
  }

  close() {
    this.rl.close();
    this.child.stdin.end();
    setTimeout(() => {
      if (!this.child.killed) this.child.kill("SIGTERM");
    }, 250).unref();
  }
}

const marker = `mcp-stdio-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`;
const clientId = `fixture-stdio-${marker}`;
const threadId = `mcp-stdio:${projectSlug}:${marker}`;
const messageId = `${marker}:handoff`;
const replyText = `stdio bridge reply ${marker}`;
const localToken = await readLocalMcpToken();
const client = new StdioMcpClient({ clientId, token: localToken });

try {
  const init = await client.rpc("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "workbench-mcp-stdio-verifier", version: "0.1.0" }
  });
  assert(init.result?.serverInfo?.name === "beagle-workbench-context-stdio", "initialize returned unexpected server", init);
  client.notify("notifications/initialized");

  const toolsPayload = await client.rpc("tools/list");
  const toolNames = (toolsPayload.result?.tools || []).map((tool) => tool.name);
  const tools = new Set(toolNames);
  for (const name of [
    "workbench_context_client_heartbeat",
    "workbench_context_send",
    "workbench_context_inbox",
    "workbench_context_claim",
    "workbench_context_reply",
    "workbench_context_graphrag",
    "cockpit_workbench_context_reply",
    "cockpit_workbench_context_client_heartbeat",
    "beagle_memory_query",
    "beagle_memory_ingest_chat"
  ]) {
    assert(tools.has(name), `missing STDIO MCP tool ${name}`, toolsPayload);
  }

  const autoHeartbeat = await client.callTool("workbench_context_export", {
    source: clientId,
    limit: 10
  });
  assert((autoHeartbeat.records || []).some((item) => (item.tags || []).includes("auto-heartbeat")), "automatic STDIO heartbeat did not write client presence", autoHeartbeat);

  const heartbeat = await client.callTool("cockpit_workbench_context_client_heartbeat", {
    client_id: clientId,
    provider: "fixture-stdio",
    session_id: threadId,
    status: "online",
    note: "stdio bridge verifier; not a model provider",
    tags: ["mcp-stdio", marker]
  });
  assert(heartbeat.status === "ok" && heartbeat.client_id === clientId, "stdio heartbeat failed", heartbeat);

  const sent = await client.callTool("workbench_context_send", {
    from_client: "project-cockpit-stdio-verifier",
    to_client: clientId,
    subject: "STDIO MCP verifier handoff",
    content: `Please reply with ${replyText}`,
    priority: "normal",
    thread_id: threadId,
    message_id: messageId,
    requires_response: true,
    tags: ["mcp-stdio", marker]
  });
  assert(sent.message?.message_id === messageId, "stdio handoff send failed", sent);

  const inbox = await client.callTool("workbench_context_inbox", { client_id: clientId, limit: 20 });
  assert((inbox.messages || []).some((item) => item.message_id === messageId), "stdio handoff missing from inbox", inbox);

  const claim = await client.callTool("workbench_context_claim", {
    message_id: messageId,
    client_id: clientId,
    note: "stdio verifier claimed"
  });
  assert(claim.message?.status === "claimed", "stdio claim failed", claim);

  const reply = await client.callTool("cockpit_workbench_context_reply", {
    message_id: messageId,
    client_id: clientId,
    provider: "fixture-stdio",
    text: replyText,
    metadata: { marker, stdio_verifier: true }
  });
  assert(reply.status === "ok" && reply.reply?.memory_id, "stdio reply failed", reply);

  const graph = await client.callTool("workbench_context_graphrag", {
    query: marker,
    limit: 5,
    query_mode: "stdio-contract"
  });
  assert((graph.highlights || []).some((item) => String(item.text || item.snippet || "").includes(replyText)), "stdio GraphRAG did not retrieve reply", graph);

  const legacyText = `stdio legacy beagle memory alias ${marker}`;
  const legacyIngest = await client.callTool("beagle_memory_ingest_chat", {
    source: "legacy-beagle-mcp-stdio",
    conversation_id: threadId,
    turn_index: 0,
    role: "assistant",
    text: legacyText,
    domain: "beagle-memory-compat",
    tags: ["mcp-stdio", marker],
    provider: "fixture-stdio",
    model: "fixture"
  });
  assert(legacyIngest.status === "ok" && legacyIngest.read_after_write === true, "stdio legacy beagle memory ingest failed", legacyIngest);

  const legacyQuery = await client.callTool("beagle_memory_query", {
    query: legacyText,
    top_k: 5,
    domain: "beagle-memory-compat",
    tags: ["mcp-stdio"]
  });
  assert((legacyQuery.results || []).some((item) => String(item.text || item.snippet || "").includes(legacyText)), "stdio legacy beagle memory query did not retrieve ingested chat", legacyQuery);

  const result = {
    ok: true,
    projectSlug,
    clientId,
    threadId,
    messageId,
    replyText,
    bridgePath,
    toolCount: tools.size,
    aliasToolCount: toolNames.filter((name) => name.startsWith("cockpit_workbench_context_")).length,
    heartbeatAt: heartbeat.heartbeat_at,
    replyMemoryId: reply.reply.memory_id,
    graphMatches: (graph.highlights || []).length,
    legacyMemoryMatches: (legacyQuery.results || []).length,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-stdio-mcp-proxy-handoff-reply-graphrag"
  };
  await appendVerificationRecord(projectSlug, {
    schema: "beagle.workbench-mcp-stdio-verification.v1",
    kind: "mcp-stdio",
    ...result,
    generatedAt: new Date().toISOString()
  });
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    clientId,
    messageId,
    error: error.message,
    detail: error.detail || null,
    stderr: client.stderr,
    truthMode: "verification-failed"
  }, null, 2));
  process.exitCode = 1;
} finally {
  client.close();
}
