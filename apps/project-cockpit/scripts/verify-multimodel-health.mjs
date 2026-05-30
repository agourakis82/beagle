#!/usr/bin/env node

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

async function fetchJson(url) {
  const res = await fetch(url);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const error = new Error(`${res.status} ${payload?.error || res.statusText}`);
    error.detail = payload;
    throw error;
  }
  return payload;
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
const minLiveNow = Number(process.env.VERIFY_MULTIMODEL_MIN_LIVE_NOW || process.argv[3] || 3);
const maxContextAgeMs = Number(process.env.VERIFY_MULTIMODEL_MAX_CONTEXT_AGE_MS || 30 * 60 * 1000);

try {
  const url = `${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/health?minLiveNow=${encodeURIComponent(minLiveNow)}&maxContextAgeMs=${encodeURIComponent(maxContextAgeMs)}`;
  const health = await fetchJson(url);
  assert(health.ok === true, "multimodel health is not ok", health);
  assert(health.checks?.activeTurnsClear === true, "active turns are not clear", health);
  assert(health.checks?.minimumLiveNow === true, "not enough live providers", health);
  assert(health.checks?.contextProofFresh === true, "context proof is stale or missing", health);
  assert(health.checks?.contextCoversLiveNow === true, "context proof does not cover live providers", health);
  assert(health.checks?.subscriptionClientsSeparated === true, "subscription clients are not separated from live realtime providers", health);
  assert(health.checks?.mcpContractFresh === true, "MCP subscription bridge contract proof is stale or missing", health);
  assert(health.checks?.mcpRealtimeFresh === true, "MCP subscription bridge realtime proof is stale or missing", health);
  assert(health.checks?.realChatFresh === true, "substantial multimodel real-chat proof is stale or missing", health);
  assert(health.checks?.mcpCancelFresh === true, "MCP subscription cancel proof is stale or missing", health);
  assert(health.checks?.uiSendFresh === true, "multimodel UI send proof is stale or missing", health);
  assert(health.checks?.uiStopFresh === true, "multimodel UI stop proof is stale or missing", health);
  assert(health.checks?.mcpStdioFresh === true, "MCP subscription STDIO bridge proof is stale or missing", health);
  assert(health.checks?.httpMcpAuthFresh === true, "HTTP MCP auth proof is stale or missing", health);
  assert(health.checks?.remoteMcpTransportFresh === true, "remote MCP streamable HTTP/SSE proof is stale or missing", health);
  assert(health.checks?.mcpClientKitFresh === true, "MCP subscription client kit proof is stale or missing", health);
  assert(health.checks?.mcpClientInstallFresh === true, "MCP subscription client install proof is stale or missing", health);
  console.log(JSON.stringify(health, null, 2));
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
