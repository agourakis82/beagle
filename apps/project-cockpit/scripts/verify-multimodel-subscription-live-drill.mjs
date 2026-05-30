#!/usr/bin/env node

import { spawn } from "node:child_process";
import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

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

function runProcess(command, args = [], { timeoutMs = 60_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(Object.assign(new Error(`command timeout after ${timeoutMs}ms`), { detail: { command, args, stdout, stderr } }));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) resolve({ stdout, stderr });
      else reject(Object.assign(new Error(`command exited ${code}`), { detail: { command: [command, ...args].join(" "), stdout, stderr } }));
    });
  });
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

async function runShell(command, options = {}) {
  return runProcess("/bin/bash", ["-lc", command], options);
}

function parseAgentBrowserJson(stdout) {
  const full = stdout.trim();
  if (full.startsWith("{")) {
    try {
      return JSON.parse(full);
    } catch {
      // Fall through.
    }
  }
  const lines = stdout.split("\n").map((line) => line.trim()).filter(Boolean);
  for (const line of [...lines].reverse()) {
    try {
      const decoded = line.startsWith("\"") && line.endsWith("\"") ? JSON.parse(line) : line;
      if (typeof decoded === "string" && decoded.startsWith("{")) return JSON.parse(decoded);
      if (decoded && typeof decoded === "object") return decoded;
    } catch {
      // Keep scanning.
    }
  }
  throw Object.assign(new Error("agent-browser JSON result not found"), { detail: { stdout } });
}

async function verifyBrowser({ appBase, projectSlug, clientId, messageId }) {
  const url = `${appBase.replace(/\/$/, "")}/workbench/${encodeURIComponent(projectSlug)}?live_drill=${encodeURIComponent(messageId)}`;
  let lastError = null;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
      await runShell(`agent-browser open ${shellQuote(url)}`, { timeoutMs: 60_000 });
      await runShell("agent-browser wait 8000", { timeoutMs: 12_000 });
      const result = await runProcess("agent-browser", ["eval", `
(() => {
  const clientId = ${JSON.stringify(clientId)};
  const messageId = ${JSON.stringify(messageId)};
  const buttons = Array.from(document.querySelectorAll('[data-testid="subscription-live-drill"]'));
  const statuses = Array.from(document.querySelectorAll('[data-testid="subscription-live-drill-status"]'));
  const matching = statuses.find((item) => item.getAttribute('data-client-id') === clientId && item.innerText.includes(messageId));
  const activationButtons = Array.from(document.querySelectorAll('[data-testid="subscription-copy-activation-prompt"]'));
  const overlay = document.querySelector('.vite-error-overlay, [data-nextjs-dialog], #webpack-dev-server-client-overlay');
  return {
    ok: buttons.length >= 3 && Boolean(matching) && activationButtons.length >= 1 && !overlay,
    buttonCount: buttons.length,
    statusCount: statuses.length,
    activationButtonCount: activationButtons.length,
    hasMatchingStatus: Boolean(matching),
    matchingText: matching?.innerText || '',
    hasOverlay: Boolean(overlay),
    body: document.body.innerText.slice(0, 2500)
  };
})()
      `], { timeoutMs: 20_000 });
      await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
      return parseAgentBrowserJson(result.stdout);
    } catch (error) {
      lastError = error;
      await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
      if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, 750 * attempt));
    }
  }
  throw lastError;
}

async function main() {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
  const appBase = cleanString(process.env.PROJECT_COCKPIT_APP_BASE || "http://127.0.0.1:4173").replace(/\/$/, "");
  const client = cleanString(process.env.CLIENT || process.env.CLIENT_ID || process.argv[3] || "chatgpt");
  const marker = `subscription-live-drill-verifier-${Date.now().toString(36)}`;
  const created = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client)}/live-drill`, {
    method: "POST",
    body: {
      marker,
      prompt: `Verifier drill. A real subscription client would reply with ${marker}.`
    }
  });
  assert(created.ok === true, "live drill was not created", created);
  assert(created.messageId, "live drill did not return messageId", created);
  assert(created.status?.phases?.sent === true, "live drill status did not mark sent", created);
  assert(created.status?.phases?.replied === false, "verifier unexpectedly observed a real subscription reply", created);

  const status = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client)}/live-drill?message_id=${encodeURIComponent(created.messageId)}`);
  assert(status.message?.message_id === created.messageId, "live drill status did not read back the created message", status);
  assert(status.phases?.sent === true, "live drill readback is missing sent phase", status);
  assert(status.phases?.replied === false, "live drill readback unexpectedly saw a real reply", status);
  assert(created.activation?.modelPrompt?.includes(created.messageId), "live drill creation did not return a copyable activation prompt", created);
  assert(status.activation?.modelPrompt?.includes(created.messageId), "live drill status did not return a copyable activation prompt", status);
  assert(status.activation?.replyArgs?.message_id === created.messageId, "live drill activation reply args do not target the handoff", status.activation);
  assert(!JSON.stringify(status.activation).includes("Bearer "), "live drill activation leaked bearer auth", status.activation);

  let browser = null;
  let cancel = null;
  let canceled = null;
  try {
    browser = await verifyBrowser({
      appBase,
      projectSlug,
      clientId: created.client.id,
      messageId: created.messageId
    });
    assert(browser.ok === true, "live drill UI did not render expected status", browser);
  } finally {
    cancel = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/mcp-inbox/${encodeURIComponent(created.messageId)}/cancel`, {
      method: "POST",
      body: {
        client_id: "project-cockpit-live-drill-verifier",
        providerId: created.client.id,
        reason: "live drill verifier cleanup",
        metadata: {
          verifier: "subscription-live-drill",
          truthMode: "observed-verifier-cleanup"
        }
      }
    }).catch((error) => ({ status: "error", error: error.message, detail: error.detail || null }));
  }
  assert(cancel.status === "ok", "live drill cleanup cancel failed", cancel);

  canceled = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client)}/live-drill?message_id=${encodeURIComponent(created.messageId)}`);
  assert(canceled.status === "canceled", "live drill status did not become canceled after cleanup", canceled);

  const result = {
    ok: true,
    schema: "beagle.multimodel-subscription-live-drill-verification.v1",
    kind: "subscription-live-drill",
    projectSlug,
    client: created.client,
    marker,
    messageId: created.messageId,
    initialStatus: status.status,
    canceledStatus: canceled.status,
    browser: {
      buttonCount: browser.buttonCount,
      statusCount: browser.statusCount,
      activationButtonCount: browser.activationButtonCount,
      hasMatchingStatus: browser.hasMatchingStatus
    },
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-live-drill-created-rendered-cancelable-no-fake-reply"
  };
  await appendVerificationRecord(projectSlug, result);
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(JSON.stringify({
    ok: false,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
});
