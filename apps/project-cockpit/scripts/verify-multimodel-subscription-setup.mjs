#!/usr/bin/env node

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

function queryParam(value, key) {
  try {
    return new URL(value, "http://127.0.0.1").searchParams.get(key) || "";
  } catch {
    return "";
  }
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const expected = [
  { id: "claude-desktop", targetClient: "claude-desktop", provider: "anthropic" },
  { id: "chatgpt-mcp", targetClient: "chatgpt", provider: "openai" },
  { id: "grok-mcp", targetClient: "grok", provider: "xai" }
];

try {
  const [setup, readiness, connectionPack] = await Promise.all([
    fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/setup`),
    fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/readiness`),
    fetchJson(`${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/connect?base_url=${encodeURIComponent(apiBase)}`)
  ]);

  const setupClients = setup.subscriptionClients || [];
  const setupActions = setup.actions || [];
  const readinessProviders = readiness.providers || [];
  const connectionClients = connectionPack.clients || [];

  const observed = [];
  for (const item of expected) {
    const client = setupClients.find((entry) => entry.id === item.id);
    const action = setupActions.find((entry) => entry.id === item.id);
    const provider = readinessProviders.find((entry) => entry.id === item.id);
    const connection = connectionClients.find((entry) => entry.client_id === item.targetClient);

    assert(client, `missing setup subscription client ${item.id}`, setup);
    assert(action, `missing setup action ${item.id}`, setup);
    assert(provider, `missing readiness provider ${item.id}`, readiness);
    assert(connection, `missing connection-pack client ${item.targetClient}`, connectionPack);

    for (const source of [client, action, provider]) {
      assert(source.mcpEndpoint?.includes(`/api/workbench/${projectSlug}/context/mcp`), `${item.id} missing project MCP endpoint`, source);
      assert(queryParam(source.mcpEndpoint, "client_id") === item.targetClient, `${item.id} endpoint missing client_id`, source);
      assert(queryParam(source.mcpEndpoint, "provider") === item.provider, `${item.id} endpoint missing provider`, source);
      assert(source.mcpHeaders?.["x-beagle-client-id"] === item.targetClient, `${item.id} missing client header`, source);
      assert(source.mcpHeaders?.["x-beagle-provider"] === item.provider, `${item.id} missing provider header`, source);
    }

    assert(action.inboxTool === "workbench_context_inbox", `${item.id} missing inbox tool`, action);
    assert(action.claimTool === "workbench_context_claim", `${item.id} missing claim tool`, action);
    assert(action.directReplyEndpoint?.includes("/multimodel/mcp-inbox/:message_id/reply"), `${item.id} missing direct reply endpoint`, action);
    assert(action.directCancelEndpoint?.includes("/multimodel/mcp-inbox/:message_id/cancel"), `${item.id} missing direct cancel endpoint`, action);

    if (client.status === "live") {
      assert(client.clientPresence === "recent", `${item.id} marked live without recent presence`, client);
    }

    observed.push({
      id: item.id,
      targetClient: item.targetClient,
      status: client.status,
      clientPresence: client.clientPresence,
      mcpEndpoint: client.mcpEndpoint
    });
  }

  const result = {
    ok: true,
    schema: "beagle.multimodel-subscription-setup-verification.v1",
    kind: "subscription-setup",
    projectSlug,
    clients: observed,
    setupTruthMode: setup.truthMode,
    readinessTruthMode: readiness.truthMode,
    connectionPackTruthMode: connectionPack.truthMode,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-runtime-setup-and-connection-pack"
  };
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
