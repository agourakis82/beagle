#!/usr/bin/env node

import { spawn } from "node:child_process";
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

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
}

async function appendVerificationRecord(slug, record) {
  const file = verificationFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
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

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
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

async function runShell(command, { timeoutMs = 60_000 } = {}) {
  return runProcess("/bin/bash", ["-lc", command], { timeoutMs });
}

function parseAgentBrowserJson(stdout) {
  const lines = stdout.split("\n").map((line) => line.trim()).filter(Boolean);
  for (const line of [...lines].reverse()) {
    const decoded = line.startsWith("\"") && line.endsWith("\"") ? JSON.parse(line) : line;
    if (typeof decoded === "string" && decoded.startsWith("{")) return JSON.parse(decoded);
    if (decoded && typeof decoded === "object") return decoded;
  }
  throw Object.assign(new Error("agent-browser JSON result not found"), { detail: { stdout } });
}

async function agentBrowserEval({ url, script, timeoutMs = 120_000, attempts = 2 }) {
  let lastError = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
      await runShell(`agent-browser open ${shellQuote(url)}`, { timeoutMs });
      await runShell("agent-browser wait 2000", { timeoutMs: 10_000 });
      const result = await runProcess("agent-browser", ["eval", script], { timeoutMs });
      return parseAgentBrowserJson(result.stdout);
    } catch (error) {
      lastError = error;
      await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
      if (attempt < attempts) await new Promise((resolve) => setTimeout(resolve, 750 * attempt));
    }
  }
  throw lastError;
}

async function waitForPersistedReply({ apiBase, projectSlug, turnId, provider, replyText, timeoutMs = 30_000 }) {
  const deadline = Date.now() + timeoutMs;
  let lastPayload = null;
  while (Date.now() < deadline) {
    lastPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=16&includeActive=1`);
    const turn = (lastPayload.turns || []).find((item) => item.turnId === turnId);
    const response = (turn?.responses || []).find((item) => item.provider === provider);
    if (response?.status === "done" && cleanString(response.text).includes(replyText)) {
      return { turn, response, payload: lastPayload };
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw Object.assign(new Error("persisted UI MCP handoff reply was not observed"), {
    detail: { turnId, provider, replyText, lastPayload }
  });
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

export async function verifyMultimodelUiMcpHandoff({
  projectSlug = "darwin-mfc",
  provider = "chatgpt-mcp",
  targetClient = "chatgpt",
  targetProvider = "openai",
  appBase = "http://127.0.0.1:4173",
  apiBase = "http://127.0.0.1:4370",
  timeoutMs = 120_000,
  marker = `ui-mcp-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`
} = {}) {
  const app = appBase.replace(/\/$/, "");
  const api = apiBase.replace(/\/$/, "");
  const url = `${app}/workbench/${encodeURIComponent(projectSlug)}`;
  const message = `UI MCP handoff verifier ${marker}`;
  const replyText = `ui mcp reply ${marker}`;
  const preflightActive = await waitForNoActiveTurns({
    apiBase: api,
    projectSlug,
    timeoutMs: Math.min(45_000, Math.max(10_000, timeoutMs / 4))
  });
  assert((preflightActive.count || 0) === 0, "active turns were still running before UI MCP handoff verification", preflightActive);

  const browser = await agentBrowserEval({
    url,
    timeoutMs,
    script: `
(async () => {
  const marker = ${JSON.stringify(marker)};
  const provider = ${JSON.stringify(provider)};
  const targetClient = ${JSON.stringify(targetClient)};
  const targetProvider = ${JSON.stringify(targetProvider)};
  const message = ${JSON.stringify(message)};
  const replyText = ${JSON.stringify(replyText)};
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const providerButtons = () => Array.from(document.querySelectorAll('[data-testid="multimodel-provider-toggle"]'));
  const providerButton = () => providerButtons().find((button) => button.getAttribute('data-provider-id') === provider);
  const input = () => document.querySelector('[data-testid="multimodel-composer-input"]');
  const send = () => document.querySelector('[data-testid="multimodel-send"]');
  const turnForMarker = () => Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]')).find((turn) => turn.innerText.includes(marker));
  const responseForTurn = (turn) => turn?.querySelector('[data-testid="multimodel-response"][data-provider="' + provider + '"]') || null;
  const snapshot = () => {
    const turn = turnForMarker();
    const response = responseForTurn(turn);
    const handoffCard = response?.querySelector('.mcp-handoff-card') || null;
    const messageId = handoffCard?.querySelector('code')?.getAttribute('title') || handoffCard?.querySelector('code')?.innerText || '';
    const copyMessageId = handoffCard?.querySelector('[data-testid="mcp-card-copy-message-id"]') || null;
    const copyReplyArgs = handoffCard?.querySelector('[data-testid="mcp-card-copy-reply-args"]') || null;
    const copyPacket = handoffCard?.querySelector('[data-testid="mcp-card-copy-packet"]') || null;
    const manualReplyInput = handoffCard?.querySelector('[data-testid="mcp-manual-reply-input"]') || null;
    const manualReplySubmit = handoffCard?.querySelector('[data-testid="mcp-manual-reply-submit"]') || null;
    return {
      hasTurn: Boolean(turn),
      turnId: turn?.getAttribute('data-turn-id') || '',
      turnStatus: turn?.getAttribute('data-turn-status') || '',
      hasResponse: Boolean(response),
      responseStatus: response?.getAttribute('data-response-status') || '',
      text: response?.innerText || '',
      messageId,
      hasCopyMessageId: Boolean(copyMessageId),
      hasCopyReplyArgs: Boolean(copyReplyArgs),
      hasCopyPacket: Boolean(copyPacket),
      hasManualReplyInput: Boolean(manualReplyInput),
      hasManualReplySubmit: Boolean(manualReplySubmit),
      manualReplySubmitDisabled: manualReplySubmit?.disabled === true,
      selected: providerButton()?.getAttribute('data-selected') === 'true',
      providerDisabled: providerButton()?.disabled === true,
      providerStatus: providerButton()?.getAttribute('data-provider-status') || '',
      providerText: providerButton()?.innerText || '',
      sendDisabled: send()?.disabled === true,
      notice: document.querySelector('[data-testid="multimodel-send-notice"]')?.innerText || '',
      overlay: Boolean(document.querySelector('.vite-error-overlay,#webpack-dev-server-client-overlay,[data-nextjs-dialog]'))
    };
  };

  let deadline = Date.now() + 15000;
  while (!providerButton() && Date.now() < deadline) await sleep(250);
  if (!providerButton()) return JSON.stringify({ ok: false, reason: 'provider toggle missing', snapshot: snapshot(), body: document.body.innerText.slice(0, 1200) });
  if (providerButton().disabled) return JSON.stringify({ ok: false, reason: 'provider toggle disabled', snapshot: snapshot() });

  for (const button of providerButtons()) {
    const shouldSelect = button.getAttribute('data-provider-id') === provider;
    const selected = button.getAttribute('data-selected') === 'true';
    if (!button.disabled && shouldSelect !== selected) {
      button.click();
      await sleep(150);
    }
  }

  if (!input() || !send()) return JSON.stringify({ ok: false, reason: 'missing composer', snapshot: snapshot() });
  input().focus();
  input().value = message;
  input().dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: message }));
  await sleep(250);
  if (send().disabled) return JSON.stringify({ ok: false, reason: 'send disabled', snapshot: snapshot() });
  send().click();

  deadline = Date.now() + 20000;
  let beforeReply = snapshot();
  while ((!beforeReply.hasTurn || !beforeReply.messageId) && Date.now() < deadline) {
    await sleep(250);
    beforeReply = snapshot();
  }
  if (!beforeReply.messageId) return JSON.stringify({ ok: false, reason: 'handoff message id not rendered', snapshot: beforeReply });

  const turn = turnForMarker();
  const response = responseForTurn(turn);
  const handoffCard = response?.querySelector('.mcp-handoff-card') || null;
  const manualReplyInput = handoffCard?.querySelector('[data-testid="mcp-manual-reply-input"]') || null;
  const manualReplySubmit = handoffCard?.querySelector('[data-testid="mcp-manual-reply-submit"]') || null;
  if (!manualReplyInput || !manualReplySubmit) return JSON.stringify({ ok: false, reason: 'manual reply controls missing', beforeReply });
  manualReplyInput.focus();
  manualReplyInput.value = replyText;
  manualReplyInput.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: replyText }));
  await sleep(150);
  if (manualReplySubmit.disabled) return JSON.stringify({ ok: false, reason: 'manual reply submit disabled', beforeReply: snapshot() });
  manualReplySubmit.click();

  deadline = Date.now() + 45000;
  let afterReply = snapshot();
  while ((!afterReply.text.includes(replyText) || afterReply.responseStatus !== 'done' || afterReply.turnStatus === 'streaming') && Date.now() < deadline) {
    await sleep(250);
    afterReply = snapshot();
  }

  return JSON.stringify({
    ok: afterReply.text.includes(replyText) && afterReply.responseStatus === 'done' && afterReply.turnStatus !== 'streaming',
    marker,
    provider,
    targetClient,
    targetProvider,
    message,
    replyText,
    beforeReply,
    replyPayload: { status: 'submitted-through-ui-manual-subscription-reply' },
    afterReply,
    body: document.body.innerText.slice(0, 1600)
  });
})()
`
  });

  assert(browser.ok, "browser UI MCP handoff flow failed", browser);
  assert(browser.beforeReply?.messageId, "browser did not render a handoff message id", browser);
  assert(browser.beforeReply?.hasCopyMessageId, "browser did not render the MCP message id copy control", browser.beforeReply);
  assert(browser.beforeReply?.hasCopyReplyArgs, "browser did not render the MCP reply args copy control", browser.beforeReply);
  assert(browser.beforeReply?.hasCopyPacket, "browser did not render the MCP packet copy control", browser.beforeReply);
  assert(browser.beforeReply?.hasManualReplyInput, "browser did not render the manual MCP reply input", browser.beforeReply);
  assert(browser.beforeReply?.hasManualReplySubmit, "browser did not render the manual MCP reply submit", browser.beforeReply);
  assert(browser.afterReply?.turnId, "browser did not expose a turn id after reply", browser);
  assert(browser.afterReply?.text?.includes(replyText), "browser did not show the MCP reply text", browser);
  assert(browser.afterReply?.turnStatus !== "streaming", "browser still showed the MCP handoff turn as streaming after reply", browser);

  const persisted = await waitForPersistedReply({
    apiBase: api,
    projectSlug,
    turnId: browser.afterReply.turnId,
    provider,
    replyText,
    timeoutMs: 30_000
  });
  const active = await waitForNoActiveTurns({ apiBase: api, projectSlug, timeoutMs: 30_000 });
  assert((active.count || 0) === 0, "active turns remained after UI MCP handoff verification", active);

  const result = {
    ok: true,
    schema: "beagle.multimodel-ui-mcp-handoff-verification.v1",
    kind: "ui-mcp-handoff",
    projectSlug,
    provider,
    targetClient,
    targetProvider,
    marker,
    turnId: browser.afterReply.turnId,
    messageId: browser.beforeReply.messageId,
    replyText,
    replyPath: "browser-ui-manual-subscription-reply",
    browser,
    persistedStatus: persisted.response.status,
    persistedTextChars: cleanString(persisted.response.text).length,
    activeTurns: active.count || 0,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-browser-ui-mcp-handoff-reply-websocket-persisted-rendered"
  };
  await appendVerificationRecord(projectSlug, {
    ...result,
    generatedAt: new Date().toISOString()
  });
  return result;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const provider = process.env.PROVIDER || process.argv[3] || "chatgpt-mcp";
  const targetClient = process.env.TARGET_CLIENT || process.argv[4] || "chatgpt";
  const targetProvider = process.env.TARGET_PROVIDER || process.argv[5] || "openai";
  const appBase = process.env.PROJECT_COCKPIT_APP_BASE || "http://127.0.0.1:4173";
  const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
  const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 120_000);
  try {
    const result = await verifyMultimodelUiMcpHandoff({
      projectSlug,
      provider,
      targetClient,
      targetProvider,
      appBase,
      apiBase,
      timeoutMs
    });
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error(JSON.stringify({
      ok: false,
      projectSlug,
      provider,
      targetClient,
      error: error.message,
      detail: error.detail || null,
      truthMode: "verification-failed"
    }, null, 2));
    process.exit(1);
  } finally {
    await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
  }
}
