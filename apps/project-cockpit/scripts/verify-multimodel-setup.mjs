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

try {
  const url = `${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/setup`;
  const setup = await fetchJson(url);
  const byId = new Map((setup.actions || []).map((item) => [item.id, item]));
  const kimi = byId.get("kimi");
  const grok = byId.get("grok");
  assert(setup.schema === "beagle.multimodel-setup.v1", "unexpected setup schema", setup);
  assert(Array.isArray(setup.liveNow) && setup.liveNow.length >= 1, "no live providers reported", setup);
  assert(kimi, "missing Kimi setup action", setup);
  assert(grok, "missing Grok setup action", setup);
  assert(setup.guards?.noImplicitKimiBridge === true, "Kimi bridge guard is not active", setup);
  assert(kimi.bridgeMode !== "cross-project-zellij" || kimi.crossProjectAllowed === true, "Kimi cross-project bridge is active without opt-in", kimi);
  assert((kimi.missing || []).includes("PROJECT_COCKPIT_KIMI_ZELLIJ_PROJECT_SLUG") || kimi.status === "ready", "Kimi setup does not expose project slug requirement", kimi);
  assert((grok.missing || []).includes("XAI_API_KEY") || grok.status === "ready", "Grok setup does not expose XAI_API_KEY requirement", grok);
  assert(setup.clientKit?.status === "ready", "MCP client kit is not setup-ready", setup.clientKit);
  assert(setup.clientKit?.installProof?.ok === true, "MCP client kit is not installed/verified locally", setup.clientKit);
  assert(Array.isArray(setup.clientKit?.files) && setup.clientKit.files.length >= 7, "MCP client kit files are missing", setup.clientKit);
  assert(setup.clientKit.files.every((file) => file.exists === true), "one or more MCP client kit files do not exist", setup.clientKit);
  assert(Array.isArray(setup.subscriptionClients) && setup.subscriptionClients.length >= 3, "subscription MCP clients are not exposed", setup);
  assert(setup.subscriptionClients.some((client) => client.targetClient === "chatgpt"), "ChatGPT subscription client is missing", setup.subscriptionClients);
  assert(setup.subscriptionClients.some((client) => client.targetClient === "claude-desktop"), "Claude Desktop subscription client is missing", setup.subscriptionClients);
  assert(setup.subscriptionClients.every((client) => Array.isArray(client.requiredToolFlow) && client.requiredToolFlow.includes("workbench_context_reply")), "subscription client tool flow is incomplete", setup.subscriptionClients);
  console.log(JSON.stringify(setup, null, 2));
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
