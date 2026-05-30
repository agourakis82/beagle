#!/usr/bin/env node

import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

function argValue(name) {
  const prefix = `--${name}=`;
  const match = process.argv.find((arg) => arg.startsWith(prefix));
  return match ? match.slice(prefix.length) : "";
}

function boolArg(name) {
  return process.argv.includes(`--${name}`);
}

function numberArg(name, fallback) {
  const value = Number(argValue(name));
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
}

async function appendVerificationRecord(slug, record) {
  const file = verificationFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function summarizeStatus(status = {}) {
  return {
    status: cleanString(status.status),
    phases: status.phases || {},
    messageId: cleanString(status.message?.message_id),
    reply: status.reply || null,
    rejectedReply: status.rejectedReply || null,
    nextAction: cleanString(status.nextAction)
  };
}

function printHuman({ connect, created, status, timeoutMs }) {
  const setupText = cleanString(connect.connect?.setupText);
  const modelPrompt = cleanString(created.activation?.modelPrompt || status.activation?.modelPrompt);
  console.log("");
  console.log("=== Beagle Workbench subscription drill ===");
  console.log(`Project: ${created.projectSlug}`);
  console.log(`Client: ${created.client?.targetClient || created.client?.id}`);
  console.log(`Message ID: ${created.messageId}`);
  console.log("");
  console.log("=== 1. Register/connect this MCP server in the real subscription app ===");
  console.log(setupText || "(setup text missing)");
  console.log("");
  console.log("=== 2. Paste this activation prompt into that app ===");
  console.log(modelPrompt || "(activation prompt missing)");
  console.log("");
  console.log(`=== 3. Watching for a real MCP reply for ${timeoutMs}ms ===`);
}

async function cancelDrill({ apiBase, projectSlug, messageId, clientId, reason }) {
  return fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/mcp-inbox/${encodeURIComponent(messageId)}/cancel`, {
    method: "POST",
    body: {
      client_id: "project-cockpit-subscription-drill-cli",
      providerId: clientId,
      reason,
      metadata: {
        verifier: "subscription-drill-cli",
        truthMode: "observed-operator-cli-cleanup"
      }
    }
  }).catch((error) => ({ status: "error", error: error.message, detail: error.detail || null }));
}

const positionals = process.argv.slice(2).filter((arg) => !arg.startsWith("--"));
const projectSlug = cleanString(argValue("project") || process.env.PROJECT_SLUG || positionals[0], "darwin-mfc");
const client = cleanString(argValue("client") || process.env.CLIENT || process.env.SUBSCRIPTION_CLIENT || positionals[1], "chatgpt");
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const publicBase = cleanString(argValue("public-base") || process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL || "");
const timeoutMs = numberArg("timeout-ms", 120_000);
const pollMs = Math.max(250, numberArg("poll-ms", 2000));
const keepOpen = boolArg("keep-open");
const jsonMode = boolArg("json");
const allowTimeout = boolArg("allow-timeout");
const marker = cleanString(argValue("marker")) || `subscription-drill-cli-${client}-${Date.now().toString(36)}`;
const prompt = cleanString(argValue("prompt")) || `Reply through the Beagle MCP reply tool with the marker ${marker}.`;

try {
  const suffix = publicBase ? `?publicBase=${encodeURIComponent(publicBase)}` : "";
  const connect = await fetchJson(
    `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client)}/connect${suffix}`
  );
  const created = await fetchJson(
    `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client)}/live-drill`,
    {
      method: "POST",
      body: { marker, prompt }
    }
  );
  let status = await fetchJson(
    `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client)}/live-drill?message_id=${encodeURIComponent(created.messageId)}`
  );
  if (!jsonMode) printHuman({ connect, created, status, timeoutMs });

  const startedAt = Date.now();
  let outcome = "timeout";
  while ((Date.now() - startedAt) <= timeoutMs) {
    status = await fetchJson(
      `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client)}/live-drill?message_id=${encodeURIComponent(created.messageId)}`
    );
    if (status.status === "reply-proven") {
      outcome = "reply-proven";
      break;
    }
    if (status.status === "canceled") {
      outcome = "canceled";
      break;
    }
    if (!jsonMode) {
      const phases = Object.entries(status.phases || {})
        .filter(([, value]) => value)
        .map(([key]) => key)
        .join(", ") || "sent";
      process.stdout.write(`\rwaiting: ${status.status || "unknown"} (${phases})`);
    }
    await sleep(pollMs);
  }
  if (!jsonMode) process.stdout.write("\n");

  const cancel = outcome === "timeout" && !keepOpen
    ? await cancelDrill({
      apiBase,
      projectSlug,
      messageId: created.messageId,
      clientId: created.client?.id || client,
      reason: "subscription drill CLI timed out without a real MCP reply"
    })
    : null;
  const finalStatus = await fetchJson(
    `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client)}/live-drill?message_id=${encodeURIComponent(created.messageId)}`
  ).catch(() => status);

  const result = {
    ok: outcome === "reply-proven",
    schema: "beagle.workbench-subscription-drill-cli.v1",
    kind: "subscription-drill-cli",
    projectSlug,
    client: created.client,
    marker,
    messageId: created.messageId,
    timeoutMs,
    pollMs,
    outcome,
    keepOpen,
    canceled: cancel?.status === "ok" || finalStatus.status === "canceled",
    status: summarizeStatus(finalStatus),
    setupTextPresent: Boolean(cleanString(connect.connect?.setupText)),
    activationPromptPresent: Boolean(cleanString(created.activation?.modelPrompt)),
    generatedAt: new Date().toISOString(),
    truthMode: outcome === "reply-proven"
      ? "observed-real-subscription-client-reply-through-mcp"
      : "observed-subscription-drill-created-and-watched-no-fake-success"
  };
  await appendVerificationRecord(projectSlug, result);
  if (jsonMode) {
    console.log(JSON.stringify(result, null, 2));
  } else if (result.ok) {
    console.log(`Real MCP reply observed for ${created.messageId}.`);
  } else {
    console.log(`No real MCP reply observed. Outcome: ${outcome}${result.canceled ? " (drill canceled)" : ""}.`);
  }
  if (!result.ok && !allowTimeout) process.exit(2);
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    client,
    error: error.message,
    detail: error.detail || null,
    truthMode: "subscription-drill-cli-failed"
  }, null, 2));
  process.exit(1);
}
