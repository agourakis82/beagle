#!/usr/bin/env node

import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

const DEFAULT_CLIENTS = ["chatgpt", "grok", "claude-desktop"];

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

function clientIdFromInput(input) {
  const text = cleanString(input);
  if (text === "chatgpt-mcp") return "chatgpt";
  if (text === "grok-mcp") return "grok";
  return text;
}

function parseClients(value) {
  const text = cleanString(value);
  if (!text || text === "all") return DEFAULT_CLIENTS;
  return text.split(",").map(clientIdFromInput).filter(Boolean);
}

function localKitDir(projectSlug) {
  return path.join(DATA_DIR, "mcp-client-kit", safeSlug(projectSlug));
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

async function writeRoomFile({ projectSlug, items, redacted }) {
  const dir = localKitDir(projectSlug);
  await mkdir(dir, { recursive: true });
  const suffix = redacted ? "redacted" : "local";
  const file = path.join(dir, `subscription_room.${suffix}.txt`);
  const body = [
    `Beagle Workbench subscription room for ${projectSlug}`,
    "",
    "Open the real apps and use the matching section. A client is not live until Beagle observes its MCP heartbeat or reply.",
    "",
    ...items.flatMap((item) => [
      "================================================================================",
      `${item.clientId}`,
      `Ready file: ${item.readyFile}`,
      `Drill message: ${item.drill?.messageId || "not-created"}`,
      "",
      item.readyText,
      ""
    ])
  ].join("\n");
  await writeFile(file, `${body}\n`, { mode: 0o600 });
  await chmod(file, 0o600).catch(() => {});
  return file;
}

async function createClientRoom({ apiBase, projectSlug, clientId, revealToken, drillEnabled, publicBase, markerPrefix }) {
  const suffix = publicBase ? `?publicBase=${encodeURIComponent(publicBase)}` : "";
  const plan = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(clientId)}/connect${suffix}`);
  const marker = `${markerPrefix}-${clientId}`;
  const drill = drillEnabled
    ? await fetchJson(
      `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(clientId)}/live-drill`,
      {
        method: "POST",
        body: {
          marker,
          prompt: `Reply through the Beagle MCP reply tool with the marker ${marker}.`
        }
      }
    )
    : null;
  const tokenFile = plan.connect?.mcpServer?.tokenFile || plan.client?.auth?.tokenFile || "";
  const token = revealToken ? await readToken(tokenFile) : "";
  const readyText = buildReadyText(plan, token, drill);
  const readyFile = await writeReadyFile({ projectSlug, clientId, text: readyText, redacted: !revealToken });
  return {
    clientId,
    readyFile,
    readyText,
    redacted: !revealToken,
    tokenFile,
    tokenIncluded: Boolean(token),
    url: plan.connect?.registration?.url || plan.connect?.mcpServer?.url || "",
    drill: drill
      ? {
          messageId: drill.messageId,
          marker: drill.marker,
          activationPromptIncluded: Boolean(cleanString(drill.activation?.modelPrompt))
        }
      : null,
    targetClient: plan.client?.targetClient || clientId,
    label: plan.client?.label || clientId
  };
}

async function readBringup(apiBase, projectSlug) {
  return await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/bringup`);
}

async function readDrillStatus(apiBase, projectSlug, item) {
  if (!item.drill?.messageId) return null;
  return await fetchJson(
    `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(item.clientId)}/live-drill?message_id=${encodeURIComponent(item.drill.messageId)}`
  ).catch((error) => ({ status: "error", error: error.message, detail: error.detail || null }));
}

function summarizeBringupClient(client = {}) {
  return {
    id: client.id || "",
    targetClient: client.targetClient || "",
    status: client.status || "",
    clientPresence: client.clientPresence || "",
    clientLatestAt: client.clientLatestAt || "",
    realConnectionObserved: client.realConnectionObserved === true,
    blockers: client.blockers || []
  };
}

function matchingBringupClient(bringup, item) {
  return (bringup.clients || []).find((client) => (
    client.id === item.clientId ||
    client.id === `${item.clientId}-mcp` ||
    client.targetClient === item.clientId ||
    client.targetClient === item.targetClient
  )) || {};
}

async function watchRoom({ apiBase, projectSlug, items, watchMs, intervalMs }) {
  const started = Date.now();
  let lastSignature = "";
  while (Date.now() - started <= watchMs) {
    const bringup = await readBringup(apiBase, projectSlug);
    const statuses = await Promise.all(items.map(async (item) => ({
      clientId: item.clientId,
      bringup: summarizeBringupClient(matchingBringupClient(bringup, item)),
      drill: await readDrillStatus(apiBase, projectSlug, item)
    })));
    const signature = JSON.stringify(statuses);
    if (signature !== lastSignature) {
      lastSignature = signature;
      console.log(JSON.stringify({
        schema: "beagle.workbench-subscription-room-watch.v1",
        projectSlug,
        statuses,
        elapsedMs: Date.now() - started,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-subscription-room-state"
      }, null, 2));
    }
    const allConnected = statuses.every((status) => status.bringup.realConnectionObserved);
    const allDrillsReplied = items.every((item) => !item.drill) ||
      statuses.every((status) => status.drill?.status === "reply-proven");
    if (allConnected && allDrillsReplied) {
      return { ok: true, statuses };
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return { ok: false, statuses: [] };
}

const positionals = process.argv.slice(2).filter((arg) => !arg.startsWith("--"));
const projectSlug = cleanString(argValue("project") || process.env.PROJECT_SLUG || positionals[0], "darwin-mfc");
const clients = parseClients(argValue("clients") || process.env.SUBSCRIPTION_CLIENTS || positionals[1] || "all");
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const publicBase = cleanString(argValue("public-base") || process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL || "");
const revealToken = hasFlag("reveal-token") || process.env.REVEAL_WORKBENCH_CONTEXT_TOKEN === "1";
const drillEnabled = hasFlag("drill") || process.env.SUBSCRIPTION_ROOM_DRILL === "1";
const watch = hasFlag("watch") || process.env.WATCH_SUBSCRIPTION_ROOM === "1";
const watchMs = Number(argValue("watch-ms") || process.env.WATCH_SUBSCRIPTION_ROOM_MS || 10 * 60_000);
const intervalMs = Number(argValue("interval-ms") || process.env.WATCH_SUBSCRIPTION_ROOM_INTERVAL_MS || 3000);
const markerPrefix = cleanString(argValue("marker")) || `subscription-room-${Date.now().toString(36)}`;

try {
  const items = [];
  for (const clientId of clients) {
    items.push(await createClientRoom({
      apiBase,
      projectSlug,
      clientId,
      revealToken,
      drillEnabled,
      publicBase,
      markerPrefix
    }));
  }
  const roomFile = await writeRoomFile({ projectSlug, items, redacted: !revealToken });
  console.log(JSON.stringify({
    schema: "beagle.workbench-subscription-room.v1",
    ok: true,
    projectSlug,
    clients,
    roomFile,
    redacted: !revealToken,
    tokenIncluded: revealToken,
    items: items.map((item) => ({
      clientId: item.clientId,
      label: item.label,
      targetClient: item.targetClient,
      readyFile: item.readyFile,
      url: item.url,
      tokenIncluded: item.tokenIncluded,
      drill: item.drill
    })),
    nextAction: revealToken
      ? `Open ${roomFile}, configure each real subscription app, and leave this command running with --watch to prove heartbeat/reply.`
      : `Generated redacted room file ${roomFile}. Re-run with --reveal-token on the trusted machine for paste-ready bearer tokens.`,
    truthMode: "observed-subscription-room-ready-files"
  }, null, 2));

  if (watch) {
    const result = await watchRoom({ apiBase, projectSlug, items, watchMs, intervalMs });
    if (!result.ok) {
      console.error(JSON.stringify({
        ok: false,
        schema: "beagle.workbench-subscription-room-watch.v1",
        projectSlug,
        clients,
        error: `not all real subscription clients connected/replied within ${watchMs}ms`,
        truthMode: "waiting-for-real-subscription-clients"
      }, null, 2));
      process.exit(2);
    }
  }
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    schema: "beagle.workbench-subscription-room.v1",
    projectSlug,
    clients,
    error: error.message,
    detail: error.detail || null,
    truthMode: "subscription-room-failed"
  }, null, 2));
  process.exit(1);
}
