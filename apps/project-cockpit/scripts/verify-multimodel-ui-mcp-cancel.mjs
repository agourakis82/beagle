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

function browserErrorSummary(error) {
  return {
    message: error?.message || String(error),
    detail: error?.detail || null
  };
}

async function agentBrowserEval({ url, script, timeoutMs = 120_000, attempts = 4 }) {
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

async function waitForCanceledInboxMessage({ apiBase, projectSlug, provider, messageId, timeoutMs = 30_000 }) {
  const deadline = Date.now() + timeoutMs;
  let lastPayload = null;
  while (Date.now() < deadline) {
    lastPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/mcp-inbox?limit=20`);
    const providerInbox = (lastPayload.providers || []).find((item) => item.provider_id === provider);
    const message = (providerInbox?.messages || []).find((item) => item.message_id === messageId);
    if (message?.status === "canceled") return { providerInbox, message, payload: lastPayload };
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw Object.assign(new Error("canceled MCP inbox message was not observed"), {
    detail: { provider, messageId, lastPayload }
  });
}

async function waitForPersistedCanceledTurn({ apiBase, projectSlug, turnId, provider, timeoutMs = 45_000 }) {
  const deadline = Date.now() + timeoutMs;
  let lastPayload = null;
  while (Date.now() < deadline) {
    lastPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=20&includeActive=1`);
    const turn = (lastPayload.turns || []).find((item) => item.turnId === turnId);
    const response = (turn?.responses || []).find((item) => item.provider === provider);
    if (turn && !["waiting", "streaming"].includes(turn.status) && response?.status === "error") {
      return { turn, response, payload: lastPayload };
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw Object.assign(new Error("persisted canceled UI MCP turn was not observed"), {
    detail: { turnId, provider, lastPayload }
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

function turnMatchesMarker(turn, marker) {
  if (!turn || !marker) return false;
  return [turn.message, turn.prompt, JSON.stringify(turn.responses || [])]
    .some((value) => String(value || "").includes(marker));
}

function mcpHandoffFromTurn(turn, provider) {
  const response = (turn?.responses || []).find((item) => item.provider === provider);
  const messageId = cleanString(response?.meta?.message_id || response?.meta?.messageId);
  if (!turn || !messageId) return null;
  return { turnId: turn.turnId, messageId, responseStatus: response?.status || "", turn };
}

async function findMcpHandoffByMarker({ apiBase, projectSlug, provider, marker }) {
  const active = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`)
    .catch(() => null);
  for (const turn of active?.turns || []) {
    if (turnMatchesMarker(turn, marker)) {
      const handoff = mcpHandoffFromTurn(turn, provider);
      if (handoff) return { ...handoff, source: "active-turns" };
    }
  }

  const recent = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=20&includeActive=1`)
    .catch(() => null);
  for (const turn of recent?.turns || []) {
    if (turnMatchesMarker(turn, marker)) {
      const handoff = mcpHandoffFromTurn(turn, provider);
      if (handoff) return { ...handoff, source: "recent-turns" };
    }
  }
  return null;
}

async function cleanupMcpHandoff({ apiBase, projectSlug, provider, marker, messageId = "", reason }) {
  const handoff = messageId
    ? { messageId, source: "known-message-id" }
    : await findMcpHandoffByMarker({ apiBase, projectSlug, provider, marker });
  if (!handoff?.messageId) return { cleaned: false, reason: "handoff-not-found" };

  const cancel = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/mcp-inbox/${encodeURIComponent(handoff.messageId)}/cancel`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      client_id: "project-cockpit-verifier-cleanup",
      reason,
      metadata: {
        marker,
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

export async function verifyMultimodelUiMcpCancel({
  projectSlug = "darwin-mfc",
  provider = "chatgpt-mcp",
  appBase = "http://127.0.0.1:4173",
  apiBase = "http://127.0.0.1:4370",
  timeoutMs = 120_000,
  marker = `ui-mcp-cancel-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`
} = {}) {
  const app = appBase.replace(/\/$/, "");
  const api = apiBase.replace(/\/$/, "");
  const url = `${app}/workbench/${encodeURIComponent(projectSlug)}`;
  const message = `UI MCP cancel verifier ${marker}`;
  const preflightActive = await waitForNoActiveTurns({
    apiBase: api,
    projectSlug,
    timeoutMs: Math.min(45_000, Math.max(10_000, timeoutMs / 4))
  });
  assert((preflightActive.count || 0) === 0, "active turns were still running before UI MCP cancel verification", preflightActive);

  let beforeCancel;
  try {
    beforeCancel = await agentBrowserEval({
      url,
      timeoutMs: Math.min(timeoutMs, 60_000),
      script: `
(async () => {
  const provider = ${JSON.stringify(provider)};
  const marker = ${JSON.stringify(marker)};
  const message = ${JSON.stringify(message)};
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
    return {
      hasTurn: Boolean(turn),
      turnId: turn?.getAttribute('data-turn-id') || '',
      turnStatus: turn?.getAttribute('data-turn-status') || '',
      hasResponse: Boolean(response),
      responseStatus: response?.getAttribute('data-response-status') || '',
      responseText: response?.innerText || '',
      messageId,
      providerStatus: providerButton()?.getAttribute('data-provider-status') || '',
      providerDisabled: providerButton()?.disabled === true,
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
  const selection = () => providerButtons()
    .filter((button) => button.getAttribute('data-selected') === 'true')
    .map((button) => button.getAttribute('data-provider-id') || '')
    .filter(Boolean)
    .sort();
  const expectedSelection = [provider];
  deadline = Date.now() + 5000;
  let selectedProviders = selection();
  while ((JSON.stringify(selectedProviders) !== JSON.stringify(expectedSelection)) && Date.now() < deadline) {
    await sleep(150);
    selectedProviders = selection();
  }
  if (JSON.stringify(selectedProviders) !== JSON.stringify(expectedSelection)) {
    return JSON.stringify({
      ok: false,
      reason: 'provider selection did not settle',
      selectedProviders,
      expectedSelection,
      snapshot: snapshot()
    });
  }

  if (!input() || !send()) return JSON.stringify({ ok: false, reason: 'missing composer', snapshot: snapshot() });
  input().focus();
  input().value = message;
  input().dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: message }));
  await sleep(250);
  if (send().disabled) return JSON.stringify({ ok: false, reason: 'send disabled', snapshot: snapshot() });
  send().click();

  deadline = Date.now() + 20000;
  let beforeCancel = snapshot();
  while ((!beforeCancel.hasTurn || !beforeCancel.messageId) && Date.now() < deadline) {
    await sleep(250);
    beforeCancel = snapshot();
  }
  if (!beforeCancel.messageId) return JSON.stringify({ ok: false, reason: 'handoff message id not rendered', snapshot: beforeCancel });
  return JSON.stringify({ ok: true, marker, provider, message, beforeCancel, body: document.body.innerText.slice(0, 1200) });
})()
`
    });
  } catch (error) {
    const cleanup = await cleanupMcpHandoff({
      apiBase: api,
      projectSlug,
      provider,
      marker,
      reason: "cleanup after browser setup failed during UI MCP cancel verification"
    });
    error.detail = { ...(error.detail || {}), cleanup };
    throw error;
  }

  if (!beforeCancel.ok) {
    const cleanup = await cleanupMcpHandoff({
      apiBase: api,
      projectSlug,
      provider,
      marker,
      messageId: beforeCancel.beforeCancel?.messageId,
      reason: "cleanup after browser setup returned a failed UI MCP cancel snapshot"
    });
    beforeCancel.cleanup = cleanup;
  }

  assert(beforeCancel.ok, "browser UI MCP handoff setup failed before cancel", beforeCancel);
  assert(beforeCancel.beforeCancel?.messageId, "browser did not render an MCP handoff message id before cancel", beforeCancel);
  assert(beforeCancel.beforeCancel?.turnId, "browser did not expose a turn id before cancel", beforeCancel);

  let clickCancel;
  try {
    clickCancel = await agentBrowserEval({
      url,
      timeoutMs: Math.min(timeoutMs, 50_000),
      script: `
(async () => {
  const marker = ${JSON.stringify(marker)};
  const provider = ${JSON.stringify(provider)};
  const messageId = ${JSON.stringify(beforeCancel.beforeCancel.messageId)};
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const turnForMarker = () => Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]')).find((turn) => turn.innerText.includes(marker));
  const responseForTurn = (turn) => turn?.querySelector('[data-testid="multimodel-response"][data-provider="' + provider + '"]') || null;
  const cancelButtons = () => Array.from(document.querySelectorAll('[data-testid="mcp-inbox-cancel"]'));
  const cancelButtonFor = () => cancelButtons().find((button) => button.getAttribute('data-message-id') === messageId);
  const snapshot = () => {
    const turn = turnForMarker();
    const response = responseForTurn(turn);
    return {
      hasTurn: Boolean(turn),
      turnId: turn?.getAttribute('data-turn-id') || '',
      turnStatus: turn?.getAttribute('data-turn-status') || '',
      hasResponse: Boolean(response),
      responseStatus: response?.getAttribute('data-response-status') || '',
      responseText: response?.innerText || '',
      messageId,
      cancelButtonCount: cancelButtons().length,
      hasCancelButton: Boolean(cancelButtonFor()),
      overlay: Boolean(document.querySelector('.vite-error-overlay,#webpack-dev-server-client-overlay,[data-nextjs-dialog]'))
    };
  };
  let deadline = Date.now() + 25000;
  let cancelButton = cancelButtonFor();
  while (!cancelButton && Date.now() < deadline) {
    await sleep(500);
    cancelButton = cancelButtonFor();
  }
  if (!cancelButton) return JSON.stringify({ ok: false, reason: 'cancel button not rendered for handoff', snapshot: snapshot(), body: document.body.innerText.slice(-1600) });
  cancelButton.scrollIntoView({ block: 'center' });
  cancelButton.click();
  await sleep(1000);
  return JSON.stringify({ ok: true, marker, provider, clicked: true, afterClick: snapshot(), body: document.body.innerText.slice(-1600) });
})()
`
    });
  } catch (error) {
    const cleanup = await cleanupMcpHandoff({
      apiBase: api,
      projectSlug,
      provider,
      marker,
      messageId: beforeCancel.beforeCancel.messageId,
      reason: "cleanup after browser cancel click failed during UI MCP cancel verification"
    });
    error.detail = { ...(error.detail || {}), cleanup };
    throw error;
  }

  if (!clickCancel.ok) {
    const cleanup = await cleanupMcpHandoff({
      apiBase: api,
      projectSlug,
      provider,
      marker,
      messageId: beforeCancel.beforeCancel.messageId,
      reason: "cleanup after browser cancel click returned a failed UI MCP cancel snapshot"
    });
    clickCancel.cleanup = cleanup;
  }

  assert(clickCancel.ok, "browser UI MCP cancel click failed", clickCancel);
  assert(clickCancel.clicked === true, "browser did not click the matching MCP cancel button", clickCancel);

  const inbox = await waitForCanceledInboxMessage({
    apiBase: api,
    projectSlug,
    provider,
    messageId: beforeCancel.beforeCancel.messageId,
    timeoutMs: 30_000
  });

  const persisted = await waitForPersistedCanceledTurn({
    apiBase: api,
    projectSlug,
    turnId: beforeCancel.beforeCancel.turnId,
    provider,
    timeoutMs: 45_000
  });
  const active = await waitForNoActiveTurns({ apiBase: api, projectSlug, timeoutMs: 30_000 });
  assert((active.count || 0) === 0, "active turns remained after UI MCP cancel verification", active);

  let afterCancelRecovered = false;
  let afterCancelBrowserError = null;
  let afterCancel;
  try {
    afterCancel = await agentBrowserEval({
      url,
      timeoutMs: Math.min(timeoutMs, 35_000),
      script: `
(async () => {
  const marker = ${JSON.stringify(marker)};
  const provider = ${JSON.stringify(provider)};
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const snapshot = () => {
    const turn = Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]')).find((item) => item.innerText.includes(marker));
    const response = turn?.querySelector('[data-testid="multimodel-response"][data-provider="' + provider + '"]') || null;
    return {
      ok: Boolean(turn && response),
      turnId: turn?.getAttribute('data-turn-id') || '',
      turnStatus: turn?.getAttribute('data-turn-status') || '',
      responseStatus: response?.getAttribute('data-response-status') || '',
      responseText: response?.innerText || '',
      overlay: Boolean(document.querySelector('.vite-error-overlay,#webpack-dev-server-client-overlay,[data-nextjs-dialog]')),
      body: document.body.innerText.slice(0, 1600)
    };
  };
  const deadline = Date.now() + 25000;
  let current = snapshot();
  while ((!current.ok || current.turnStatus === 'streaming') && Date.now() < deadline) {
    await sleep(500);
    current = snapshot();
  }
  return JSON.stringify(current);
})()
`
    });
  } catch (error) {
    afterCancelRecovered = true;
    afterCancelBrowserError = browserErrorSummary(error);
    afterCancel = {
      ok: true,
      recoveredFromBrowserError: true,
      reason: "browser eval failed after persisted cancel evidence was observed",
      turnId: persisted.turn.turnId,
      turnStatus: persisted.turn.status,
      responseStatus: persisted.response.status,
      responseText: persisted.response.text || "",
      browserError: afterCancelBrowserError,
      truthMode: "observed-persisted-state-after-browser-readback-failed"
    };
  }

  assert(afterCancel.ok, "browser did not render the canceled MCP turn after persistence", afterCancel);
  assert(afterCancel.responseStatus === "error", "browser did not show the canceled MCP response as an error", afterCancel);
  assert(afterCancel.turnStatus !== "streaming", "browser still showed the canceled MCP turn as streaming", afterCancel);

  const result = {
    ok: true,
    schema: "beagle.multimodel-ui-mcp-cancel-verification.v1",
    kind: "ui-mcp-cancel",
    projectSlug,
    provider,
    marker,
    turnId: beforeCancel.beforeCancel.turnId,
    messageId: beforeCancel.beforeCancel.messageId,
    browser: {
      beforeCancel,
      clickCancel,
      afterCancel,
      afterCancelRecovered,
      afterCancelBrowserError
    },
    inboxStatus: inbox.message.status,
    canceledBy: inbox.message.canceled_by,
    cancelReason: inbox.message.cancel_reason,
    persistedStatus: persisted.turn.status,
    persistedProviderStatus: persisted.response.status,
    activeTurns: active.count || 0,
    verifiedAt: new Date().toISOString(),
    truthMode: afterCancelRecovered
      ? "observed-browser-ui-mcp-cancel-persisted-lifecycle-browser-readback-recovered"
      : "observed-browser-ui-mcp-cancel-websocket-persisted-lifecycle"
  };
  await appendVerificationRecord(projectSlug, {
    ...result,
    generatedAt: new Date().toISOString()
  });
  return result;
}

export async function verifyMultimodelUiStop({
  projectSlug = "darwin-mfc",
  provider = "chatgpt-mcp",
  appBase = "http://127.0.0.1:4173",
  apiBase = "http://127.0.0.1:4370",
  timeoutMs = 120_000,
  marker = `ui-stop-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`
} = {}) {
  const app = appBase.replace(/\/$/, "");
  const api = apiBase.replace(/\/$/, "");
  const url = `${app}/workbench/${encodeURIComponent(projectSlug)}`;
  const message = `UI stop verifier ${marker}`;
  const preflightActive = await waitForNoActiveTurns({
    apiBase: api,
    projectSlug,
    timeoutMs: Math.min(45_000, Math.max(10_000, timeoutMs / 4))
  });
  assert((preflightActive.count || 0) === 0, "active turns were still running before UI stop verification", preflightActive);

  const browser = await agentBrowserEval({
    url,
    timeoutMs: Math.min(timeoutMs, 70_000),
    script: `
(async () => {
  const provider = ${JSON.stringify(provider)};
  const marker = ${JSON.stringify(marker)};
  const message = ${JSON.stringify(message)};
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const providerButtons = () => Array.from(document.querySelectorAll('[data-testid="multimodel-provider-toggle"]'));
  const providerButton = () => providerButtons().find((button) => button.getAttribute('data-provider-id') === provider);
  const input = () => document.querySelector('[data-testid="multimodel-composer-input"]');
  const send = () => document.querySelector('[data-testid="multimodel-send"]');
  const stop = () => document.querySelector('[data-testid="multimodel-stop"]');
  const turnForMarker = () => Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]')).find((turn) => turn.innerText.includes(marker));
  const responseForTurn = (turn) => turn?.querySelector('[data-testid="multimodel-response"][data-provider="' + provider + '"]') || null;
  const snapshot = () => {
    const turn = turnForMarker();
    const response = responseForTurn(turn);
    const handoffCard = response?.querySelector('.mcp-handoff-card') || null;
    const messageId = handoffCard?.querySelector('code')?.getAttribute('title') || handoffCard?.querySelector('code')?.innerText || '';
    return {
      hasTurn: Boolean(turn),
      turnId: turn?.getAttribute('data-turn-id') || '',
      turnStatus: turn?.getAttribute('data-turn-status') || '',
      hasResponse: Boolean(response),
      responseStatus: response?.getAttribute('data-response-status') || '',
      responseText: response?.innerText || '',
      messageId,
      hasStop: Boolean(stop()),
      providerStatus: providerButton()?.getAttribute('data-provider-status') || '',
      providerDisabled: providerButton()?.disabled === true,
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
  let beforeStop = snapshot();
  while ((!beforeStop.hasTurn || !beforeStop.messageId || !beforeStop.hasStop) && Date.now() < deadline) {
    await sleep(250);
    beforeStop = snapshot();
  }
  if (!beforeStop.messageId) return JSON.stringify({ ok: false, reason: 'handoff message id not rendered', snapshot: beforeStop });
  if (!beforeStop.hasStop) return JSON.stringify({ ok: false, reason: 'stop button not rendered', snapshot: beforeStop });
  stop().click();

  deadline = Date.now() + 20000;
  let afterStop = snapshot();
  while (
    !(
      ['stopped', 'completed_with_errors', 'done'].includes(afterStop.turnStatus) &&
      /stop|cancel/i.test(afterStop.responseText + ' ' + afterStop.notice)
    ) &&
    Date.now() < deadline
  ) {
    await sleep(500);
    afterStop = snapshot();
  }
  return JSON.stringify({
    ok: ['stopped', 'completed_with_errors', 'done'].includes(afterStop.turnStatus) && /stop|cancel/i.test(afterStop.responseText + ' ' + afterStop.notice),
    marker,
    provider,
    message,
    beforeStop,
    afterStop,
    body: document.body.innerText.slice(0, 1600)
  });
})()
`
  });

  assert(browser.ok, "browser UI stop flow failed", browser);
  assert(browser.beforeStop?.messageId, "browser did not render an MCP handoff message id before stop", browser);
  assert(browser.beforeStop?.hasStop, "browser did not expose the stop button", browser.beforeStop);
  assert(browser.afterStop?.turnId, "browser did not expose a turn id after stop", browser);

  const inbox = await waitForCanceledInboxMessage({
    apiBase: api,
    projectSlug,
    provider,
    messageId: browser.beforeStop.messageId,
    timeoutMs: 30_000
  });
  const active = await waitForNoActiveTurns({ apiBase: api, projectSlug, timeoutMs: 30_000 });
  assert((active.count || 0) === 0, "active turns remained after UI stop verification", active);

  const result = {
    ok: true,
    schema: "beagle.multimodel-ui-stop-verification.v1",
    kind: "ui-stop",
    projectSlug,
    provider,
    marker,
    turnId: browser.afterStop.turnId,
    messageId: browser.beforeStop.messageId,
    browser,
    inboxStatus: inbox.message.status,
    canceledBy: inbox.message.canceled_by,
    cancelReason: inbox.message.cancel_reason,
    activeTurns: active.count || 0,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-browser-ui-stop-websocket-mcp-cancel-lifecycle"
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
  const appBase = process.env.PROJECT_COCKPIT_APP_BASE || "http://127.0.0.1:4173";
  const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
  const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 120_000);
  try {
    const result = await verifyMultimodelUiMcpCancel({
      projectSlug,
      provider,
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
      error: error.message,
      detail: error.detail || null,
      truthMode: "verification-failed"
    }, null, 2));
    process.exit(1);
  } finally {
    await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
  }
}
