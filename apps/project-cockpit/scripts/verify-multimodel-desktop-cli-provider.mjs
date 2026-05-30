#!/usr/bin/env node

import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";
import WebSocket from "ws";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function cleanString(value, fallback = "") {
  const text = String(value ?? "").trim();
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

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
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

async function waitForNoActiveTurns({ apiBase, projectSlug, timeoutMs = 30_000 }) {
  const deadline = Date.now() + timeoutMs;
  let active = null;
  while (Date.now() < deadline) {
    active = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
    if ((active.count || 0) === 0) return active;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return active;
}

function agentKindFromProvider(provider) {
  return cleanString(provider).replace(/^agent-terminal:/, "");
}

function expectedSourceProvider(provider) {
  const kind = agentKindFromProvider(provider);
  if (kind === "desktop-claude") return "claude";
  if (kind === "desktop-codex") return "codex";
  if (kind === "desktop-cursor") return "cursor";
  return "";
}

function isAcceptedHeadlessTransport(sourceProvider, transport) {
  const value = cleanString(transport);
  if (sourceProvider === "claude") return value === "claude-code-stream-json";
  if (sourceProvider === "codex") return value === "codex-exec-json";
  if (sourceProvider === "cursor") return value === "cursor-agent-stream-json";
  return /stream-json|exec-json/.test(value);
}

async function ensureDesktopSession({ apiBase, projectSlug, provider }) {
  const kind = agentKindFromProvider(provider);
  assert(kind.startsWith("desktop-"), "provider must be an agent-terminal:desktop-* provider", { provider, kind });
  await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/agent/session/start`, {
    method: "POST",
    body: { kind, confirmed: true }
  });
  const providers = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/providers`);
  const record = (providers.providers || []).find((item) => item.id === provider);
  assert(record?.status === "available", "desktop provider was not available after session start", { provider, record });
  return record;
}

async function verifyDesktopProvider({
  projectSlug = "darwin-mfc",
  provider = "agent-terminal:desktop-cursor",
  apiBase = "http://127.0.0.1:4370",
  wsBase = apiBase.replace(/^http/, "ws"),
  timeoutMs = 120_000
} = {}) {
  const api = apiBase.replace(/\/$/, "");
  const wsUrl = `${wsBase.replace(/\/$/, "")}/ws/projects/${encodeURIComponent(projectSlug)}/multimodel-chat`;
  const preflightActive = await waitForNoActiveTurns({ apiBase: api, projectSlug, timeoutMs: 45_000 });
  assert((preflightActive.count || 0) === 0, "active turns were still running before desktop CLI provider verification", preflightActive);
  const providerRecord = await ensureDesktopSession({ apiBase: api, projectSlug, provider });
  const expectedSource = expectedSourceProvider(provider);
  const marker = `${provider.replace(/[^a-z0-9]+/gi, "-")}-${Date.now().toString(36)}`;
  const turnId = `verify-desktop-cli-${marker}`;
  const events = [];

  const realtime = await new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl);
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      try { socket.send(JSON.stringify({ type: "stop", turnId })); } catch {
        // ignore best-effort stop failure
      }
      try { socket.close(); } catch {
        // ignore close failure
      }
      reject(Object.assign(new Error("desktop CLI provider verification timed out"), {
        detail: { provider, turnId, marker, events }
      }));
    }, timeoutMs);

    function finish(payload) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { socket.close(); } catch {
        // ignore close failure
      }
      resolve(payload);
    }

    socket.on("message", (raw) => {
      let event;
      try {
        event = JSON.parse(raw.toString());
      } catch (error) {
        finish({ ok: false, error: `invalid JSON event: ${error.message}` });
        return;
      }
      if (["ready", "turn_started", "provider_started", "provider_meta", "delta", "provider_done", "provider_error", "turn_done"].includes(event.type)) {
        events.push({
          type: event.type,
          turnId: event.turnId || "",
          provider: event.provider || "",
          text: cleanString(event.text).slice(0, 300),
          error: event.error || "",
          meta: event.meta || null
        });
      }
      if (event.type === "ready") {
        socket.send(JSON.stringify({
          type: "chat",
          turnId,
          message: `Reply with exactly this marker and nothing else: ${marker}`,
          providers: [provider],
          history: [],
          enableSynthesis: false
        }));
      }
      if (event.type === "provider_done" && event.provider === provider && event.turnId === turnId) {
        finish({
          ok: cleanString(event.text).includes(marker),
          text: cleanString(event.text),
          meta: event.meta || {}
        });
      }
      if (event.type === "provider_error" && event.provider === provider && event.turnId === turnId) {
        finish({ ok: false, error: event.error || "provider error" });
      }
    });
    socket.on("error", (error) => finish({ ok: false, error: error.message }));
  });

  const turnEvents = events.filter((event) => !event.turnId || event.turnId === turnId);
  const sourceProvider = turnEvents.find((event) => event.provider === provider && event.meta?.sourceProvider)?.meta?.sourceProvider || "";
  const streamTransport = turnEvents.find((event) =>
    event.provider === provider && isAcceptedHeadlessTransport(sourceProvider || expectedSource, event.meta?.transport)
  )?.meta?.transport || "";
  assert(realtime.ok === true, "desktop CLI provider did not return the expected marker", { provider, marker, realtime, events });
  assert(sourceProvider, "desktop CLI provider did not expose source provider identity", { provider, events });
  assert(!expectedSource || sourceProvider === expectedSource, "desktop CLI provider exposed the wrong source provider identity", { provider, expectedSource, sourceProvider, events });
  assert(streamTransport, "desktop CLI provider did not prove accepted headless transport", { provider, expectedSource, events });

  const active = await waitForNoActiveTurns({ apiBase: api, projectSlug, timeoutMs: 30_000 });
  assert((active.count || 0) === 0, "active turns remained after desktop CLI provider verification", active);

  const result = {
    ok: true,
    schema: "beagle.multimodel-desktop-cli-provider-verification.v1",
    projectSlug,
    provider,
    providerLabel: providerRecord.label || "",
    sourceProvider,
    streamTransport,
    turnId,
    marker,
    text: realtime.text,
    eventCount: events.length,
    activeTurns: active.count || 0,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-websocket-desktop-subscription-cli-headless-stream"
  };
  await appendVerificationRecord(projectSlug, {
    kind: "desktop-cli-provider",
    ...result,
    generatedAt: new Date().toISOString()
  });
  return result;
}

async function verifyDesktopProviders({
  projectSlug,
  providers,
  apiBase,
  wsBase,
  timeoutMs
}) {
  const results = [];
  for (const provider of providers) {
    results.push(await verifyDesktopProvider({ projectSlug, provider, apiBase, wsBase, timeoutMs }));
  }
  const result = {
    ok: true,
    schema: "beagle.multimodel-desktop-cli-providers-verification.v1",
    projectSlug,
    providers: results.map((item) => item.provider),
    providerCount: results.length,
    results,
    activeTurns: results.at(-1)?.activeTurns ?? 0,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-websocket-desktop-subscription-cli-headless-streams"
  };
  await appendVerificationRecord(projectSlug, {
    kind: "desktop-cli-providers",
    ...result,
    generatedAt: new Date().toISOString()
  });
  return result;
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const providerArg = process.env.PROVIDERS || process.env.PROVIDER || process.argv[3] || "agent-terminal:desktop-claude,agent-terminal:desktop-codex,agent-terminal:desktop-cursor";
const providers = providerArg.split(",").map((item) => item.trim()).filter(Boolean);
const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
const wsBase = process.env.PROJECT_COCKPIT_WS_BASE || apiBase.replace(/^http/, "ws");
const timeoutMs = Number(process.env.TIMEOUT_MS || process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 120_000);

try {
  const result = providers.length === 1
    ? await verifyDesktopProvider({ projectSlug, provider: providers[0], apiBase, wsBase, timeoutMs })
    : await verifyDesktopProviders({ projectSlug, providers, apiBase, wsBase, timeoutMs });
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    schema: "beagle.multimodel-desktop-cli-provider-verification.v1",
    projectSlug,
    providers,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
