#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

function fallbackPublicEndpointStatus(value) {
  try {
    const parsed = new URL(value);
    const host = parsed.hostname.toLowerCase();
    const loopback = ["127.0.0.1", "::1", "localhost", "0.0.0.0"].includes(host);
    const privateLan = /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[0-1])\.)/.test(host);
    const tailnet = host.endsWith(".ts.net");
    const https = parsed.protocol === "https:";
    const trustedHosted = /^(1|true|yes)$/i.test(cleanString(process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL_HOSTED_REACHABLE || ""));
    const hostedClientReachable = https && !loopback && !privateLan && (!tailnet || trustedHosted);
    return {
      url: parsed.toString().replace(/\/$/, ""),
      protocol: parsed.protocol.replace(":", ""),
      host,
      loopback,
      privateLan,
      tailnet,
      https,
      trustedHosted,
      hostedClientReachable,
      reason: hostedClientReachable
        ? "public HTTPS endpoint can be registered by hosted subscription clients"
        : tailnet
          ? "tailnet HTTPS is usable by local tailnet clients, but hosted ChatGPT/Grok need public Funnel or another internet-reachable HTTPS endpoint"
          : "hosted subscription clients cannot reach a loopback/private/non-HTTPS MCP endpoint"
    };
  } catch {
    return {
      url: value,
      protocol: "",
      host: "",
      loopback: false,
      privateLan: false,
      tailnet: false,
      https: false,
      trustedHosted: false,
      hostedClientReachable: false,
      reason: "invalid public base URL"
    };
  }
}

async function fetchJson(url, options = {}) {
  const res = await fetch(url, {
    method: options.method || "GET",
    headers: options.body ? { "content-type": "application/json" } : undefined,
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

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const publicBaseInput = cleanString(process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL || "").replace(/\/$/, "");
let publicBase = publicBaseInput || apiBase;
const bridgePath = path.resolve(process.cwd(), "bin/workbench-context-mcp.mjs");
const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");
const outDir = path.resolve(
  process.env.WORKBENCH_MCP_CLIENT_KIT_DIR ||
    path.join(DATA_DIR, "mcp-client-kit", safeSlug(projectSlug))
);
const tokenFile = path.join(DATA_DIR, "workbench-context", `${safeSlug(projectSlug)}.http-mcp-token`);
let localMcpToken = "";
const SUBSCRIPTION_SETUP_CLIENTS = [
  { id: "claude-desktop", file: "claude_desktop_subscription_setup.txt" },
  { id: "chatgpt", file: "chatgpt_subscription_setup.txt" },
  { id: "grok", file: "grok_subscription_setup.txt" }
];

async function readLocalMcpToken() {
  if (localMcpToken) return localMcpToken;
  localMcpToken =
    cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
    cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
  if (localMcpToken) return localMcpToken;
  try {
    localMcpToken = cleanString(await readFile(tokenFile, "utf8"));
  } catch {
    localMcpToken = "";
  }
  return localMcpToken;
}

function stdioServerConfig({ clientId, token = "" }) {
  return {
    command: "node",
    args: [bridgePath],
    env: {
      COCKPIT_API: publicBase,
      COCKPIT_PROJECT: projectSlug,
      COCKPIT_MCP_PATH: `/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp`,
      COCKPIT_CLIENT_ID: clientId,
      COCKPIT_CLIENT_PROVIDER: clientId,
      COCKPIT_AUTO_HEARTBEAT: "1",
      ...(token ? { COCKPIT_TOKEN: token } : {})
    }
  };
}

function configPayload(clientId, token = "") {
  return {
    mcpServers: {
      [`beagle-workbench-${projectSlug}`]: stdioServerConfig({ clientId, token })
    }
  };
}

function httpPayload(connectionPack, publicEndpoint) {
  const chatgpt = (connectionPack.clients || []).find((client) => client.client_id === "chatgpt");
  const grok = (connectionPack.clients || []).find((client) => client.client_id === "grok");
  const hostedClientReachable = publicEndpoint?.hostedClientReachable === true;
  const hostedBlockers = hostedClientReachable ? [] : [publicEndpoint?.reason || "hosted subscription clients need a public HTTPS MCP endpoint"];
  const mcpContextUrl = `${publicBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp`;
  const clientUrl = (client) => client?.config?.streamable_http_url || client?.config?.url || mcpContextUrl;
  const clientAlternateUrl = (client) => client?.config?.alternate_url || mcpContextUrl;
  return {
    schema: "beagle.workbench-http-mcp-client-config.v1",
    projectSlug,
    generatedAt: new Date().toISOString(),
    publicEndpoint,
    hostedClientReachable,
    authRequired: connectionPack.auth?.required?.http_mcp === true,
    tokenConfigured: connectionPack.auth?.token_configured === true || Boolean(localMcpToken),
    protocol: "streamable-http",
    protocolVersion: "2025-06-18",
    supportedTransports: ["streamable-http", "sse-listen"],
    warnings: hostedBlockers,
    clients: {
      chatgpt: {
        label: "ChatGPT MCP connector",
        networkReady: hostedClientReachable,
        blockers: hostedBlockers,
        url: clientUrl(chatgpt),
        alternate_url: clientAlternateUrl(chatgpt),
        transport: "streamable-http",
        headers: chatgpt?.config?.headers || { "content-type": "application/json" }
      },
      grok: {
        label: "Grok MCP connector",
        networkReady: hostedClientReachable,
        blockers: hostedBlockers,
        url: clientUrl(grok),
        alternate_url: clientAlternateUrl(grok),
        transport: "streamable-http",
        headers: grok?.config?.headers || { "content-type": "application/json" }
      }
    }
  };
}

function redactHostedPayload(payload) {
  return {
    ...payload,
    clients: Object.fromEntries(Object.entries(payload.clients || {}).map(([id, client]) => ([
      id,
      {
        ...client,
        headers: {
          ...(client.headers || {}),
          authorization: client.headers?.authorization ? "Bearer <workbench-context-token>" : ""
        }
      }
    ])))
  };
}

function hostedConnectionPayload(httpConfig, token = "") {
  const clients = Object.fromEntries(Object.entries(httpConfig.clients || {}).map(([id, client]) => ([
    id,
    {
      name: `beagle-workbench-${projectSlug}-${id}`,
      url: client.url,
      alternate_url: client.alternate_url,
      protocol: httpConfig.protocol,
      protocolVersion: httpConfig.protocolVersion,
      transport: client.transport,
      headers: {
        ...(client.headers || {}),
        ...(token ? { authorization: `Bearer ${token}` } : {})
      },
      expectedFirstContact: [
        "GET with Accept: text/event-stream",
        "POST initialize",
        "tools/list",
        "workbench_context_join"
      ]
    }
  ])));
  return {
    schema: "beagle.workbench-hosted-subscription-connection.v1",
    projectSlug,
    generatedAt: new Date().toISOString(),
    publicEndpoint: httpConfig.publicEndpoint,
    authRequired: true,
    tokenConfigured: Boolean(token),
    tokenSource: token ? tokenFile : "",
    clients,
    verifyCommands: Object.keys(clients).map((id) => `CLIENT=${id} npm run verify:multimodel:subscription-live ${projectSlug}`),
    replyVerifyCommands: Object.keys(clients).map((id) => `CLIENT=${id} npm run verify:multimodel:subscription-reply-live ${projectSlug}`),
    replyGate: {
      proofRequired: "The reply-live verifier only passes after the hosted subscription client writes a Workbench Context reply through MCP. Manual paste, direct endpoint replies, and fixture replies are rejected.",
      tool: "workbench_context_reply",
      flow: [
        "connect hosted client to the Streamable HTTP MCP URL",
        "call workbench_context_join",
        "start a multimodel turn targeting chatgpt-mcp or grok-mcp",
        "client reads next_handoff from workbench_context_join and replies with workbench_context_reply",
        "run the reply-live verifier"
      ]
    },
    truthMode: "generated-hosted-subscription-mcp-connection-packet"
  };
}

function redactHostedConnectionPayload(payload) {
  return {
    ...payload,
    tokenSource: payload.tokenSource ? "<local-token-file>" : "",
    clients: Object.fromEntries(Object.entries(payload.clients || {}).map(([id, client]) => ([
      id,
      {
        ...client,
        headers: {
          ...(client.headers || {}),
          authorization: client.headers?.authorization ? "Bearer <workbench-context-token>" : ""
        }
      }
    ])))
  };
}

function readmePayload(connectionPack, publicEndpoint) {
  const serverName = `beagle-workbench-${projectSlug}`;
  const hostedReady = publicEndpoint?.hostedClientReachable === true;
  const endpointWarning = hostedReady
    ? "Hosted HTTP clients can register this endpoint."
    : `Hosted HTTP clients are not ready yet: ${publicEndpoint?.reason || "missing public endpoint"}`;
  return [
    `# Beagle Workbench MCP Client Kit: ${projectSlug}`,
    "",
    "This kit connects subscription clients to the real Project Cockpit Workbench Context MCP bridge.",
    "",
    "It does not use model APIs. The clients keep their own subscriptions and use MCP to share presence, inbox handoffs, replies, and RAG++ memory.",
    "",
    "## STDIO clients",
    "",
    `MCP server name: \`${serverName}\``,
    "",
    "- Claude Desktop / Claude Code: use `claude_desktop_config.json` as the `mcpServers` entry.",
    "- Cursor: use `cursor_mcp.json` as the `mcpServers` entry.",
    "- Kimi CLI or other local MCP clients: use `kimi_mcp.json` or the generic stdio shape.",
    "",
    "The STDIO command is:",
    "",
    "```bash",
    `node ${bridgePath}`,
    "```",
    "",
    "## HTTP MCP clients",
    "",
    "Use `http_mcp.json` for clients that can register an HTTP MCP endpoint directly, such as ChatGPT/Grok when available in the client UI.",
    "",
    `Base HTTP endpoint: \`${connectionPack.endpoints?.mcp_context_http || `${publicBase}/api/workbench/${projectSlug}/context/mcp`}\``,
    "",
    "Transport: `streamable-http` with `Accept: application/json, text/event-stream`. A GET with `Accept: text/event-stream` opens an MCP SSE listen stream; a POST returns either JSON or SSE according to the client `Accept` header.",
    "",
    `Public endpoint status: \`${endpointWarning}\``,
    "",
    hostedReady
      ? "This endpoint is marked reachable for hosted clients by the Project Cockpit doctor."
      : "Do not expect ChatGPT/Grok hosted clients to connect until this is an internet-reachable HTTPS endpoint. Loopback, LAN IPs, and private tailnet names are intentionally not marked live.",
    "",
    "Use the per-client URLs in `http_mcp.json`; they include `client_id` and provider identity so the Workbench only marks a subscription client live after a real MCP connection.",
    "",
    "`hosted_subscription_connection.json` includes the local bearer token for operator use. Do not publish it. `hosted_subscription_connection.redacted.json` is safe to inspect or paste into notes.",
    "",
    "The per-client setup text files are the easiest thing to paste into the subscription app UI:",
    "",
    "- `claude_desktop_subscription_setup.txt`",
    "- `chatgpt_subscription_setup.txt`",
    "- `grok_subscription_setup.txt`",
    "",
    "## Required first tool calls",
    "",
    "After connecting a client, call:",
    "",
    "1. Call `workbench_context_join` with your `client_id`. It records heartbeat and returns pending handoffs plus exact reply args.",
    "2. Use `workbench_context_handoff_compile` if the handoff needs more RAG++ context.",
    "3. Use `workbench_context_reply` to answer a handoff into the live multimodel thread.",
    "",
    "Legacy Beagle MCP memory aliases are also available for older client prompts/configs: `beagle_memory_query` and `beagle_memory_ingest_chat`. They write to and read from the same Workbench Context/RAG++ memory, not a separate store.",
    "",
    "For STDIO aliases, `cockpit_workbench_context_client_heartbeat` and `cockpit_workbench_context_reply` are also available.",
    "",
    "## Verification",
    "",
    "From Project Cockpit:",
    "",
    "```bash",
    "npm run verify:workbench:mcp-client-kit",
    "npm run verify:workbench:mcp-stdio",
    "npm run verify:multimodel:health",
    `CLIENT=chatgpt npm run verify:multimodel:subscription-live ${projectSlug}`,
    `CLIENT=chatgpt npm run verify:multimodel:subscription-reply-live ${projectSlug}`,
    "```",
    ""
  ].join("\n");
}

async function fetchSubscriptionSetupFiles() {
  const suffix = publicBaseInput ? `?publicBase=${encodeURIComponent(publicBaseInput)}` : "";
  const files = {};
  const plans = [];
  for (const client of SUBSCRIPTION_SETUP_CLIENTS) {
    const connectPlan = await fetchJson(
      `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client.id)}/connect${suffix}`
    );
    const setupText = cleanString(connectPlan.connect?.setupText);
    files[client.file] = setupText || [
      `Beagle Workbench MCP setup for ${client.id}`,
      "",
      "Setup text was not returned by the backend. Regenerate this kit after restarting Project Cockpit."
    ].join("\n");
    plans.push({
      id: connectPlan.client?.id || client.id,
      targetClient: connectPlan.client?.targetClient || client.id,
      file: client.file,
      status: connectPlan.client?.status || "",
      setupTextPresent: Boolean(setupText),
      url: connectPlan.connect?.mcpServer?.url || ""
    });
  }
  return { files, plans };
}

try {
  const doctor = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/doctor${
    publicBaseInput ? `?publicBase=${encodeURIComponent(publicBaseInput)}` : ""
  }`).catch(() => null);
  const publicEndpoint = doctor?.publicEndpoint || fallbackPublicEndpointStatus(publicBase);
  publicBase = publicBaseInput || publicEndpoint.url || apiBase;
  const connectionPack = await fetchJson(
    `${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/connect?base_url=${encodeURIComponent(publicBase)}`
  );
  const token = await readLocalMcpToken();
  const subscriptionSetup = await fetchSubscriptionSetupFiles();
  await mkdir(outDir, { recursive: true });

  const httpConfig = httpPayload(connectionPack, publicEndpoint);
  const hostedConnection = hostedConnectionPayload(httpConfig, token);
  const files = {
    "claude_desktop_config.json": configPayload("claude-desktop", token),
    "cursor_mcp.json": configPayload("cursor", token),
    "kimi_mcp.json": configPayload("kimi", token),
    "generic_stdio_mcp.json": configPayload("local-subscription-client", token),
    "http_mcp.json": httpConfig,
    "http_mcp.redacted.json": redactHostedPayload(httpConfig),
    "hosted_subscription_connection.json": hostedConnection,
    "hosted_subscription_connection.redacted.json": redactHostedConnectionPayload(hostedConnection),
    "connection-pack.json": connectionPack
  };

  const written = [];
  for (const [name, payload] of Object.entries(files)) {
    const file = path.join(outDir, name);
    await writeFile(file, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
    written.push(file);
  }

  const setupTextFiles = [];
  for (const [name, text] of Object.entries(subscriptionSetup.files)) {
    const file = path.join(outDir, name);
    await writeFile(file, `${text.replace(/\s+$/g, "")}\n`, "utf8");
    written.push(file);
    setupTextFiles.push(file);
  }

  const readme = path.join(outDir, "README.md");
  await writeFile(readme, readmePayload(connectionPack, publicEndpoint), "utf8");
  written.push(readme);

  const result = {
    ok: true,
    schema: "beagle.workbench-mcp-client-kit.v1",
    projectSlug,
    outDir,
    bridgePath,
    publicBase,
    publicEndpoint,
    hostedClientReachable: publicEndpoint.hostedClientReachable === true,
    httpMcpUrl: connectionPack.endpoints?.mcp_context_http || "",
    files: written,
    subscriptionSetup: subscriptionSetup.plans,
    setupTextFiles,
    generatedAt: new Date().toISOString(),
    truthMode: "generated-from-observed-connection-pack"
  };
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    outDir,
    error: error.message,
    detail: error.detail || null,
    truthMode: "generation-failed"
  }, null, 2));
  process.exit(1);
}
