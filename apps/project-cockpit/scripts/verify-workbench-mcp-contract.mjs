#!/usr/bin/env node

import { appendFile, mkdir, readFile } from "node:fs/promises";
import path from "node:path";

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

let mcpHeaders = {};

async function callTool({ mcpUrl, name, args = {} }) {
  const response = await fetchJson(mcpUrl, {
    method: "POST",
    headers: mcpHeaders,
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

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
}

async function readLocalMcpToken(slug) {
  const envToken =
    cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
    cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
  if (envToken) return envToken;
  try {
    return cleanString(await readFile(path.join(DATA_DIR, "workbench-context", `${safeSlug(slug)}.http-mcp-token`), "utf8"));
  } catch {
    return "";
  }
}

async function appendVerificationRecord(slug, record) {
  const file = verificationFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
const base = apiBase.replace(/\/$/, "");
const mcpUrl = `${base}/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp`;
const localToken = await readLocalMcpToken(projectSlug);
mcpHeaders = localToken ? { authorization: `Bearer ${localToken}` } : {};
const marker = `mcp-contract-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`;
const clientId = `fixture-mcp-${marker}`;
const threadId = `mcp-contract:${projectSlug}:${marker}`;
const messageId = `${marker}:handoff`;
const replyText = `fixture reply ${marker}`;

try {
  const toolsPayload = await fetchJson(mcpUrl, {
    method: "POST",
    headers: mcpHeaders,
    body: { jsonrpc: "2.0", id: "tools", method: "tools/list", params: {} }
  });
  const tools = new Set((toolsPayload.result?.tools || []).map((tool) => tool.name));
  for (const name of [
    "workbench_context_client_heartbeat",
    "workbench_context_join",
    "workbench_context_send",
    "workbench_context_inbox",
    "workbench_context_claim",
    "workbench_context_heartbeat",
    "workbench_context_reply",
    "workbench_context_board",
    "workbench_context_graphrag",
    "beagle_memory_query",
    "beagle_memory_ingest_chat"
  ]) {
    assert(tools.has(name), `missing MCP tool ${name}`, toolsPayload);
  }

  const heartbeat = await callTool({
    mcpUrl,
    name: "workbench_context_client_heartbeat",
    args: {
      client_id: clientId,
      provider: "fixture",
      session_id: threadId,
      status: "online",
      note: "contract verifier; not a model provider",
      tags: ["mcp-contract", marker]
    }
  });
  assert(heartbeat.status === "ok" && heartbeat.client_id === clientId, "heartbeat failed", heartbeat);

  const joinedBeforeHandoff = await callTool({
    mcpUrl,
    name: "workbench_context_join",
    args: {
      client_id: clientId,
      provider: "fixture",
      session_id: threadId,
      note: "contract verifier join before handoff",
      limit: 5
    }
  });
  assert(joinedBeforeHandoff.status === "ok" && joinedBeforeHandoff.client_id === clientId, "join failed before handoff", joinedBeforeHandoff);

  const sent = await callTool({
    mcpUrl,
    name: "workbench_context_send",
    args: {
      from_client: "project-cockpit-contract-verifier",
      to_client: clientId,
      subject: "MCP contract verifier handoff",
      content: `Please reply with ${replyText}`,
      priority: "normal",
      thread_id: threadId,
      message_id: messageId,
      requires_response: true,
      tags: ["mcp-contract", marker]
    }
  });
  assert(sent.message?.message_id === messageId, "handoff send failed", sent);

  const inbox = await callTool({
    mcpUrl,
    name: "workbench_context_inbox",
    args: { client_id: clientId, limit: 20 }
  });
  const inboxMessage = (inbox.messages || []).find((item) => item.message_id === messageId);
  assert(inboxMessage, "handoff did not appear in client inbox", inbox);

  const joined = await callTool({
    mcpUrl,
    name: "workbench_context_join",
    args: {
      client_id: clientId,
      provider: "fixture",
      session_id: threadId,
      note: "contract verifier join after handoff",
      limit: 5
    }
  });
  assert(joined.next_handoff?.message_id === messageId, "join did not return next handoff", joined);
  assert(joined.next_handoff?.reply_args?.message_id === messageId, "join did not return reply args", joined);

  const claim = await callTool({
    mcpUrl,
    name: "workbench_context_claim",
    args: { message_id: messageId, client_id: clientId, note: "contract verifier claimed" }
  });
  assert(claim.message?.status === "claimed", "claim failed", claim);

  const progress = await callTool({
    mcpUrl,
    name: "workbench_context_heartbeat",
    args: { message_id: messageId, client_id: clientId, progress: "halfway", note: marker }
  });
  assert(progress.message?.last_heartbeat_at || progress.lifecycle?.heartbeat_at, "message heartbeat failed", progress);

  const reply = await callTool({
    mcpUrl,
    name: "workbench_context_reply",
    args: {
      message_id: messageId,
      client_id: clientId,
      provider: "fixture",
      text: replyText,
      metadata: { marker, contract_verifier: true }
    }
  });
  assert(reply.status === "ok" && reply.reply?.memory_id, "reply failed", reply);

  const board = await callTool({
    mcpUrl,
    name: "workbench_context_board",
    args: { client_id: clientId, include_completed: true, limit: 50 }
  });
  const boardMessage = (board.messages || []).find((item) => item.message_id === messageId);
  assert(boardMessage?.status === "completed", "board did not show completed handoff", board);

  const graph = await callTool({
    mcpUrl,
    name: "workbench_context_graphrag",
    args: { query: marker, limit: 5, query_mode: "contract" }
  });
  assert((graph.highlights || []).some((item) => String(item.text || item.snippet || "").includes(replyText)), "GraphRAG did not retrieve reply", graph);

  const legacyText = `legacy beagle memory alias ${marker}`;
  const legacyIngest = await callTool({
    mcpUrl,
    name: "beagle_memory_ingest_chat",
    args: {
      source: "legacy-beagle-mcp-contract",
      conversation_id: threadId,
      turn_index: 0,
      role: "assistant",
      text: legacyText,
      domain: "beagle-memory-compat",
      tags: ["mcp-contract", marker],
      provider: "fixture",
      model: "fixture"
    }
  });
  assert(legacyIngest.status === "ok" && legacyIngest.read_after_write === true, "legacy beagle memory ingest failed", legacyIngest);

  const legacyQuery = await callTool({
    mcpUrl,
    name: "beagle_memory_query",
    args: { query: legacyText, top_k: 5, domain: "beagle-memory-compat", tags: ["mcp-contract"] }
  });
  assert((legacyQuery.results || []).some((item) => String(item.text || item.snippet || "").includes(legacyText)), "legacy beagle memory query did not retrieve ingested chat", legacyQuery);

  const result = {
    ok: true,
    projectSlug,
    clientId,
    threadId,
    messageId,
    replyText,
    toolCount: tools.size,
    heartbeatAt: heartbeat.heartbeat_at,
    replyMemoryId: reply.reply.memory_id,
    boardStatus: boardMessage.status,
    graphMatches: (graph.highlights || []).length,
    legacyMemoryMatches: (legacyQuery.results || []).length,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-http-mcp-handoff-reply-graphrag"
  };
  await appendVerificationRecord(projectSlug, {
    schema: "beagle.workbench-mcp-contract-verification.v1",
    kind: "mcp-contract",
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
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
