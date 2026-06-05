#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
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
    headers: options.body
      ? { "content-type": "application/json", ...(options.headers || {}) }
      : options.headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
    signal: options.signal
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const error = new Error(`${res.status} ${payload?.error || res.statusText}`);
    error.detail = payload;
    throw error;
  }
  return payload;
}

async function fetchText(url, options = {}) {
  const res = await fetch(url, {
    method: options.method || "GET",
    headers: options.headers,
    signal: options.signal
  });
  const text = await res.text().catch(() => "");
  if (!res.ok) {
    const error = new Error(`${res.status} ${text || res.statusText}`);
    error.detail = { text };
    throw error;
  }
  return text;
}

async function readSseReady(url, options = {}, { timeoutMs = 7000 } = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  let reader = null;
  let text = "";
  try {
    const res = await fetch(url, {
      method: options.method || "GET",
      headers: options.headers,
      signal: ctrl.signal
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      const error = new Error(`${res.status} ${body || res.statusText}`);
      error.detail = { text: body };
      throw error;
    }
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
      if (text.includes("event: ready") || text.includes("\n\n")) {
        return {
          status: res.status,
          contentType: res.headers.get("content-type") || "",
          sessionId: res.headers.get("mcp-session-id") || "",
          text
        };
      }
    }
    return {
      status: res.status,
      contentType: res.headers.get("content-type") || "",
      sessionId: res.headers.get("mcp-session-id") || "",
      text
    };
  } finally {
    clearTimeout(timer);
    await reader?.cancel?.().catch(() => {});
    ctrl.abort();
  }
}

function clientById(bringup = {}, id) {
  return (bringup.clients || []).find((client) => client.id === id || client.targetClient === id) || null;
}

function wasLive(client = {}) {
  return client.realConnectionObserved === true || client.status === "live";
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");
const tokenFile = path.join(DATA_DIR, "workbench-context", `${projectSlug.replace(/[^a-zA-Z0-9_-]/g, "_")}.http-mcp-token`);
const startedAt = Date.now();
const targets = [
  { id: "chatgpt-mcp", clientId: "chatgpt", provider: "openai", method: "initialize" },
  { id: "grok-mcp", clientId: "grok", provider: "xai", method: "sse-listen" }
];

try {
  const token =
    cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
    cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
    cleanString(await readFile(tokenFile, "utf8").catch(() => ""));
  const before = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/bringup`);
  const beforeState = Object.fromEntries(targets.map((target) => [target.id, clientById(before, target.id)]));

  for (const target of targets) {
    const url = `${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp?client_id=${encodeURIComponent(target.clientId)}&provider=${encodeURIComponent(target.provider)}`;
    const headers = {
      "user-agent": "beagle-subscription-probe-guard/0.1 curl-compatible",
      "x-beagle-client-id": target.clientId,
      "x-beagle-provider": target.provider,
      ...(token ? { authorization: `Bearer ${token}` } : {})
    };
    if (target.method === "initialize") {
      await fetchJson(url, {
        method: "POST",
        headers: { ...headers, accept: "application/json" },
        body: {
          jsonrpc: "2.0",
          id: `probe-guard-${target.clientId}`,
          method: "initialize",
          params: {
            protocolVersion: "2025-06-18",
            capabilities: {},
            clientInfo: { name: "beagle-probe-guard", version: "0.1.0" }
          }
        }
      });
    } else {
      const sse = await readSseReady(url, {
        headers: { ...headers, accept: "text/event-stream" }
      });
      assert(sse.contentType.includes("text/event-stream"), "probe SSE did not return event-stream", { target, sse });
      assert(sse.text.includes("event: ready"), "probe SSE did not emit ready", { target, sse });
    }
  }

  const after = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/bringup`);
  for (const target of targets) {
    const beforeClient = beforeState[target.id] || {};
    const afterClient = clientById(after, target.id) || {};
    const becameLiveFromProbe = !wasLive(beforeClient) && wasLive(afterClient);
    assert(!becameLiveFromProbe, "probe traffic promoted a hosted subscription client to live", {
      target,
      before: beforeClient,
      after: afterClient,
      startedAt: new Date(startedAt).toISOString()
    });
  }

  console.log(JSON.stringify({
    ok: true,
    schema: "beagle.multimodel-subscription-probe-guard.v1",
    projectSlug,
    targets: targets.map((target) => ({
      id: target.id,
      beforeLive: wasLive(beforeState[target.id] || {}),
      afterLive: wasLive(clientById(after, target.id) || {}),
      afterPresence: clientById(after, target.id)?.clientPresence || "",
      afterLatestAt: clientById(after, target.id)?.clientLatestAt || ""
    })),
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-probe-traffic-does-not-satisfy-subscription-live"
  }, null, 2));
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
