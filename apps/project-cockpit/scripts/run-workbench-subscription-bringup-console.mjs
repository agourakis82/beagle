#!/usr/bin/env node

import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function cleanString(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function argValue(name) {
  const prefix = `--${name}=`;
  const match = process.argv.find((arg) => arg.startsWith(prefix));
  return match ? match.slice(prefix.length) : "";
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
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

async function readToken(tokenFile) {
  if (!tokenFile) return "";
  try {
    return cleanString(await readFile(tokenFile, "utf8"));
  } catch {
    return "";
  }
}

function clientIdFromInput(input) {
  const text = cleanString(input, "chatgpt");
  if (text === "chatgpt-mcp") return "chatgpt";
  if (text === "grok-mcp") return "grok";
  return text;
}

function localKitDir(projectSlug) {
  return path.join(DATA_DIR, "mcp-client-kit", safeSlug(projectSlug));
}

function headersWithToken(headers = {}, token = "") {
  return {
    ...headers,
    authorization: token ? `Bearer ${token}` : headers.authorization
  };
}

function buildReadyText(plan, token, drill = null) {
  const client = plan.client || {};
  const connect = plan.connect || {};
  const registration = connect.registration || {};
  const mcpServer = connect.mcpServer || {};
  const headers = headersWithToken(registration.headers || mcpServer.headers || {}, token);
  const firstCalls = connect.firstToolCalls || [];
  const verifyCommand = `CLIENT=${client.targetClient || client.id || ""} npm run verify:multimodel:subscription-live ${plan.projectSlug || "darwin-mfc"}`;
  const replyVerifyCommand = client.replyGate?.verifyCommand || `CLIENT=${client.targetClient || client.id || ""} npm run verify:multimodel:subscription-reply-live ${plan.projectSlug || "darwin-mfc"}`;
  const activationPrompt = cleanString(drill?.activation?.modelPrompt);
  return [
    `Beagle Workbench MCP connection for ${client.label || client.id}`,
    "",
    "Use this inside the real subscription app. This is not a model API route.",
    "",
    `Name: ${registration.name || "beagle-workbench-darwin-mfc"}`,
    `Transport: ${registration.transport || "streamable-http+sse"}`,
    `URL: ${registration.url || mcpServer.url || client.url || ""}`,
    "",
    "Headers:",
    ...Object.entries(headers).map(([key, value]) => `- ${key}: ${value}`),
    "",
    "First tool calls:",
    ...firstCalls.map((item, index) => `${index + 1}. ${item.tool} ${JSON.stringify(item.args || {})}`),
    "",
    "After connection:",
    `- Live check: ${verifyCommand}`,
    `- Reply check: ${replyVerifyCommand}`,
    "",
    "Proof rules:",
    "- Beagle only marks this live after this exact client writes a fresh heartbeat or MCP reply.",
    "- Manual paste, direct endpoint replies, fixture replies, and debug probes do not count.",
    "",
    activationPrompt ? "Live drill activation prompt:" : "",
    activationPrompt || "",
    activationPrompt ? "" : "",
    connect.operatorPrompt ? `Operator prompt:\n${connect.operatorPrompt}` : ""
  ].filter((line) => line !== "").join("\n");
}

async function writeReadyFile({ projectSlug, clientId, text, redacted }) {
  const dir = localKitDir(projectSlug);
  await mkdir(dir, { recursive: true });
  const suffix = redacted ? "redacted" : "local";
  const file = path.join(dir, `${clientId}_ready_to_paste.${suffix}.txt`);
  await writeFile(file, `${text}\n`, { mode: 0o600 });
  await chmod(file, 0o600).catch(() => {});
  return file;
}

function summarizeClient(client = {}) {
  return {
    id: client.id,
    targetClient: client.targetClient,
    status: client.status,
    clientPresence: client.clientPresence,
    realConnectionObserved: client.realConnectionObserved === true,
    clientLatestAt: client.clientLatestAt || "",
    blockers: client.blockers || [],
    verifyCommand: client.verifyCommand || "",
    replyVerifyCommand: client.replyVerifyCommand || ""
  };
}

async function pollBringup({ apiBase, projectSlug, clientId, watchMs, intervalMs }) {
  const started = Date.now();
  const targetIds = new Set([clientId, `${clientId}-mcp`]);
  let lastSignature = "";
  while (Date.now() - started <= watchMs) {
    const payload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/bringup`);
    const client = (payload.clients || []).find((item) => targetIds.has(item.id) || item.targetClient === clientId);
    const summary = summarizeClient(client || {});
    const signature = JSON.stringify(summary);
    if (signature !== lastSignature) {
      lastSignature = signature;
      console.log(JSON.stringify({
        schema: "beagle.workbench-subscription-bringup-watch.v1",
        projectSlug,
        client: summary,
        elapsedMs: Date.now() - started,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-bringup-state"
      }, null, 2));
    }
    if (summary.realConnectionObserved) return summary;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return null;
}

async function pollDrill({ apiBase, projectSlug, clientId, messageId, watchMs, intervalMs }) {
  const started = Date.now();
  let lastSignature = "";
  while (Date.now() - started <= watchMs) {
    const status = await fetchJson(
      `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(clientId)}/live-drill?message_id=${encodeURIComponent(messageId)}`
    );
    const summary = {
      status: status.status || "",
      messageId: status.message?.message_id || messageId,
      phases: status.phases || {},
      reply: status.reply
        ? {
            memory_id: status.reply.memory_id || "",
            client_id: status.reply.client_id || "",
            source: status.reply.source || "",
            truthMode: status.reply.truthMode || ""
          }
        : null,
      rejectedReply: status.rejectedReply || null,
      nextAction: status.nextAction || ""
    };
    const signature = JSON.stringify(summary);
    if (signature !== lastSignature) {
      lastSignature = signature;
      console.log(JSON.stringify({
        schema: "beagle.workbench-subscription-live-drill-watch.v1",
        projectSlug,
        clientId,
        drill: summary,
        elapsedMs: Date.now() - started,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-live-drill-state"
      }, null, 2));
    }
    if (status.status === "reply-proven") return status;
    if (status.status === "canceled") return status;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return null;
}

const positionals = process.argv.slice(2).filter((arg) => !arg.startsWith("--"));
const projectSlug = cleanString(argValue("project") || process.env.PROJECT_SLUG || positionals[0], "darwin-mfc");
const clientId = clientIdFromInput(argValue("client") || process.env.CLIENT || process.env.SUBSCRIPTION_CLIENT || positionals[1]);
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const publicBase = cleanString(argValue("public-base") || process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL || "");
const revealToken = hasFlag("reveal-token") || process.env.REVEAL_WORKBENCH_CONTEXT_TOKEN === "1";
const watch = hasFlag("watch") || process.env.WATCH_SUBSCRIPTION_BRINGUP === "1";
const drillEnabled = hasFlag("drill") || process.env.SUBSCRIPTION_BRINGUP_DRILL === "1";
const marker = cleanString(argValue("marker")) || `pair-${clientId}-${Date.now().toString(36)}`;
const prompt = cleanString(argValue("prompt")) || `Reply through the Beagle MCP reply tool with the marker ${marker}.`;
const watchMs = Number(argValue("watch-ms") || process.env.WATCH_SUBSCRIPTION_BRINGUP_MS || 10 * 60_000);
const intervalMs = Number(argValue("interval-ms") || process.env.WATCH_SUBSCRIPTION_BRINGUP_INTERVAL_MS || 3000);

try {
  const suffix = publicBase ? `?publicBase=${encodeURIComponent(publicBase)}` : "";
  const plan = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(clientId)}/connect${suffix}`);
  const drill = drillEnabled
    ? await fetchJson(
        `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(clientId)}/live-drill`,
        {
          method: "POST",
          body: { marker, prompt }
        }
      )
    : null;
  const tokenFile = plan.connect?.mcpServer?.tokenFile || plan.client?.auth?.tokenFile || "";
  const token = revealToken ? await readToken(tokenFile) : "";
  const readyText = buildReadyText(plan, token, drill);
  const readyFile = await writeReadyFile({ projectSlug, clientId, text: readyText, redacted: !revealToken });
  const verifyCommand = `CLIENT=${clientId} npm run verify:multimodel:subscription-live ${projectSlug}`;
  const replyVerifyCommand = plan.client?.replyGate?.verifyCommand || `CLIENT=${clientId} npm run verify:multimodel:subscription-reply-live ${projectSlug}`;

  console.log(JSON.stringify({
    schema: "beagle.workbench-subscription-bringup-console.v1",
    ok: true,
    projectSlug,
    clientId,
    readyFile,
    redacted: !revealToken,
    tokenFile,
    tokenIncluded: Boolean(token),
    url: plan.connect?.registration?.url || plan.connect?.mcpServer?.url || "",
    verifyCommand,
    replyVerifyCommand,
    drill: drill
      ? {
          messageId: drill.messageId,
          marker: drill.marker,
          verifyCommand: drill.activation?.verifyCommand || replyVerifyCommand,
          activationPromptIncluded: Boolean(cleanString(drill.activation?.modelPrompt))
        }
      : null,
    nextAction: revealToken
      ? `Paste ${readyFile} into the real ${clientId} subscription app MCP setup${drill ? " and activation prompt" : ""}, then let it call workbench_context_join.`
      : `Generated redacted file ${readyFile}. Re-run with --reveal-token locally to write a paste-ready file with the bearer token.`,
    truthMode: "observed-subscription-connect-plan-ready-file"
  }, null, 2));

  if (watch) {
    const drillStatus = drill
      ? await pollDrill({ apiBase, projectSlug, clientId, messageId: drill.messageId, watchMs, intervalMs })
      : null;
    const observed = drill ? null : await pollBringup({ apiBase, projectSlug, clientId, watchMs, intervalMs });
    if ((!drill && !observed) || (drill && drillStatus?.status !== "reply-proven")) {
      console.error(JSON.stringify({
        ok: false,
        schema: "beagle.workbench-subscription-bringup-watch.v1",
        projectSlug,
        clientId,
        heartbeatObserved: Boolean(observed) || drillStatus?.status === "reply-proven",
        drillStatus: drillStatus?.status || "",
        error: drill
          ? `no real ${clientId} heartbeat/reply observed within ${watchMs}ms`
          : `no real ${clientId} heartbeat observed within ${watchMs}ms`,
        truthMode: drill ? "waiting-for-real-subscription-client-reply" : "waiting-for-real-subscription-client"
      }, null, 2));
      process.exit(2);
    }
  }
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    schema: "beagle.workbench-subscription-bringup-console.v1",
    projectSlug,
    clientId,
    error: error.message,
    detail: error.detail || null,
    truthMode: "subscription-bringup-console-failed"
  }, null, 2));
  process.exit(1);
}
