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
  const res = await fetch(url, options);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const error = new Error(`${res.status} ${payload?.error || res.statusText}`);
    error.detail = payload;
    throw error;
  }
  return payload;
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function runShell(command, { timeoutMs = 60_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn("/bin/bash", ["-lc", command], {
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(Object.assign(new Error(`command timeout after ${timeoutMs}ms`), { detail: { command, stdout, stderr } }));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(Object.assign(new Error(`command exited ${code}`), { detail: { command, stdout, stderr } }));
      }
    });
  });
}

function runProcess(command, args = [], { timeoutMs = 60_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"]
    });
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
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(Object.assign(new Error(`command exited ${code}`), { detail: { command: [command, ...args].join(" "), stdout, stderr } }));
      }
    });
  });
}

function parseAgentBrowserJson(stdout) {
  const full = stdout.trim();
  if (full.startsWith("{")) {
    try {
      return JSON.parse(full);
    } catch {
      // Fall back to line scanning below.
    }
  }
  const lines = stdout.split("\n").map((line) => line.trim()).filter(Boolean);
  for (const line of [...lines].reverse()) {
    try {
      const decoded = line.startsWith("\"") && line.endsWith("\"") ? JSON.parse(line) : line;
      if (typeof decoded === "string" && decoded.startsWith("{")) return JSON.parse(decoded);
      if (decoded && typeof decoded === "object") return decoded;
    } catch {
      // agent-browser may print progress text next to JSON; keep scanning.
    }
  }
  throw Object.assign(new Error("agent-browser JSON result not found"), { detail: { stdout } });
}

async function agentBrowserEval({ url, script, timeoutMs = 90_000, attempts = 4 }) {
  let lastError = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
      await runShell(`agent-browser open ${shellQuote(url)}`, { timeoutMs });
      await runShell(`agent-browser wait ${attempt === 1 ? 2500 : 3500}`, { timeoutMs: 10_000 });
      const result = await runProcess("agent-browser", ["eval", script], { timeoutMs });
      return parseAgentBrowserJson(result.stdout);
    } catch (error) {
      lastError = error;
      await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
      if (attempt < attempts) await new Promise((resolve) => setTimeout(resolve, 1500 * attempt));
    }
  }
  throw lastError;
}

async function waitForNoActiveTurns({ apiBase, projectSlug, timeoutMs = 30_000 }) {
  const deadline = Date.now() + timeoutMs;
  let activePayload = null;
  while (Date.now() < deadline) {
    activePayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
    if ((activePayload.count || 0) === 0) return activePayload;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return activePayload;
}

function turnLooksLikeSubscriptionDrill(turn, provider) {
  const target = provider.replace("-mcp", "");
  return [turn?.message, turn?.prompt, JSON.stringify(turn?.responses || [])]
    .some((value) => {
      const text = String(value || "");
      return text.includes("Subscription reply drill") && text.includes(target);
    });
}

function mcpHandoffFromTurn(turn, provider) {
  const response = (turn?.responses || []).find((item) => item.provider === provider);
  const messageId = cleanString(response?.meta?.message_id || response?.meta?.messageId);
  if (!turn || !messageId) return null;
  return { turnId: turn.turnId, messageId, turnStatus: turn.status, responseStatus: response?.status || "" };
}

async function findSubscriptionDrillHandoff({ apiBase, projectSlug, provider }) {
  const active = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`)
    .catch(() => null);
  for (const turn of active?.turns || []) {
    if (turnLooksLikeSubscriptionDrill(turn, provider)) {
      const handoff = mcpHandoffFromTurn(turn, provider);
      if (handoff) return { ...handoff, source: "active-turns" };
    }
  }

  const recent = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=20&includeActive=1`)
    .catch(() => null);
  for (const turn of recent?.turns || []) {
    if (turnLooksLikeSubscriptionDrill(turn, provider)) {
      const handoff = mcpHandoffFromTurn(turn, provider);
      if (handoff) return { ...handoff, source: "recent-turns" };
    }
  }
  return null;
}

async function cleanupSubscriptionDrill({ apiBase, projectSlug, provider, reason }) {
  const handoff = await findSubscriptionDrillHandoff({ apiBase, projectSlug, provider });
  if (!handoff?.messageId) return { cleaned: false, reason: "handoff-not-found" };

  const cancel = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/mcp-inbox/${encodeURIComponent(handoff.messageId)}/cancel`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      client_id: "project-cockpit-verifier-cleanup",
      reason,
      metadata: {
        provider,
        truthMode: "observed-verifier-cleanup"
      }
    })
  }).catch((error) => ({ ok: false, error: error?.message || String(error), detail: error?.detail || null }));

  const active = await waitForNoActiveTurns({ apiBase, projectSlug, timeoutMs: 20_000 });
  return {
    cleaned: true,
    handoff,
    cancelStatus: cancel?.status || (cancel?.ok === false ? "failed" : ""),
    activeTurns: active?.count ?? null
  };
}

async function verifyMultimodelUiSubscriptionDrill({
  projectSlug = "darwin-mfc",
  provider = "chatgpt-mcp",
  appBase = "http://127.0.0.1:4173",
  apiBase = "http://127.0.0.1:4370",
  timeoutMs = 90_000
} = {}) {
  const app = appBase.replace(/\/$/, "");
  const api = apiBase.replace(/\/$/, "");
  const url = `${app}/workbench/${encodeURIComponent(projectSlug)}`;
  const preflightActive = await waitForNoActiveTurns({
    apiBase: api,
    projectSlug,
    timeoutMs: Math.min(30_000, Math.max(10_000, timeoutMs / 4))
  });
  assert((preflightActive.count || 0) === 0, "active turns were still running before subscription drill verification", preflightActive);

  let browser;
  try {
    browser = await agentBrowserEval({
      url,
      timeoutMs,
      script: `
(async () => {
  const provider = ${JSON.stringify(provider)};
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const drillButton = () => document.querySelector('[data-testid="subscription-reply-drill"][data-client-id="' + provider + '"]');
  const turns = () => Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]'));
  const latestDrillTurn = () => turns().reverse().find((turn) => turn.innerText.includes('Subscription reply drill') && turn.innerText.includes(provider.replace('-mcp', '')));
  const responseForTurn = (turn) => turn?.querySelector('[data-testid="multimodel-response"][data-provider="' + provider + '"]') || null;
  const state = (turn) => {
    const response = responseForTurn(turn);
    const card = response?.querySelector('.mcp-handoff-card') || null;
    return {
      hasTurn: Boolean(turn),
      turnId: turn?.getAttribute('data-turn-id') || '',
      turnStatus: turn?.getAttribute('data-turn-status') || '',
      responseStatus: response?.getAttribute('data-response-status') || '',
      responseTransport: response?.getAttribute('data-provider-transport') || '',
      messageId: card?.querySelector('code')?.innerText?.trim() || '',
      hasReplyTool: response?.innerText?.includes('workbench_context_reply') || false,
      hasActivationPrompt: Boolean(response?.querySelector('[data-testid="mcp-card-copy-activation-prompt"]')),
      queueActivationPromptCount: document.querySelectorAll('[data-testid="mcp-copy-activation-prompt"]').length,
      hasDeveloperPasteBridge: response?.innerText?.includes('Developer paste bridge') || false,
      body: document.body.innerText.slice(0, 3000)
    };
  };

  for (let i = 0; i < 80 && !drillButton(); i += 1) await sleep(250);
  const button = drillButton();
  if (!button) return { ok: false, reason: 'subscription drill button not found', body: document.body.innerText.slice(0, 3000) };
  if (button.disabled) return { ok: false, reason: 'subscription drill button disabled', body: document.body.innerText.slice(0, 3000) };
  button.click();

  let beforeStop = null;
  for (let i = 0; i < 100; i += 1) {
    const turn = latestDrillTurn();
    const current = state(turn);
    if (current.messageId && current.hasReplyTool && current.responseTransport === 'workbench-context-mcp-inbox') {
      beforeStop = current;
      break;
    }
    await sleep(300);
  }
  if (!beforeStop) return { ok: false, reason: 'MCP handoff was not rendered', latest: state(latestDrillTurn()) };

  const stop = latestDrillTurn()?.querySelector('.multimodel-user-head button');
  if (stop) stop.click();
  let afterStop = state(latestDrillTurn());
  for (let i = 0; i < 80 && ['waiting', 'streaming'].includes(afterStop.turnStatus); i += 1) {
    await sleep(300);
    afterStop = state(latestDrillTurn());
  }
  return {
    ok: true,
    provider,
    beforeStop,
    afterStop,
    clickedStop: Boolean(stop),
    body: document.body.innerText.slice(0, 3000)
  };
})()
    `
    });
  } catch (error) {
    const cleanup = await cleanupSubscriptionDrill({
      apiBase: api,
      projectSlug,
      provider,
      reason: "cleanup after browser failed during subscription drill verification"
    });
    error.detail = { ...(error.detail || {}), cleanup };
    throw error;
  }

  if (browser.ok !== true) {
    const cleanup = await cleanupSubscriptionDrill({
      apiBase: api,
      projectSlug,
      provider,
      reason: "cleanup after browser returned a failed subscription drill snapshot"
    });
    browser.cleanup = cleanup;
  }

  assert(browser.ok === true, "browser UI subscription reply drill failed", browser);
  assert(browser.beforeStop?.messageId, "subscription drill did not render an MCP handoff message id", browser);
  assert(browser.beforeStop?.hasReplyTool === true, "subscription drill did not render MCP reply tool instructions", browser.beforeStop);
  assert(browser.beforeStop?.hasActivationPrompt === true, "subscription drill did not render the handoff activation prompt button", browser.beforeStop);
  assert(Number(browser.beforeStop?.queueActivationPromptCount || 0) >= 1, "subscription drill did not render queue activation prompt controls", browser.beforeStop);
  assert(browser.beforeStop?.hasDeveloperPasteBridge === true, "subscription drill did not keep developer paste bridge demoted and visible as debug-only", browser.beforeStop);
  assert(browser.clickedStop === true, "subscription drill did not expose a stop control for the pending MCP turn", browser);

  const active = await waitForNoActiveTurns({ apiBase: api, projectSlug, timeoutMs: 30_000 });
  assert((active.count || 0) === 0, "active turns remained after subscription drill verification", active);

  const result = {
    ok: true,
    schema: "beagle.multimodel-ui-subscription-drill-verification.v1",
    kind: "ui-subscription-reply-drill",
    projectSlug,
    provider,
    turnId: browser.beforeStop.turnId,
    messageId: browser.beforeStop.messageId,
    responseTransport: browser.beforeStop.responseTransport,
    stopped: browser.clickedStop === true,
    activeTurns: active.count || 0,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-browser-ui-subscription-reply-drill-handoff"
  };
  await appendVerificationRecord(projectSlug, {
    ...result,
    generatedAt: new Date().toISOString()
  });
  return result;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const provider = process.env.PROVIDER || process.env.CLIENT || process.argv[3] || "chatgpt-mcp";
  const appBase = process.env.PROJECT_COCKPIT_APP_BASE || "http://127.0.0.1:4173";
  const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
  const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 90_000);
  try {
    const result = await verifyMultimodelUiSubscriptionDrill({ projectSlug, provider, appBase, apiBase, timeoutMs });
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error(JSON.stringify({
      ok: false,
      schema: "beagle.multimodel-ui-subscription-drill-verification.v1",
      projectSlug,
      provider,
      error: error.message,
      detail: error.detail || null,
      truthMode: "verification-failed"
    }, null, 2));
    process.exit(1);
  }
}
