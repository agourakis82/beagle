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

async function postJson(url, body) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body || {})
  });
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

async function agentBrowserEval({ url, script, timeoutMs = 240_000, attempts = 2 }) {
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

async function openAgentBrowser(url, { timeoutMs = 60_000 } = {}) {
  await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
  await runShell(`agent-browser open ${shellQuote(url)}`, { timeoutMs });
  await runShell("agent-browser wait 2000", { timeoutMs: 10_000 });
}

async function agentBrowserEvalCurrent(script, { timeoutMs = 60_000 } = {}) {
  const result = await runProcess("agent-browser", ["eval", script], { timeoutMs });
  return parseAgentBrowserJson(result.stdout);
}

async function waitForPersistedMixedTurn({ apiBase, projectSlug, turnId, providers, mcpProvider, mcpReplyText, timeoutMs = 60_000 }) {
  const deadline = Date.now() + timeoutMs;
  let lastPayload = null;
  while (Date.now() < deadline) {
    lastPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=20&includeActive=1`);
    const turn = (lastPayload.turns || []).find((item) => item.turnId === turnId);
    const responses = new Map((turn?.responses || []).map((item) => [item.provider, item]));
    const allDone = providers.every((provider) => {
      const response = responses.get(provider);
      if (response?.status !== "done") return false;
      if (provider === mcpProvider) return cleanString(response.text).includes(mcpReplyText);
      return cleanString(response.text).length > 0;
    });
    if (turn && allDone && !["waiting", "streaming"].includes(turn.status)) {
      return { turn, payload: lastPayload };
    }
    await new Promise((resolve) => setTimeout(resolve, 750));
  }
  throw Object.assign(new Error("persisted mixed UI turn did not finish in time"), {
    detail: { turnId, providers, mcpProvider, mcpReplyText, lastPayload }
  });
}

async function waitForNoActiveTurns({ apiBase, projectSlug, timeoutMs = 45_000 }) {
  const deadline = Date.now() + timeoutMs;
  let activePayload = null;
  while (Date.now() < deadline) {
    activePayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
    if ((activePayload.count || 0) === 0) return activePayload;
    await new Promise((resolve) => setTimeout(resolve, 750));
  }
  return activePayload;
}

export async function verifyMultimodelUiMixedTurn({
  projectSlug = "darwin-mfc",
  immediateProvider = "codex",
  mcpProvider = "chatgpt-mcp",
  targetClient = "chatgpt",
  targetProvider = "openai",
  appBase = "http://127.0.0.1:4173",
  apiBase = "http://127.0.0.1:4370",
  timeoutMs = 240_000,
  marker = `ui-mixed-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`
} = {}) {
  const app = appBase.replace(/\/$/, "");
  const api = apiBase.replace(/\/$/, "");
  const url = `${app}/workbench/${encodeURIComponent(projectSlug)}`;
  const providers = [immediateProvider, mcpProvider];
  const message = `Mixed realtime verifier ${marker}. ${immediateProvider} should answer briefly.`;
  const mcpReplyText = `mixed mcp reply ${marker}`;

  await openAgentBrowser(url, { timeoutMs });

  const beforeReply = await agentBrowserEvalCurrent(`
(async () => {
  const marker = ${JSON.stringify(marker)};
  const providers = ${JSON.stringify(providers)};
  const immediateProvider = ${JSON.stringify(immediateProvider)};
  const mcpProvider = ${JSON.stringify(mcpProvider)};
  const message = ${JSON.stringify(message)};
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const buttons = () => Array.from(document.querySelectorAll('[data-testid="multimodel-provider-toggle"]'));
  const buttonFor = (id) => buttons().find((button) => button.getAttribute('data-provider-id') === id);
  const input = () => document.querySelector('[data-testid="multimodel-composer-input"]');
  const send = () => document.querySelector('[data-testid="multimodel-send"]');
  const turnForMarker = () => Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]')).find((turn) => turn.innerText.includes(marker));
  const responsesFor = (turn) => Array.from(turn?.querySelectorAll('[data-testid="multimodel-response"]') || []).map((el) => ({
    provider: el.getAttribute('data-provider') || '',
    status: el.getAttribute('data-response-status') || '',
    text: el.innerText || '',
    messageId: el.querySelector('.mcp-handoff-card code')?.getAttribute('title') || el.querySelector('.mcp-handoff-card code')?.innerText || ''
  }));
  const snapshot = () => {
    const turn = turnForMarker();
    const responses = responsesFor(turn);
    return {
      hasTurn: Boolean(turn),
      turnId: turn?.getAttribute('data-turn-id') || '',
      turnStatus: turn?.getAttribute('data-turn-status') || '',
      responses,
      selected: providers.map((id) => ({
        id,
        exists: Boolean(buttonFor(id)),
        selected: buttonFor(id)?.getAttribute('data-selected') === 'true',
        disabled: buttonFor(id)?.disabled === true,
        status: buttonFor(id)?.getAttribute('data-provider-status') || '',
        text: buttonFor(id)?.innerText || ''
      })),
      sendDisabled: send()?.disabled === true,
      notice: document.querySelector('[data-testid="multimodel-send-notice"]')?.innerText || '',
      overlay: Boolean(document.querySelector('.vite-error-overlay,#webpack-dev-server-client-overlay,[data-nextjs-dialog]')),
      body: document.body.innerText.slice(0, 1400)
    };
  };

  let deadline = Date.now() + 20000;
  while (providers.some((id) => !buttonFor(id)) && Date.now() < deadline) await sleep(250);
  const missing = providers.filter((id) => !buttonFor(id));
  if (missing.length) return JSON.stringify({ ok: false, reason: 'provider toggles missing', missing, snapshot: snapshot() });
  const disabled = providers.filter((id) => buttonFor(id).disabled);
  if (disabled.length) return JSON.stringify({ ok: false, reason: 'provider toggles disabled', disabled, snapshot: snapshot() });

  for (const button of buttons()) {
    const id = button.getAttribute('data-provider-id') || '';
    const shouldSelect = providers.includes(id);
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

  deadline = Date.now() + 30000;
  let beforeReply = snapshot();
  let mcpMessageId = '';
  while (!mcpMessageId && Date.now() < deadline) {
    await sleep(250);
    beforeReply = snapshot();
    mcpMessageId = beforeReply.responses.find((response) => response.provider === mcpProvider)?.messageId || '';
  }
  if (!mcpMessageId) return JSON.stringify({ ok: false, reason: 'mcp message id missing', beforeReply });

  return JSON.stringify({
    ok: true,
    marker,
    providers,
    immediateProvider,
    mcpProvider,
    message,
    mcpMessageId,
    beforeReply
  });
})()
`, { timeoutMs: Math.min(timeoutMs, 90_000) });

  assert(beforeReply.ok, "browser mixed UI turn failed before MCP reply", beforeReply);
  assert(beforeReply.mcpMessageId, "mixed UI turn did not expose an MCP message id", beforeReply);

  const replyPayload = await postJson(
    `${api}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/mcp-inbox/${encodeURIComponent(beforeReply.mcpMessageId)}/reply`,
    {
      client_id: targetClient,
      provider: targetProvider,
      text: mcpReplyText,
      metadata: {
        marker,
        verifier: "multimodel-ui-mixed-turn",
        reply_path: "node-fetch-direct-multimodel-mcp-inbox-endpoint"
      }
    }
  );
  assert(replyPayload?.status === "ok", "direct MCP reply did not return ok", replyPayload);
  assert(replyPayload?.realtime?.notified !== false, "direct MCP reply did not notify realtime runtime", replyPayload);

  const turnId = beforeReply.beforeReply?.turnId || "";
  assert(turnId, "browser did not expose the mixed UI turn id", beforeReply);

  const persisted = await waitForPersistedMixedTurn({
    apiBase: api,
    projectSlug,
    turnId,
    providers,
    mcpProvider,
    mcpReplyText,
    timeoutMs: 60_000
  });
  const active = await waitForNoActiveTurns({ apiBase: api, projectSlug, timeoutMs: 45_000 });
  assert((active.count || 0) === 0, "active turns remained after mixed UI verification", active);

  await openAgentBrowser(url, { timeoutMs: 60_000 });
  const browserRender = await agentBrowserEvalCurrent(`
(async () => {
  const marker = ${JSON.stringify(marker)};
  const providers = ${JSON.stringify(providers)};
  const mcpProvider = ${JSON.stringify(mcpProvider)};
  const mcpReplyText = ${JSON.stringify(mcpReplyText)};
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const turnForMarker = () => Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]')).find((turn) => turn.innerText.includes(marker));
  const responsesFor = (turn) => Array.from(turn?.querySelectorAll('[data-testid="multimodel-response"]') || []).map((el) => ({
    provider: el.getAttribute('data-provider') || '',
    status: el.getAttribute('data-response-status') || '',
    text: el.innerText || '',
    messageId: el.querySelector('.mcp-handoff-card code')?.getAttribute('title') || el.querySelector('.mcp-handoff-card code')?.innerText || ''
  }));
  const snapshot = () => {
    const turn = turnForMarker();
    return {
      hasTurn: Boolean(turn),
      turnId: turn?.getAttribute('data-turn-id') || '',
      turnStatus: turn?.getAttribute('data-turn-status') || '',
      responses: responsesFor(turn),
      overlay: Boolean(document.querySelector('.vite-error-overlay,#webpack-dev-server-client-overlay,[data-nextjs-dialog]')),
      body: document.body.innerText.slice(0, 1400)
    };
  };
  const deadline = Date.now() + 20000;
  let afterReply = snapshot();
  const providerDone = (snap, provider) => {
    const response = snap.responses.find((item) => item.provider === provider);
    if (!response || response.status !== 'done') return false;
    if (provider === mcpProvider) return response.text.includes(mcpReplyText);
    return response.text.trim().length > 20;
  };
  while ((afterReply.turnStatus === 'streaming' || providers.some((provider) => !providerDone(afterReply, provider))) && Date.now() < deadline) {
    await sleep(500);
    afterReply = snapshot();
  }

  return JSON.stringify({
    ok: afterReply.turnStatus !== 'streaming' && providers.every((provider) => providerDone(afterReply, provider)),
    marker,
    providers,
    mcpProvider,
    mcpReplyText,
    afterReply
  });
})()
`, { timeoutMs: 30_000 });

  assert(browserRender.ok, "browser did not render the completed mixed UI turn", { beforeReply, replyPayload, browserRender, persisted });
  assert(browserRender.afterReply?.turnStatus !== "streaming", "mixed UI turn stayed streaming", { beforeReply, replyPayload, browserRender });
  for (const provider of providers) {
    const response = (browserRender.afterReply?.responses || []).find((item) => item.provider === provider);
    assert(response?.status === "done", `${provider} did not finish in browser mixed turn`, { beforeReply, replyPayload, browserRender });
    if (provider === mcpProvider) {
      assert(cleanString(response.text).includes(mcpReplyText), `${provider} did not render the MCP reply`, response);
    } else {
      assert(cleanString(response.text).length > 20, `${provider} rendered no useful text`, response);
    }
  }

  const persistedByProvider = new Map((persisted.turn.responses || []).map((response) => [response.provider, response]));
  const result = {
    ok: true,
    schema: "beagle.multimodel-ui-mixed-turn-verification.v1",
    kind: "ui-mixed-turn",
    projectSlug,
    marker,
    providers,
    immediateProvider,
    mcpProvider,
    targetClient,
    targetProvider,
    turnId,
    mcpMessageId: beforeReply.mcpMessageId,
    mcpReplyText,
    browser: {
      beforeReply,
      replyPayload,
      afterReply: browserRender
    },
    persisted: providers.map((provider) => {
      const response = persistedByProvider.get(provider) || {};
      return {
        provider,
        status: response.status || "",
        textChars: cleanString(response.text).length,
        deltaCount: Number(response.deltaCount || 0),
        streamedChars: Number(response.streamedChars || 0),
        durationMs: response.durationMs ?? null
      };
    }),
    activeTurns: active.count || 0,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-browser-ui-mixed-local-and-mcp-turn-websocket-persisted-rendered"
  };
  await appendVerificationRecord(projectSlug, {
    ...result,
    generatedAt: new Date().toISOString()
  });
  return result;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const immediateProvider = process.env.IMMEDIATE_PROVIDER || process.argv[3] || "codex";
  const mcpProvider = process.env.MCP_PROVIDER || process.argv[4] || "chatgpt-mcp";
  const targetClient = process.env.TARGET_CLIENT || process.argv[5] || "chatgpt";
  const targetProvider = process.env.TARGET_PROVIDER || process.argv[6] || "openai";
  const appBase = process.env.PROJECT_COCKPIT_APP_BASE || "http://127.0.0.1:4173";
  const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
  const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 240_000);
  try {
    const result = await verifyMultimodelUiMixedTurn({
      projectSlug,
      immediateProvider,
      mcpProvider,
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
      immediateProvider,
      mcpProvider,
      error: error.message,
      detail: error.detail || null,
      truthMode: "verification-failed"
    }, null, 2));
    process.exit(1);
  } finally {
    await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
  }
}
