// multimodel-chat-routes.mjs
//
// Real-time chat fan-out over actual local/subscription CLIs where available.
// No provider emits a synthetic answer: unavailable adapters are reported as
// unavailable, and connected adapters stream their own process output.

import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { access, chmod, mkdir, readFile, appendFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { WebSocketServer } from "ws";
import {
  agentTerminalSnapshot,
  ensureAgentTerminalSession,
  listAgentSessions,
  writeAgentTerminalInput
} from "./agent-routes.mjs";
import { verifyMultimodelRealtime } from "./multimodel-realtime-verifier.mjs";
import { verifyMultimodelReconnect } from "./multimodel-reconnect-verifier.mjs";
import { verifyMultimodelConversation } from "./multimodel-conversation-verifier.mjs";

const DEFAULT_PROVIDER_PRIORITY = ["claude", "codex", "cursor", "kimi"];
const SYNTHESIS_RESPONSE_ID = "synthesis";
const MAX_PROMPT_CHARS = Number(process.env.PROJECT_COCKPIT_MULTIMODEL_MAX_PROMPT_CHARS || 24000);
const PROVIDER_TIMEOUT_MS = Number(process.env.PROJECT_COCKPIT_MULTIMODEL_PROVIDER_TIMEOUT_MS || 180000);
const MCP_INBOX_TIMEOUT_MS = Number(process.env.PROJECT_COCKPIT_MCP_INBOX_TIMEOUT_MS || 60000);
const MCP_INBOX_RECENT_MS = Number(process.env.PROJECT_COCKPIT_MCP_INBOX_RECENT_MS || 10 * 60 * 1000);
const SUBSCRIPTION_REPLY_PROOF_RECENT_MS = Number(process.env.PROJECT_COCKPIT_SUBSCRIPTION_REPLY_PROOF_RECENT_MS || 30 * 60 * 1000);
const TURN_HEARTBEAT_MS = Number(process.env.PROJECT_COCKPIT_MULTIMODEL_TURN_HEARTBEAT_MS || 5000);
const AGENT_TERMINAL_PROVIDER_TIMEOUT_MS = Number(process.env.PROJECT_COCKPIT_AGENT_TERMINAL_PROVIDER_TIMEOUT_MS || 120000);
const AGENT_TERMINAL_PROVIDER_IDLE_MS = Number(process.env.PROJECT_COCKPIT_AGENT_TERMINAL_PROVIDER_IDLE_MS || 1200);
const AGENT_TERMINAL_PROVIDER_READY_TIMEOUT_MS = Number(process.env.PROJECT_COCKPIT_AGENT_TERMINAL_PROVIDER_READY_TIMEOUT_MS || 15000);
const AGENT_TERMINAL_PROVIDER_READY_IDLE_MS = Number(process.env.PROJECT_COCKPIT_AGENT_TERMINAL_PROVIDER_READY_IDLE_MS || 1500);
const AGENT_NAMESPACE = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "kubectl";
const CLAUDE_SESSION_MODE = process.env.PROJECT_COCKPIT_CLAUDE_SESSION_MODE || "fresh-per-turn";
const LOCAL_REPO_BASE = process.env.PROJECT_COCKPIT_LOCAL_REPO_BASE || "/home/devsounio";
const XAI_MODEL = process.env.PROJECT_COCKPIT_XAI_MODEL || "grok-4";
const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  "/var/lib/cockpit";
const COCKPIT_LOOPBACK =
  process.env.PROJECT_COCKPIT_LOOPBACK_URL ||
  `http://127.0.0.1:${process.env.PROJECT_COCKPIT_PORT || 4370}`;
const KIMI_ZELLIJ_SESSION = process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_SESSION || "";
const KIMI_ZELLIJ_PROJECT_SLUG = process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_PROJECT_SLUG || "";
const ALLOW_CROSS_PROJECT_KIMI_ZELLIJ = process.env.PROJECT_COCKPIT_ALLOW_CROSS_PROJECT_KIMI_ZELLIJ === "1";
const KIMI_ZELLIJ_TAB = process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_TAB || "";
const KIMI_ZELLIJ_PANE = process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_PANE || "";
const KIMI_ZELLIJ_SSH_HOST = process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_SSH_HOST || "";
const KIMI_ZELLIJ_SSH_PORT = process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_SSH_PORT || "2222";
const KIMI_ZELLIJ_SSH_KEY = process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_SSH_KEY || "/home/devsounio/.ssh/id_ed25519";
const KIMI_ZELLIJ_KNOWN_HOSTS = process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_KNOWN_HOSTS || "/home/devsounio/.ssh/known_hosts";
const KIMI_ZELLIJ_CHECK_COMMAND = process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_CHECK_COMMAND || "";
const KIMI_LOCAL_COMMAND = process.env.PROJECT_COCKPIT_KIMI_COMMAND || "";
const KIMI_LOCAL_ARGS = process.env.PROJECT_COCKPIT_KIMI_ARGS || "";
const KIMI_LOCAL_CHECK_COMMAND = process.env.PROJECT_COCKPIT_KIMI_CHECK_COMMAND || KIMI_LOCAL_COMMAND;
const WORKBENCH_CONTEXT_HTTP_MCP_TOKEN =
  cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
  cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
const WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE =
  cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE) ||
  cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE);
const MCP_INBOX_PROVIDERS = [
  {
    id: "claude-desktop",
    label: "Claude Desktop",
    targetClient: "claude-desktop",
    provider: "anthropic",
    aliases: ["claude-desktop", "claude"]
  },
  {
    id: "chatgpt-mcp",
    label: "ChatGPT MCP",
    targetClient: "chatgpt",
    provider: "openai",
    aliases: ["chatgpt", "openai"]
  },
  {
    id: "grok-mcp",
    label: "Grok MCP",
    targetClient: "grok",
    provider: "xai",
    aliases: ["grok", "xai", "grok-cli"]
  }
];
const multimodelRuntimes = new Map();

function cleanString(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  const text = String(value).trim();
  return text || fallback;
}

function normalizedId(value) {
  return cleanString(value).toLowerCase();
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

function isForbiddenKimiBridgeValue(value) {
  const text = normalizedId(value);
  if (!text) return false;
  return (
    /(^|[/:._-])sounio([/:._-]|$)/i.test(text) ||
    /(^|[/:._-])sounio-workspace([/:._-]|$)/i.test(text) ||
    /(^|[/:._-])sounio-dev([/:._-]|$)/i.test(text)
  );
}

function kimiBridgeSafety({ slug }) {
  const offenders = [];
  for (const [name, value] of Object.entries({
    PROJECT_COCKPIT_KIMI_COMMAND: KIMI_LOCAL_COMMAND,
    PROJECT_COCKPIT_KIMI_CHECK_COMMAND: KIMI_LOCAL_CHECK_COMMAND,
    PROJECT_COCKPIT_KIMI_ZELLIJ_PROJECT_SLUG: KIMI_ZELLIJ_PROJECT_SLUG,
    PROJECT_COCKPIT_KIMI_ZELLIJ_SESSION: KIMI_ZELLIJ_SESSION,
    PROJECT_COCKPIT_KIMI_ZELLIJ_TAB: KIMI_ZELLIJ_TAB,
    PROJECT_COCKPIT_KIMI_ZELLIJ_SSH_HOST: KIMI_ZELLIJ_SSH_HOST,
    PROJECT_COCKPIT_KIMI_ZELLIJ_CHECK_COMMAND: KIMI_ZELLIJ_CHECK_COMMAND
  })) {
    if (isForbiddenKimiBridgeValue(value) && safeSlug(slug) !== "sounio") {
      offenders.push({ name, value: cleanString(value) });
    }
  }
  return {
    safe: offenders.length === 0,
    offenders,
    reason: offenders.length
      ? `Kimi bridge for ${slug} points at Sounio; configure a project-local Kimi command or Darwin-MFC zellij lane instead.`
      : ""
  };
}

function shellCommandBinary(command) {
  return cleanString(command).split(/\s+/)[0] || "";
}

function internalContextHeaders(extra = {}) {
  const token = WORKBENCH_CONTEXT_HTTP_MCP_TOKEN || readWorkbenchContextHttpMcpTokenFile();
  return {
    "content-type": "application/json",
    ...(token ? { authorization: `Bearer ${token}` } : {}),
    ...extra
  };
}

function readWorkbenchContextHttpMcpTokenFile() {
  if (!WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE) return "";
  try {
    return cleanString(readFileSync(WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE, "utf8"));
  } catch {
    return "";
  }
}

function isAgentTerminalProviderId(providerId) {
  return cleanString(providerId).startsWith("agent-terminal:");
}

function agentKindFromProviderId(providerId) {
  return cleanString(providerId).replace(/^agent-terminal:/, "");
}

function boundedText(value, max = MAX_PROMPT_CHARS) {
  return cleanString(value).slice(0, max);
}

function countOccurrences(text, needle) {
  const source = String(text || "");
  const target = String(needle || "");
  if (!target) return 0;
  let count = 0;
  let index = 0;
  while ((index = source.indexOf(target, index)) !== -1) {
    count += 1;
    index += target.length;
  }
  return count;
}

function textAfterStablePrefix(before = "", after = "") {
  if (!after) return "";
  if (!before) return after;
  if (after.startsWith(before)) return after.slice(before.length);
  const max = Math.min(before.length, after.length, 2000);
  for (let size = max; size > 24; size -= 1) {
    if (after.startsWith(before.slice(-size))) {
      return after.slice(size);
    }
  }
  return after;
}

function transcriptFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.jsonl`);
}

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
}

function sessionStateFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.sessions.json`);
}

function workbenchContextFile(slug) {
  return path.join(DATA_DIR, "workbench-context", `${safeSlug(slug)}.jsonl`);
}

async function appendTurnRecord(slug, record) {
  const file = transcriptFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
}

async function appendVerificationRecord(slug, record) {
  const file = verificationFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
}

function verificationKind(record = {}) {
  if (record.kind) return cleanString(record.kind);
  const schema = cleanString(record.schema);
  if (schema.includes("realtime-verification")) return "realtime";
  if (schema.includes("reconnect-verification")) return "reconnect";
  if (schema.includes("conversation-verification")) return "conversation";
  if (schema.includes("ui-send-verification")) return "ui-send";
  if (schema.includes("ui-context-verification")) return "ui-context";
  if (schema.includes("mcp-contract-verification")) return "mcp-contract";
  if (schema.includes("mcp-realtime-verification")) return "mcp-realtime";
  if (schema.includes("mcp-stdio-verification")) return "mcp-stdio";
  if (schema.includes("mcp-client-kit-verification")) return "mcp-client-kit";
  if (schema.includes("mcp-client-install-verification")) return "mcp-client-install";
  if (schema.includes("multimodel-full-verification")) return "full";
  return "";
}

async function readVerificationRecords(slug, { limit = 12, kind = "" } = {}) {
  const file = verificationFile(slug);
  try {
    const expectedKind = cleanString(kind);
    const raw = await readFile(file, "utf8");
    return raw
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean)
      .filter((record) => !expectedKind || verificationKind(record) === expectedKind)
      .sort((left, right) => timestampMs(right.verifiedAt || right.generatedAt) - timestampMs(left.verifiedAt || left.generatedAt))
      .slice(0, Math.max(1, Math.min(50, Number(limit) || 12)));
  } catch {
    return [];
  }
}

function hasTurnDoneTrace(record = {}) {
  return Array.isArray(record.trace) && record.trace.some((event) => event?.type === "turn_done");
}

function terminalResponseScore(record = {}) {
  return (Array.isArray(record.responses) ? record.responses : []).reduce((score, response) => {
    if (response.status === "done") return score + 4;
    if (response.status === "error" || response.status === "unavailable") return score + 3;
    if (response.status === "streaming") return score + 1;
    return score;
  }, 0);
}

function turnRecordCompletenessScore(record = {}) {
  const status = cleanString(record.status);
  const completed = ["done", "completed_with_errors", "stopped", "interrupted"].includes(status);
  return [
    hasTurnDoneTrace(record) ? 100000 : 0,
    completed ? 50000 : 0,
    terminalResponseScore(record) * 1000,
    (Array.isArray(record.trace) ? record.trace.length : 0) * 10,
    timestampMs(record.completedAt || record.updatedAt || record.persistedAt || record.createdAt) / 1000000000000
  ].reduce((sum, item) => sum + Number(item || 0), 0);
}

function preferredTurnRecord(left = null, right = null) {
  if (!left) return right;
  if (!right) return left;
  const leftScore = turnRecordCompletenessScore(left);
  const rightScore = turnRecordCompletenessScore(right);
  if (rightScore > leftScore) return right;
  if (leftScore > rightScore) return left;
  return turnRecordTimestamp(right) >= turnRecordTimestamp(left) ? right : left;
}

async function readTurnRecords(slug, { limit = 24 } = {}) {
  const file = transcriptFile(slug);
  try {
    const raw = await readFile(file, "utf8");
    const rows = raw
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean);
    const byTurn = new Map();
    for (const row of rows) {
      const turnId = cleanString(row.turnId || row.id);
      if (!turnId) continue;
      byTurn.set(turnId, preferredTurnRecord(byTurn.get(turnId), row));
    }
    return [...byTurn.values()]
      .sort((left, right) => turnRecordTimestamp(right) - turnRecordTimestamp(left))
      .slice(0, Math.max(1, Math.min(100, Number(limit) || 24)));
  } catch {
    return [];
  }
}

function buildProviderProofs(records = []) {
  const proofs = new Map();
  const sorted = [...records].sort((left, right) => turnRecordTimestamp(right) - turnRecordTimestamp(left));
  for (const record of sorted) {
    const observedAt = cleanString(record.completedAt || record.updatedAt || record.persistedAt || record.createdAt);
    const observedMs = timestampMs(observedAt);
    for (const response of record.responses || []) {
      const provider = cleanString(response.provider);
      if (!provider) continue;
      const existing = proofs.get(provider) || {
        provider,
        successCount: 0,
        errorCount: 0,
        unavailableCount: 0,
        truthMode: "observed-persisted-turns"
      };
      if (response.status === "done" && response.text) existing.successCount += 1;
      if (response.status === "error") existing.errorCount += 1;
      if (response.status === "unavailable") existing.unavailableCount += 1;

      const isNewer = !existing.lastObservedAt || observedMs >= timestampMs(existing.lastObservedAt);
      if (isNewer) {
        existing.lastObservedAt = observedAt;
        existing.lastTurnId = record.turnId || "";
        existing.lastStatus = response.status || "";
        existing.lastTextChars = cleanString(response.text).length;
        existing.lastError = cleanString(response.error);
        existing.lastDurationMs = response.durationMs ?? null;
        existing.lastTransport = cleanString(response.meta?.transport || "");
      }

      const isSuccess = response.status === "done" && cleanString(response.text);
      const isNewerSuccess = !existing.lastSuccessAt || observedMs >= timestampMs(existing.lastSuccessAt);
      if (isSuccess && isNewerSuccess) {
        existing.lastSuccessAt = observedAt;
        existing.lastSuccessTurnId = record.turnId || "";
        existing.lastSuccessTextChars = cleanString(response.text).length;
        existing.lastSuccessDurationMs = response.durationMs ?? null;
        existing.lastSuccessTransport = cleanString(response.meta?.transport || "");
      }
      proofs.set(provider, existing);
    }
  }
  return proofs;
}

function providerTemporaryBlockFromProof(provider, proof = {}) {
  if (!provider || provider.status !== "available") return null;
  if (cleanString(proof.lastStatus) !== "error") return null;
  const lastError = cleanString(proof.lastError);
  if (!lastError) return null;
  const isQuotaLike = /usage limit|rate limit|quota|credits|billing|try again/i.test(lastError);
  if (!isQuotaLike) return null;
  const observedMs = timestampMs(proof.lastObservedAt);
  const ageMs = observedMs ? Date.now() - observedMs : Number.POSITIVE_INFINITY;
  const blockMs = Number(process.env.PROJECT_COCKPIT_PROVIDER_TEMP_BLOCK_MS || 30 * 60 * 1000);
  if (ageMs < 0 || ageMs > blockMs) return null;
  return {
    ...provider,
    status: "unavailable",
    reason: lastError,
    deliveryStatus: "temporarily-blocked-by-provider",
    temporaryBlock: {
      reason: lastError,
      lastObservedAt: proof.lastObservedAt,
      ageMs,
      blockMs,
      truthMode: "observed-provider-process-quota-error"
    }
  };
}

async function attachProviderProofs(slug, providers) {
  const records = await readTurnRecords(slug, { limit: 100 });
  const proofs = buildProviderProofs(records);
  const emptyProof = (provider, truthMode = "observed-persisted-turns") => ({
      provider: provider.id,
      successCount: 0,
      errorCount: 0,
      unavailableCount: 0,
      truthMode
    });
  const withProofs = providers.map((provider) => {
    const proof = proofs.get(provider.id);
    if (provider.id === "kimi") {
      if (provider.status !== "available") {
        return {
          ...provider,
          proof: emptyProof(provider, "current-kimi-bridge-unavailable")
        };
      }
      const lastTransport = cleanString(proof?.lastSuccessTransport || proof?.lastTransport);
      if (provider.bridgeMode === "local-command" && lastTransport && !lastTransport.includes("kimi-local-command")) {
        return {
          ...provider,
          proof: emptyProof(provider, "current-kimi-bridge-mismatch")
        };
      }
      if (provider.bridgeMode === "native-project-zellij" && lastTransport && lastTransport !== "zellij-screen-poll") {
        return {
          ...provider,
          proof: emptyProof(provider, "current-kimi-bridge-mismatch")
        };
      }
    }
    const temporarilyBlocked = providerTemporaryBlockFromProof(provider, proof);
    if (temporarilyBlocked) {
      return {
        ...temporarilyBlocked,
        proof: proof || emptyProof(provider)
      };
    }
    return {
      ...provider,
      proof: proof || emptyProof(provider)
    }
  });
  const providerById = new Map(withProofs.map((provider) => [provider.id, provider]));
  return withProofs.map((provider) => {
    if (!isAgentTerminalProviderId(provider.id) || provider.status !== "available") {
      return provider;
    }
    const kind = cleanString(provider.agentKind || agentKindFromProviderId(provider.id));
    const baseProviderId = kind === "codex"
      ? "codex"
      : kind === "desktop-claude"
        ? "claude"
        : kind === "desktop-codex"
          ? "codex"
          : kind === "desktop-cursor"
            ? "cursor"
            : kind === "desktop-kimi"
              ? "kimi"
              : "";
    const baseProvider = baseProviderId ? providerById.get(baseProviderId) : null;
    if (!baseProvider || baseProvider.status === "available") {
      return provider;
    }
    return {
      ...provider,
      status: "unavailable",
      reason: baseProvider.reason || `${kind} runtime is unavailable`,
      deliveryStatus: baseProvider.deliveryStatus || "temporarily-blocked-by-provider",
      temporaryBlock: baseProvider.temporaryBlock || null,
      inheritedAvailabilityFrom: baseProviderId
    };
  });
}

function turnRecordTimestamp(record) {
  return timestampMs(record.completedAt || record.updatedAt || record.createdAt);
}

async function readWorkbenchContextRecords(slug) {
  try {
    const raw = await readFile(workbenchContextFile(slug), "utf8");
    return raw
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean);
  } catch {
    return [];
  }
}

async function readSessionState(slug) {
  try {
    const raw = await readFile(sessionStateFile(slug), "utf8");
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

async function writeSessionState(slug, state) {
  const file = sessionStateFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, `${JSON.stringify(state, null, 2)}\n`, "utf8");
}

async function ensureProviderSession(slug, providerId) {
  const state = await readSessionState(slug);
  const now = new Date().toISOString();
  const providers = state.providers && typeof state.providers === "object" ? state.providers : {};
  let provider = providers[providerId] && typeof providers[providerId] === "object"
    ? providers[providerId]
    : {};
  let isNew = false;

  if (providerId === "claude" && CLAUDE_SESSION_MODE === "resume" && !provider.sessionId) {
    isNew = true;
    provider = {
      ...provider,
      sessionId: randomUUID(),
      nativeContinuity: "claude-code-resume",
      createdAt: now
    };
  }

  if (providerId === "claude" && CLAUDE_SESSION_MODE !== "resume") {
    provider = {
      ...provider,
      nativeContinuity: "claude-code-fresh-session-prompt-history",
      createdAt: provider.createdAt || now
    };
  }

  if (providerId === "cursor" && !provider.sessionId) {
    isNew = true;
    provider = {
      ...provider,
      nativeContinuity: "cursor-agent-new-chat",
      createdAt: now
    };
  }

  providers[providerId] = {
    ...provider,
    updatedAt: now
  };
  const next = {
    schema: "beagle.multimodel-provider-sessions.v1",
    projectSlug: slug,
    updatedAt: now,
    providers
  };
  await writeSessionState(slug, next);
  return { ...providers[providerId], isNew };
}

async function updateProviderSession(slug, providerId, patch) {
  const state = await readSessionState(slug);
  const now = new Date().toISOString();
  const providers = state.providers && typeof state.providers === "object" ? state.providers : {};
  providers[providerId] = {
    ...(providers[providerId] || {}),
    ...patch,
    updatedAt: now
  };
  const next = {
    schema: "beagle.multimodel-provider-sessions.v1",
    projectSlug: slug,
    updatedAt: now,
    providers
  };
  await writeSessionState(slug, next);
  return providers[providerId];
}

async function commandExists(command) {
  return new Promise((resolve) => {
    const child = spawn("bash", ["-lc", `command -v ${JSON.stringify(command)} >/dev/null 2>&1`], {
      stdio: "ignore"
    });
    child.on("close", (code) => resolve(code === 0));
    child.on("error", () => resolve(false));
  });
}

function abortError(reason = "turn stopped") {
  const error = new Error(reason);
  error.name = "AbortError";
  return error;
}

function assertNotAborted(signal) {
  if (signal?.aborted) {
    const reason = signal.reason instanceof Error ? signal.reason.message : cleanString(signal.reason, "turn stopped");
    throw abortError(reason);
  }
}

function isAbortError(error) {
  return error?.name === "AbortError" || /aborted|stopped/i.test(cleanString(error?.message));
}

function combinedSignal(signal, timeoutMs, timeoutMessage = `timeout after ${timeoutMs}ms`) {
  const controller = new AbortController();
  let timer = null;
  const abortFromParent = () => {
    controller.abort(signal?.reason || abortError("turn stopped"));
  };
  if (timeoutMs) {
    timer = setTimeout(() => {
      controller.abort(abortError(timeoutMessage));
    }, timeoutMs);
  }
  if (signal?.aborted) {
    abortFromParent();
  } else if (signal) {
    signal.addEventListener("abort", abortFromParent, { once: true });
  }
  return {
    signal: controller.signal,
    cleanup() {
      if (timer) clearTimeout(timer);
      if (signal) signal.removeEventListener("abort", abortFromParent);
    }
  };
}

function wait(ms, signal) {
  assertNotAborted(signal);
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      if (signal) signal.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      reject(abortError("turn stopped"));
    };
    if (signal) signal.addEventListener("abort", onAbort, { once: true });
  });
}

function runCommandCapture(command, args, { stdin = "", timeoutMs = 10000, signal = null } = {}) {
  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    let settled = false;
    const child = spawn(command, args, {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"]
    });
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (signal) signal.removeEventListener("abort", onAbort);
      resolve(result);
    };

    const timer = setTimeout(() => {
      try { child.kill("SIGTERM"); } catch { /* already closed */ }
      finish({ code: 124, stdout, stderr: stderr || `timeout after ${timeoutMs}ms` });
    }, timeoutMs);

    const onAbort = () => {
      try { child.kill("SIGTERM"); } catch { /* already closed */ }
      finish({ code: 130, stdout, stderr: "turn stopped" });
    };
    if (signal?.aborted) {
      onAbort();
      return;
    }
    if (signal) signal.addEventListener("abort", onAbort, { once: true });

    child.stdout.on("data", (data) => { stdout += data.toString(); });
    child.stderr.on("data", (data) => { stderr += data.toString(); });
    child.stdin.on("error", () => {
      // Some subscription/CLI providers close stdin early; let the child close
      // path report the real process result instead of crashing the server.
    });
    child.on("close", (code) => {
      finish({ code, stdout, stderr });
    });
    child.on("error", (error) => {
      finish({ code: 1, stdout, stderr: error.message });
    });
    endChildStdin(child, stdin);
  });
}

function endChildStdin(child, stdin) {
  if (!child?.stdin || child.stdin.destroyed || child.stdin.writableEnded) return;
  child.stdin.on("error", () => {
    // Providers may close stdin before Node finishes writing. The process close
    // handler owns the actual success/error result; stdin errors are transport noise.
  });
  try {
    child.stdin.end(stdin);
  } catch {
    // Keep the server alive; the child close/error event will settle the provider.
  }
}

async function commandSucceeds(command, args = [], timeoutMs = 5000) {
  const result = await runCommandCapture(command, args, { timeoutMs });
  return result.code === 0;
}

function isVerifierContextRecord(record = {}) {
  const tags = Array.isArray(record.tags) ? record.tags.map(normalizedId) : [];
  const metadata = record.metadata || {};
  const userAgent = normalizedId(
    metadata.user_agent ||
      metadata.userAgent ||
      metadata.mcp_request?.user_agent ||
      metadata.mcpRequest?.userAgent
  );
  const clientInfoName = normalizedId(
    metadata.client_info?.name ||
      metadata.clientInfo?.name ||
      metadata.mcp_request?.client_info?.name ||
      metadata.mcpRequest?.clientInfo?.name
  );
  const automationText = `${userAgent} ${clientInfoName}`;
  return Boolean(
    metadata.verifier ||
      metadata.contract_verifier ||
      metadata.operator_ui ||
      metadata.reply_path === "manual-subscription-paste-ui" ||
      metadata.truthMode === "observed-human-mediated-subscription-reply" ||
      ["fixture", "public-mcp-smoke", "beagle-probe-guard"].some((needle) => automationText.includes(needle)) ||
      /\b(curl|undici|node-fetch|playwright|verifier|project-cockpit)\b/.test(automationText) ||
      normalizedId(record.client_id || record.source).startsWith("fixture-") ||
      tags.includes("mcp-realtime") ||
      tags.includes("fixture") ||
      tags.includes("probe") ||
      tags.some((tag) => tag.startsWith("fixture-"))
  );
}

function isHandoffLifecycleRecord(record = {}) {
  return Boolean(
    record.metadata?.agent_message_ack ||
      record.metadata?.agent_message_claim ||
      record.metadata?.agent_message_release ||
      record.metadata?.agent_message_complete ||
      record.metadata?.agent_message_cancel ||
      record.metadata?.agent_message_reopen ||
      record.metadata?.agent_message_heartbeat
  );
}

function clientPresenceFromRecords(records, client) {
  const aliases = new Set([client.targetClient, ...(client.aliases || [])].map(normalizedId).filter(Boolean));
  const matching = records
    .filter((record) => !isVerifierContextRecord(record))
    .filter((record) => !isHandoffLifecycleRecord(record))
    .filter((record) => (
      [record.source, record.provider, record.client_id]
        .map(normalizedId)
        .some((value) => aliases.has(value))
    ));
  const latestAt = matching
    .map((record) => cleanString(record.created_at))
    .sort()
    .at(-1) || "";
  const latestMs = Date.parse(latestAt || "");
  const ageMs = Number.isFinite(latestMs) ? Date.now() - latestMs : null;
  const presenceStatus = !matching.length
    ? "unobserved"
    : ageMs !== null && ageMs <= MCP_INBOX_RECENT_MS
      ? "recent"
      : "stale";
  return {
    clientPresence: presenceStatus,
    clientLatestAt: latestAt,
    clientMemoryCount: matching.length,
    clientSessionCount: new Set(matching.map((record) => record.session_id).filter(Boolean)).size,
    clientAgeMs: ageMs
  };
}

function mcpInboxProviderReadiness(presence) {
  if (presence.clientPresence === "recent") {
    return {
      status: "available",
      deliveryStatus: "client-recent",
      reason: ""
    };
  }
  const age = presence.clientAgeMs !== null && presence.clientAgeMs !== undefined
    ? `${Math.max(1, Math.round(presence.clientAgeMs / 1000))}s ago`
    : "never";
  return {
    status: "waiting",
    deliveryStatus: presence.clientPresence === "stale" ? "client-stale" : "client-unobserved",
    reason: `Workbench Context mailbox is ready; waiting for the subscription client to reply through MCP. Latest client write: ${age}`
  };
}

function timestampMs(value) {
  const parsed = Date.parse(cleanString(value));
  return Number.isFinite(parsed) ? parsed : 0;
}

function latestBy(items = [], key) {
  return [...items]
    .filter((item) => timestampMs(item?.[key]))
    .sort((left, right) => timestampMs(left[key]) - timestampMs(right[key]))
    .at(-1) || null;
}

function collectMcpMessageLifecycle(records) {
  const lifecycle = {
    acknowledgements: new Map(),
    claims: new Map(),
    completions: new Map(),
    cancellations: new Map(),
    heartbeats: new Map()
  };

  function push(map, messageId, item) {
    const id = cleanString(messageId);
    if (!id) return;
    const list = map.get(id) || [];
    list.push(item);
    map.set(id, list);
  }

  for (const record of records) {
    const ack = record.metadata?.agent_message_ack;
    if (ack?.message_id) {
      push(lifecycle.acknowledgements, ack.message_id, {
        client_id: cleanString(ack.client_id || record.client_id || record.source),
        ack_at: cleanString(ack.ack_at || record.created_at),
        memory_id: record.memory_id
      });
    }
    const claim = record.metadata?.agent_message_claim;
    if (claim?.message_id) {
      push(lifecycle.claims, claim.message_id, {
        client_id: cleanString(claim.client_id || record.client_id || record.source),
        claimed_at: cleanString(claim.claimed_at || record.created_at),
        memory_id: record.memory_id
      });
    }
    const completion = record.metadata?.agent_message_complete;
    if (completion?.message_id) {
      push(lifecycle.completions, completion.message_id, {
        client_id: cleanString(completion.client_id || record.client_id || record.source),
        completed_at: cleanString(completion.completed_at || record.created_at),
        result: cleanString(completion.result),
        memory_id: record.memory_id
      });
    }
    const cancellation = record.metadata?.agent_message_cancel;
    if (cancellation?.message_id) {
      push(lifecycle.cancellations, cancellation.message_id, {
        client_id: cleanString(cancellation.client_id || record.client_id || record.source),
        canceled_at: cleanString(cancellation.canceled_at || record.created_at),
        reason: cleanString(cancellation.reason),
        memory_id: record.memory_id
      });
    }
    const heartbeat = record.metadata?.agent_message_heartbeat;
    if (heartbeat?.message_id) {
      push(lifecycle.heartbeats, heartbeat.message_id, {
        client_id: cleanString(heartbeat.client_id || record.client_id || record.source),
        heartbeat_at: cleanString(heartbeat.heartbeat_at || record.created_at),
        progress: cleanString(heartbeat.progress),
        memory_id: record.memory_id
      });
    }
  }
  return lifecycle;
}

function mcpMessageState(lifecycle, messageId) {
  const acknowledgements = lifecycle.acknowledgements.get(messageId) || [];
  const claims = lifecycle.claims.get(messageId) || [];
  const completions = lifecycle.completions.get(messageId) || [];
  const cancellations = lifecycle.cancellations.get(messageId) || [];
  const heartbeats = lifecycle.heartbeats.get(messageId) || [];
  const latestAck = latestBy(acknowledgements, "ack_at");
  const latestClaim = latestBy(claims, "claimed_at");
  const latestCompletion = latestBy(completions, "completed_at");
  const latestCancellation = latestBy(cancellations, "canceled_at");
  const latestHeartbeat = latestBy(heartbeats, "heartbeat_at");
  const cancelMs = timestampMs(latestCancellation?.canceled_at);
  const completeMs = timestampMs(latestCompletion?.completed_at);
  const claimMs = timestampMs(latestClaim?.claimed_at);
  const ackMs = timestampMs(latestAck?.ack_at);
  const status = cancelMs && cancelMs >= Math.max(completeMs, claimMs, ackMs)
    ? "canceled"
    : completeMs && completeMs >= Math.max(cancelMs, claimMs, ackMs)
      ? "completed"
      : claimMs && claimMs >= Math.max(cancelMs, completeMs)
        ? "claimed"
        : ackMs && ackMs >= cancelMs
          ? "acknowledged"
          : "sent";

  return {
    status,
    acked_by: cleanString(latestAck?.client_id),
    ack_at: cleanString(latestAck?.ack_at),
    claimed_by: status === "claimed" ? cleanString(latestClaim?.client_id) : "",
    claimed_at: cleanString(latestClaim?.claimed_at),
    completed_by: status === "completed" ? cleanString(latestCompletion?.client_id) : "",
    completed_at: cleanString(latestCompletion?.completed_at),
    canceled_by: status === "canceled" ? cleanString(latestCancellation?.client_id) : "",
    canceled_at: cleanString(latestCancellation?.canceled_at),
    cancel_reason: cleanString(latestCancellation?.reason),
    heartbeat_at: cleanString(latestHeartbeat?.heartbeat_at),
    heartbeat_by: cleanString(latestHeartbeat?.client_id)
  };
}

function findMcpInboxReplyInRecords({ records, targetClient, aliases = [], threadId, sentAt, messageId }) {
  const aliasSet = new Set([targetClient, ...aliases].map(normalizedId).filter(Boolean));
  const sentMs = timestampMs(sentAt);
  return records
    .filter((record) => recordThreadId(record) === threadId)
    .filter((record) => timestampMs(record.created_at) > sentMs)
    .filter((record) => cleanString(record.external_id) !== messageId)
    .filter((record) => !(
      record.metadata?.agent_message ||
      record.metadata?.agent_message_ack ||
      record.metadata?.agent_message_claim ||
      record.metadata?.agent_message_complete ||
      record.metadata?.agent_message_cancel ||
      record.metadata?.agent_message_reopen ||
      record.metadata?.agent_message_heartbeat
    ))
    .filter((record) => recordClientAliases(record).some((alias) => aliasSet.has(alias)))
    .filter((record) => cleanString(record.text || record.content))
    .sort((left, right) => cleanString(left.created_at).localeCompare(cleanString(right.created_at)))
    .at(0) || null;
}

async function inspectMcpInboxHandoff({ slug, handoff }) {
  const records = await readWorkbenchContextRecords(slug);
  const lifecycle = collectMcpMessageLifecycle(records);
  const state = mcpMessageState(lifecycle, handoff.messageId);
  const reply = findMcpInboxReplyInRecords({
    records,
    targetClient: handoff.config.targetClient,
    aliases: handoff.config.aliases,
    threadId: handoff.threadId,
    sentAt: handoff.sentAt,
    messageId: handoff.messageId
  });
  const completion = latestBy(lifecycle.completions.get(handoff.messageId) || [], "completed_at");
  const cancellation = latestBy(lifecycle.cancellations.get(handoff.messageId) || [], "canceled_at");
  const heartbeat = latestBy(lifecycle.heartbeats.get(handoff.messageId) || [], "heartbeat_at");
  return {
    records,
    state,
    reply,
    completion,
    cancellation,
    heartbeat,
    meta: {
      transport: "workbench-context-mcp-inbox",
      message_id: handoff.messageId,
      thread_id: handoff.threadId,
      targetClient: handoff.config.targetClient,
      state: `handoff-${state.status}`,
      lifecycle_status: state.status,
      acked_by: state.acked_by,
      ack_at: state.ack_at,
      claimed_by: state.claimed_by,
      claimed_at: state.claimed_at,
      completed_by: state.completed_by,
      completed_at: state.completed_at,
      canceled_by: state.canceled_by,
      canceled_at: state.canceled_at,
      cancel_reason: state.cancel_reason,
      heartbeat_at: state.heartbeat_at,
      heartbeat_by: state.heartbeat_by
    }
  };
}

function buildMcpInboxStatusFromRecords(slug, records, { limit = 5 } = {}) {
  const lifecycle = collectMcpMessageLifecycle(records);
  const now = Date.now();
  const providers = MCP_INBOX_PROVIDERS.map((provider) => {
    const messages = records
      .filter((record) => record.metadata?.agent_message?.message_id)
      .filter((record) => cleanString(record.metadata.agent_message.to_client) === provider.targetClient)
      .filter((record) => {
        const providerId = cleanString(record.metadata?.providerId || record.metadata?.agent_message?.providerId);
        const tags = record.tags || [];
        return !providerId || providerId === provider.id || tags.includes(provider.id) || tags.includes("mcp-inbox");
      })
      .map((record) => {
        const meta = record.metadata.agent_message;
        const messageId = cleanString(meta.message_id);
        const sentAt = cleanString(meta.sent_at || record.created_at);
        const reply = findMcpInboxReplyInRecords({
          records,
          targetClient: provider.targetClient,
          aliases: provider.aliases,
          threadId: cleanString(meta.thread_id || record.session_id),
          sentAt,
          messageId
        });
        const state = mcpMessageState(lifecycle, messageId);
        const status = reply
          ? "replied"
          : state.status;
        const sentMs = timestampMs(sentAt);
        return {
          message_id: messageId,
          provider_id: provider.id,
          targetClient: provider.targetClient,
          reply_endpoint: `/api/workbench/${slug}/context/messages/${encodeURIComponent(messageId)}/reply`,
          direct_reply_endpoint: `/api/projects/${slug}/multimodel/mcp-inbox/${encodeURIComponent(messageId)}/reply`,
          subject: cleanString(meta.subject || "multimodel realtime inbox turn"),
          status,
          lifecycle_status: state.status,
          thread_id: cleanString(meta.thread_id || record.session_id),
          sent_at: sentAt,
          age_ms: sentMs ? Math.max(0, now - sentMs) : null,
          age_seconds: sentMs ? Math.max(0, Math.round((now - sentMs) / 1000)) : null,
          requires_response: meta.requires_response === true,
          reply_memory_id: cleanString(reply?.memory_id),
          reply_source: cleanString(reply?.source),
          reply_client_id: cleanString(reply?.client_id),
          reply_at: cleanString(reply?.created_at),
          acked_by: state.acked_by,
          ack_at: state.ack_at,
          claimed_by: state.claimed_by,
          claimed_at: state.claimed_at,
          completed_by: state.completed_by,
          completed_at: state.completed_at,
          canceled_by: state.canceled_by,
          canceled_at: state.canceled_at,
          cancel_reason: state.cancel_reason,
          heartbeat_at: state.heartbeat_at,
          snippet: cleanString(record.text).slice(0, 280)
        };
      })
      .sort((left, right) => cleanString(right.sent_at).localeCompare(cleanString(left.sent_at)))
      .slice(0, limit);
    const counts = messages.reduce((acc, item) => {
      acc[item.status] = (acc[item.status] || 0) + 1;
      acc.total += 1;
      if (!["replied", "completed", "canceled"].includes(item.status)) acc.open += 1;
      return acc;
    }, { total: 0, open: 0, sent: 0, acknowledged: 0, claimed: 0, replied: 0, completed: 0, canceled: 0 });
    return {
      provider_id: provider.id,
      label: provider.label,
      targetClient: provider.targetClient,
      transport: "workbench-context-mcp-inbox",
      ...clientPresenceFromRecords(records, provider),
      counts,
      latest: messages[0] || null,
      messages
    };
  });
  return {
    schema: "beagle.multimodel-mcp-inbox-status.v1",
    projectSlug: slug,
    generatedAt: new Date().toISOString(),
    providers,
    truthMode: "observed"
  };
}

function findMcpHandoffRecord(records, messageId) {
  const id = cleanString(messageId);
  if (!id) return null;
  return records.find((record) => cleanString(record.metadata?.agent_message?.message_id) === id) || null;
}

function reconciledMcpText({ reply, completion }) {
  return cleanString(reply ? extractContextReplyText(reply) : completion?.result);
}

function reconcileMcpResponseFromContext(response, records, now = new Date().toISOString()) {
  if (!response || response.status === "done") return response;
  if (response.meta?.transport !== "workbench-context-mcp-inbox") return response;

  const messageId = cleanString(response.meta?.message_id);
  if (!messageId) return response;

  const config = mcpInboxConfig(response.provider);
  if (!config) return response;

  const handoffRecord = findMcpHandoffRecord(records, messageId);
  const handoffMeta = handoffRecord?.metadata?.agent_message || {};
  const targetClient = cleanString(response.meta?.targetClient || handoffMeta.to_client || config.targetClient);
  const threadId = cleanString(response.meta?.thread_id || handoffMeta.thread_id || handoffRecord?.session_id);
  const sentAt = cleanString(handoffMeta.sent_at || handoffRecord?.created_at || response.startedAt || response.meta?.sent_at);
  if (!targetClient || !threadId || !sentAt) return response;

  const lifecycle = collectMcpMessageLifecycle(records);
  const state = mcpMessageState(lifecycle, messageId);
  if (state.status === "canceled") return {
    ...response,
    meta: {
      ...(response.meta || {}),
      lifecycle_status: state.status,
      state: "handoff-canceled",
      canceled_by: state.canceled_by,
      canceled_at: state.canceled_at,
      cancel_reason: state.cancel_reason
    }
  };

  const reply = findMcpInboxReplyInRecords({
    records,
    targetClient,
    aliases: config.aliases,
    threadId,
    sentAt,
    messageId
  });
  const completion = latestBy(lifecycle.completions.get(messageId) || [], "completed_at");
  const text = reconciledMcpText({ reply, completion });
  const nextMeta = {
    ...(response.meta || {}),
    lifecycle_status: state.status,
    state: `handoff-${reply ? "replied" : state.status}`,
    targetClient,
    thread_id: threadId,
    message_id: messageId,
    acked_by: state.acked_by,
    ack_at: state.ack_at,
    claimed_by: state.claimed_by,
    claimed_at: state.claimed_at,
    completed_by: state.completed_by || completion?.client_id || "",
    completed_at: state.completed_at || completion?.completed_at || "",
    heartbeat_at: state.heartbeat_at,
    heartbeat_by: state.heartbeat_by
  };

  if (!text) {
    return {
      ...response,
      meta: nextMeta
    };
  }

  return {
    ...response,
    status: "done",
    text,
    error: "",
    meta: {
      ...nextMeta,
      late_reply: true,
      reconciled_at: now,
      reply_memory_id: cleanString(reply?.memory_id || completion?.memory_id),
      reply_client_id: cleanString(reply?.client_id || completion?.client_id),
      reply_source: cleanString(reply?.source || completion?.client_id || targetClient)
    }
  };
}

async function reconcileTurnRecordsWithMcpContext(slug, records) {
  if (!records.some((record) =>
    (record.responses || []).some((response) => response.meta?.transport === "workbench-context-mcp-inbox")
  )) {
    return records;
  }

  const contextRecords = await readWorkbenchContextRecords(slug);
  if (!contextRecords.length) return records;
  const now = new Date().toISOString();
  return records.map((record) => {
    const previousResponses = record.responses || [];
    const responses = previousResponses.map((response) =>
      reconcileMcpResponseFromContext(response, contextRecords, now)
    );
    const changed = responses.some((response, index) => response !== previousResponses[index]);
    if (!changed) return record;
    const blocking = responses.some((response) => ["waiting", "streaming"].includes(response.status));
    const anyDone = responses.some((response) => response.status === "done");
    return {
      ...record,
      responses,
      status: blocking ? record.status : anyDone ? "done" : record.status,
      reconciledAt: now
    };
  });
}

async function pathExists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

function repoBasename(repoUrl) {
  try {
    const pathname = new URL(repoUrl).pathname;
    return path.basename(pathname, ".git");
  } catch {
    return "";
  }
}

async function loadProjectContext(slug) {
  try {
    const catalogPath = path.join(process.cwd(), "public", "project-catalog.json");
    const catalog = JSON.parse(await readFile(catalogPath, "utf8"));
    const project = (catalog.projects || []).find((item) => item.projectSlug === slug) || {};
    const candidates = [
      project.localRepoRoot,
      repoBasename(project.repoUrl) ? path.join(LOCAL_REPO_BASE, repoBasename(project.repoUrl)) : "",
      path.join(LOCAL_REPO_BASE, slug),
      path.join(LOCAL_REPO_BASE, "projects", slug)
    ].filter(Boolean);

    for (const candidate of candidates) {
      if (await pathExists(path.join(candidate, ".git"))) {
        return { project, repoRoot: candidate };
      }
    }

    return { project, repoRoot: candidates[0] || process.cwd() };
  } catch {
    return { project: {}, repoRoot: process.cwd() };
  }
}

async function detectProviders(slug) {
  const kimiSafety = kimiBridgeSafety({ slug });
  const kimiLocalConfigured = Boolean(cleanString(KIMI_LOCAL_COMMAND));
  const kimiLocalBinary = shellCommandBinary(KIMI_LOCAL_COMMAND);
  const kimiConfigured = Boolean(KIMI_ZELLIJ_PROJECT_SLUG && KIMI_ZELLIJ_SESSION && KIMI_ZELLIJ_TAB && KIMI_ZELLIJ_SSH_HOST);
  const kimiProjectAligned = kimiConfigured && safeSlug(slug) === safeSlug(KIMI_ZELLIJ_PROJECT_SLUG);
  const kimiCrossProject = kimiConfigured && !kimiProjectAligned;
  const shouldProbeKimiZellij = kimiSafety.safe && kimiConfigured && (kimiProjectAligned || ALLOW_CROSS_PROJECT_KIMI_ZELLIJ);
  const shouldProbeKimiLocal = kimiSafety.safe && kimiLocalConfigured && Boolean(kimiLocalBinary);
  const [{ repoRoot }, hasClaude, hasCodex, hasCursor, hasKimiLocal, hasKimiZellij, sessionState, contextRecords, agentSessions] = await Promise.all([
    loadProjectContext(slug),
    commandExists("claude"),
    commandExists("codex"),
    commandExists("cursor-agent"),
    shouldProbeKimiLocal ? commandExists(kimiLocalBinary) : Promise.resolve(false),
    shouldProbeKimiZellij && KIMI_ZELLIJ_CHECK_COMMAND ? commandSucceeds(KIMI_ZELLIJ_CHECK_COMMAND, ["--check"], 3000) : Promise.resolve(false),
    readSessionState(slug),
    readWorkbenchContextRecords(slug),
    listAgentSessions(slug).catch(() => [])
  ]);
  const sessions = sessionState.providers || {};
  const kimiBridgeAllowed = kimiSafety.safe && kimiConfigured && (kimiProjectAligned || ALLOW_CROSS_PROJECT_KIMI_ZELLIJ);
  const kimiLocalAvailable = hasKimiLocal && kimiLocalConfigured;
  const kimiZellijAvailable = hasKimiZellij && kimiBridgeAllowed;
  const kimiAvailable = kimiLocalAvailable || kimiZellijAvailable;
  const kimiBridgeMode = kimiLocalAvailable
    ? "local-command"
    : kimiProjectAligned
      ? "native-project-zellij"
      : kimiCrossProject
        ? "cross-project-zellij"
        : "not-configured";

  const coreProviders = [
    {
      id: "claude",
      label: "Claude Code",
      transport: "local-subscription-cli",
      status: hasClaude ? "available" : "unavailable",
      command: hasClaude ? "claude" : "",
      model: process.env.PROJECT_COCKPIT_CLAUDE_MODEL || "sonnet",
      nativeSessionId: CLAUDE_SESSION_MODE === "resume"
        ? sessions.claude?.sessionId || ""
        : sessions.claude?.lastSessionId || "",
      nativeContinuity: CLAUDE_SESSION_MODE === "resume"
        ? sessions.claude?.nativeContinuity || "claude-code-resume"
        : "claude-code-fresh-session-prompt-history",
      repoRoot,
      reason: hasClaude ? "" : "claude binary not found on PATH"
    },
    {
      id: "codex",
      label: "Codex",
      transport: "local-subscription-cli",
      status: hasCodex ? "available" : "unavailable",
      command: hasCodex ? "codex" : "",
      model: process.env.PROJECT_COCKPIT_CODEX_MODEL || "",
      nativeSessionId: sessions.codex?.threadId || "",
      nativeContinuity: sessions.codex?.threadId ? "codex-exec-resume-read-only" : "stateless-read-only",
      repoRoot,
      reason: hasCodex ? "" : "codex binary not found on PATH"
    },
    {
      id: "cursor",
      label: "Cursor Agent",
      transport: "local-subscription-cli",
      status: hasCursor ? "available" : "unavailable",
      command: hasCursor ? "cursor-agent" : "",
      model: sessions.cursor?.model || process.env.PROJECT_COCKPIT_CURSOR_MODEL || "",
      nativeSessionId: sessions.cursor?.sessionId || "",
      nativeContinuity: sessions.cursor?.sessionId ? "cursor-agent-resume" : "cursor-agent-new-chat",
      repoRoot,
      reason: hasCursor ? "" : "cursor-agent binary not found on PATH"
    },
    {
      id: "grok",
      label: "Grok",
      transport: "xai-api-stream",
      status: cleanString(process.env.XAI_API_KEY) ? "available" : "unavailable",
      command: "",
      model: XAI_MODEL,
      nativeSessionId: "",
      nativeContinuity: "api-history",
      repoRoot,
      reason: cleanString(process.env.XAI_API_KEY) ? "" : "XAI_API_KEY is not set for the real Grok API adapter"
    },
    {
      id: "kimi",
      label: kimiCrossProject ? `Kimi Code (via ${KIMI_ZELLIJ_PROJECT_SLUG})` : "Kimi Code",
      transport: kimiLocalAvailable ? "local-subscription-cli" : "remote-zellij-terminal",
      status: kimiAvailable ? "available" : "unavailable",
      command: kimiLocalAvailable ? KIMI_LOCAL_COMMAND : kimiZellijAvailable ? KIMI_ZELLIJ_CHECK_COMMAND : "",
      model: cleanString(process.env.PROJECT_COCKPIT_KIMI_MODEL || "kimi-k2.5"),
      nativeSessionId: kimiLocalAvailable
        ? "kimi-local-command"
        : KIMI_ZELLIJ_SESSION && KIMI_ZELLIJ_TAB
        ? `${KIMI_ZELLIJ_SESSION}:${KIMI_ZELLIJ_TAB}${KIMI_ZELLIJ_PANE ? `:${KIMI_ZELLIJ_PANE}` : ""}`
        : "",
      nativeContinuity: kimiBridgeMode,
      repoRoot,
      bridgeProjectSlug: KIMI_ZELLIJ_PROJECT_SLUG,
      bridgeMode: kimiBridgeMode,
      bridgeSafety: kimiSafety,
      reason: kimiAvailable
        ? (kimiLocalAvailable ? "" : `chat bridge is live through ${KIMI_ZELLIJ_PROJECT_SLUG}; Kimi answers in ${KIMI_ZELLIJ_SESSION}:${KIMI_ZELLIJ_TAB}`)
        : !kimiSafety.safe
          ? kimiSafety.reason
          : !kimiConfigured && !kimiLocalConfigured
          ? `Kimi bridge is not configured for project ${slug}; set PROJECT_COCKPIT_KIMI_COMMAND for a local subscription CLI or PROJECT_COCKPIT_KIMI_ZELLIJ_PROJECT_SLUG, SESSION, TAB, PANE, and SSH_HOST for this project.`
          : kimiLocalConfigured && !hasKimiLocal
            ? `Kimi command binary was not found: ${kimiLocalBinary}`
          : !shouldProbeKimiZellij
            ? `Kimi bridge points at ${KIMI_ZELLIJ_PROJECT_SLUG}; cross-project use is blocked unless PROJECT_COCKPIT_ALLOW_CROSS_PROJECT_KIMI_ZELLIJ=1.`
            : "configured Kimi zellij workspace bridge is not available"
    }
  ].concat(MCP_INBOX_PROVIDERS.map((provider) => {
    const presence = clientPresenceFromRecords(contextRecords, provider);
    const readiness = mcpInboxProviderReadiness(presence);
    return {
      id: provider.id,
      label: provider.label,
      transport: "workbench-context-mcp-inbox",
      status: readiness.status,
      command: "",
      model: "",
      nativeSessionId: `workbench-context:${provider.targetClient}`,
      nativeContinuity: "mcp-client-writes-back-to-context",
      repoRoot,
      reason: readiness.reason,
      targetClient: provider.targetClient,
      provider: provider.provider,
      deliveryStatus: readiness.deliveryStatus,
      mailboxStatus: "available",
      selectable: true,
      ...presence
    };
  }));

  const coreProviderById = new Map(coreProviders.map((provider) => [provider.id, provider]));
  const terminalProviderBase = (session = {}) => {
    if (session.kind === "codex") return coreProviderById.get("codex") || null;
    if (session.kind === "desktop-claude") return coreProviderById.get("claude") || null;
    if (session.kind === "desktop-codex") return coreProviderById.get("codex") || null;
    if (session.kind === "desktop-cursor") return coreProviderById.get("cursor") || null;
    if (session.kind === "desktop-kimi") return coreProviderById.get("kimi") || null;
    return null;
  };

  const terminalProviders = (agentSessions || []).map((session) => {
    const baseProvider = terminalProviderBase(session);
    const inheritedUnavailable = baseProvider && baseProvider.status !== "available";
    const running = session.status === "running";
    return {
      id: `agent-terminal:${session.kind}`,
      label: session.label || `${session.kind} terminal`,
      transport: session.local ? "local-desktop-pty" : session.kind === "codex" ? "agent-pod-codex-exec-json" : "shared-agent-pty",
      status: running && !inheritedUnavailable ? "available" : "unavailable",
      command: session.command || "",
      model: "",
      nativeSessionId: session.name || "",
      nativeContinuity: session.local ? "local-desktop-subscription-cli" : session.kind === "codex" ? "agent-pod-subscription-cli" : "shared-agent-pty",
      repoRoot,
      reason: !running
        ? `${session.kind} agent is ${session.status}`
        : inheritedUnavailable
          ? (baseProvider?.reason || `${session.kind} runtime is unavailable`)
          : "",
      agentKind: session.kind,
      workspaceAuthority: session.workspaceAuthority || "",
      terminalProvider: true
    };
  });

  return coreProviders.concat(terminalProviders);
}

function providerById(providers, id) {
  return providers.find((provider) => provider.id === id);
}

function isImmediateRealtimeProvider(provider = {}) {
  if (provider.id === "kimi" && provider.status === "available" && provider.transport === "remote-zellij-terminal") {
    return true;
  }
  return provider.status === "available" && [
    "local-subscription-cli",
    "xai-api-stream",
    "shared-agent-pty",
    "local-desktop-pty",
    "agent-pod-codex-exec-json"
  ].includes(provider.transport);
}

function isRunnableProvider(provider = {}) {
  if (provider.transport === "workbench-context-mcp-inbox") {
    return provider.mailboxStatus === "available";
  }
  return provider.status === "available";
}

function providerReadinessState(provider = {}) {
  if (isImmediateRealtimeProvider(provider)) return "live-now";
  if (provider.transport === "workbench-context-mcp-inbox") {
    return provider.status === "available" ? "handoff-live" : "handoff-stale";
  }
  if (provider.id === "kimi" && provider.bridgeMode === "cross-project-zellij") {
    return provider.status === "available" ? "cross-project-live" : "cross-project-blocked";
  }
  return provider.status === "available" ? "available" : "blocked";
}

function providerReadinessReason(provider = {}) {
  if (isImmediateRealtimeProvider(provider)) return "streams on the active WebSocket turn";
  if (provider.transport === "workbench-context-mcp-inbox") {
    if (provider.status === "available") return "subscription client is writing fresh Workbench Context records";
    return provider.reason || "subscription client has not written a fresh heartbeat";
  }
  return provider.reason || "";
}

function mcpHttpEndpointForClient(slug, targetClient, provider = "") {
  const clientId = cleanString(targetClient);
  if (!clientId) return `/api/workbench/${slug}/context/mcp`;
  const query = new URLSearchParams({
    client_id: clientId,
    provider: cleanString(provider || clientId)
  }).toString();
  return `/api/workbench/${slug}/context/mcp?${query}`;
}

function mcpHttpHeadersForClient(targetClient, provider = "") {
  const clientId = cleanString(targetClient);
  if (!clientId) return { "content-type": "application/json" };
  return {
    "content-type": "application/json",
    "x-beagle-client-id": clientId,
    "x-beagle-provider": cleanString(provider || clientId)
  };
}

function providerReadinessRecord(provider = {}, slug = "") {
  const proof = provider.proof || {};
  return {
    id: provider.id,
    label: provider.label,
    status: provider.status,
    transport: provider.transport,
    state: providerReadinessState(provider),
    immediateRealtime: isImmediateRealtimeProvider(provider),
    selectable: isRunnableProvider(provider),
    reason: providerReadinessReason(provider),
    lastSuccessAt: proof.lastSuccessAt || "",
    lastSuccessTextChars: proof.lastSuccessTextChars || 0,
    lastSuccessTransport: proof.lastSuccessTransport || "",
    deliveryStatus: provider.deliveryStatus || "",
    targetClient: provider.targetClient || "",
    mcpEndpoint: provider.transport === "workbench-context-mcp-inbox"
      ? mcpHttpEndpointForClient(slug, provider.targetClient, provider.provider)
      : "",
    mcpHeaders: provider.transport === "workbench-context-mcp-inbox"
      ? mcpHttpHeadersForClient(provider.targetClient, provider.provider)
      : null,
    clientPresence: provider.clientPresence || "",
    clientLatestAt: provider.clientLatestAt || "",
    nativeSessionId: provider.nativeSessionId || "",
    bridgeMode: provider.bridgeMode || "",
    terminalProvider: provider.terminalProvider === true,
    temporaryBlock: provider.temporaryBlock || null
  };
}

function verificationAgeMs(record = {}) {
  const observed = timestampMs(record.verifiedAt || record.generatedAt);
  return observed ? Date.now() - observed : null;
}

function uiContextProofSummary(record = {}) {
  const providers = Array.isArray(record.providers) ? record.providers.filter(Boolean) : [];
  const recalled = Array.isArray(record.recalled) ? record.recalled : [];
  const recalledProviders = recalled
    .filter((item) => item?.recalled === true && item.status === "done")
    .map((item) => item.provider)
    .filter(Boolean);
  const missingProviders = providers.filter((provider) => !recalledProviders.includes(provider));
  return {
    ok: record.ok === true && providers.length > 0 && missingProviders.length === 0,
    providers,
    recalledProviders,
    recalledCount: recalledProviders.length,
    expectedCount: providers.length,
    missingProviders,
    firstTurnId: record.firstTurnId || "",
    secondTurnId: record.secondTurnId || "",
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function mcpContractProofSummary(record = {}) {
  return {
    ok: record.ok === true
      && cleanString(record.clientId)
      && cleanString(record.messageId)
      && cleanString(record.replyMemoryId)
      && record.boardStatus === "completed"
      && Number(record.graphMatches || 0) > 0,
    clientId: cleanString(record.clientId),
    messageId: cleanString(record.messageId),
    replyMemoryId: cleanString(record.replyMemoryId),
    boardStatus: cleanString(record.boardStatus),
    graphMatches: Number(record.graphMatches || 0),
    toolCount: Number(record.toolCount || 0),
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function mcpRealtimeProofSummary(record = {}) {
  return {
    ok: record.ok === true
      && cleanString(record.provider)
      && cleanString(record.targetClient)
      && cleanString(record.messageId)
      && record.persistedStatus === "done"
      && Number(record.persistedTextChars || 0) > 0
      && record.activeTurns === 0
      && (record.sawReplyEvent === true || record.sawSnapshotReply === true),
    provider: cleanString(record.provider),
    targetClient: cleanString(record.targetClient),
    turnId: cleanString(record.turnId),
    messageId: cleanString(record.messageId),
    persistedStatus: cleanString(record.persistedStatus),
    persistedTextChars: Number(record.persistedTextChars || 0),
    sawReplyEvent: record.sawReplyEvent === true,
    sawSnapshotReply: record.sawSnapshotReply === true,
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function mcpCancelProofSummary(record = {}) {
  const persistedCanceledStatus = ["completed_with_errors", "interrupted"].includes(cleanString(record.persistedStatus));
  return {
    ok: record.ok === true
      && cleanString(record.provider)
      && cleanString(record.messageId)
      && record.inboxStatus === "canceled"
      && cleanString(record.canceledBy)
      && persistedCanceledStatus
      && record.persistedProviderStatus === "error"
      && record.activeTurns === 0,
    provider: cleanString(record.provider),
    turnId: cleanString(record.turnId),
    messageId: cleanString(record.messageId),
    inboxStatus: cleanString(record.inboxStatus),
    canceledBy: cleanString(record.canceledBy),
    cancelReason: cleanString(record.cancelReason),
    persistedStatus: cleanString(record.persistedStatus),
    persistedProviderStatus: cleanString(record.persistedProviderStatus),
    activeTurns: Number(record.activeTurns || 0),
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function uiStopProofSummary(record = {}) {
  return {
    ok: record.ok === true
      && cleanString(record.provider)
      && cleanString(record.turnId)
      && cleanString(record.messageId)
      && record.inboxStatus === "canceled"
      && cleanString(record.canceledBy)
      && record.activeTurns === 0,
    provider: cleanString(record.provider),
    turnId: cleanString(record.turnId),
    messageId: cleanString(record.messageId),
    inboxStatus: cleanString(record.inboxStatus),
    canceledBy: cleanString(record.canceledBy),
    cancelReason: cleanString(record.cancelReason),
    activeTurns: Number(record.activeTurns || 0),
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function uiSendProofSummary(record = {}) {
  const providers = Array.isArray(record.providers) ? record.providers.filter(Boolean) : [];
  const persisted = Array.isArray(record.persisted) ? record.persisted : [];
  const persistedByProvider = new Map(persisted.map((item) => [cleanString(item.provider), item]));
  const missingProviders = providers.filter((provider) => !persistedByProvider.has(provider));
  const incompleteProviders = providers.filter((provider) => {
    const item = persistedByProvider.get(provider) || {};
    return item.status !== "done"
      || !cleanString(item.text)
      || Number(item.streamedChars || 0) <= 0
      || Number(item.deltaCount || 0) <= 0;
  });
  return {
    ok: record.ok === true
      && cleanString(record.turnId)
      && providers.length > 0
      && missingProviders.length === 0
      && incompleteProviders.length === 0
      && record.activeTurns === 0
      && record.rendered?.ok === true,
    turnId: cleanString(record.turnId),
    providers,
    missingProviders,
    incompleteProviders,
    activeTurns: Number(record.activeTurns || 0),
    rendered: record.rendered?.ok === true,
    persisted: persisted.map((item) => ({
      provider: cleanString(item.provider),
      status: cleanString(item.status),
      textChars: cleanString(item.text).length,
      firstDeltaMs: item.firstDeltaMs ?? null,
      deltaCount: Number(item.deltaCount || 0),
      streamedChars: Number(item.streamedChars || 0),
      durationMs: item.durationMs ?? null
    })),
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function liveRoomProofSummary(record = {}) {
  const providers = Array.isArray(record.providers) ? record.providers.filter(Boolean) : [];
  const persisted = Array.isArray(record.persisted) ? record.persisted : [];
  const persistedByProvider = new Map(persisted.map((item) => [cleanString(item.provider), item]));
  const missingProviders = providers.filter((provider) => !persistedByProvider.has(provider));
  const incompleteProviders = providers.filter((provider) => {
    const item = persistedByProvider.get(provider) || {};
    return item.status !== "done"
      || Number(item.streamedChars || 0) <= 0
      || Number(item.deltaCount || 0) <= 0;
  });
  return {
    ok: record.ok === true
      && cleanString(record.turnId)
      && providers.length >= 2
      && missingProviders.length === 0
      && incompleteProviders.length === 0
      && record.activeTurns === 0,
    turnId: cleanString(record.turnId),
    providers,
    providerCount: providers.length,
    missingProviders,
    incompleteProviders,
    activeTurns: Number(record.activeTurns || 0),
    persisted: persisted.map((item) => ({
      provider: cleanString(item.provider),
      status: cleanString(item.status),
      firstDeltaMs: item.firstDeltaMs ?? null,
      deltaCount: Number(item.deltaCount || 0),
      streamedChars: Number(item.streamedChars || 0),
      durationMs: item.durationMs ?? null
    })),
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function realChatProofSummary(record = {}) {
  const providers = Array.isArray(record.providers) ? record.providers.filter(Boolean) : [];
  const responses = Array.isArray(record.responses) ? record.responses : [];
  const persisted = Array.isArray(record.persisted) ? record.persisted : [];
  const marker = cleanString(record.marker);
  const minChars = Math.max(1, Number(record.minChars || 80));
  const responsesByProvider = new Map(responses.map((item) => [cleanString(item.provider), item]));
  const persistedByProvider = new Map(persisted.map((item) => [cleanString(item.provider), item]));
  const missingProviders = providers.filter((provider) => !responsesByProvider.has(provider) || !persistedByProvider.has(provider));
  const incompleteProviders = providers.filter((provider) => {
    const response = responsesByProvider.get(provider) || {};
    const persistedResponse = persistedByProvider.get(provider) || {};
    const text = cleanString(response.text || persistedResponse.text);
    return persistedResponse.status !== "done"
      || text.length < minChars
      || (marker && !text.includes(marker))
      || Number(persistedResponse.deltaCount || 0) <= 0
      || Number(persistedResponse.streamedChars || 0) < minChars;
  });
  return {
    ok: record.ok === true
      && cleanString(record.turnId)
      && cleanString(record.marker)
      && providers.length >= 2
      && missingProviders.length === 0
      && incompleteProviders.length === 0
      && record.activeTurns === 0
      && cleanString(record.truthMode) === "observed-substantial-websocket-model-replies-persisted",
    turnId: cleanString(record.turnId),
    marker,
    minChars,
    providers,
    providerCount: providers.length,
    missingProviders,
    incompleteProviders,
    activeTurns: Number(record.activeTurns || 0),
    responses: responses.map((item) => ({
      provider: cleanString(item.provider),
      chars: cleanString(item.text).length
    })),
    persisted: persisted.map((item) => ({
      provider: cleanString(item.provider),
      status: cleanString(item.status),
      textChars: cleanString(item.text).length,
      firstDeltaMs: item.firstDeltaMs ?? null,
      deltaCount: Number(item.deltaCount || 0),
      streamedChars: Number(item.streamedChars || 0),
      durationMs: item.durationMs ?? null
    })),
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: cleanString(record.truthMode)
  };
}

function mcpStdioProofSummary(record = {}) {
  return {
    ok: record.ok === true
      && cleanString(record.clientId)
      && cleanString(record.messageId)
      && cleanString(record.replyMemoryId)
      && Number(record.graphMatches || 0) > 0
      && Number(record.aliasToolCount || 0) > 0,
    clientId: cleanString(record.clientId),
    messageId: cleanString(record.messageId),
    replyMemoryId: cleanString(record.replyMemoryId),
    graphMatches: Number(record.graphMatches || 0),
    toolCount: Number(record.toolCount || 0),
    aliasToolCount: Number(record.aliasToolCount || 0),
    bridgePath: cleanString(record.bridgePath),
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function mcpClientKitProofSummary(record = {}) {
  const stdioClients = Array.isArray(record.stdioClients) ? record.stdioClients : [];
  const httpClients = Array.isArray(record.httpClients) ? record.httpClients : [];
  const subscriptionSetupFiles = Array.isArray(record.subscriptionSetupFiles) ? record.subscriptionSetupFiles : [];
  return {
    ok: record.ok === true
      && cleanString(record.kitDir)
      && cleanString(record.bridgePath)
      && Number(record.fileCount || 0) >= 13
      && stdioClients.includes("claude-desktop")
      && stdioClients.includes("cursor")
      && stdioClients.includes("kimi")
      && httpClients.includes("chatgpt")
      && httpClients.includes("grok")
      && subscriptionSetupFiles.includes("claude_desktop_subscription_setup.txt")
      && subscriptionSetupFiles.includes("chatgpt_subscription_setup.txt")
      && subscriptionSetupFiles.includes("grok_subscription_setup.txt"),
    kitDir: cleanString(record.kitDir),
    bridgePath: cleanString(record.bridgePath),
    fileCount: Number(record.fileCount || 0),
    stdioClients,
    httpClients,
    subscriptionSetupFiles,
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function mcpClientInstallProofSummary(record = {}) {
  const configuredTargets = Array.isArray(record.configuredTargets) ? record.configuredTargets : [];
  return {
    ok: record.ok === true
      && cleanString(record.installDir)
      && cleanString(record.launcher)
      && Number(record.copiedCount || 0) >= 7
      && configuredTargets.length > 0,
    installDir: cleanString(record.installDir),
    launcher: cleanString(record.launcher),
    copiedCount: Number(record.copiedCount || 0),
    configuredTargets,
    heartbeatFixtureClientId: cleanString(record.heartbeatFixtureClientId),
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function subscriptionDrillCliProofSummary(record = {}) {
  const outcome = cleanString(record.outcome);
  const ok = cleanString(record.schema) === "beagle.workbench-subscription-drill-cli.v1"
    && cleanString(record.messageId)
    && cleanString(record.marker)
    && record.setupTextPresent === true
    && record.activationPromptPresent === true
    && (
      (outcome === "reply-proven" && record.ok === true)
      || (outcome === "timeout" && record.canceled === true)
      || (outcome === "canceled" && record.canceled === true)
    );
  return {
    ok,
    realReplyObserved: outcome === "reply-proven" && record.ok === true,
    outcome,
    client: record.client || null,
    marker: cleanString(record.marker),
    messageId: cleanString(record.messageId),
    setupTextPresent: record.setupTextPresent === true,
    activationPromptPresent: record.activationPromptPresent === true,
    canceled: record.canceled === true,
    status: record.status || null,
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: cleanString(record.truthMode)
  };
}

function httpMcpAuthProofSummary(record = {}) {
  return {
    ok: record.ok === true
      && Number(record.noAuthStatus || 0) === 401
      && Number(record.wrongAuthStatus || 0) === 401
      && Number(record.authorizedStatus || 0) === 200
      && record.authRequired === true
      && record.tokenConfigured === true,
    tokenFile: cleanString(record.tokenFile),
    noAuthStatus: Number(record.noAuthStatus || 0),
    wrongAuthStatus: Number(record.wrongAuthStatus || 0),
    authorizedStatus: Number(record.authorizedStatus || 0),
    authRequired: record.authRequired === true,
    tokenConfigured: record.tokenConfigured === true,
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function remoteMcpTransportProofSummary(record = {}) {
  const checks = record.checks && typeof record.checks === "object" ? record.checks : {};
  const transports = Array.isArray(record.transports) ? record.transports : [];
  return {
    ok: record.ok === true
      && checks.diagnostics === true
      && checks.sseListen === true
      && checks.sseHeartbeat === true
      && checks.sseSessionRegistry === true
      && checks.jsonInitialize === true
      && checks.sseInitialize === true
      && checks.legacyAlias === true
      && checks.notificationAccepted === true
      && transports.includes("streamable-http")
      && transports.includes("sse-listen"),
    endpoint: cleanString(record.endpoint),
    protocolVersion: cleanString(record.protocolVersion),
    transports,
    checks,
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function fullProofSummary(record = {}) {
  const steps = Array.isArray(record.steps) ? record.steps : [];
  const completedSteps = steps
    .map((step) => cleanString(step?.name))
    .filter(Boolean);
  const requiredSteps = [
    "subscription setup",
    "subscription client doctor",
    "subscription client bringup",
    "subscription connect plan",
    "subscription live drill",
    "subscription drill CLI",
    "subscription probe guard",
    "public endpoint doctor",
    "public endpoint candidates",
    "Tailscale Funnel guard",
    "Tailscale Funnel path guard",
    "Kimi bridge guard",
    "HTTP MCP auth",
    "remote MCP transport",
    "MCP client kit generate",
    "MCP client kit install",
    "MCP client install",
    "MCP client kit",
    "MCP contract",
    "MCP stdio",
    "MCP realtime",
    "UI send real chat",
    "substantial real chat",
    "UI context across live providers",
    "turn evidence",
    "local live room",
    "UI MCP cancel",
    "UI subscription reply drill",
    "desktop CLI provider",
    "UI stop",
    "health"
  ];
  const missingSteps = requiredSteps.filter((step) => !completedSteps.includes(step));
  const providers = Array.isArray(record.providers) ? record.providers.filter(Boolean) : [];
  return {
    ok: record.ok === true && missingSteps.length === 0 && providers.length > 0,
    providers,
    stepCount: completedSteps.length,
    completedSteps,
    missingSteps,
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs: verificationAgeMs(record),
    truthMode: record.truthMode || ""
  };
}

function subscriptionReplyProofSummary(record = {}) {
  const ageMs = verificationAgeMs(record);
  const ok = record.ok === true
    && cleanString(record.messageId)
    && cleanString(record.replyMemoryId)
    && cleanString(record.targetClient)
    && cleanString(record.replyClientId)
    && cleanString(record.replyTruthMode) === "observed-client-reply"
    && cleanString(record.truthMode) === "observed-real-subscription-client-reply";
  return {
    ok,
    fresh: ok && Number(ageMs) >= 0 && Number(ageMs) <= SUBSCRIPTION_REPLY_PROOF_RECENT_MS,
    provider: cleanString(record.provider),
    targetClient: cleanString(record.targetClient),
    messageId: cleanString(record.messageId),
    turnId: cleanString(record.turnId),
    replyMemoryId: cleanString(record.replyMemoryId),
    replyClientId: cleanString(record.replyClientId),
    replySource: cleanString(record.replySource),
    replyTruthMode: cleanString(record.replyTruthMode),
    expectedText: cleanString(record.expectedText),
    persistedStatus: cleanString(record.persistedStatus),
    persistedTextChars: Number(record.persistedTextChars || 0),
    eventCount: Number(record.eventCount || 0),
    verifiedAt: record.verifiedAt || record.generatedAt || "",
    ageMs,
    truthMode: cleanString(record.truthMode)
  };
}

function latestSubscriptionReplyProofForClient(records = [], client = {}) {
  const ids = new Set([client.targetClient, client.id, client.provider].map(normalizedId).filter(Boolean));
  const aliases = new Set([client.targetClient, client.id, client.provider, ...(client.aliases || [])].map(normalizedId).filter(Boolean));
  const match = records.find((record) => {
    const targetClient = normalizedId(record.targetClient);
    const provider = normalizedId(record.provider || record.targetProvider);
    const replyClient = normalizedId(record.replyClientId || record.replySource);
    return ids.has(targetClient) || aliases.has(replyClient) || aliases.has(provider);
  });
  return subscriptionReplyProofSummary(match || {});
}

async function buildMultimodelReadiness(slug) {
  const providers = await attachProviderProofs(slug, await detectProviders(slug));
  const fullVerifications = await readVerificationRecords(slug, { limit: 1, kind: "full" });
  const realtimeVerifications = await readVerificationRecords(slug, { limit: 1, kind: "realtime" });
  const conversationVerifications = await readVerificationRecords(slug, { limit: 1, kind: "conversation" });
  const realChatVerifications = await readVerificationRecords(slug, { limit: 1, kind: "real-chat" });
  const liveRoomVerifications = await readVerificationRecords(slug, { limit: 1, kind: "live-room" });
  const uiSendVerifications = await readVerificationRecords(slug, { limit: 1, kind: "ui-send" });
  const uiContextVerifications = await readVerificationRecords(slug, { limit: 1, kind: "ui-context" });
  const mcpContractVerifications = await readVerificationRecords(slug, { limit: 1, kind: "mcp-contract" });
  const mcpRealtimeVerifications = await readVerificationRecords(slug, { limit: 1, kind: "mcp-realtime" });
  const mcpCancelVerifications = await readVerificationRecords(slug, { limit: 1, kind: "ui-mcp-cancel" });
  const uiStopVerifications = await readVerificationRecords(slug, { limit: 1, kind: "ui-stop" });
  const mcpStdioVerifications = await readVerificationRecords(slug, { limit: 1, kind: "mcp-stdio" });
  const httpMcpAuthVerifications = await readVerificationRecords(slug, { limit: 1, kind: "http-mcp-auth" });
  const remoteMcpTransportVerifications = await readVerificationRecords(slug, { limit: 1, kind: "remote-mcp-transport" });
  const mcpClientKitVerifications = await readVerificationRecords(slug, { limit: 1, kind: "mcp-client-kit" });
  const mcpClientInstallVerifications = await readVerificationRecords(slug, { limit: 1, kind: "mcp-client-install" });
  const subscriptionDrillCliVerifications = await readVerificationRecords(slug, { limit: 1, kind: "subscription-drill-cli" });
  const subscriptionReplyVerifications = await readVerificationRecords(slug, { limit: 12, kind: "subscription-reply-live" });
  const reconnectVerifications = await readVerificationRecords(slug, { limit: 1, kind: "reconnect" });
  const providerRecords = providers.map((provider) => providerReadinessRecord(provider, slug));
  const liveNow = providerRecords.filter((provider) => ["live-now", "cross-project-live"].includes(provider.state));
  const handoffStale = providerRecords.filter((provider) => provider.state === "handoff-stale");
  const blocked = providerRecords.filter((provider) => ["blocked", "cross-project-blocked"].includes(provider.state));
  const latestUiContextVerification = uiContextVerifications[0] || null;
  const latestRealChatVerification = realChatVerifications[0] || null;
  const latestLiveRoomVerification = liveRoomVerifications[0] || null;
  const latestUiSendVerification = uiSendVerifications[0] || null;
  const latestMcpContractVerification = mcpContractVerifications[0] || null;
  const latestMcpRealtimeVerification = mcpRealtimeVerifications[0] || null;
  const latestMcpCancelVerification = mcpCancelVerifications[0] || null;
  const latestUiStopVerification = uiStopVerifications[0] || null;
  const latestMcpStdioVerification = mcpStdioVerifications[0] || null;
  const latestHttpMcpAuthVerification = httpMcpAuthVerifications[0] || null;
  const latestRemoteMcpTransportVerification = remoteMcpTransportVerifications[0] || null;
  const latestMcpClientKitVerification = mcpClientKitVerifications[0] || null;
  const latestMcpClientInstallVerification = mcpClientInstallVerifications[0] || null;
  const latestSubscriptionDrillCliVerification = subscriptionDrillCliVerifications[0] || null;
  const latestSubscriptionReplyVerification = subscriptionReplyVerifications[0] || null;
  const latestFullVerification = fullVerifications[0] || null;
  return {
    schema: "beagle.multimodel-readiness.v1",
    projectSlug: slug,
    providers: providerRecords,
    summary: {
      total: providerRecords.length,
      liveNow: liveNow.length,
      handoffStale: handoffStale.length,
      blocked: blocked.length,
      defaultProviders: defaultProviderIds(providers),
      activeTurns: activeTurnRecords(slug).length
    },
    liveNow: liveNow.map((provider) => provider.id),
    handoffStale: handoffStale.map((provider) => provider.id),
    blocked: blocked.map((provider) => provider.id),
    latestRealtimeVerification: realtimeVerifications[0] || null,
    latestConversationVerification: conversationVerifications[0] || null,
    latestRealChatVerification,
    realChatProof: realChatProofSummary(latestRealChatVerification || {}),
    latestLiveRoomVerification,
    liveRoomProof: liveRoomProofSummary(latestLiveRoomVerification || {}),
    latestUiSendVerification,
    uiSendProof: uiSendProofSummary(latestUiSendVerification || {}),
    latestFullVerification,
    fullProof: fullProofSummary(latestFullVerification || {}),
    latestUiContextVerification,
    contextProof: uiContextProofSummary(latestUiContextVerification || {}),
    latestMcpContractVerification,
    mcpContractProof: mcpContractProofSummary(latestMcpContractVerification || {}),
    latestMcpRealtimeVerification,
    mcpRealtimeProof: mcpRealtimeProofSummary(latestMcpRealtimeVerification || {}),
    latestMcpCancelVerification,
    mcpCancelProof: mcpCancelProofSummary(latestMcpCancelVerification || {}),
    latestUiStopVerification,
    uiStopProof: uiStopProofSummary(latestUiStopVerification || {}),
    latestMcpStdioVerification,
    mcpStdioProof: mcpStdioProofSummary(latestMcpStdioVerification || {}),
    latestHttpMcpAuthVerification,
    httpMcpAuthProof: httpMcpAuthProofSummary(latestHttpMcpAuthVerification || {}),
    latestRemoteMcpTransportVerification,
    remoteMcpTransportProof: remoteMcpTransportProofSummary(latestRemoteMcpTransportVerification || {}),
    latestMcpClientKitVerification,
    mcpClientKitProof: mcpClientKitProofSummary(latestMcpClientKitVerification || {}),
    latestMcpClientInstallVerification,
    mcpClientInstallProof: mcpClientInstallProofSummary(latestMcpClientInstallVerification || {}),
    latestSubscriptionDrillCliVerification,
    subscriptionDrillCliProof: subscriptionDrillCliProofSummary(latestSubscriptionDrillCliVerification || {}),
    latestSubscriptionReplyVerification,
    subscriptionReplyProof: subscriptionReplyProofSummary(latestSubscriptionReplyVerification || {}),
    subscriptionReplyProofs: subscriptionReplyVerifications.map((record) => subscriptionReplyProofSummary(record)),
    latestReconnectVerification: reconnectVerifications[0] || null,
    generatedAt: new Date().toISOString(),
    truthMode: "observed-runtime-and-persisted-verifications"
  };
}

async function buildMultimodelHealth(slug, { minLiveNow = 3, maxContextAgeMs = 30 * 60 * 1000 } = {}) {
  const readiness = await buildMultimodelReadiness(slug);
  const liveNow = readiness.liveNow || [];
  const contextProof = readiness.contextProof || {};
  const mcpContractProof = readiness.mcpContractProof || {};
  const mcpRealtimeProof = readiness.mcpRealtimeProof || {};
  const mcpCancelProof = readiness.mcpCancelProof || {};
  const realChatProof = readiness.realChatProof || {};
  const liveRoomProof = readiness.liveRoomProof || {};
  const uiSendProof = readiness.uiSendProof || {};
  const uiStopProof = readiness.uiStopProof || {};
  const mcpStdioProof = readiness.mcpStdioProof || {};
  const httpMcpAuthProof = readiness.httpMcpAuthProof || {};
  const remoteMcpTransportProof = readiness.remoteMcpTransportProof || {};
  const mcpClientKitProof = readiness.mcpClientKitProof || {};
  const mcpClientInstallProof = readiness.mcpClientInstallProof || {};
  const subscriptionDrillCliProof = readiness.subscriptionDrillCliProof || {};
  const fullProof = readiness.fullProof || {};
  const contextFresh = contextProof.ok === true
    && Number(contextProof.ageMs) >= 0
    && Number(contextProof.ageMs) <= maxContextAgeMs;
  const mcpContractFresh = mcpContractProof.ok === true
    && Number(mcpContractProof.ageMs) >= 0
    && Number(mcpContractProof.ageMs) <= maxContextAgeMs;
  const mcpRealtimeFresh = mcpRealtimeProof.ok === true
    && Number(mcpRealtimeProof.ageMs) >= 0
    && Number(mcpRealtimeProof.ageMs) <= maxContextAgeMs;
  const realChatFresh = realChatProof.ok === true
    && Number(realChatProof.ageMs) >= 0
    && Number(realChatProof.ageMs) <= maxContextAgeMs;
  const liveRoomFresh = liveRoomProof.ok === true
    && Number(liveRoomProof.ageMs) >= 0
    && Number(liveRoomProof.ageMs) <= maxContextAgeMs;
  const mcpCancelFresh = mcpCancelProof.ok === true
    && Number(mcpCancelProof.ageMs) >= 0
    && Number(mcpCancelProof.ageMs) <= maxContextAgeMs;
  const uiSendFresh = uiSendProof.ok === true
    && Number(uiSendProof.ageMs) >= 0
    && Number(uiSendProof.ageMs) <= maxContextAgeMs;
  const uiStopFresh = uiStopProof.ok === true
    && Number(uiStopProof.ageMs) >= 0
    && Number(uiStopProof.ageMs) <= maxContextAgeMs;
  const mcpStdioFresh = mcpStdioProof.ok === true
    && Number(mcpStdioProof.ageMs) >= 0
    && Number(mcpStdioProof.ageMs) <= maxContextAgeMs;
  const httpMcpAuthFresh = httpMcpAuthProof.ok === true
    && Number(httpMcpAuthProof.ageMs) >= 0
    && Number(httpMcpAuthProof.ageMs) <= maxContextAgeMs;
  const remoteMcpTransportFresh = remoteMcpTransportProof.ok === true
    && Number(remoteMcpTransportProof.ageMs) >= 0
    && Number(remoteMcpTransportProof.ageMs) <= maxContextAgeMs;
  const mcpClientKitFresh = mcpClientKitProof.ok === true
    && Number(mcpClientKitProof.ageMs) >= 0
    && Number(mcpClientKitProof.ageMs) <= maxContextAgeMs;
  const mcpClientInstallFresh = mcpClientInstallProof.ok === true
    && Number(mcpClientInstallProof.ageMs) >= 0
    && Number(mcpClientInstallProof.ageMs) <= maxContextAgeMs;
  const subscriptionDrillCliFresh = subscriptionDrillCliProof.ok === true
    && Number(subscriptionDrillCliProof.ageMs) >= 0
    && Number(subscriptionDrillCliProof.ageMs) <= maxContextAgeMs;
  const requiredContextProviders = (readiness.summary?.defaultProviders || [])
    .filter((provider) => liveNow.includes(provider));
  const liveContextProviders = requiredContextProviders.filter((provider) => (contextProof.recalledProviders || []).includes(provider));
  const checks = {
    activeTurnsClear: Number(readiness.summary?.activeTurns || 0) === 0,
    minimumLiveNow: liveNow.length >= Math.max(1, Number(minLiveNow) || 3),
    contextProofFresh: contextFresh,
    contextCoversLiveNow: liveContextProviders.length === requiredContextProviders.length && requiredContextProviders.length > 0,
    subscriptionClientsSeparated: Array.isArray(readiness.handoffStale),
    mcpContractFresh,
    mcpRealtimeFresh,
    realChatFresh,
    liveRoomFresh,
    mcpCancelFresh,
    uiSendFresh,
    uiStopFresh,
    mcpStdioFresh,
    httpMcpAuthFresh,
    remoteMcpTransportFresh,
    mcpClientKitFresh,
    mcpClientInstallFresh,
    subscriptionDrillCliFresh
  };
  const ok = Object.values(checks).every(Boolean);
  return {
    schema: "beagle.multimodel-health.v1",
    projectSlug: slug,
    ok,
    checks,
    liveNow,
    requiredContextProviders,
    liveContextProviders,
    missingLiveContextProviders: requiredContextProviders.filter((provider) => !liveContextProviders.includes(provider)),
    handoffStale: readiness.handoffStale || [],
    blocked: readiness.blocked || [],
    contextProof,
    mcpContractProof,
    mcpRealtimeProof,
    realChatProof,
    liveRoomProof,
    mcpCancelProof,
    uiSendProof,
    uiStopProof,
    mcpStdioProof,
    httpMcpAuthProof,
    remoteMcpTransportProof,
    mcpClientKitProof,
    mcpClientInstallProof,
    subscriptionDrillCliProof,
    fullProof,
    summary: readiness.summary,
    generatedAt: new Date().toISOString(),
    truthMode: "observed-runtime-and-persisted-verifications"
  };
}

function defaultProviderIds(providers = []) {
  const available = new Set(providers
    .filter((provider) => provider.status === "available")
    .map((provider) => provider.id));
  return DEFAULT_PROVIDER_PRIORITY.filter((providerId) => available.has(providerId));
}

function envRequirement(name, { secret = false, value = process.env[name] } = {}) {
  const set = Boolean(cleanString(value));
  return {
    name,
    set,
    secret,
    value: set && !secret ? cleanString(value) : ""
  };
}

function missingEnv(requirements = []) {
  return requirements.filter((item) => !item.set).map((item) => item.name);
}

function clientKitDir(slug) {
  return path.join(DATA_DIR, "mcp-client-kit", safeSlug(slug));
}

function publicEndpointConfigFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.public-endpoint.json`);
}

function clientKitFiles(slug) {
  const dir = clientKitDir(slug);
  return [
    "README.md",
    "claude_desktop_config.json",
    "cursor_mcp.json",
    "kimi_mcp.json",
    "generic_stdio_mcp.json",
    "http_mcp.json",
    "http_mcp.redacted.json",
    "hosted_subscription_connection.json",
    "hosted_subscription_connection.redacted.json",
    "connection-pack.json",
    "claude_desktop_subscription_setup.txt",
    "chatgpt_subscription_setup.txt",
    "grok_subscription_setup.txt"
  ].map((name) => ({ name, path: path.join(dir, name) }));
}

function installedMcpDir(slug) {
  return path.join(process.env.HOME || "/home/devsounio", ".config", "beagle-workbench", "mcp", safeSlug(slug));
}

async function fileExists(file) {
  try {
    await access(file);
    return true;
  } catch {
    return false;
  }
}

async function fileContains(file, needle) {
  try {
    const raw = await readFile(file, "utf8");
    return raw.includes(needle);
  } catch {
    return false;
  }
}

async function readPublicEndpointConfig(slug) {
  try {
    return JSON.parse(await readFile(publicEndpointConfigFile(slug), "utf8"));
  } catch {
    return {};
  }
}

async function readJsonIfPresent(file) {
  try {
    return JSON.parse(await readFile(file, "utf8"));
  } catch {
    return null;
  }
}

async function writePublicEndpointConfig(slug, config = {}) {
  const file = publicEndpointConfigFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  const record = {
    schema: "beagle.multimodel-public-endpoint-config.v1",
    projectSlug: slug,
    publicBase: cleanString(config.publicBase),
    trustedHosted: Boolean(config.trustedHosted),
    note: cleanString(config.note).slice(0, 1000),
    updatedAt: new Date().toISOString(),
    truthMode: "operator-declared-public-endpoint"
  };
  await writeFile(file, `${JSON.stringify(record, null, 2)}\n`, "utf8");
  return record;
}

function publicEndpointStatus(value, { trustedHosted = false, source = "" } = {}) {
  const url = cleanString(value || process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL || COCKPIT_LOOPBACK);
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();
    const loopback = ["127.0.0.1", "::1", "localhost", "0.0.0.0"].includes(host);
    const privateLan = /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[0-1])\.)/.test(host);
    const tailnet = host.endsWith(".ts.net");
    const https = parsed.protocol === "https:";
    const envTrustedHosted = /^(1|true|yes)$/i.test(cleanString(process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL_HOSTED_REACHABLE || ""));
    const trustedHostedValue = Boolean(trustedHosted || envTrustedHosted);
    const hostedClientReachable = https && !loopback && !privateLan && (!tailnet || trustedHostedValue);
    return {
      url: parsed.toString().replace(/\/$/, ""),
      protocol: parsed.protocol.replace(":", ""),
      host,
      loopback,
      privateLan,
      tailnet,
      https,
      trustedHosted: trustedHostedValue,
      hostedClientReachable,
      source: source || (value ? "explicit" : process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL ? "env" : "loopback-default"),
      reason: hostedClientReachable
        ? "public HTTPS endpoint can be registered by hosted subscription clients"
        : tailnet
          ? "tailnet HTTPS is usable by local tailnet clients, but hosted ChatGPT/Grok need public Funnel or another internet-reachable HTTPS endpoint"
          : "hosted subscription clients cannot reach a loopback/private/non-HTTPS MCP endpoint"
    };
  } catch {
    return {
      url,
      protocol: "",
      host: "",
      loopback: false,
      privateLan: false,
      tailnet: false,
      https: false,
      trustedHosted: false,
      hostedClientReachable: false,
      source: source || "invalid",
      reason: "invalid public base URL"
    };
  }
}

async function resolvePublicEndpointStatus(slug, { publicBase = "" } = {}) {
  const explicit = cleanString(publicBase);
  const config = await readPublicEndpointConfig(slug);
  const configuredBase = cleanString(config.publicBase);
  const envBase = cleanString(process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL);
  const selectedBase = explicit || envBase || configuredBase || COCKPIT_LOOPBACK;
  const selectedSource = explicit
    ? "query"
    : envBase
      ? "env"
      : configuredBase
        ? "project-config"
        : "loopback-default";
  const configApplies = configuredBase && selectedBase.replace(/\/$/, "") === configuredBase.replace(/\/$/, "");
  const status = publicEndpointStatus(selectedBase, {
    trustedHosted: configApplies && config.trustedHosted === true,
    source: selectedSource
  });
  return {
    ...status,
    configured: Boolean(configuredBase),
    config: {
      publicBase: configuredBase,
      trustedHosted: config.trustedHosted === true,
      note: cleanString(config.note),
      updatedAt: cleanString(config.updatedAt)
    }
  };
}

function parseJsonQuietly(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function commandAvailableResult(command, result = {}) {
  return {
    command,
    available: result.code === 0 && Boolean(cleanString(result.stdout)),
    path: cleanString(result.stdout).split(/\s+/)[0] || "",
    stderr: cleanString(result.stderr)
  };
}

function serveTargetMatchesCockpit(target = "") {
  const text = cleanString(target).toLowerCase();
  const loopbackUrl = cleanString(COCKPIT_LOOPBACK).toLowerCase().replace(/\/$/, "");
  if (!text) return false;
  if (loopbackUrl && text.replace(/\/$/, "") === loopbackUrl) return true;
  return /(^|\/\/)(127\.0\.0\.1|localhost):4370(\/|$)/.test(text);
}

function flattenTailscaleServeRoutes(serveStatus = {}) {
  const routes = [];
  const web = serveStatus && typeof serveStatus === "object" ? serveStatus.Web || {} : {};
  for (const [hostPort, hostConfig] of Object.entries(web)) {
    const handlers = hostConfig?.Handlers || {};
    for (const [pathName, handler] of Object.entries(handlers)) {
      const target = cleanString(handler?.Proxy || handler?.ReverseProxy || handler?.Text || "");
      routes.push({
        hostPort,
        path: pathName,
        target,
        matchesCockpit: serveTargetMatchesCockpit(target)
      });
    }
  }
  const tcp = serveStatus && typeof serveStatus === "object" ? serveStatus.TCP || {} : {};
  for (const [port, tcpConfig] of Object.entries(tcp)) {
    const target = cleanString(tcpConfig?.TCPForward || "");
    if (!target) continue;
    routes.push({
      hostPort: `tcp:${port}`,
      path: "",
      target,
      matchesCockpit: serveTargetMatchesCockpit(target)
    });
  }
  return routes;
}

function httpMcpAuthRequiredForPublic() {
  return /^(1|true|yes)$/i.test(cleanString(
    process.env.WORKBENCH_CONTEXT_HTTP_MCP_REQUIRE_AUTH ||
      process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_REQUIRE_AUTH ||
      ""
  ));
}

async function buildPublicEndpointCandidates(slug) {
  const configured = await resolvePublicEndpointStatus(slug);
  const candidates = [
    {
      id: "loopback",
      label: "Local backend",
      url: COCKPIT_LOOPBACK,
      status: "blocked",
      hostedClientReachable: false,
      blockers: ["loopback is only reachable from this machine"],
      mutates: false
    }
  ];

  const tailscaleWhich = await runCommandCapture("bash", ["-lc", "command -v tailscale"], { timeoutMs: 3000 });
  const tailscaleCommand = commandAvailableResult("tailscale", tailscaleWhich);

  let tailscaleStatus = null;
  let tailscaleServe = null;
  let tailscaleFunnel = null;
  let serveRoutes = [];
  if (tailscaleCommand.available) {
    const statusResult = await runCommandCapture("tailscale", ["status", "--json"], { timeoutMs: 8000 });
    tailscaleStatus = {
      ok: statusResult.code === 0,
      stderr: cleanString(statusResult.stderr),
      data: statusResult.code === 0 ? parseJsonQuietly(statusResult.stdout) : null
    };
    const self = tailscaleStatus.data?.Self || {};
    const dnsName = cleanString(self.DNSName).replace(/\.$/, "");
    if (dnsName) {
      const url = `https://${dnsName}`;
      const trustedMatch = configured.url === url && configured.trustedHosted === true;
      candidates.push({
        id: "tailscale-dns",
        label: "Tailscale HTTPS",
        url,
        status: trustedMatch ? "ready" : "waiting",
        hostedClientReachable: trustedMatch,
        tailnet: true,
        trustedHosted: trustedMatch,
        blockers: trustedMatch
          ? []
          : ["tailnet HTTPS needs Funnel or an operator-trusted public tunnel for hosted ChatGPT/Grok"],
        mutates: false
      });
    }

    const serveResult = await runCommandCapture("tailscale", ["serve", "status", "--json"], { timeoutMs: 8000 });
    tailscaleServe = {
      ok: serveResult.code === 0,
      stderr: cleanString(serveResult.stderr),
      data: serveResult.code === 0 ? parseJsonQuietly(serveResult.stdout) : null
    };
    serveRoutes = flattenTailscaleServeRoutes(tailscaleServe.data || {});
    if (serveRoutes.length) {
      const cockpitRoutes = serveRoutes.filter((route) => route.matchesCockpit);
      candidates.push({
        id: "tailscale-serve-current",
        label: "Current Tailscale serve",
        url: serveRoutes.find((route) => route.hostPort.includes(":443"))?.hostPort || serveRoutes[0]?.hostPort || "",
        status: cockpitRoutes.length ? "waiting" : "blocked",
        hostedClientReachable: false,
        routes: serveRoutes,
        blockers: cockpitRoutes.length
          ? ["serve reaches Project Cockpit on the tailnet; hosted clients still need Funnel/public reachability"]
          : ["current Tailscale serve does not route to Project Cockpit backend 4370"],
        mutates: false
      });
    }

    const funnelResult = await runCommandCapture("tailscale", ["funnel", "status", "--json"], { timeoutMs: 8000 });
    tailscaleFunnel = {
      ok: funnelResult.code === 0,
      stderr: cleanString(funnelResult.stderr),
      data: funnelResult.code === 0 ? parseJsonQuietly(funnelResult.stdout) : null
    };
  }

  const localCloudflaredPath = path.join(DATA_DIR, "tools", "cloudflared");
  const localCloudflaredAvailable = await fileExists(localCloudflaredPath);
  const cloudflaredWhich = localCloudflaredAvailable
    ? { code: 0, stdout: localCloudflaredPath, stderr: "" }
    : await runCommandCapture("bash", ["-lc", "command -v cloudflared"], { timeoutMs: 3000 });
  const cloudflaredCommand = commandAvailableResult("cloudflared", cloudflaredWhich);
  const cloudflaredState = await readJsonIfPresent(path.join(DATA_DIR, "tunnels", `${safeSlug(slug)}.cloudflared.json`));
  const cloudflaredReady = cloudflaredState?.ok === true && cleanString(cloudflaredState.publicBase);
  candidates.push({
    id: "cloudflared",
    label: "Cloudflare tunnel",
    url: cleanString(cloudflaredState?.publicBase),
    status: cloudflaredReady ? "ready" : cloudflaredCommand.available ? "waiting" : "missing",
    hostedClientReachable: Boolean(cloudflaredReady),
    blockers: cloudflaredReady
      ? []
      : cloudflaredCommand.available
      ? ["cloudflared exists, but no Project Cockpit hosted URL is recorded"]
      : ["cloudflared is not installed on this machine"],
    state: cloudflaredState || null,
    mutates: false
  });

  return {
    schema: "beagle.multimodel-public-endpoint-candidates.v1",
    projectSlug: slug,
    selected: configured,
    candidates,
    observations: {
      tailscale: {
        available: tailscaleCommand.available,
        path: tailscaleCommand.path,
        backendState: cleanString(tailscaleStatus?.data?.BackendState),
        dnsName: cleanString(tailscaleStatus?.data?.Self?.DNSName).replace(/\.$/, ""),
        ips: tailscaleStatus?.data?.Self?.TailscaleIPs || tailscaleStatus?.data?.TailscaleIPs || [],
        health: tailscaleStatus?.data?.Health || [],
        serveRoutes,
        serveOk: tailscaleServe?.ok === true,
        funnelOk: tailscaleFunnel?.ok === true,
        funnelStatus: tailscaleFunnel?.data || null,
        serveError: cleanString(tailscaleServe?.stderr),
        funnelError: cleanString(tailscaleFunnel?.stderr)
      },
      cloudflared: cloudflaredCommand
    },
    operatorCommands: [
      "Use Tailscale serve/Funnel or Cloudflare only after choosing the public route explicitly.",
      "Do not overwrite the current Tailscale serve map without checking what it already fronts."
    ],
    generatedAt: new Date().toISOString(),
    mutates: false,
    truthMode: "observed-non-mutating-public-endpoint-candidates"
  };
}

async function buildTailscaleFunnelActivationPlan(slug, { apply = false } = {}) {
  const candidateState = await buildPublicEndpointCandidates(slug);
  const tailscale = candidateState.observations?.tailscale || {};
  const dnsName = cleanString(tailscale.dnsName);
  const publicBase = dnsName ? `https://${dnsName}` : "";
  const rootRoutes = (tailscale.serveRoutes || [])
    .filter((route) => cleanString(route.hostPort).includes(":443") && cleanString(route.path || "/") === "/");
  const rootCockpitRoutes = rootRoutes.filter((route) => route.matchesCockpit);
  const rootConflictRoutes = rootRoutes.filter((route) => !route.matchesCockpit);
  const command = ["tailscale", "funnel", "--bg", "--yes", COCKPIT_LOOPBACK];
  const blockers = [];
  if (!tailscale.available) blockers.push("tailscale is not installed or not available");
  if (!dnsName) blockers.push("tailscale DNS name is not available");
  if (rootConflictRoutes.length) {
    blockers.push("Tailscale Funnel root is already routing to another service");
  }

  const safeToApply = blockers.length === 0;
  const plan = {
    schema: "beagle.multimodel-tailscale-funnel-activation.v1",
    projectSlug: slug,
    mode: "tailscale-funnel-root",
    publicBase,
    target: COCKPIT_LOOPBACK,
    command,
    safeToApply,
    applyRequested: Boolean(apply),
    applied: false,
    rootRoutes,
    rootCockpitRoutes,
    rootConflictRoutes,
    blockers,
    candidateState,
    generatedAt: new Date().toISOString(),
    mutates: false,
    truthMode: "observed-tailscale-funnel-activation-plan"
  };

  if (!apply) return plan;
  if (!safeToApply) {
    return {
      ...plan,
      ok: false,
      error: blockers.join("; ") || "not safe to apply",
      mutates: false,
      truthMode: "refused-tailscale-funnel-activation"
    };
  }

  const result = await runCommandCapture(command[0], command.slice(1), { timeoutMs: 20000 });
  if (result.code !== 0) {
    return {
      ...plan,
      ok: false,
      error: cleanString(result.stderr || result.stdout || `tailscale funnel exited ${result.code}`),
      commandResult: {
        code: result.code,
        stdout: cleanString(result.stdout),
        stderr: cleanString(result.stderr)
      },
      mutates: true,
      truthMode: "failed-tailscale-funnel-activation"
    };
  }

  const config = await writePublicEndpointConfig(slug, {
    publicBase,
    trustedHosted: true,
    note: "Tailscale Funnel activated by Project Cockpit after guard checks."
  });
  const publicEndpoint = await resolvePublicEndpointStatus(slug);
  return {
    ...plan,
    ok: true,
    applied: true,
    config,
    publicEndpoint,
    commandResult: {
      code: result.code,
      stdout: cleanString(result.stdout),
      stderr: cleanString(result.stderr)
    },
    mutates: true,
    truthMode: "observed-tailscale-funnel-activation"
  };
}

async function buildTailscaleFunnelPathPlan(slug, { apply = false, pathPrefix = "/api/workbench" } = {}) {
  const candidateState = await buildPublicEndpointCandidates(slug);
  const tailscale = candidateState.observations?.tailscale || {};
  const dnsName = cleanString(tailscale.dnsName);
  const publicBase = dnsName ? `https://${dnsName}` : "";
  const normalizedPath = cleanString(pathPrefix, "/api/workbench").startsWith("/")
    ? cleanString(pathPrefix, "/api/workbench")
    : `/${cleanString(pathPrefix, "api/workbench")}`;
  const publicMcpBase = publicBase ? `${publicBase}${normalizedPath}` : "";
  const routes = tailscale.serveRoutes || [];
  const pathRoutes = routes
    .filter((route) => cleanString(route.hostPort).includes(":443") && cleanString(route.path || "/") === normalizedPath);
  const pathCockpitRoutes = pathRoutes.filter((route) => route.matchesCockpit);
  const pathConflictRoutes = pathRoutes.filter((route) => !route.matchesCockpit);
  const rootRoutes = routes
    .filter((route) => cleanString(route.hostPort).includes(":443") && cleanString(route.path || "/") === "/");
  const command = ["tailscale", "funnel", "--bg", "--yes", "--set-path", normalizedPath, COCKPIT_LOOPBACK];
  const mutationAllowed = process.env.PROJECT_COCKPIT_ALLOW_TAILSCALE_FUNNEL_APPLY === "1";
  const authRequired = httpMcpAuthRequiredForPublic();
  const blockers = [];
  const warnings = [];
  if (!tailscale.available) blockers.push("tailscale is not installed or not available");
  if (!dnsName) blockers.push("tailscale DNS name is not available");
  if (!authRequired) blockers.push("Workbench HTTP MCP auth must be required before public Funnel activation");
  if (pathConflictRoutes.length) {
    blockers.push(`${normalizedPath} is already routing to another service`);
  }
  if (rootRoutes.some((route) => !route.matchesCockpit)) {
    warnings.push("root Funnel route is occupied; path-specific MCP should preserve it");
  }

  const alreadyActive = pathCockpitRoutes.length > 0;
  const safeToApply = blockers.length === 0;
  const plan = {
    schema: "beagle.multimodel-tailscale-funnel-path-activation.v1",
    projectSlug: slug,
    mode: "tailscale-funnel-path",
    pathPrefix: normalizedPath,
    publicBase,
    publicMcpBase,
    target: COCKPIT_LOOPBACK,
    command,
    safeToApply,
    applyAllowed: mutationAllowed,
    authRequired,
    applyRequested: Boolean(apply),
    alreadyActive,
    applied: false,
    rootRoutes,
    pathRoutes,
    pathCockpitRoutes,
    pathConflictRoutes,
    blockers,
    warnings,
    candidateState,
    generatedAt: new Date().toISOString(),
    mutates: false,
    truthMode: "observed-tailscale-funnel-path-activation-plan"
  };

  if (!apply) return plan;
  if (!safeToApply) {
    return {
      ...plan,
      ok: false,
      error: blockers.join("; ") || "not safe to apply",
      mutates: false,
      truthMode: "refused-tailscale-funnel-path-activation"
    };
  }
  if (!mutationAllowed) {
    return {
      ...plan,
      ok: false,
      error: "PROJECT_COCKPIT_ALLOW_TAILSCALE_FUNNEL_APPLY=1 is required before mutating Tailscale Funnel",
      mutates: false,
      truthMode: "refused-tailscale-funnel-path-activation"
    };
  }

  const result = await runCommandCapture(command[0], command.slice(1), { timeoutMs: 20000 });
  if (result.code !== 0) {
    return {
      ...plan,
      ok: false,
      error: cleanString(result.stderr || result.stdout || `tailscale funnel exited ${result.code}`),
      commandResult: {
        code: result.code,
        stdout: cleanString(result.stdout),
        stderr: cleanString(result.stderr)
      },
      mutates: true,
      truthMode: "failed-tailscale-funnel-path-activation"
    };
  }

  const config = await writePublicEndpointConfig(slug, {
    publicBase,
    trustedHosted: true,
    note: `Tailscale Funnel ${normalizedPath} activated by Project Cockpit after guard checks.`
  });
  const publicEndpoint = await resolvePublicEndpointStatus(slug);
  return {
    ...plan,
    ok: true,
    applied: true,
    config,
    publicEndpoint,
    commandResult: {
      code: result.code,
      stdout: cleanString(result.stdout),
      stderr: cleanString(result.stderr)
    },
    mutates: true,
    truthMode: "observed-tailscale-funnel-path-activation"
  };
}

async function buildClientKitSetup(slug, readiness = {}, { publicEndpoint = null } = {}) {
  const files = await Promise.all(clientKitFiles(slug).map(async (file) => ({
    ...file,
    exists: await fileExists(file.path)
  })));
  const proof = readiness.mcpClientKitProof || {};
  return {
    schema: "beagle.multimodel-client-kit-setup.v1",
    status: proof.ok ? "ready" : files.every((file) => file.exists) ? "generated-unverified" : "missing",
    kitDir: clientKitDir(slug),
    files,
    stdioBridgePath: path.resolve(process.cwd(), "bin/workbench-context-mcp.mjs"),
    connectionPackEndpoint: `/api/workbench/${slug}/context/connect`,
    generateCommand: "npm run generate:workbench:mcp-client-kit",
    verifyCommand: "npm run verify:workbench:mcp-client-kit",
    publicEndpoint,
    proof,
    installProof: readiness.mcpClientInstallProof || {},
    truthMode: "observed-client-kit-files"
  };
}

async function subscriptionInstallEvidence(slug, clientId) {
  const serverName = `beagle-workbench-${slug}`;
  const installDir = installedMcpDir(slug);
  const launcher = path.join(installDir, `beagle-workbench-${slug}-mcp`);
  const home = process.env.HOME || "/home/devsounio";
  const kit = clientKitFiles(slug);
  const kitExists = await Promise.all(kit.map(async (file) => ({
    name: file.name,
    path: file.path,
    exists: await fileExists(file.path)
  })));
  const common = {
    installDir,
    launcher,
    launcherExists: await fileExists(launcher),
    kitDir: clientKitDir(slug),
    kitFiles: kitExists,
    kitComplete: kitExists.every((file) => file.exists)
  };
  if (clientId === "claude-desktop") {
    const targets = [
      path.join(home, ".claude", "settings.json"),
      path.join(home, ".config", "Claude", "claude_desktop_config.json")
    ];
    const configs = await Promise.all(targets.map(async (file) => ({
      path: file,
      exists: await fileExists(file),
      mentionsServer: await fileContains(file, serverName)
    })));
    return {
      ...common,
      expectedTransport: "stdio-proxy",
      configs,
      installed: common.launcherExists && configs.some((file) => file.exists && file.mentionsServer)
    };
  }
  if (clientId === "cursor") {
    const file = path.join(home, ".cursor", "mcp.json");
    const configs = [{
      path: file,
      exists: await fileExists(file),
      mentionsServer: await fileContains(file, serverName)
    }];
    return {
      ...common,
      expectedTransport: "stdio-proxy",
      configs,
      installed: common.launcherExists && configs.some((item) => item.exists && item.mentionsServer)
    };
  }
  if (["chatgpt", "grok"].includes(clientId)) {
    const httpKit = path.join(clientKitDir(slug), "http_mcp.json");
    const expectedKey = clientId === "chatgpt" ? "\"chatgpt\"" : "\"grok\"";
    return {
      ...common,
      expectedTransport: "http-mcp",
      configs: [{
        path: httpKit,
        exists: await fileExists(httpKit),
        mentionsServer: await fileContains(httpKit, expectedKey)
      }],
      installed: await fileExists(httpKit) && await fileContains(httpKit, expectedKey)
    };
  }
  return {
    ...common,
    expectedTransport: "unknown",
    configs: [],
    installed: common.launcherExists
  };
}

function subscriptionClientSetup(readiness = {}) {
  return (readiness.providers || [])
    .filter((provider) => provider.transport === "workbench-context-mcp-inbox")
    .map((provider) => ({
      id: provider.id,
      label: provider.label,
      targetClient: provider.targetClient || "",
      status: provider.state === "handoff-live" || provider.status === "available"
        ? "live"
        : provider.state === "handoff-stale"
          ? "stale"
          : provider.status || "unknown",
      mcpEndpoint: provider.mcpEndpoint || "",
      mcpHeaders: provider.mcpHeaders || null,
      clientPresence: provider.clientPresence || "",
      clientLatestAt: provider.clientLatestAt || "",
      reason: provider.reason || "",
      requiredToolFlow: [
        "workbench_context_join",
        "workbench_context_client_heartbeat",
        "workbench_context_inbox",
        "workbench_context_claim",
        "workbench_context_reply"
      ]
    }));
}

function setupStatusForProvider(provider = {}) {
  if (provider.status === "available") return "ready";
  if (provider.state === "handoff-stale" || provider.transport === "workbench-context-mcp-inbox") return "waiting-for-client";
  return "blocked";
}

function buildProviderSetupAction({ slug, provider }) {
  const status = setupStatusForProvider(provider);
  if (provider.id === "grok") {
    const requirements = [
      envRequirement("XAI_API_KEY", { secret: true }),
      envRequirement("PROJECT_COCKPIT_XAI_MODEL", { value: XAI_MODEL })
    ];
    return {
      id: provider.id,
      label: provider.label,
      status,
      transport: provider.transport,
      summary: provider.status === "available"
        ? "Grok API streaming is configured."
        : "Set the real xAI key for Grok streaming. No mock fallback is used.",
      requirements,
      missing: missingEnv(requirements),
      verifyCommand: `PROVIDERS=grok npm run verify:multimodel:conversation ${slug}`,
      reason: provider.reason || "",
      truthMode: "runtime-env-check"
    };
  }

  if (provider.id === "kimi") {
    const kimiSafety = provider.bridgeSafety || kimiBridgeSafety({ slug });
    const requirements = [
      envRequirement("PROJECT_COCKPIT_KIMI_COMMAND", { value: KIMI_LOCAL_COMMAND }),
      envRequirement("PROJECT_COCKPIT_KIMI_ZELLIJ_PROJECT_SLUG", { value: KIMI_ZELLIJ_PROJECT_SLUG }),
      envRequirement("PROJECT_COCKPIT_KIMI_ZELLIJ_SESSION", { value: KIMI_ZELLIJ_SESSION }),
      envRequirement("PROJECT_COCKPIT_KIMI_ZELLIJ_TAB", { value: KIMI_ZELLIJ_TAB }),
      envRequirement("PROJECT_COCKPIT_KIMI_ZELLIJ_SSH_HOST", { value: KIMI_ZELLIJ_SSH_HOST }),
      envRequirement("PROJECT_COCKPIT_KIMI_ZELLIJ_CHECK_COMMAND", { value: KIMI_ZELLIJ_CHECK_COMMAND })
    ];
    const bridgeProject = cleanString(KIMI_ZELLIJ_PROJECT_SLUG);
    const crossProject = Boolean(bridgeProject && safeSlug(bridgeProject) !== safeSlug(slug));
    return {
      id: provider.id,
      label: provider.label,
      status,
      transport: provider.transport,
      summary: provider.status === "available"
        ? "Kimi streaming is configured for this project."
        : "Configure a project-local Kimi CLI or zellij bridge. Beagle will not silently reuse another project.",
      requirements,
      missing: missingEnv(requirements),
      bridgeProjectSlug: bridgeProject,
      bridgeMode: provider.bridgeMode || "not-configured",
      localCommand: KIMI_LOCAL_COMMAND,
      localCommandBinary: shellCommandBinary(KIMI_LOCAL_COMMAND),
      pane: KIMI_ZELLIJ_PANE || "focused-pane",
      crossProject,
      crossProjectAllowed: ALLOW_CROSS_PROJECT_KIMI_ZELLIJ,
      noImplicitCrossProjectBridge: !crossProject || ALLOW_CROSS_PROJECT_KIMI_ZELLIJ,
      bridgeSafety: kimiSafety,
      forbiddenBridgeValues: kimiSafety.offenders || [],
      verifyCommand: `PROVIDERS=kimi npm run verify:multimodel:conversation ${slug}`,
      reason: provider.reason || "",
      truthMode: "runtime-env-check"
    };
  }

  if (provider.transport === "workbench-context-mcp-inbox") {
    return {
      id: provider.id,
      label: provider.label,
      status,
      transport: provider.transport,
      summary: provider.status === "available"
        ? `${provider.label} is writing fresh Workbench Context records.`
        : `${provider.label} must open the Beagle MCP inbox and reply through Workbench Context.`,
      targetClient: provider.targetClient || "",
      mcpEndpoint: provider.mcpEndpoint || mcpHttpEndpointForClient(slug, provider.targetClient, provider.provider),
      mcpHeaders: provider.mcpHeaders || mcpHttpHeadersForClient(provider.targetClient, provider.provider),
      heartbeatTool: "workbench_context_client_heartbeat",
      replyTool: provider.targetClient === "claude-desktop" ? "cockpit_workbench_context_reply" : "workbench_context_reply",
      inboxTool: "workbench_context_inbox",
      claimTool: "workbench_context_claim",
      progressTool: "workbench_context_heartbeat",
      inboxEndpoint: `/api/projects/${slug}/multimodel/mcp-inbox`,
      clientInboxEndpoint: `/api/workbench/${slug}/context/messages/inbox/${encodeURIComponent(provider.targetClient || "")}`,
      directReplyEndpoint: `/api/projects/${slug}/multimodel/mcp-inbox/:message_id/reply`,
      directCancelEndpoint: `/api/projects/${slug}/multimodel/mcp-inbox/:message_id/cancel`,
      reason: provider.reason || "",
      truthMode: "workbench-context-presence"
    };
  }

  return {
    id: provider.id,
    label: provider.label || provider.id,
    status,
    transport: provider.transport || "",
    summary: provider.status === "available" ? "Provider is live." : "Provider is not ready.",
    reason: provider.reason || "",
    truthMode: "runtime-provider-check"
  };
}

async function buildMultimodelSetup(slug, { publicBase = "" } = {}) {
  const readiness = await buildMultimodelReadiness(slug);
  const actionableIds = new Set([...(readiness.blocked || []), ...(readiness.handoffStale || [])]);
  const actions = (readiness.providers || [])
    .filter((provider) => actionableIds.has(provider.id) || ["grok", "kimi"].includes(provider.id))
    .map((provider) => buildProviderSetupAction({ slug, provider }));
  const kimi = actions.find((item) => item.id === "kimi") || null;
  const publicEndpoint = await resolvePublicEndpointStatus(slug, { publicBase });
  const hostedNetworkBlocked = MCP_INBOX_PROVIDERS
    .filter((provider) => ["chatgpt", "grok"].includes(provider.targetClient) && !publicEndpoint.hostedClientReachable)
    .map((provider) => provider.id);
  const clientKit = await buildClientKitSetup(slug, readiness, { publicEndpoint });
  return {
    schema: "beagle.multimodel-setup.v1",
    projectSlug: slug,
    liveNow: readiness.liveNow || [],
    blocked: readiness.blocked || [],
    handoffStale: readiness.handoffStale || [],
    publicEndpoint,
    hostedNetworkBlocked,
    actions,
    clientKit,
    subscriptionClients: subscriptionClientSetup(readiness),
    guards: {
      noImplicitKimiBridge: Boolean((kimi?.bridgeSafety?.safe !== false) && (kimi?.bridgeMode === "not-configured" || kimi?.noImplicitCrossProjectBridge || kimi?.bridgeMode === "local-command")),
      kimiBridgeProjectSlug: kimi?.bridgeProjectSlug || "",
      crossProjectKimiAllowed: ALLOW_CROSS_PROJECT_KIMI_ZELLIJ,
      kimiBridgeSafety: kimi?.bridgeSafety || kimiBridgeSafety({ slug })
    },
    generatedAt: new Date().toISOString(),
    truthMode: "observed-runtime-provider-setup"
  };
}

async function buildSubscriptionClientDoctor(slug, { publicBase = "" } = {}) {
  const readiness = await buildMultimodelReadiness(slug);
  const setup = await buildMultimodelSetup(slug, { publicBase });
  const publicEndpoint = await resolvePublicEndpointStatus(slug, { publicBase });
  const setupById = new Map((setup.subscriptionClients || []).map((client) => [client.id, client]));
  const providerById = new Map((readiness.providers || []).map((provider) => [provider.id, provider]));
  const clients = [];
  for (const provider of MCP_INBOX_PROVIDERS) {
    const setupClient = setupById.get(provider.id) || {};
    const readinessProvider = providerById.get(provider.id) || {};
    const targetClient = cleanString(provider.targetClient);
    const install = await subscriptionInstallEvidence(slug, targetClient);
    const hostedHttpClient = ["chatgpt", "grok"].includes(targetClient);
    const clientPresence = cleanString(setupClient.clientPresence || readinessProvider.clientPresence || "unobserved");
    const recentHeartbeat = clientPresence === "recent";
    const status = recentHeartbeat
      ? "live"
      : clientPresence === "stale"
        ? "waiting-stale-client"
        : "waiting-unobserved-client";
    const hasEndpoint = Boolean(cleanString(setupClient.mcpEndpoint || readinessProvider.mcpEndpoint));
    const hasHeaders = Boolean(
      (setupClient.mcpHeaders || readinessProvider.mcpHeaders || {})["x-beagle-client-id"]
        && (setupClient.mcpHeaders || readinessProvider.mcpHeaders || {})["x-beagle-provider"]
    );
    const networkReady = !hostedHttpClient || publicEndpoint.hostedClientReachable;
    const checks = {
      providerDeclared: Boolean(readinessProvider.id),
      mcpEndpointDeclared: hasEndpoint,
      mcpHeadersDeclared: hasHeaders,
      kitComplete: install.kitComplete === true,
      installPresent: install.installed === true,
      networkReady,
      recentHeartbeat,
      notFalselyLive: setupClient.status !== "live" || recentHeartbeat
    };
    clients.push({
      id: provider.id,
      label: provider.label,
      targetClient,
      provider: provider.provider,
      status,
      transport: setupClient.transport || readinessProvider.transport || provider.transport || "workbench-context-mcp-inbox",
      preferredTransport: install.expectedTransport,
      mcpEndpoint: setupClient.mcpEndpoint || readinessProvider.mcpEndpoint || "",
      mcpHeaders: setupClient.mcpHeaders || readinessProvider.mcpHeaders || null,
      clientPresence,
      clientLatestAt: setupClient.clientLatestAt || readinessProvider.clientLatestAt || "",
      clientAgeMs: readinessProvider.clientAgeMs ?? null,
      realConnectionObserved: recentHeartbeat,
      install,
      hostedHttpClient,
      checks,
      blockers: [
        !checks.providerDeclared ? "provider not declared in readiness" : "",
        !checks.mcpEndpointDeclared ? "missing MCP endpoint" : "",
        !checks.mcpHeadersDeclared ? "missing client/provider headers" : "",
        !checks.kitComplete ? "MCP client kit is incomplete" : "",
        !checks.installPresent ? "client config/install evidence is missing" : "",
        !checks.networkReady ? "hosted subscription client needs public HTTPS MCP endpoint" : "",
        !checks.recentHeartbeat ? "no recent real client heartbeat" : ""
      ].filter(Boolean),
      truthMode: "observed-subscription-client-connection-state"
    });
  }
  const checks = {
    allClientsDeclared: clients.every((client) => client.checks.providerDeclared),
    allEndpointsDeclared: clients.every((client) => client.checks.mcpEndpointDeclared),
    allHeadersDeclared: clients.every((client) => client.checks.mcpHeadersDeclared),
    allKitsComplete: clients.every((client) => client.checks.kitComplete),
    noFalseLiveClaims: clients.every((client) => client.checks.notFalselyLive),
    allNetworkReady: clients.every((client) => client.checks.networkReady),
    allClientsLive: clients.every((client) => client.realConnectionObserved)
  };
  return {
    schema: "beagle.multimodel-subscription-client-doctor.v1",
    projectSlug: slug,
    ok: checks.allClientsDeclared
      && checks.allEndpointsDeclared
      && checks.allHeadersDeclared
      && checks.allKitsComplete
      && checks.noFalseLiveClaims,
    allConnectionReady: Object.values(checks).every(Boolean),
    checks,
    publicEndpoint,
    clients,
    liveClients: clients.filter((client) => client.realConnectionObserved).map((client) => client.id),
    waitingClients: clients.filter((client) => !client.realConnectionObserved).map((client) => client.id),
    hostedNetworkBlocked: clients
      .filter((client) => client.hostedHttpClient && !client.checks.networkReady)
      .map((client) => client.id),
    generatedAt: new Date().toISOString(),
    truthMode: "observed-runtime-subscription-client-doctor"
  };
}

function subscriptionClientSurface(targetClient) {
  if (targetClient === "chatgpt") return "ChatGPT connector/custom MCP";
  if (targetClient === "grok") return "Grok MCP connector";
  if (targetClient === "claude-desktop") return "Claude Desktop MCP";
  return "MCP client";
}

function buildSubscriptionClientConnectPlan({ slug, client, url, headers, tokenConfigured, tokenFile }) {
  const targetClient = cleanString(client.targetClient || client.id, "subscription-client");
  const provider = cleanString(client.provider || targetClient);
  const authHeaders = {
    ...headers,
    authorization: tokenConfigured ? "Bearer <workbench-context-token>" : ""
  };
  const joinArgs = {
    client_id: targetClient,
    provider,
    status: "online",
    note: "real subscription client connected to Beagle Workbench",
    tags: ["subscription-client", "beagle-workbench", slug]
  };
  const inboxArgs = {
    client_id: targetClient,
    limit: 10
  };
  const replyArgs = {
    message_id: "<message_id from next_handoff>",
    client_id: targetClient,
    text: "<real client response>"
  };
  const registration = {
    name: `beagle-workbench-${slug}`,
    transport: client.hostedHttpClient ? "streamable-http+sse" : client.preferredTransport || "stdio-proxy",
    url,
    headers: authHeaders,
    client_id: targetClient,
    provider,
    required_tools: [
      "workbench_context_join",
      "workbench_context_client_heartbeat",
      "workbench_context_inbox",
      "workbench_context_handoff_compile",
      targetClient === "claude-desktop" ? "cockpit_workbench_context_reply" : "workbench_context_reply"
    ]
  };
  const replyTool = targetClient === "claude-desktop" ? "cockpit_workbench_context_reply" : "workbench_context_reply";
  const setupText = [
    `Beagle Workbench MCP setup for ${subscriptionClientSurface(targetClient)} (${targetClient})`,
    "",
    "Register this MCP server in the real subscription client. This is not a model API route.",
    "",
    `Name: beagle-workbench-${slug}`,
    `Transport: ${registration.transport}`,
    `URL: ${url}`,
    "",
    "Headers:",
    ...Object.entries(authHeaders)
      .filter(([, value]) => cleanString(value))
      .map(([key, value]) => `- ${key}: ${value}`),
    "",
    tokenConfigured
      ? `Authorization token: read it locally from ${tokenFile || "the Workbench Context token file"} and replace <workbench-context-token>.`
      : "Authorization token: not configured yet.",
    "",
    "After connecting, use MCP tools in this order:",
    `1. workbench_context_join ${JSON.stringify(joinArgs)}`,
    `2. workbench_context_client_heartbeat ${JSON.stringify(joinArgs)}`,
    `3. workbench_context_inbox ${JSON.stringify(inboxArgs)}`,
    `4. workbench_context_handoff_compile with the message_id from next_handoff`,
    `5. ${replyTool} with message_id from next_handoff, client_id=${targetClient}, and the real model response`,
    "",
    "Proof rules:",
    "- Beagle marks this live only after a fresh real client heartbeat or MCP reply.",
    "- Probe traffic, fixture replies, manual paste, and direct debug endpoints do not count.",
    "",
    `Verify connection: CLIENT=${targetClient} npm run verify:multimodel:subscription-live ${slug}`,
    `Verify reply: CLIENT=${targetClient} npm run verify:multimodel:subscription-reply-live ${slug}`
  ].join("\n");
  return {
    surface: subscriptionClientSurface(targetClient),
    mcpServer: {
      url,
      headers: authHeaders,
      tokenConfigured,
      tokenFile,
      tokenInstruction: tokenConfigured
        ? `Read the bearer token from ${tokenFile || "the Workbench Context token file"} and replace <workbench-context-token>.`
        : "No Workbench Context token is configured; configure one before registering a hosted client."
    },
    registration,
    firstToolCalls: [
      { tool: "workbench_context_join", args: joinArgs },
      { tool: "workbench_context_client_heartbeat", args: joinArgs },
      { tool: "workbench_context_inbox", args: inboxArgs },
      { tool: replyTool, args: replyArgs }
    ],
    setupText,
    operatorPrompt: [
      "You are connected to Beagle Workbench through MCP as a subscription client.",
      `Use client_id=${targetClient}.`,
      "First call workbench_context_join.",
      `If next_handoff is present, read it and reply with ${replyTool} using the exact message_id.`,
      "Do not answer outside the MCP reply tool for the live drill."
    ].join("\n"),
    liveCriteria: [
      "fresh non-fixture client heartbeat",
      "reply written through workbench_context_reply or cockpit_workbench_context_reply",
      "manual paste/direct endpoint replies rejected as proof"
    ],
    truthMode: "declared-real-subscription-client-connect-plan"
  };
}

function subscriptionClientByIdentifier(identifier) {
  const id = cleanString(identifier);
  if (!id) return null;
  return MCP_INBOX_PROVIDERS.find((client) => (
    client.id === id ||
    client.targetClient === id ||
    normalizedId(client.id) === normalizedId(id) ||
    normalizedId(client.targetClient) === normalizedId(id)
  )) || null;
}

function latestSubscriptionLiveDrillRecord(records = [], client) {
  if (!client) return null;
  return records
    .filter((record) => record.metadata?.agent_message?.message_id)
    .filter((record) => cleanString(record.metadata.agent_message.to_client) === client.targetClient)
    .filter((record) => {
      const tags = record.tags || [];
      const meta = record.metadata || {};
      return tags.includes("subscription-live-drill")
        || meta.subscription_live_drill === true
        || cleanString(meta.agent_message?.subject).toLowerCase().includes("subscription live drill");
    })
    .sort((left, right) => cleanString(right.created_at).localeCompare(cleanString(left.created_at)))
    .at(0) || null;
}

function subscriptionLiveDrillStatusFromRecords({ slug, client, records, messageId = "" }) {
  const lifecycle = collectMcpMessageLifecycle(records);
  const selectedRecord = messageId
    ? findMcpHandoffRecord(records, messageId)
    : latestSubscriptionLiveDrillRecord(records, client);
  const presence = clientPresenceFromRecords(records, client);
  if (!selectedRecord) {
    return {
      schema: "beagle.multimodel-subscription-live-drill-status.v1",
      projectSlug: slug,
      client: {
        id: client.id,
        label: client.label,
        targetClient: client.targetClient,
        provider: client.provider
      },
      status: presence.clientPresence === "recent" ? "connected-no-drill" : "not-started",
      phases: {
        connect: presence.clientPresence === "recent",
        sent: false,
        acknowledged: false,
        claimed: false,
        heartbeat: false,
        replied: false,
        completed: false,
        canceled: false
      },
      presence,
      nextAction: presence.clientPresence === "recent"
        ? "Start a live drill for this connected client."
        : "Register the client with the connect plan, then start a live drill.",
      generatedAt: new Date().toISOString(),
      truthMode: "observed-subscription-live-drill-status"
    };
  }

  const meta = selectedRecord.metadata?.agent_message || {};
  const selectedMessageId = cleanString(meta.message_id);
  const sentAt = cleanString(meta.sent_at || selectedRecord.created_at);
  const threadId = cleanString(meta.thread_id || selectedRecord.session_id);
  const state = mcpMessageState(lifecycle, selectedMessageId);
  const rawReply = findMcpInboxReplyInRecords({
    records,
    targetClient: client.targetClient,
    aliases: client.aliases,
    threadId,
    sentAt,
    messageId: selectedMessageId
  });
  const reply = rawReply && !isVerifierContextRecord(rawReply) ? rawReply : null;
  const rejectedReply = rawReply && !reply
    ? {
      memory_id: cleanString(rawReply.memory_id),
      client_id: cleanString(rawReply.client_id),
      source: cleanString(rawReply.source),
      truthMode: cleanString(rawReply.metadata?.truthMode),
      reason: "reply matched the handoff but was verifier/manual/debug evidence"
    }
    : null;
  const replied = Boolean(reply);
  const completed = replied || state.status === "completed";
  const canceled = state.status === "canceled";
  const marker = cleanString(selectedRecord.metadata?.subscription_live_drill_marker);
  const activation = buildSubscriptionLiveDrillActivation({
    slug,
    client,
    marker,
    messageId: selectedMessageId,
    threadId
  });
  const phases = {
    connect: presence.clientPresence === "recent",
    sent: true,
    acknowledged: Boolean(state.acked_by),
    claimed: Boolean(state.claimed_by),
    heartbeat: Boolean(state.heartbeat_at),
    replied,
    completed,
    canceled
  };
  const status = canceled
    ? "canceled"
    : replied
      ? "reply-proven"
      : presence.clientPresence === "recent"
        ? "waiting-for-real-reply"
        : "waiting-for-real-client";
  return {
    schema: "beagle.multimodel-subscription-live-drill-status.v1",
    projectSlug: slug,
    client: {
      id: client.id,
      label: client.label,
      targetClient: client.targetClient,
      provider: client.provider
    },
    status,
    phases,
    presence,
    message: {
      message_id: selectedMessageId,
      thread_id: threadId,
      subject: cleanString(meta.subject),
      sent_at: sentAt,
      reply_endpoint: `/api/workbench/${slug}/context/messages/${encodeURIComponent(selectedMessageId)}/reply`,
      cancel_endpoint: `/api/projects/${slug}/multimodel/mcp-inbox/${encodeURIComponent(selectedMessageId)}/cancel`,
      compile_endpoint: `/api/workbench/${slug}/context/messages/${encodeURIComponent(selectedMessageId)}/compile`,
      marker,
      text: cleanString(selectedRecord.text).slice(0, 4000)
    },
    activation,
    lifecycle: state,
    reply: reply ? {
      memory_id: cleanString(reply.memory_id),
      client_id: cleanString(reply.client_id),
      source: cleanString(reply.source),
      created_at: cleanString(reply.created_at),
      text: extractContextReplyText(reply),
      truthMode: cleanString(reply.metadata?.truthMode)
    } : null,
    rejectedReply,
    nextAction: replied
      ? "Real subscription reply observed."
      : canceled
        ? "Start another live drill when the client is ready."
        : "Open the subscription app, run workbench_context_join, inspect next_handoff, then reply through the MCP reply tool.",
    generatedAt: new Date().toISOString(),
    truthMode: "observed-subscription-live-drill-status"
  };
}

function buildSubscriptionLiveDrillActivation({ slug, client, marker, messageId, threadId }) {
  const targetClient = cleanString(client?.targetClient || client?.id, "subscription-client");
  const provider = cleanString(client?.provider || targetClient);
  const replyTool = targetClient === "claude-desktop" ? "cockpit_workbench_context_reply" : "workbench_context_reply";
  const joinArgs = {
    client_id: targetClient,
    provider,
    status: "online",
    note: "real subscription client connected to Beagle Workbench",
    tags: ["subscription-client", "beagle-workbench", slug]
  };
  const replyArgs = {
    message_id: messageId,
    client_id: targetClient,
    text: `real subscription reply ${marker}`
  };
  const compileArgs = {
    message_id: messageId,
    client_id: targetClient
  };
  const modelPrompt = [
    `You are the real ${targetClient} subscription client for Beagle Workbench project ${slug}.`,
    "Use MCP tools only for the handoff; do not answer in ordinary chat.",
    "",
    `1. Call workbench_context_join with: ${JSON.stringify(joinArgs)}`,
    `2. If you need context, call workbench_context_handoff_compile with: ${JSON.stringify(compileArgs)}`,
    `3. Reply through ${replyTool} with: ${JSON.stringify(replyArgs)}`,
    "",
    `The message_id is ${messageId}.`,
    `The thread_id is ${threadId}.`,
    `The marker is ${marker}.`,
    "The reply must be written through the MCP reply tool so Beagle can mark this as real."
  ].join("\n");
  return {
    schema: "beagle.multimodel-subscription-live-drill-activation.v1",
    projectSlug: slug,
    client: {
      id: cleanString(client?.id),
      targetClient,
      provider,
      label: cleanString(client?.label)
    },
    messageId,
    threadId,
    marker,
    replyTool,
    joinArgs,
    compileArgs,
    replyArgs,
    modelPrompt,
    checklist: [
      "register the MCP server in the subscription app if it is not already registered",
      "paste the modelPrompt into the subscription app",
      "the app must call workbench_context_join",
      "the app must call the MCP reply tool with the exact message_id",
      "run the subscription reply-live verifier after the reply lands"
    ],
    verifyCommand: `CLIENT=${targetClient} npm run verify:multimodel:subscription-reply-live ${slug}`,
    truthMode: "declared-real-subscription-client-activation-prompt"
  };
}

async function buildSubscriptionLiveDrillStatus(slug, clientId, { messageId = "" } = {}) {
  const client = subscriptionClientByIdentifier(clientId);
  if (!client) {
    const error = new Error(`subscription client not found: ${clientId}`);
    error.statusCode = 404;
    throw error;
  }
  const records = await readWorkbenchContextRecords(slug);
  return subscriptionLiveDrillStatusFromRecords({ slug, client, records, messageId });
}

async function createSubscriptionLiveDrill(slug, clientId, body = {}) {
  const client = subscriptionClientByIdentifier(clientId);
  if (!client) {
    const error = new Error(`subscription client not found: ${clientId}`);
    error.statusCode = 404;
    throw error;
  }
  const marker = cleanString(body.marker) || `subscription-live-drill-${client.targetClient}-${Date.now()}-${randomUUID().slice(0, 8)}`;
  const threadId = `subscription-live-drill:${slug}:${client.targetClient}:${marker}`.replace(/[^a-zA-Z0-9:_-]/g, "_");
  const messageId = `${threadId}:handoff`.replace(/[^a-zA-Z0-9:_-]/g, "_");
  const replyTool = client.targetClient === "claude-desktop" ? "cockpit_workbench_context_reply" : "workbench_context_reply";
  const content = [
    `Project: ${slug}`,
    `Subscription live drill: ${marker}`,
    `Target client: ${client.targetClient}`,
    `Message ID: ${messageId}`,
    `Thread: ${threadId}`,
    `Reply tool: ${replyTool}`,
    `Reply args: {"message_id":"${messageId}","client_id":"${client.targetClient}","text":"<real response mentioning ${marker}>"}`,
    "",
    "This is a real Beagle Workbench subscription-client drill.",
    "First call workbench_context_join with your client_id.",
    "Then read next_handoff or this inbox message.",
    "Reply through the MCP reply tool. Do not paste into the Beagle debug endpoint.",
    "",
    cleanString(body.prompt, `Reply with the marker ${marker} and one short sentence.`)
  ].join("\n");

  const response = await fetch(`${COCKPIT_LOOPBACK}/api/workbench/${encodeURIComponent(slug)}/context/messages/send`, {
    method: "POST",
    headers: internalContextHeaders(),
    body: JSON.stringify({
      from_client: "project-cockpit-live-drill",
      to_client: client.targetClient,
      subject: "subscription live drill",
      priority: "normal",
      thread_id: threadId,
      message_id: messageId,
      requires_response: true,
      tags: ["subscription-live-drill", "mcp-inbox", client.id, client.targetClient],
      metadata: {
        subscription_live_drill: true,
        subscription_live_drill_marker: marker,
        providerId: client.id,
        targetClient: client.targetClient,
        reply_tool: "workbench_context_reply",
        reply_tool_stdio_proxy: "cockpit_workbench_context_reply",
        reply_endpoint: `/api/workbench/${slug}/context/messages/${encodeURIComponent(messageId)}/reply`,
        truthMode: "awaiting-real-subscription-client"
      },
      content
    }),
    signal: AbortSignal.timeout(10000)
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload?.error || `subscription live drill send failed: HTTP ${response.status}`);
    error.statusCode = response.status;
    error.payload = payload;
    throw error;
  }
  const status = await buildSubscriptionLiveDrillStatus(slug, client.id, { messageId });
  const activation = buildSubscriptionLiveDrillActivation({
    slug,
    client,
    marker,
    messageId,
    threadId
  });
  return {
    schema: "beagle.multimodel-subscription-live-drill.v1",
    ok: true,
    projectSlug: slug,
    client: {
      id: client.id,
      label: client.label,
      targetClient: client.targetClient,
      provider: client.provider
    },
    marker,
    messageId,
    threadId,
    activation,
    status,
    sent: payload,
    generatedAt: new Date().toISOString(),
    truthMode: "observed-subscription-live-drill-created"
  };
}

function subscriptionRoomReadyText({ slug, client, token = "", drill = null }) {
  const connect = client.connect || {};
  const registration = connect.registration || {};
  const mcpServer = connect.mcpServer || {};
  const headers = {
    ...(registration.headers || mcpServer.headers || {}),
    authorization: token ? `Bearer ${token}` : registration.headers?.authorization || mcpServer.headers?.authorization || ""
  };
  const targetClient = cleanString(client.targetClient || client.id);
  const activationPrompt = cleanString(drill?.activation?.modelPrompt);
  return [
    `Beagle Workbench MCP connection for ${client.label || client.id}`,
    "",
    "Use this inside the real subscription app. This is not a model API route.",
    "",
    `Name: ${registration.name || `beagle-workbench-${slug}`}`,
    `Transport: ${registration.transport || client.preferredTransport || "streamable-http+sse"}`,
    `URL: ${registration.url || mcpServer.url || client.url || ""}`,
    "",
    "Headers:",
    ...Object.entries(headers)
      .filter(([, value]) => cleanString(value))
      .map(([key, value]) => `- ${key}: ${value}`),
    "",
    "First tool calls:",
    ...(connect.firstToolCalls || []).map((item, index) => `${index + 1}. ${item.tool} ${JSON.stringify(item.args || {})}`),
    "",
    "After connection:",
    `- Live check: CLIENT=${targetClient} npm run verify:multimodel:subscription-live ${slug}`,
    `- Reply check: CLIENT=${targetClient} npm run verify:multimodel:subscription-reply-live ${slug}`,
    "",
    "Proof rules:",
    "- Beagle only marks this live after this exact client writes a fresh heartbeat or MCP reply.",
    "- Manual paste, direct endpoint replies, fixture replies, and debug probes do not count.",
    "",
    activationPrompt ? "Live drill activation prompt:" : "",
    activationPrompt || "",
    connect.operatorPrompt ? `Operator prompt:\n${connect.operatorPrompt}` : ""
  ].filter((line) => line !== "").join("\n");
}

async function writeSubscriptionRoomFile({ slug, items, redacted }) {
  const dir = clientKitDir(slug);
  await mkdir(dir, { recursive: true });
  const suffix = redacted ? "redacted" : "local";
  const file = path.join(dir, `subscription_room.${suffix}.txt`);
  const body = [
    `Beagle Workbench subscription room for ${slug}`,
    "",
    "Open the real apps and use the matching section. A client is not live until Beagle observes its MCP heartbeat or reply.",
    "",
    ...items.flatMap((item) => [
      "================================================================================",
      item.clientId,
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

async function writeSubscriptionReadyFile({ slug, clientId, readyText, redacted }) {
  const dir = clientKitDir(slug);
  await mkdir(dir, { recursive: true });
  const suffix = redacted ? "redacted" : "local";
  const file = path.join(dir, `${clientId}_ready_to_paste.${suffix}.txt`);
  await writeFile(file, `${readyText}\n`, { mode: 0o600 });
  await chmod(file, 0o600).catch(() => {});
  return file;
}

function parseSubscriptionRoomClients(value) {
  const text = cleanString(value, "all");
  if (text === "all") return ["chatgpt", "grok", "claude-desktop"];
  return text.split(",").map((item) => {
    const client = cleanString(item);
    if (client === "chatgpt-mcp") return "chatgpt";
    if (client === "grok-mcp") return "grok";
    return client;
  }).filter(Boolean);
}

async function createSubscriptionRoom(slug, body = {}) {
  const clients = parseSubscriptionRoomClients(body.clients || body.client || "all");
  const revealToken = body.revealToken === true || body.reveal_token === true;
  const createDrills = body.drill !== false;
  const markerPrefix = cleanString(body.marker) || `subscription-room-${Date.now().toString(36)}`;
  const bringup = await buildSubscriptionClientBringup(slug, {
    publicBase: cleanString(body.publicBase || body.public_base || "")
  });
  const token = revealToken ? readWorkbenchContextHttpMcpTokenFile() : "";
  const items = [];
  for (const clientId of clients) {
    const client = (bringup.clients || []).find((item) => (
      item.id === clientId ||
      item.targetClient === clientId ||
      item.id === `${clientId}-mcp`
    ));
    if (!client) {
      const error = new Error(`subscription client not found: ${clientId}`);
      error.statusCode = 404;
      error.payload = { knownClients: (bringup.clients || []).map((item) => item.id) };
      throw error;
    }
    const drill = createDrills
      ? await createSubscriptionLiveDrill(slug, client.targetClient || client.id, {
        marker: `${markerPrefix}-${client.targetClient || client.id}`,
        prompt: `Reply through the Beagle MCP reply tool with the marker ${markerPrefix}-${client.targetClient || client.id}.`
      })
      : null;
    const readyText = subscriptionRoomReadyText({ slug, client, token, drill });
    const readyFile = await writeSubscriptionReadyFile({
      slug,
      clientId: client.targetClient || client.id,
      readyText,
      redacted: !revealToken
    });
    items.push({
      clientId: client.targetClient || client.id,
      providerId: client.id,
      label: client.label,
      targetClient: client.targetClient,
      url: client.url,
      readyFile,
      readyText,
      tokenIncluded: Boolean(token),
      drill: drill
        ? {
          messageId: drill.messageId,
          marker: drill.marker,
          activationPromptIncluded: Boolean(cleanString(drill.activation?.modelPrompt))
        }
        : null
    });
  }
  const roomFile = await writeSubscriptionRoomFile({ slug, items, redacted: !revealToken });
  return {
    schema: "beagle.multimodel-subscription-room.v1",
    ok: true,
    projectSlug: slug,
    clients,
    roomFile,
    redacted: !revealToken,
    tokenIncluded: Boolean(token),
    tokenFile: bringup.auth?.tokenFile || "",
    items: items.map((item) => ({
      clientId: item.clientId,
      providerId: item.providerId,
      label: item.label,
      targetClient: item.targetClient,
      readyFile: item.readyFile,
      url: item.url,
      tokenIncluded: item.tokenIncluded,
      drill: item.drill
    })),
    nextAction: revealToken
      ? `Open ${roomFile}, configure each real subscription app, and keep watching for heartbeat/reply.`
      : `Generated redacted room file ${roomFile}. Use the CLI with --reveal-token on the trusted machine for paste-ready bearer tokens.`,
    generatedAt: new Date().toISOString(),
    truthMode: "observed-subscription-room-ready-files-no-live-claim"
  };
}

async function buildSubscriptionClientBringup(slug, { publicBase = "" } = {}) {
  const doctor = await buildSubscriptionClientDoctor(slug, { publicBase });
  const inboxStatus = buildMcpInboxStatusFromRecords(slug, await readWorkbenchContextRecords(slug), { limit: 20 });
  const subscriptionReplyVerifications = await readVerificationRecords(slug, { limit: 24, kind: "subscription-reply-live" });
  const publicEndpoint = doctor.publicEndpoint || {};
  const publicBaseUrl = cleanString(publicEndpoint.url);
  const tokenConfigured = Boolean(WORKBENCH_CONTEXT_HTTP_MCP_TOKEN || readWorkbenchContextHttpMcpTokenFile());
  const tokenFile = cleanString(WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE);
  const hostedPacketPath = path.join(clientKitDir(slug), "hosted_subscription_connection.json");
  const hostedPacketRedactedPath = path.join(clientKitDir(slug), "hosted_subscription_connection.redacted.json");
  const hostedPacketExists = await fileExists(hostedPacketPath);
  const hostedPacketRedactedExists = await fileExists(hostedPacketRedactedPath);
  const clients = (doctor.clients || []).map((client) => {
    const relativeEndpoint = client.mcpEndpoint || mcpHttpEndpointForClient(slug, client.targetClient, client.provider);
    let url = relativeEndpoint;
    if (publicBaseUrl) {
      try {
        url = new URL(relativeEndpoint, publicBaseUrl).toString();
      } catch {
        url = `${publicBaseUrl.replace(/\/$/, "")}${relativeEndpoint.startsWith("/") ? "" : "/"}${relativeEndpoint}`;
      }
    }
    const headers = {
      ...(client.mcpHeaders || mcpHttpHeadersForClient(client.targetClient, client.provider)),
      authorization: tokenConfigured ? "Bearer <workbench-context-token>" : ""
    };
    const connectPlan = buildSubscriptionClientConnectPlan({
      slug,
      client,
      url,
      headers,
      tokenConfigured,
      tokenFile
    });
    return {
      id: client.id,
      label: client.label,
      targetClient: client.targetClient,
      provider: client.provider,
      status: client.realConnectionObserved ? "live" : "waiting",
      clientPresence: client.clientPresence,
      clientLatestAt: client.clientLatestAt || "",
      clientAgeMs: client.clientAgeMs ?? null,
      realConnectionObserved: client.realConnectionObserved === true,
      preferredTransport: client.preferredTransport,
      hostedHttpClient: client.hostedHttpClient === true,
      url,
      relativeEndpoint,
      headers,
      connect: connectPlan,
      auth: {
        required: true,
        tokenConfigured,
        tokenFile
      },
      connectionPacket: {
        path: hostedPacketPath,
        redactedPath: hostedPacketRedactedPath,
        exists: hostedPacketExists,
        redactedExists: hostedPacketRedactedExists
      },
      expectedFirstContact: [
        "GET with Accept: text/event-stream for SSE listen",
        "POST initialize",
        "tools/list",
        "workbench_context_join"
      ],
      liveProof: client.realConnectionObserved
        ? `fresh heartbeat at ${client.clientLatestAt}`
        : "not live until this exact client writes a fresh heartbeat",
      verifyCommand: `CLIENT=${client.targetClient} npm run verify:multimodel:subscription-live ${slug}`,
      replyVerifyCommand: `CLIENT=${client.targetClient} npm run verify:multimodel:subscription-reply-live ${slug}`,
      replyGate: (() => {
        const providerInbox = (inboxStatus.providers || []).find((item) => item.provider_id === client.id) || null;
        const openMessages = (providerInbox?.messages || []).filter((message) => !["replied", "completed", "canceled"].includes(message.status));
        const latestOpen = openMessages[0] || null;
        const latestProof = latestSubscriptionReplyProofForClient(subscriptionReplyVerifications, client);
        const replyProven = latestProof.fresh === true;
        return {
          status: replyProven
            ? "reply-proven"
            : client.realConnectionObserved
              ? "ready-to-test"
              : "waiting-for-real-client",
          proofRequired: "A real subscription client must call workbench_context_reply/cockpit_workbench_context_reply for the handoff. Manual paste, direct endpoint replies, and fixture replies do not satisfy this gate.",
          latestProof,
          latestOpenMessageId: latestOpen?.message_id || "",
          latestOpenReplyEndpoint: latestOpen?.reply_endpoint || "",
          latestInboxStatus: providerInbox?.latest?.status || "",
          openCount: providerInbox?.counts?.open || 0,
          verifyCommand: `CLIENT=${client.targetClient} npm run verify:multimodel:subscription-reply-live ${slug}`,
          rejectedEvidence: [
            "manual-subscription-paste-ui",
            "developer-mcp-paste-ui",
            "direct-multimodel-mcp-inbox-endpoint",
            "fixture-*",
            "project-cockpit-multimodel"
          ],
          truthMode: "real-subscription-reply-gate"
        };
      })(),
      blockers: client.blockers || [],
      truthMode: "real-client-bringup-state"
    };
  });
  return {
    schema: "beagle.multimodel-subscription-client-bringup.v1",
    projectSlug: slug,
    ok: doctor.ok === true,
    allConnectionReady: doctor.allConnectionReady === true,
    publicEndpoint,
    auth: {
      required: true,
      tokenConfigured,
      tokenFile
    },
    connectionPacket: {
      path: hostedPacketPath,
      redactedPath: hostedPacketRedactedPath,
      exists: hostedPacketExists,
      redactedExists: hostedPacketRedactedExists
    },
    clients,
    liveClients: doctor.liveClients || [],
    waitingClients: doctor.waitingClients || [],
    nextAction: clients.some((client) => !client.realConnectionObserved)
      ? "Register one waiting client with its URL, headers, and token; then let it call the MCP server."
      : "All declared subscription clients have fresh real heartbeats.",
    generatedAt: new Date().toISOString(),
    truthMode: "observed-real-subscription-client-bringup"
  };
}

function buildProviderPrompt({ slug, message, history = [] }) {
  const recent = Array.isArray(history) ? history.slice(-12) : [];
  const transcript = recent
    .map((item) => {
      const role = cleanString(item.role || item.provider || "message");
      return `${role}: ${boundedText(item.text || item.content, 4000)}`;
    })
    .filter(Boolean)
    .join("\n\n");

  return boundedText([
    `Project: ${slug}`,
    "You are participating in a real-time multimodel work chat inside Beagle.",
    "Answer as yourself. Be concrete. Do not claim that another model answered.",
    "If the request asks for coding direction, name the next file or validation gate when useful.",
    transcript ? `Recent conversation:\n${transcript}` : "",
    `User:\n${boundedText(message)}`
  ].filter(Boolean).join("\n\n"));
}

function buildSynthesisPrompt({ slug, message, responses = [] }) {
  const providerBrief = responses
    .filter((response) => response.provider !== SYNTHESIS_RESPONSE_ID)
    .map((response) => [
      `${response.label || response.provider} (${response.status || "unknown"})`,
      boundedText(response.text || response.error || "", 6000)
    ].filter(Boolean).join("\n"))
    .join("\n\n---\n\n");

  return boundedText([
    `Project: ${slug}`,
    "You are the real synthesis agent for a multimodel Beagle chat turn.",
    "Read the provider outputs below and consolidate them for the user.",
    "Name useful agreements, disagreements, uncertainty, and the next concrete action.",
    "Do not pretend you contacted providers yourself; you are reading the captured outputs.",
    `Original user message:\n${boundedText(message)}`,
    providerBrief ? `Provider outputs:\n${providerBrief}` : "Provider outputs: none"
  ].filter(Boolean).join("\n\n"));
}

function emit(socket, payload) {
  if (socket && socket.readyState === socket.OPEN) {
    socket.send(JSON.stringify(payload));
  }
}

function runtimeFor(slug) {
  const key = safeSlug(slug);
  if (!multimodelRuntimes.has(key)) {
    multimodelRuntimes.set(key, {
      slug: key,
      sockets: new Set(),
      activeTurns: new Map(),
      activeChildren: new Set(),
      providerLanes: new Map()
    });
  }
  return multimodelRuntimes.get(key);
}

function existingRuntime(slug) {
  return multimodelRuntimes.get(safeSlug(slug)) || null;
}

function cleanupRuntime(runtime) {
  if (!runtime.sockets.size && !runtime.activeTurns.size) {
    multimodelRuntimes.delete(runtime.slug);
  }
}

function broadcast(runtime, payload) {
  for (const client of runtime.sockets) {
    emit(client, payload);
  }
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function activeTurnRecords(slug) {
  const runtime = existingRuntime(slug);
  if (!runtime) return [];
  return [...runtime.activeTurns.values()]
    .map((state) => decorateActiveTurnRecord(state))
    .sort((left, right) => cleanString(right.createdAt).localeCompare(cleanString(left.createdAt)));
}

function isTerminalResponseStatus(status) {
  return ["done", "error", "unavailable"].includes(cleanString(status));
}

function completedStatusFromResponses(responses = []) {
  const items = Array.isArray(responses) ? responses : [];
  if (!items.length || !items.every((response) => isTerminalResponseStatus(response.status))) {
    return "";
  }
  return items.some((response) => response.status === "error") ? "completed_with_errors" : "done";
}

function markInterruptedRuntimeTurns(slug, records) {
  const activeIds = new Set(activeTurnRecords(slug).map((record) => record.turnId));
  const now = new Date().toISOString();
  return records.map((record) => {
    if (activeIds.has(record.turnId) || !["waiting", "streaming"].includes(record.status)) {
      return record;
    }
    const completedStatus = completedStatusFromResponses(record.responses || []);
    if (completedStatus) {
      return {
        ...record,
        status: completedStatus,
        updatedAt: now,
        completedAt: record.completedAt || now
      };
    }
    return {
      ...record,
      status: "interrupted",
      updatedAt: now,
      completedAt: record.completedAt || now,
      responses: (record.responses || []).map((response) => (
        ["waiting", "streaming"].includes(response.status)
          ? {
              ...response,
              status: "error",
              error: response.error || "server restarted before this provider completed",
              meta: {
                ...(response.meta || {}),
                runtime_state: "interrupted"
              }
            }
          : response
      ))
    };
  });
}

function persistedTurnSnapshot(record, reason) {
  return {
    ...cloneJson(record),
    persistReason: reason,
    persistedAt: new Date().toISOString()
  };
}

function shouldPersistProviderEvent(event) {
  return [
    "provider_started",
    "provider_meta",
    "provider_done",
    "provider_error",
    "provider_unavailable"
  ].includes(event?.type);
}

function turnTraceDetail(event = {}) {
  if (event.type === "turn_accepted" || event.type === "turn_started") {
    const count = Number(event.providerCount || event.providers?.length || event.availableProviders?.length || 0);
    return count ? `${count} provider${count === 1 ? "" : "s"}` : "";
  }
  if (event.type === "provider_started") return "started";
  if (event.type === "provider_meta") return event.meta?.state || event.meta?.transport || "meta";
  if (event.type === "delta") {
    const chars = cleanString(event.text).length;
    return `${chars} char${chars === 1 ? "" : "s"}`;
  }
  if (event.type === "provider_done") {
    const chars = cleanString(event.text).length;
    return [
      "done",
      event.durationMs ? `${Math.round(Number(event.durationMs) / 1000)}s` : "",
      chars ? `${chars} chars` : ""
    ].filter(Boolean).join(" · ");
  }
  if (event.type === "provider_error") return cleanString(event.error, "error");
  if (event.type === "provider_unavailable") return cleanString(event.reason, "unavailable");
  if (event.type === "turn_done") return cleanString(event.status, "persisted");
  if (event.type === "turn_stopped") return cleanString(event.reason, "stopped");
  return cleanString(event.detail || event.type);
}

function appendTurnTrace(record, event = {}, at = new Date().toISOString()) {
  if (!record) return null;
  const entry = {
    id: cleanString(event.id) || `${record.turnId}:${event.type || "event"}:${event.provider || ""}:${timestampMs(at) || Date.now()}:${Math.random().toString(16).slice(2, 8)}`,
    at,
    type: cleanString(event.type, "event"),
    provider: cleanString(event.provider),
    label: cleanString(event.label || event.provider || event.type, "event"),
    detail: turnTraceDetail(event)
  };
  record.trace = [...(Array.isArray(record.trace) ? record.trace : []), entry].slice(-160);
  return entry;
}

function traceEventsForProvider(trace = [], provider = "") {
  const expected = cleanString(provider);
  return (Array.isArray(trace) ? trace : []).filter((event) => cleanString(event.provider) === expected);
}

function providerTraceCounts(trace = [], provider = "") {
  const counts = {
    started: 0,
    delta: 0,
    done: 0,
    meta: 0,
    error: 0,
    unavailable: 0
  };
  for (const event of traceEventsForProvider(trace, provider)) {
    if (event.type === "provider_started") counts.started += 1;
    if (event.type === "delta") counts.delta += 1;
    if (event.type === "provider_done") counts.done += 1;
    if (event.type === "provider_meta") counts.meta += 1;
    if (event.type === "provider_error") counts.error += 1;
    if (event.type === "provider_unavailable") counts.unavailable += 1;
  }
  return counts;
}

function responseEvidenceSummary(response = {}, selectedProvider = {}, trace = []) {
  const provider = cleanString(response.provider || selectedProvider.id);
  const traceCounts = providerTraceCounts(trace, provider);
  const textChars = cleanString(response.text).length;
  const streamedChars = Number(response.streamedChars || 0);
  const deltaCount = Number(response.deltaCount || 0);
  const transport = cleanString(response.meta?.transport || selectedProvider.transport);
  const model = cleanString(response.meta?.model || selectedProvider.model);
  const hasStarted = Boolean(response.startedAt) || traceCounts.started > 0;
  const hasDelta = deltaCount > 0 || streamedChars > 0 || traceCounts.delta > 0;
  const hasDone = ["done", "error", "unavailable"].includes(cleanString(response.status))
    || traceCounts.done > 0
    || traceCounts.error > 0
    || traceCounts.unavailable > 0;
  return {
    provider,
    label: cleanString(response.label || selectedProvider.label || provider),
    status: cleanString(response.status),
    responseStatus: cleanString(response.status),
    transport,
    model,
    sourceProvider: cleanString(response.meta?.sourceProvider || selectedProvider.id || provider),
    textChars,
    streamedChars,
    deltaCount,
    firstDeltaMs: response.firstDeltaMs ?? null,
    durationMs: response.durationMs ?? null,
    startedAt: cleanString(response.startedAt),
    firstDeltaAt: cleanString(response.firstDeltaAt),
    completedAt: cleanString(response.completedAt),
    hasText: textChars > 0,
    hasTransport: Boolean(transport),
    hasStarted,
    hasDelta,
    hasDone,
    hasDeltaOrDone: hasDelta || hasDone,
    traceCounts,
    error: cleanString(response.error),
    truthMode: "observed-persisted-provider-response"
  };
}

function turnEvidenceSummary(turn = {}, { activeCount = 0 } = {}) {
  const trace = Array.isArray(turn.trace) ? turn.trace : [];
  const providers = Array.isArray(turn.providers) ? turn.providers : [];
  const responses = Array.isArray(turn.responses) ? turn.responses : [];
  const providerMap = new Map(providers.map((provider) => [cleanString(provider.id), provider]));
  const responseMap = new Map(responses.map((response) => [cleanString(response.provider), response]));
  const providerIds = [...new Set([
    ...providers.map((provider) => cleanString(provider.id)).filter(Boolean),
    ...responses.map((response) => cleanString(response.provider)).filter(Boolean)
  ])];
  const responseEvidence = providerIds.map((providerId) =>
    responseEvidenceSummary(
      responseMap.get(providerId) || { provider: providerId, status: "missing" },
      providerMap.get(providerId) || { id: providerId },
      trace
    )
  );
  const traceTypes = new Set(trace.map((event) => cleanString(event.type)));
  const providerCount = responseEvidence.length;
  const activeForThisTurn = turn.active === true || ["waiting", "streaming"].includes(cleanString(turn.status));
  const checks = {
    turnStarted: traceTypes.has("turn_started"),
    turnDone: traceTypes.has("turn_done") || ["done", "completed_with_errors", "interrupted"].includes(cleanString(turn.status)),
    providersPresent: providerCount > 0,
    allProvidersStarted: providerCount > 0 && responseEvidence.every((item) => item.hasStarted),
    allProvidersHaveTransport: providerCount > 0 && responseEvidence.every((item) => item.hasTransport),
    allProvidersHaveText: providerCount > 0 && responseEvidence.every((item) => item.hasText),
    allProvidersHaveDeltaOrDone: providerCount > 0 && responseEvidence.every((item) => item.hasDeltaOrDone),
    allProvidersDone: providerCount > 0 && responseEvidence.every((item) => item.status === "done"),
    activeTurnsClear: activeCount === 0 || activeForThisTurn === true
  };
  const ok = checks.turnStarted
    && checks.turnDone
    && checks.providersPresent
    && checks.allProvidersStarted
    && checks.allProvidersHaveTransport
    && checks.allProvidersHaveText
    && checks.allProvidersHaveDeltaOrDone
    && checks.activeTurnsClear;
  return {
    schema: "beagle.multimodel-turn-evidence.v1",
    projectSlug: cleanString(turn.projectSlug),
    turnId: cleanString(turn.turnId),
    status: cleanString(turn.status),
    ok,
    checks,
    providerCount,
    providers: responseEvidence,
    active: turn.active === true,
    activeCount,
    traceCount: trace.length,
    traceTail: trace.slice(-40),
    createdAt: cleanString(turn.createdAt),
    updatedAt: cleanString(turn.updatedAt),
    completedAt: cleanString(turn.completedAt),
    generatedAt: new Date().toISOString(),
    truthMode: "observed-persisted-turn-evidence"
  };
}

function decorateActiveTurnRecord(state) {
  const record = cloneJson(state.turnRecord);
  const now = Date.now();
  return {
    ...record,
    active: true,
    activeAgeMs: Math.max(0, now - (state.startedAtMs || now)),
    activeForSeconds: Math.max(0, Math.round((now - (state.startedAtMs || now)) / 1000)),
    lastRuntimeEventAt: state.lastEventAt || record.updatedAt || record.createdAt || "",
    providerStatuses: providerRuntimeStatuses(record)
  };
}

function turnRecordForMcpMessage(records, messageId) {
  const id = cleanString(messageId);
  if (!id) return null;
  return (records || []).find((record) =>
    (record.responses || []).some((response) => cleanString(response.meta?.message_id) === id)
  ) || null;
}

function mergeMcpResponseIntoActiveTurn(activeRecord, reconciledTurn, messageId) {
  const id = cleanString(messageId);
  if (!activeRecord || !reconciledTurn || !id) return false;
  const source = (reconciledTurn.responses || []).find((response) =>
    cleanString(response.meta?.message_id) === id
  );
  if (!source) return false;
  const target = (activeRecord.responses || []).find((response) =>
    response.provider === source.provider || cleanString(response.meta?.message_id) === id
  );
  if (!target) return false;

  target.status = source.status || target.status;
  target.text = source.text || target.text || "";
  target.error = source.error || target.error || "";
  target.durationMs = source.durationMs ?? target.durationMs;
  target.stderr = source.stderr || target.stderr || "";
  target.meta = {
    ...(target.meta || {}),
    ...(source.meta || {})
  };
  activeRecord.updatedAt = new Date().toISOString();
  return true;
}

export async function notifyMultimodelContextMessage(payload = {}) {
  const slug = safeSlug(payload.slug);
  const messageId = cleanString(payload.messageId || payload.message_id || payload.result?.message_id);
  if (!messageId) return { notified: false, reason: "missing-message-id" };
  const kind = cleanString(payload.kind, "reply");
  const eventType = kind === "reply" ? "mcp_reply_observed" : "mcp_lifecycle_observed";

  const runtime = existingRuntime(slug);
  const persistedRecords = markInterruptedRuntimeTurns(slug, await readTurnRecords(slug, { limit: 100 }));
  const turns = await reconcileTurnRecordsWithMcpContext(slug, persistedRecords);
  const turn = turnRecordForMcpMessage(turns, messageId);
  if (!turn) return { notified: false, reason: "turn-not-found", messageId };

  const activeState = runtime?.activeTurns.get(turn.turnId);
  if (activeState) {
    const changed = mergeMcpResponseIntoActiveTurn(activeState.turnRecord, turn, messageId);
    if (changed) {
      activeState.lastEventAt = new Date().toISOString();
      appendTurnRecord(slug, persistedTurnSnapshot(activeState.turnRecord, `mcp-${kind}`)).catch(() => {});
      broadcast(runtime, {
        type: "turn_snapshot",
        turnId: turn.turnId,
        turn: decorateActiveTurnRecord(activeState),
        detached: false,
        reason: `workbench-context-${kind}`
      });
    }
    broadcast(runtime, {
      type: eventType,
      turnId: turn.turnId,
      messageId,
      kind,
      status: "active-runtime-will-reconcile",
      generatedAt: new Date().toISOString()
    });
    return { notified: true, active: true, turnId: turn.turnId, messageId };
  }

  if (runtime?.sockets?.size) {
    broadcast(runtime, {
      type: "turn_snapshot",
      turnId: turn.turnId,
      turn,
      detached: true,
      reason: `workbench-context-${kind}`
    });
    broadcast(runtime, {
      type: eventType,
      turnId: turn.turnId,
      messageId,
      kind,
      status: turn.status,
      generatedAt: new Date().toISOString()
    });
  }
  return { notified: Boolean(runtime?.sockets?.size), active: false, turnId: turn.turnId, messageId };
}

export async function notifyMultimodelClientPresence(payload = {}) {
  const slug = safeSlug(payload.slug);
  const runtime = existingRuntime(slug);
  if (!runtime?.sockets?.size) {
    return { notified: false, reason: "no-active-sockets", clientId: cleanString(payload.clientId || payload.client_id) };
  }

  const providers = await detectProviders(slug);
  const defaultProviders = defaultProviderIds(providers);
  broadcast(runtime, {
    type: "providers_snapshot",
    projectSlug: slug,
    providers,
    defaultProviders,
    clientId: cleanString(payload.clientId || payload.client_id),
    reason: cleanString(payload.reason || "workbench-context-client-heartbeat"),
    generatedAt: new Date().toISOString(),
    truthMode: "observed"
  });
  return {
    notified: true,
    sockets: runtime.sockets.size,
    providers: providers.length,
    defaultProviders,
    clientId: cleanString(payload.clientId || payload.client_id)
  };
}

function turnHeartbeatPayload(state) {
  return {
    type: "turn_heartbeat",
    turnId: state.turnId,
    status: state.turnRecord.status,
    activeAgeMs: Math.max(0, Date.now() - (state.startedAtMs || Date.now())),
    activeForSeconds: Math.max(0, Math.round((Date.now() - (state.startedAtMs || Date.now())) / 1000)),
    lastRuntimeEventAt: state.lastEventAt || state.turnRecord.updatedAt || state.turnRecord.createdAt || "",
    providerStatuses: providerRuntimeStatuses(state.turnRecord)
  };
}

function providerRuntimeStatuses(record) {
  return (record.responses || []).map((response) => ({
    provider: response.provider,
    label: response.label || response.provider,
    status: response.status,
    hasText: Boolean(cleanString(response.text)),
    hasError: Boolean(cleanString(response.error)),
    durationMs: response.durationMs ?? null
  }));
}

function singleLaneKey(provider) {
  if (provider?.id === "kimi") {
    if (provider.bridgeMode === "local-command") {
      return `kimi-local:${KIMI_LOCAL_COMMAND}`;
    }
    return `kimi:${KIMI_ZELLIJ_SESSION}:${KIMI_ZELLIJ_TAB}:${KIMI_ZELLIJ_PANE || "focused-pane"}`;
  }
  if (provider?.id === "cursor") {
    return `cursor-local:${provider.repoRoot || ""}`;
  }
  return "";
}

function enqueueProviderLane(runtime, laneKey, task) {
  const previous = runtime.providerLanes.get(laneKey) || Promise.resolve();
  const current = previous
    .catch(() => {})
    .then(task)
    .finally(() => {
      if (runtime.providerLanes.get(laneKey) === current) {
        runtime.providerLanes.delete(laneKey);
      }
    });
  runtime.providerLanes.set(laneKey, current);
  return current;
}

function emitProviderEvent(socket, payload, onProviderEvent) {
  if (typeof onProviderEvent === "function") {
    onProviderEvent(payload);
  }
  emit(socket, payload);
}

function parseJsonLines(buffer, chunk, onJson, onRemainder) {
  const combined = buffer + chunk;
  const lines = combined.split(/\r?\n/);
  const remainder = lines.pop() || "";
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      onJson(JSON.parse(line));
    } catch {
      onRemainder(line);
    }
  }
  return remainder;
}

function spawnJsonCommand({
  provider,
  command,
  args,
  cwd,
  stdin,
  socket,
  turnId,
  parseEvent,
  onProviderEvent,
  eventProvider = provider.id,
  eventLabel = provider.label,
  signal = null
}) {
  const startedAt = Date.now();
  let stdoutBuffer = "";
  let stderr = "";
  let text = "";
  let providerProcessError = "";
  let finished = false;

  const child = spawn(command, args, {
    cwd,
    env: process.env,
    stdio: ["pipe", "pipe", "pipe"]
  });

  const onAbort = () => {
    try { child.kill("SIGTERM"); } catch { /* already closed */ }
    done("error", { error: "stopped by user", aborted: true });
  };

  const done = (status, extra = {}) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    if (signal) signal.removeEventListener("abort", onAbort);
    emitProviderEvent(socket, {
      type: status === "error" ? "provider_error" : "provider_done",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      text,
      durationMs: Date.now() - startedAt,
      stderr: stderr.slice(-4000),
      ...extra
    }, onProviderEvent);
  };

  const timer = setTimeout(() => {
    try { child.kill("SIGTERM"); } catch { /* already closed */ }
    done("error", { error: `provider timeout after ${PROVIDER_TIMEOUT_MS}ms` });
  }, PROVIDER_TIMEOUT_MS);

  if (signal?.aborted) {
    onAbort();
    return child;
  }
  if (signal) signal.addEventListener("abort", onAbort, { once: true });

  emitProviderEvent(socket, {
    type: "provider_started",
    turnId,
    provider: eventProvider,
    label: eventLabel,
    sourceProvider: provider.id,
    meta: {
      transport: provider.transport || "",
      model: provider.model || "",
      sourceProvider: provider.id,
      truthMode: "observed-live-provider-process"
    }
  }, onProviderEvent);

  child.stdout.on("data", (data) => {
    stdoutBuffer = parseJsonLines(
      stdoutBuffer,
      data.toString(),
      (event) => {
        const eventError = cleanString(event?.message || event?.error?.message);
        if (eventError && (event?.type === "error" || event?.type === "turn.failed")) {
          providerProcessError = eventError;
        }
        const parsed = parseEvent(event);
        if (parsed?.delta) {
          text += parsed.delta;
          emitProviderEvent(socket, {
            type: "delta",
            turnId,
            provider: eventProvider,
            label: eventLabel,
            sourceProvider: provider.id,
            text: parsed.delta
          }, onProviderEvent);
        }
        if (parsed?.finalText && !text) {
          text = parsed.finalText;
        }
        if (parsed?.meta) {
          emitProviderEvent(socket, {
            type: "provider_meta",
            turnId,
            provider: eventProvider,
            label: eventLabel,
            sourceProvider: provider.id,
            meta: { ...parsed.meta, sourceProvider: provider.id }
          }, onProviderEvent);
        }
      },
      (line) => {
        text += `${line}\n`;
        emitProviderEvent(socket, {
          type: "delta",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          text: `${line}\n`
        }, onProviderEvent);
      }
    );
  });

  child.stderr.on("data", (data) => {
    stderr += data.toString();
  });

  child.on("close", (code) => {
    if (stdoutBuffer.trim()) {
      try {
        const parsed = parseEvent(JSON.parse(stdoutBuffer));
        if (parsed?.delta) {
          text += parsed.delta;
          emitProviderEvent(socket, {
            type: "delta",
            turnId,
            provider: eventProvider,
            label: eventLabel,
            sourceProvider: provider.id,
            text: parsed.delta
          }, onProviderEvent);
        }
        if (parsed?.finalText && !text) {
          text = parsed.finalText;
        }
      } catch {
        text += stdoutBuffer;
        emitProviderEvent(socket, {
          type: "delta",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          text: stdoutBuffer
        }, onProviderEvent);
      }
    }
    if (code === 0) {
      done("done", { exitCode: code });
    } else {
      done("error", { exitCode: code, error: stderr || providerProcessError || `${provider.label} exited ${code}` });
    }
  });

  child.on("error", (error) => {
    done("error", { error: error.message });
  });

  endChildStdin(child, stdin);
  return child;
}

function runClaude({ socket, turnId, provider, prompt, repoRoot, nativeSession, onProviderEvent, eventProvider, eventLabel, signal }) {
  const args = [
    "-p",
    "--output-format", "stream-json",
    "--include-partial-messages",
    "--permission-mode", "dontAsk",
    "--tools", "",
    "--strict-mcp-config",
    "--mcp-config", "{\"mcpServers\":{}}",
    "--model", provider.model || "sonnet"
  ];
  if (CLAUDE_SESSION_MODE === "resume" && nativeSession?.sessionId) {
    args.push(nativeSession.isNew ? "--session-id" : "--resume", nativeSession.sessionId);
  } else if (CLAUDE_SESSION_MODE !== "stateless") {
    args.push("--session-id", randomUUID());
  }
  args.push(prompt);

  return spawnJsonCommand({
    provider,
    command: "claude",
    args,
    cwd: repoRoot,
    stdin: "",
    socket,
    turnId,
    onProviderEvent,
    eventProvider,
    eventLabel,
    signal,
    parseEvent(event) {
      if (event?.type === "stream_event" && event.event?.type === "content_block_delta") {
        const delta = event.event?.delta?.text;
        return delta ? { delta } : null;
      }
      if (event?.type === "result") {
        return {
          finalText: cleanString(event.result),
          meta: {
            session_id: event.session_id,
            duration_ms: event.duration_ms,
            cost_usd: event.total_cost_usd,
            model_usage: event.modelUsage
          }
        };
      }
      if (event?.type === "system" && event.subtype === "init") {
        return {
          meta: {
            session_id: event.session_id,
            model: event.model,
            tools: event.tools || [],
            transport: "claude-code-stream-json"
          }
        };
      }
      return null;
    }
  });
}

function runCodex({ socket, turnId, provider, prompt, repoRoot, nativeSession, onProviderEvent, eventProvider, eventLabel, signal }) {
  const args = nativeSession?.threadId
    ? [
        "exec",
        "resume",
        "--json",
        "--strict-config",
        "-c", "sandbox_mode=\"read-only\"",
        nativeSession.threadId
      ]
    : ["exec", "--json", "-C", repoRoot, "--sandbox", "read-only"];
  if (provider.model) {
    args.push("--model", provider.model);
  }
  args.push("-");

  return spawnJsonCommand({
    provider,
    command: "codex",
    args,
    cwd: repoRoot,
    stdin: prompt,
    socket,
    turnId,
    onProviderEvent,
    eventProvider,
    eventLabel,
    signal,
    parseEvent(event) {
      if (event?.type === "item.completed" && event.item?.type === "agent_message") {
        const finalText = cleanString(event.item.text);
        return finalText ? { delta: finalText, finalText } : null;
      }
      if (event?.type === "turn.completed") {
        return {
          meta: {
            usage: event.usage,
            transport: "codex-exec-json"
          }
        };
      }
      if (event?.type === "thread.started") {
        return {
          meta: {
            thread_id: event.thread_id,
            transport: "codex-exec-json"
          }
        };
      }
      return null;
    }
  });
}

function runCursor({ socket, turnId, provider, prompt, repoRoot, nativeSession, onProviderEvent, eventProvider, eventLabel, signal }) {
  const args = [
    "--print",
    "--output-format", "stream-json",
    "--stream-partial-output",
    "--mode", "ask",
    "--trust",
    "--workspace", repoRoot
  ];
  if (provider.model) {
    args.push("--model", provider.model);
  }
  if (nativeSession?.sessionId && !nativeSession.isNew) {
    args.push("--resume", nativeSession.sessionId);
  }
  args.push(prompt);

  return spawnJsonCommand({
    provider,
    command: "cursor-agent",
    args,
    cwd: repoRoot,
    stdin: "",
    socket,
    turnId,
    onProviderEvent,
    eventProvider,
    eventLabel,
    signal,
    parseEvent(event) {
      if (event?.type === "assistant") {
        const text = Array.isArray(event.message?.content)
          ? event.message.content.map((part) => cleanString(part.text)).join("")
          : "";
        if (text && event.timestamp_ms) {
          return { delta: text };
        }
        if (text) {
          return { finalText: text };
        }
      }
      if (event?.type === "result") {
        return {
          finalText: cleanString(event.result),
          meta: {
            session_id: event.session_id,
            request_id: event.request_id,
            duration_ms: event.duration_ms,
            duration_api_ms: event.duration_api_ms,
            usage: event.usage,
            transport: "cursor-agent-stream-json"
          }
        };
      }
      if (event?.type === "system" && event.subtype === "init") {
        return {
          meta: {
            session_id: event.session_id,
            model: event.model,
            apiKeySource: event.apiKeySource,
            permissionMode: event.permissionMode,
            transport: "cursor-agent-stream-json"
          }
        };
      }
      return null;
    }
  });
}

function runKimiLocalCommand({ socket, turnId, provider, prompt, repoRoot, onProviderEvent, eventProvider, eventLabel, signal }) {
  const commandText = [KIMI_LOCAL_COMMAND, KIMI_LOCAL_ARGS].filter(Boolean).join(" ").trim();
  return spawnJsonCommand({
    provider,
    command: "bash",
    args: ["-lc", commandText],
    cwd: repoRoot,
    stdin: prompt,
    socket,
    turnId,
    onProviderEvent,
    eventProvider,
    eventLabel,
    signal,
    parseEvent(event) {
      if (typeof event?.delta === "string") return { delta: event.delta };
      if (typeof event?.text === "string") return { delta: event.text };
      if (typeof event?.content === "string") return { delta: event.content };
      if (typeof event?.result === "string") return { finalText: event.result };
      if (event?.type === "result" && typeof event.result === "string") return { finalText: event.result };
      if (event?.type === "assistant") {
        const text = Array.isArray(event.message?.content)
          ? event.message.content.map((part) => cleanString(part.text)).join("")
          : typeof event.message?.content === "string"
            ? event.message.content
            : "";
        if (text && event.timestamp_ms) {
          return { delta: text };
        }
        if (text) {
          return { finalText: text };
        }
      }
      if (event?.type === "meta" || event?.type === "system") {
        return {
          meta: {
            ...event,
            transport: "kimi-local-command"
          }
        };
      }
      return null;
    }
  });
}

function runAgentPodCodex({ socket, turnId, provider, prompt, slug, onProviderEvent, eventProvider, eventLabel, signal }) {
  const kind = cleanString(provider.agentKind || agentKindFromProviderId(provider.id), "codex");
  const sessionName = cleanString(provider.nativeSessionId || `agent-${slug}-${kind}`);
  const podName = sessionName.endsWith("-0") ? sessionName : `${sessionName}-0`;
  return spawnJsonCommand({
    provider,
    command: KUBECTL,
    args: [
      "-n", AGENT_NAMESPACE,
      "exec", "-i", podName,
      "-c", "agent",
      "--",
      "/home/agent/start-agent.sh",
      "exec",
      "--json",
      "--sandbox", "read-only",
      "-"
    ],
    cwd: process.cwd(),
    stdin: prompt,
    socket,
    turnId,
    onProviderEvent,
    eventProvider,
    eventLabel,
    signal,
    parseEvent(event) {
      if (event?.type === "item.completed" && event.item?.type === "agent_message") {
        const finalText = cleanString(event.item.text);
        return finalText ? { delta: finalText, finalText } : null;
      }
      if (event?.type === "turn.completed") {
        return {
          meta: {
            usage: event.usage,
            transport: "agent-pod-codex-exec-json",
            podName,
            agentKind: kind
          }
        };
      }
      if (event?.type === "thread.started") {
        return {
          meta: {
            thread_id: event.thread_id,
            transport: "agent-pod-codex-exec-json",
            podName,
            agentKind: kind
          }
        };
      }
      return null;
    }
  });
}

async function runXai({ socket, turnId, provider, prompt, history = [], onProviderEvent, eventProvider = provider.id, eventLabel = provider.label, signal }) {
  const startedAt = Date.now();
  let text = "";
  assertNotAborted(signal);
  emitProviderEvent(socket, {
    type: "provider_started",
    turnId,
    provider: eventProvider,
    label: eventLabel,
    sourceProvider: provider.id,
    meta: {
      transport: provider.transport || "",
      model: provider.model || "",
      sourceProvider: provider.id,
      truthMode: "observed-live-provider-process"
    }
  }, onProviderEvent);

  const messages = [
    {
      role: "system",
      content: "You are participating in a real-time multimodel work chat inside Beagle. Be concrete and concise."
    },
    ...history.slice(-10).map((item) => ({
      role: item.role === "assistant" ? "assistant" : "user",
      content: boundedText(item.text || item.content, 4000)
    })),
    { role: "user", content: prompt }
  ];

  let requestSignal = null;
  try {
    requestSignal = combinedSignal(signal, PROVIDER_TIMEOUT_MS, `provider timeout after ${PROVIDER_TIMEOUT_MS}ms`);
    const response = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${process.env.XAI_API_KEY}`
      },
      body: JSON.stringify({
        model: provider.model || XAI_MODEL,
        messages,
        stream: true
      }),
      signal: requestSignal.signal
    });

    if (!response.ok || !response.body) {
      throw new Error(`xAI HTTP ${response.status}: ${await response.text().catch(() => "")}`);
    }

    const decoder = new TextDecoder();
    let buffer = "";
    for await (const chunk of response.body) {
      assertNotAborted(signal);
      buffer += decoder.decode(chunk, { stream: true });
      const frames = buffer.split("\n\n");
      buffer = frames.pop() || "";
      for (const frame of frames) {
        const line = frame.split(/\r?\n/).find((item) => item.startsWith("data:"));
        if (!line) continue;
        const payload = line.replace(/^data:\s*/, "");
        if (payload === "[DONE]") continue;
        const event = JSON.parse(payload);
        const delta = event?.choices?.[0]?.delta?.content || "";
        if (delta) {
          text += delta;
          emitProviderEvent(socket, {
            type: "delta",
            turnId,
            provider: eventProvider,
            label: eventLabel,
            sourceProvider: provider.id,
            text: delta
          }, onProviderEvent);
        }
      }
    }

    emitProviderEvent(socket, {
      type: "provider_done",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      text,
      durationMs: Date.now() - startedAt
    }, onProviderEvent);
  } catch (error) {
    const stopped = signal?.aborted && isAbortError(error);
    const message = stopped ? "stopped by user" : error.message;
    emitProviderEvent(socket, {
      type: "provider_error",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      text,
      error: message,
      aborted: stopped,
      durationMs: Date.now() - startedAt
    }, onProviderEvent);
  } finally {
    requestSignal?.cleanup();
  }
}

function kimiSshArgs(extraArgs = []) {
  return [
    "-4",
    "-F", "/dev/null",
    "-o", `UserKnownHostsFile=${KIMI_ZELLIJ_KNOWN_HOSTS}`,
    "-o", "StrictHostKeyChecking=accept-new",
    "-i", KIMI_ZELLIJ_SSH_KEY,
    "-p", KIMI_ZELLIJ_SSH_PORT,
    KIMI_ZELLIJ_SSH_HOST,
    "bash",
    "-s",
    "--",
    ...extraArgs
  ];
}

function kimiRemoteScript(body) {
  const focusPane = KIMI_ZELLIJ_PANE
    ? `zellij action focus-pane-id ${JSON.stringify(KIMI_ZELLIJ_PANE)} >/dev/null 2>&1 || true`
    : ":";
  return [
    "set -euo pipefail",
    "export HOME=/workspace/.home/openvscode-server",
    "export USER=openvscode-server",
    "export LOGNAME=openvscode-server",
    "export SHELL=/usr/bin/zsh",
    "export XDG_CONFIG_HOME=\"$HOME/.config\"",
    "export XDG_DATA_HOME=\"$HOME/.local/share\"",
    "export PATH=\"$HOME/bin:$HOME/.local/node-v20.20.2-linux-x64/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"",
    `export ZELLIJ_SESSION_NAME=${JSON.stringify(KIMI_ZELLIJ_SESSION)}`,
    `zellij action go-to-tab-name ${JSON.stringify(KIMI_ZELLIJ_TAB)} >/dev/null 2>&1 || true`,
    focusPane,
    body
  ].join("\n");
}

async function dumpKimiScreen(signal) {
  assertNotAborted(signal);
  const paneArg = KIMI_ZELLIJ_PANE ? ` -p ${JSON.stringify(KIMI_ZELLIJ_PANE)}` : "";
  const result = await runCommandCapture("ssh", kimiSshArgs(), {
    stdin: kimiRemoteScript(`zellij action dump-screen --full${paneArg} || true`),
    timeoutMs: 12000,
    signal
  });
  assertNotAborted(signal);
  if (result.code !== 0) {
    throw new Error(result.stderr || `ssh exited ${result.code}`);
  }
  return result.stdout || "";
}

async function sendKimiPrompt(prompt, signal) {
  assertNotAborted(signal);
  const encoded = Buffer.from(prompt, "utf8").toString("base64");
  const paneArg = KIMI_ZELLIJ_PANE ? ` -p ${JSON.stringify(KIMI_ZELLIJ_PANE)}` : "";
  const script = kimiRemoteScript([
    "prompt=$(printf '%s' \"$1\" | base64 -d)",
    `zellij action write-chars${paneArg} "$prompt"`,
    `zellij action send-keys${paneArg} Enter`
  ].join("\n"));
  const result = await runCommandCapture("ssh", kimiSshArgs([encoded]), {
    stdin: script,
    timeoutMs: 12000,
    signal
  });
  assertNotAborted(signal);
  if (result.code !== 0) {
    throw new Error(result.stderr || `ssh exited ${result.code}`);
  }
}

function extractScreenDelta(before, after) {
  if (!after) return "";
  if (before && after.startsWith(before)) {
    return after.slice(before.length);
  }
  const tail = before ? before.slice(-2000) : "";
  const tailIndex = tail ? after.indexOf(tail) : -1;
  if (tailIndex >= 0) {
    return after.slice(tailIndex + tail.length);
  }
  return after;
}

function cleanKimiScreenText(text, marker) {
  let normalized = cleanString(text)
    .replace(/\r/g, "")
    .replace(/\n{3,}/g, "\n\n");
  const inputDivider = normalized.search(/\n?── input ─+/);
  if (inputDivider >= 0) {
    normalized = normalized.slice(0, inputDivider).trim();
  }
  const bulletIndex = normalized.lastIndexOf("\n• ");
  if (bulletIndex >= 0) {
    return normalized.slice(bulletIndex + 3).trim();
  }
  if (normalized.startsWith("• ")) {
    return normalized.slice(2).trim();
  }
  if (!marker) return normalized;
  const markerIndex = normalized.indexOf(marker);
  return markerIndex >= 0 ? normalized.slice(markerIndex + marker.length).trim() : normalized;
}

async function runKimiZellij({ socket, turnId, provider, prompt, onProviderEvent, eventProvider = provider.id, eventLabel = provider.label, signal }) {
  const startedAt = Date.now();
  const marker = `BEAGLE_TURN_${turnId}`;
  let text = "";
  let stablePolls = 0;
  assertNotAborted(signal);
  emitProviderEvent(socket, {
    type: "provider_started",
    turnId,
    provider: eventProvider,
    label: eventLabel,
    sourceProvider: provider.id,
    meta: {
      transport: provider.transport || "",
      model: provider.model || "",
      sourceProvider: provider.id,
      truthMode: "observed-live-provider-process"
    }
  }, onProviderEvent);

  try {
    const before = await dumpKimiScreen(signal);
    const kimiPrompt = [
      `[${marker}]`,
      "Beagle multimodel chat message. Answer in chat only. Do not edit files or run commands.",
      "Keep the answer concise unless the user explicitly asks for a plan.",
      prompt
    ].join("\n\n");
    await sendKimiPrompt(kimiPrompt, signal);

    const maxPolls = Math.max(4, Math.floor(PROVIDER_TIMEOUT_MS / 2500));
    for (let index = 0; index < maxPolls; index += 1) {
      await wait(2500, signal);
      const screen = await dumpKimiScreen(signal);
      const nextText = cleanKimiScreenText(extractScreenDelta(before, screen), marker);
      if (nextText && nextText !== text) {
        const previousText = text;
        const deltaText = textAfterStablePrefix(previousText, nextText) || nextText;
        text = nextText;
        stablePolls = 0;
        emitProviderEvent(socket, {
          type: "delta",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          text: deltaText
        }, onProviderEvent);
      } else if (text) {
        stablePolls += 1;
      }
      if (text && stablePolls >= 3) break;
    }

    if (!text) {
      throw new Error("Kimi zellij pane did not produce captured text before timeout");
    }

    emitProviderEvent(socket, {
      type: "provider_done",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      text,
      durationMs: Date.now() - startedAt,
      meta: {
        session_id: `${KIMI_ZELLIJ_SESSION}:${KIMI_ZELLIJ_TAB}`,
        pane_id: KIMI_ZELLIJ_PANE || "focused-pane",
        transport: "zellij-screen-poll",
        model: provider.model
      }
    }, onProviderEvent);
  } catch (error) {
    const stopped = signal?.aborted && isAbortError(error);
    emitProviderEvent(socket, {
      type: "provider_error",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      text,
      error: stopped ? "stopped by user" : error.message,
      aborted: stopped,
      durationMs: Date.now() - startedAt
    }, onProviderEvent);
  }
}

function mcpInboxConfig(providerId) {
  return MCP_INBOX_PROVIDERS.find((provider) => provider.id === providerId) || null;
}

function recordThreadId(record) {
  return cleanString(
    record.conversation_id ||
      record.session_id ||
      record.metadata?.agent_message?.thread_id ||
      record.metadata?.agent_message_complete?.thread_id ||
      record.metadata?.agent_message_ack?.thread_id
  );
}

function recordClientAliases(record) {
  return [
    record.source,
    record.provider,
    record.client_id,
    record.metadata?.agent_message?.from_client,
    record.metadata?.agent_message_complete?.client_id,
    record.metadata?.agent_message_ack?.client_id
  ].map(normalizedId).filter(Boolean);
}

function extractContextReplyText(record) {
  const text = cleanString(record.text || record.content);
  const match = text.match(/\n\n([\s\S]+)$/);
  return cleanString(match?.[1] || text);
}

async function findMcpInboxReply({ slug, targetClient, aliases, threadId, sentAt, messageId }) {
  const records = await readWorkbenchContextRecords(slug);
  return findMcpInboxReplyInRecords({ records, targetClient, aliases, threadId, sentAt, messageId });
}

async function sendMcpInboxMessage({ slug, provider, turnId, prompt, history, signal }) {
  const config = mcpInboxConfig(provider.id);
  if (!config) throw new Error(`${provider.label} is not a Workbench Context inbox provider`);
  assertNotAborted(signal);
  const threadId = `multimodel:${slug}:${turnId}`;
  const messageId = `${turnId}:${provider.id}:handoff`.replace(/[^a-zA-Z0-9:_-]/g, "_");
  const recent = Array.isArray(history) && history.length
    ? history.slice(-8).map((item) => `${cleanString(item.role || item.provider || "message")}: ${boundedText(item.text || item.content, 2000)}`).join("\n\n")
    : "";
  const content = [
    `Project: ${slug}`,
    `Thread: ${threadId}`,
    `Message ID: ${messageId}`,
    `Reply tool (HTTP MCP): workbench_context_reply`,
    `Reply tool (stdio proxy): cockpit_workbench_context_reply`,
    `Reply args: {"message_id":"${messageId}","client_id":"${config.targetClient}","text":"<your response>"}`,
    `Reply endpoint: /api/workbench/${slug}/context/messages/${encodeURIComponent(messageId)}/reply`,
    "You are being called as a subscription client through Beagle Workbench Context, not through an API.",
    "Read this packet in your MCP/inbox client and reply with workbench_context_reply, or cockpit_workbench_context_reply if your client is connected through the stdio proxy. That writes your response into this thread and closes the handoff.",
    "Do not fabricate execution. If you cannot inspect something, say that directly.",
    recent ? `Recent multimodel context:\n${recent}` : "",
    `Current user message:\n${prompt}`
  ].filter(Boolean).join("\n\n");

  const requestSignal = combinedSignal(signal, 10000, "Workbench Context send timed out after 10000ms");
  let response;
  try {
    response = await fetch(`${COCKPIT_LOOPBACK}/api/workbench/${encodeURIComponent(slug)}/context/messages/send`, {
      method: "POST",
      headers: internalContextHeaders(),
      body: JSON.stringify({
        from_client: "project-cockpit-multimodel",
        to_client: config.targetClient,
        subject: "multimodel realtime inbox turn",
        priority: "normal",
        thread_id: threadId,
        message_id: messageId,
        requires_response: true,
        tags: ["multimodel-chat", "mcp-inbox", provider.id, config.targetClient],
        metadata: {
          turnId,
          providerId: provider.id,
          targetClient: config.targetClient,
          reply_tool: "workbench_context_reply",
          reply_tool_stdio_proxy: "cockpit_workbench_context_reply",
          reply_endpoint: `/api/workbench/${slug}/context/messages/${encodeURIComponent(messageId)}/reply`,
          truthMode: "awaiting-subscription-client"
        },
        content
      }),
      signal: requestSignal.signal
    });
  } finally {
    requestSignal.cleanup();
  }
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload?.error || `Workbench Context send failed: HTTP ${response.status}`);
  }
  return {
    config,
    threadId,
    messageId,
    sentAt: payload?.message?.sent_at || payload?.generatedAt || new Date().toISOString(),
    payload
  };
}

async function cancelMcpInboxHandoff({ slug, messageId, providerId, reason = "stopped by user", clientId = "project-cockpit-multimodel", metadata = {} }) {
  const id = cleanString(messageId);
  if (!id) return null;
  const actor = cleanString(clientId, "project-cockpit-multimodel");
  try {
    const response = await fetch(`${COCKPIT_LOOPBACK}/api/workbench/${encodeURIComponent(slug)}/context/messages/${encodeURIComponent(id)}/cancel`, {
      method: "POST",
      headers: internalContextHeaders(),
      body: JSON.stringify({
        client_id: actor,
        provider: actor,
        reason,
        metadata: {
          ...(metadata && typeof metadata === "object" ? metadata : {}),
          providerId: cleanString(providerId),
          truthMode: "multimodel-turn-cancel"
        }
      }),
      signal: AbortSignal.timeout(10000)
    });
    return await response.json().catch(() => ({}));
  } catch {
    return null;
  }
}

async function completeMcpInboxHandoff({ slug, messageId, providerId, result, reply, clientId = "project-cockpit-multimodel" }) {
  const id = cleanString(messageId);
  if (!id) return null;
  const actor = cleanString(clientId, "project-cockpit-multimodel");
  try {
    const response = await fetch(`${COCKPIT_LOOPBACK}/api/workbench/${encodeURIComponent(slug)}/context/messages/${encodeURIComponent(id)}/complete`, {
      method: "POST",
      headers: internalContextHeaders(),
      body: JSON.stringify({
        client_id: actor,
        provider: actor,
        result: boundedText(result, 4000),
        artifact_refs: [
          cleanString(reply?.memory_id),
          cleanString(reply?.external_id)
        ].filter(Boolean),
        metadata: {
          providerId: cleanString(providerId),
          reply_memory_id: cleanString(reply?.memory_id),
          reply_source: cleanString(reply?.source),
          reply_client_id: cleanString(reply?.client_id),
          suppress_realtime_notify: true,
          truthMode: "observed-subscription-client-reply"
        }
      }),
      signal: AbortSignal.timeout(10000)
    });
    return await response.json().catch(() => ({}));
  } catch {
    return null;
  }
}

async function replyToMcpInboxHandoff(slug, messageId, body = {}) {
  const id = cleanString(messageId || body.message_id || body.messageId);
  if (!id) {
    const error = new Error("message_id is required");
    error.statusCode = 400;
    throw error;
  }
  const text = boundedText(body.text || body.reply || body.response || body.result || body.content);
  if (!text) {
    const error = new Error("reply text is required");
    error.statusCode = 400;
    throw error;
  }
  const records = await readWorkbenchContextRecords(slug);
  const handoffRecord = findMcpHandoffRecord(records, id);
  if (!handoffRecord) {
    const error = new Error(`MCP inbox handoff not found: ${id}`);
    error.statusCode = 404;
    throw error;
  }
  const meta = handoffRecord.metadata?.agent_message || {};
  const threadId = cleanString(meta.thread_id || handoffRecord.session_id);
  const clientId = cleanString(body.client_id || body.clientId || body.source || meta.to_client, "subscription-client");
  const providerId = cleanString(body.provider_id || body.providerId || handoffRecord.metadata?.providerId || (handoffRecord.tags || []).find((tag) => tag.endsWith("-mcp")));
  const externalId = cleanString(body.external_id || body.externalId) ||
    `${id}:reply:${clientId}:${Date.now()}`.replace(/[^a-zA-Z0-9:_-]/g, "_");

  const ingestResponse = await fetch(`${COCKPIT_LOOPBACK}/api/workbench/${encodeURIComponent(slug)}/context/ingest`, {
    method: "POST",
    headers: internalContextHeaders(),
    body: JSON.stringify({
      source: clientId,
      provider: cleanString(body.provider || clientId),
      client_id: clientId,
      session_id: threadId,
      conversation_id: threadId,
      request_id: cleanString(body.request_id || body.requestId || id),
      tags: ["multimodel-chat", "mcp-inbox", "subscription-client-reply", clientId, providerId].filter(Boolean),
      metadata: {
        ...(body.metadata && typeof body.metadata === "object" ? body.metadata : {}),
        domain: "beagle-workbench-multimodel",
        reply_to_message_id: id,
        providerId,
        targetClient: clientId,
        truthMode: "observed-subscription-client-reply"
      },
      turns: [{
        role: "assistant",
        external_id: externalId,
        text
      }]
    }),
    signal: AbortSignal.timeout(10000)
  });
  const ingest = await ingestResponse.json().catch(() => ({}));
  if (!ingestResponse.ok) {
    const error = new Error(ingest?.error || `Workbench Context ingest failed: HTTP ${ingestResponse.status}`);
    error.statusCode = ingestResponse.status;
    throw error;
  }

  const reply = {
    memory_id: ingest.memory_ids?.[0] || "",
    external_id: externalId,
    source: clientId,
    client_id: clientId
  };
  const complete = await completeMcpInboxHandoff({
    slug,
    messageId: id,
    providerId,
    result: text,
    reply,
    clientId
  });
  const latest = buildMcpInboxStatusFromRecords(slug, await readWorkbenchContextRecords(slug), { limit: 8 })
    .providers
    .flatMap((provider) => provider.messages || [])
    .find((message) => message.message_id === id) || null;

  const result = {
    schema: "beagle.multimodel-mcp-inbox-reply.v1",
    status: "ok",
    projectSlug: slug,
    message_id: id,
    client_id: clientId,
    provider_id: providerId,
    thread_id: threadId,
    text,
    reply,
    ingest,
    complete,
    latest,
    generatedAt: new Date().toISOString(),
    truthMode: "observed"
  };
  const realtime = await notifyMultimodelContextMessage({ slug, messageId: id, kind: "reply", result });
  return {
    ...result,
    realtime: {
      ...(realtime || {}),
      truthMode: "observed"
    }
  };
}

async function runMcpInboxProvider({ socket, turnId, provider, prompt, history, slug, onProviderEvent, eventProvider = provider.id, eventLabel = provider.label, signal }) {
  const startedAt = Date.now();
  let text = "";
  assertNotAborted(signal);
  emitProviderEvent(socket, {
    type: "provider_started",
    turnId,
    provider: eventProvider,
    label: eventLabel,
    sourceProvider: provider.id,
    meta: {
      transport: provider.transport || "",
      model: provider.model || "",
      sourceProvider: provider.id,
      truthMode: "observed-live-provider-process"
    }
  }, onProviderEvent);

  try {
    const handoff = await sendMcpInboxMessage({ slug, provider, turnId, prompt, history, signal });
    emitProviderEvent(socket, {
      type: "provider_meta",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      meta: {
        transport: "workbench-context-mcp-inbox",
        message_id: handoff.messageId,
        thread_id: handoff.threadId,
        targetClient: handoff.config.targetClient,
        state: "awaiting-client-context-write"
      }
    }, onProviderEvent);

    const started = Date.now();
    let lastLifecycleSignature = "";
    while (Date.now() - started < MCP_INBOX_TIMEOUT_MS) {
      await wait(2000, signal);
      const handoffState = await inspectMcpInboxHandoff({ slug, handoff });
      const lifecycleSignature = JSON.stringify(handoffState.meta);
      if (lifecycleSignature !== lastLifecycleSignature) {
        lastLifecycleSignature = lifecycleSignature;
        emitProviderEvent(socket, {
          type: "provider_meta",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          meta: handoffState.meta
        }, onProviderEvent);
      }

      if (handoffState.state.status === "canceled") {
        throw new Error(handoffState.state.cancel_reason || `${provider.label} handoff was canceled`);
      }

      const completedText = cleanString(handoffState.completion?.result);
      if (handoffState.state.status === "completed" && completedText) {
        text = completedText;
        emitProviderEvent(socket, {
          type: "delta",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          text
        }, onProviderEvent);
        emitProviderEvent(socket, {
          type: "provider_done",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          text,
          durationMs: Date.now() - startedAt,
          meta: {
            ...handoffState.meta,
            completed_by: handoffState.completion.client_id,
            completed_at: handoffState.completion.completed_at,
            completion_memory_id: handoffState.completion.memory_id,
            reply_memory_id: handoffState.reply?.memory_id,
            reply_client_id: handoffState.reply?.client_id,
            reply_source: handoffState.reply?.source
          }
        }, onProviderEvent);
        return;
      }

      const reply = handoffState.reply;
      if (reply) {
        text = extractContextReplyText(reply);
        void completeMcpInboxHandoff({
          slug,
          messageId: handoff.messageId,
          providerId: provider.id,
          result: text,
          reply,
          clientId: reply.client_id || reply.source || handoff.config.targetClient
        });
        emitProviderEvent(socket, {
          type: "delta",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          text
        }, onProviderEvent);
        emitProviderEvent(socket, {
          type: "provider_done",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          text,
          durationMs: Date.now() - startedAt,
          meta: {
            ...handoffState.meta,
            message_id: handoff.messageId,
            thread_id: handoff.threadId,
            reply_memory_id: reply.memory_id,
            reply_client_id: reply.client_id,
            reply_source: reply.source,
            targetClient: handoff.config.targetClient
          }
        }, onProviderEvent);
        return;
      }
    }

    throw new Error(`${provider.label} did not write a Workbench Context reply within ${MCP_INBOX_TIMEOUT_MS}ms`);
  } catch (error) {
    const stopped = signal?.aborted && isAbortError(error);
    emitProviderEvent(socket, {
      type: "provider_error",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      text,
      error: stopped ? "stopped by user" : error.message,
      aborted: stopped,
      durationMs: Date.now() - startedAt
    }, onProviderEvent);
  }
}

async function waitForAgentTerminalReady({ slug, kind, signal, onSnapshot }) {
  const started = Date.now();
  let snapshot = ensureAgentTerminalSession(slug, kind, { tailBytes: 4000 });
  let lastOutputAt = cleanString(snapshot.lastOutputAt);
  let quietSince = lastOutputAt ? Date.parse(lastOutputAt) : Date.now();
  while (Date.now() - started < AGENT_TERMINAL_PROVIDER_READY_TIMEOUT_MS) {
    await wait(250, signal);
    snapshot = agentTerminalSnapshot(slug, kind, { tailBytes: 4000 });
    if (typeof onSnapshot === "function") onSnapshot(snapshot);
    const nextLastOutputAt = cleanString(snapshot.lastOutputAt);
    if (nextLastOutputAt && nextLastOutputAt !== lastOutputAt) {
      lastOutputAt = nextLastOutputAt;
      quietSince = Date.parse(nextLastOutputAt) || Date.now();
      continue;
    }
    if (Date.now() - quietSince >= AGENT_TERMINAL_PROVIDER_READY_IDLE_MS) {
      return snapshot;
    }
  }
  return snapshot;
}

function terminalTurnFrame(turnId) {
  return `BEAGLE_DONE_${cleanString(turnId).replace(/[^a-zA-Z0-9]/g, "").slice(0, 18)}_${Date.now().toString(36)}`;
}

function buildAgentTerminalPrompt(message, frame) {
  const compactMessage = boundedText(message, 8000).replace(/\s+/g, " ").trim();
  return `${compactMessage} Beagle Workbench bridge instruction: when your answer is complete, print this exact line on its own final line: ${frame}`;
}

function cleanAgentTerminalResponse(text, frame) {
  const raw = String(text || "");
  const parts = raw.split(frame);
  const body = parts.length >= 3
    ? parts.slice(1, -1).join(frame)
    : (parts.length === 2 ? parts[0] : raw);
  return body
    .replace(/\bBeagle\s*Workbench\s*bridge\s*instruction:[\s\S]*$/i, "")
    .replace(/\bBeagleWorkbenchbridgeinstruction:[\s\S]*$/i, "")
    .replace(/\bWorking\([^)]*\)/gi, "")
    .replace(/^›\s*Implement \{feature\}.*$/gmi, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function compactForEchoCompare(value = "") {
  return cleanString(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

function isEchoOnlyAgentTerminalResponse(text = "", originalMessage = "") {
  const cleaned = cleanString(text);
  const compactText = compactForEchoCompare(cleaned);
  const compactOriginal = compactForEchoCompare(originalMessage).slice(0, 220);
  return Boolean(
    !cleaned ||
      /(^|\n)\s*❯\s*/.test(cleaned) ||
      /reply\s+with\s+exactly\s+this\s+marker/i.test(cleaned) ||
      (compactOriginal.length >= 24 && compactText.includes(compactOriginal))
  );
}

async function runAgentTerminalProvider({ socket, turnId, provider, message, prompt, slug, onProviderEvent, eventProvider = provider.id, eventLabel = provider.label, signal }) {
  const startedAt = Date.now();
  const kind = cleanString(provider.agentKind || agentKindFromProviderId(provider.id));
  let text = "";
  assertNotAborted(signal);
  emitProviderEvent(socket, {
    type: "provider_started",
    turnId,
    provider: eventProvider,
    label: eventLabel,
    sourceProvider: provider.id,
    meta: {
      transport: provider.transport || "shared-agent-pty",
      model: provider.model || "",
      sourceProvider: provider.id,
      truthMode: "observed-live-provider-process"
    }
  }, onProviderEvent);

  try {
    emitProviderEvent(socket, {
      type: "provider_meta",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      meta: {
        transport: "shared-agent-pty",
        agentKind: kind,
        state: "waiting-for-terminal-ready"
      }
    }, onProviderEvent);
    const ready = await waitForAgentTerminalReady({
      slug,
      kind,
      signal,
      onSnapshot: (snapshot) => {
        emitProviderEvent(socket, {
          type: "provider_meta",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          meta: {
            transport: "shared-agent-pty",
            agentKind: kind,
            podName: snapshot.podName,
            attachedSockets: snapshot.attachedSockets,
            lastOutputAt: snapshot.lastOutputAt,
            state: "waiting-for-terminal-ready"
          }
        }, onProviderEvent);
      }
    });
    const before = ready || agentTerminalSnapshot(slug, kind, { tailBytes: 4000 });
    const frame = terminalTurnFrame(turnId);
    const terminalPrompt = buildAgentTerminalPrompt(message || prompt, frame);
    const input = writeAgentTerminalInput(slug, kind, {
      data: `\u0015${terminalPrompt}`
    });
    await wait(350, signal);
    const submit = writeAgentTerminalInput(slug, kind, {
      data: "\r"
    });
    const terminalInput = submit;
    emitProviderEvent(socket, {
      type: "provider_meta",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      meta: {
        transport: "shared-agent-pty",
        agentKind: kind,
        podName: submit.podName || input.podName,
        bytes: input.bytes + submit.bytes,
        attachedSockets: submit.attachedSockets,
        lastInputAt: submit.lastInputAt,
        frame,
        state: "sent-framed-turn-to-terminal"
      }
    }, onProviderEvent);

    const started = Date.now();
    let lastSignature = "";
    let lastDeltaAt = 0;
    let latestSnapshot = null;
    let bestCandidate = "";
    const beforePlainTail = before.plainTail || "";
    const requiredFrameCount = countOccurrences(beforePlainTail, frame) + 1;
    while (Date.now() - started < AGENT_TERMINAL_PROVIDER_TIMEOUT_MS) {
      await wait(250, signal);
      const snapshot = agentTerminalSnapshot(slug, kind, { tailBytes: 4000 });
      latestSnapshot = snapshot;
      const signature = JSON.stringify({
        lastOutputAt: snapshot.lastOutputAt,
        tailBytes: snapshot.tailBytes,
        plainTail: snapshot.plainTail
      });
      if (signature !== lastSignature) {
        lastSignature = signature;
        emitProviderEvent(socket, {
          type: "provider_meta",
          turnId,
          provider: eventProvider,
          label: eventLabel,
          sourceProvider: provider.id,
          meta: {
            transport: "shared-agent-pty",
            agentKind: kind,
            podName: snapshot.podName,
            attachedSockets: snapshot.attachedSockets,
            lastInputAt: snapshot.lastInputAt,
            lastOutputAt: snapshot.lastOutputAt,
            frame,
            state: "terminal-output-observed"
          }
        }, onProviderEvent);
      }
      const changed = snapshot.plainTail && snapshot.plainTail !== beforePlainTail;
      const outputAfterInput = snapshot.lastOutputAt && terminalInput.lastInputAt
        ? Date.parse(snapshot.lastOutputAt) >= Date.parse(terminalInput.lastInputAt)
        : changed;
      if (changed && outputAfterInput) {
        const candidate = textAfterStablePrefix(beforePlainTail, snapshot.plainTail);
        if (candidate && candidate !== bestCandidate) {
          bestCandidate = candidate;
          lastDeltaAt = Date.now();
          emitProviderEvent(socket, {
            type: "provider_meta",
            turnId,
            provider: eventProvider,
            label: eventLabel,
            sourceProvider: provider.id,
            meta: {
              transport: "shared-agent-pty",
              agentKind: kind,
              podName: snapshot.podName,
              frame,
              observedChars: bestCandidate.length,
              observedFrameCount: countOccurrences(snapshot.plainTail, frame),
              state: "terminal-framed-output-observed"
            }
          }, onProviderEvent);
        }
        const candidateLooksLikePromptEcho = /Beagle\s*Workbench\s*bridge\s*instruction/i.test(candidate)
          || /BeagleWorkbenchbridgeinstruction/i.test(candidate.replace(/\s+/g, ""));
        const effectiveRequiredFrameCount = requiredFrameCount + (candidateLooksLikePromptEcho ? 1 : 0);
        if (
          countOccurrences(snapshot.plainTail, frame) >= effectiveRequiredFrameCount
          && lastDeltaAt
          && Date.now() - lastDeltaAt >= AGENT_TERMINAL_PROVIDER_IDLE_MS
        ) {
          const cleanedText = cleanAgentTerminalResponse(bestCandidate || snapshot.plainTail, frame);
          if (isEchoOnlyAgentTerminalResponse(cleanedText, message || prompt)) {
            continue;
          }
          text = cleanedText;
          if (!text) {
            throw new Error(`${provider.label} completed the framed terminal turn but produced no readable answer`);
          }
          emitProviderEvent(socket, {
            type: "delta",
            turnId,
            provider: eventProvider,
            label: eventLabel,
            sourceProvider: provider.id,
            text
          }, onProviderEvent);
          emitProviderEvent(socket, {
            type: "provider_done",
            turnId,
            provider: eventProvider,
            label: eventLabel,
            sourceProvider: provider.id,
            text,
            durationMs: Date.now() - startedAt,
            meta: {
              transport: "shared-agent-pty",
              agentKind: kind,
              podName: snapshot.podName,
              attachedSockets: snapshot.attachedSockets,
              lastInputAt: terminalInput.lastInputAt || snapshot.lastInputAt,
              lastOutputAt: snapshot.lastOutputAt,
              idleMs: Date.now() - lastDeltaAt,
              frame,
              state: "terminal-framed-turn-complete"
            }
          }, onProviderEvent);
          return;
        }
      }
    }
    const snapshot = latestSnapshot || agentTerminalSnapshot(slug, kind, { tailBytes: 4000 });
    throw new Error(`${provider.label} did not complete framed terminal turn ${frame} within ${AGENT_TERMINAL_PROVIDER_TIMEOUT_MS}ms; observed ${bestCandidate.length} chars, frame count ${countOccurrences(snapshot.plainTail || "", frame)}/${requiredFrameCount}`);
  } catch (error) {
    const stopped = signal?.aborted && isAbortError(error);
    emitProviderEvent(socket, {
      type: "provider_error",
      turnId,
      provider: eventProvider,
      label: eventLabel,
      sourceProvider: provider.id,
      text,
      error: stopped ? "stopped by user" : error.message,
      aborted: stopped,
      durationMs: Date.now() - startedAt
    }, onProviderEvent);
  }
}

function runProvider({ socket, turnId, provider, message, prompt, history, repoRoot, nativeSession, onProviderEvent, eventProvider, eventLabel, slug, signal }) {
  if (provider.id === "claude") {
    return runClaude({ socket, turnId, provider, prompt, repoRoot, nativeSession, onProviderEvent, eventProvider, eventLabel, signal });
  }
  if (provider.id === "codex") {
    return runCodex({ socket, turnId, provider, prompt, repoRoot, nativeSession, onProviderEvent, eventProvider, eventLabel, signal });
  }
  if (provider.id === "cursor") {
    return runCursor({ socket, turnId, provider, prompt, repoRoot, nativeSession, onProviderEvent, eventProvider, eventLabel, signal });
  }
  if (provider.id === "grok") {
    return runXai({ socket, turnId, provider, prompt, history, onProviderEvent, eventProvider, eventLabel, signal });
  }
  if (provider.id === "kimi") {
    if (provider.bridgeMode === "local-command" || provider.transport === "local-subscription-cli") {
      return runKimiLocalCommand({ socket, turnId, provider, prompt, repoRoot, onProviderEvent, eventProvider, eventLabel, signal });
    }
    return runKimiZellij({ socket, turnId, provider, prompt, onProviderEvent, eventProvider, eventLabel, signal });
  }
  if (mcpInboxConfig(provider.id)) {
    return runMcpInboxProvider({ socket, turnId, provider, prompt, history, slug, onProviderEvent, eventProvider, eventLabel, signal });
  }
  if (isAgentTerminalProviderId(provider.id)) {
    const kind = cleanString(provider.agentKind || agentKindFromProviderId(provider.id));
    const terminalEventProvider = eventProvider || provider.id;
    const terminalEventLabel = eventLabel || provider.label;
    if (kind === "desktop-claude") {
      return runClaude({ socket, turnId, provider: { ...provider, id: "claude", model: provider.model || "sonnet" }, prompt, repoRoot, nativeSession: null, onProviderEvent, eventProvider: terminalEventProvider, eventLabel: terminalEventLabel, signal });
    }
    if (kind === "desktop-codex") {
      return runCodex({ socket, turnId, provider: { ...provider, id: "codex" }, prompt, repoRoot, nativeSession: null, onProviderEvent, eventProvider: terminalEventProvider, eventLabel: terminalEventLabel, signal });
    }
    if (kind === "desktop-cursor") {
      return runCursor({ socket, turnId, provider: { ...provider, id: "cursor" }, prompt, repoRoot, nativeSession: null, onProviderEvent, eventProvider: terminalEventProvider, eventLabel: terminalEventLabel, signal });
    }
    if (kind === "codex") {
      return runAgentPodCodex({ socket, turnId, provider, prompt, slug, onProviderEvent, eventProvider, eventLabel, signal });
    }
    return runAgentTerminalProvider({ socket, turnId, provider, message, prompt, slug, onProviderEvent, eventProvider, eventLabel, signal });
  }
  emitProviderEvent(socket, {
    type: "provider_error",
    turnId,
    provider: eventProvider || provider.id,
    label: eventLabel || provider.label,
    sourceProvider: provider.id,
    error: provider.reason || "provider is not wired"
  }, onProviderEvent);
  return null;
}

function initialTurnRecord({ slug, turnId, text, selected, prompt }) {
  const now = new Date().toISOString();
  return {
    schema: "beagle.multimodel-chat-turn.v1",
    projectSlug: slug,
    turnId,
    createdAt: now,
    updatedAt: now,
    completedAt: "",
    status: "streaming",
    message: text,
    prompt,
    trace: [{
      id: `${turnId}:turn_accepted:${timestampMs(now) || Date.now()}`,
      at: now,
      type: "turn_accepted",
      provider: "beagle",
      label: "accepted",
      detail: `${selected.length} provider${selected.length === 1 ? "" : "s"}`
    }],
    providers: selected.map((provider) => ({
      id: provider.id,
      label: provider.label,
      transport: provider.transport,
      status: provider.status,
      model: provider.model || "",
      nativeSessionId: provider.nativeSessionId || "",
      nativeContinuity: provider.nativeContinuity || "",
      reason: provider.reason || ""
    })),
    responses: selected.map((provider) => ({
      provider: provider.id,
      label: provider.label,
      status: isRunnableProvider(provider) ? "waiting" : "unavailable",
      text: "",
      error: isRunnableProvider(provider) ? "" : provider.reason,
      meta: {
        transport: provider.transport || "",
        model: provider.model || "",
        sourceProvider: provider.id,
        truthMode: "observed-runtime-selected-provider"
      },
      durationMs: null,
      stderr: ""
    })),
    truthMode: "observed"
  };
}

function updateRecordFromProviderEvent(record, event) {
  const now = new Date().toISOString();
  const nowMs = timestampMs(now);
  record.updatedAt = now;
  appendTurnTrace(record, event, now);
  let response = record.responses.find((item) => item.provider === event.provider);
  if (!response) {
    response = {
      provider: event.provider,
      label: event.label || event.provider,
      status: "waiting",
      text: "",
      error: "",
      meta: {},
      durationMs: null,
      stderr: ""
    };
    record.responses.push(response);
  }

  if (event.type === "provider_started") {
    response.status = "streaming";
    response.error = "";
    response.startedAt = now;
    response.deltaCount = response.deltaCount || 0;
    response.streamedChars = response.streamedChars || 0;
    response.meta = {
      ...(response.meta || {}),
      ...(event.meta || {}),
      sourceProvider: event.sourceProvider || response.meta?.sourceProvider || event.provider,
      state: response.meta?.state || "provider-started"
    };
  } else if (event.type === "delta") {
    if (response.status === "done" && response.text && event.text && response.text.includes(event.text)) {
      return record;
    }
    response.status = "streaming";
    const deltaText = event.text || "";
    response.text = `${response.text || ""}${deltaText}`;
    response.deltaCount = (Number(response.deltaCount) || 0) + 1;
    response.streamedChars = (Number(response.streamedChars) || 0) + deltaText.length;
    response.firstDeltaAt = response.firstDeltaAt || now;
    response.lastDeltaAt = now;
    const startedMs = timestampMs(response.startedAt);
    if (!response.firstDeltaMs && startedMs && nowMs >= startedMs) {
      response.firstDeltaMs = nowMs - startedMs;
    }
  } else if (event.type === "provider_meta") {
    response.meta = { ...(response.meta || {}), ...(event.meta || {}) };
  } else if (event.type === "provider_done") {
    response.status = "done";
    response.text = event.text || response.text || "";
    response.durationMs = event.durationMs ?? response.durationMs;
    response.completedAt = now;
    response.stderr = event.stderr || "";
    response.meta = { ...(response.meta || {}), ...(event.meta || {}) };
  } else if (event.type === "provider_error" || event.type === "provider_unavailable") {
    response.status = event.type === "provider_unavailable" ? "unavailable" : "error";
    response.text = event.text || response.text || "";
    response.error = event.error || event.reason || response.error || "provider error";
    response.durationMs = event.durationMs ?? response.durationMs;
    response.completedAt = now;
  }

  return record;
}

async function prepareNativeSession(slug, provider) {
  if (!["claude", "codex", "cursor"].includes(provider.id)) {
    return null;
  }
  const nativeSession = await ensureProviderSession(slug, provider.id);
  if (provider.id === "claude") {
    provider.nativeSessionId = nativeSession?.sessionId || provider.nativeSessionId || "";
    provider.nativeContinuity = nativeSession?.nativeContinuity || provider.nativeContinuity || "";
  }
  if (provider.id === "cursor") {
    provider.nativeSessionId = nativeSession?.sessionId || provider.nativeSessionId || "";
    provider.nativeContinuity = nativeSession?.nativeContinuity || provider.nativeContinuity || "";
  }
  return nativeSession;
}

function chooseSynthesisProvider(availableProviders) {
  const requested = cleanString(process.env.PROJECT_COCKPIT_MULTIMODEL_SYNTHESIS_PROVIDER || "codex");
  return availableProviders.find((provider) => provider.id === requested)
    || availableProviders.find((provider) => provider.id === "codex")
    || availableProviders.find((provider) => provider.id === "claude")
    || availableProviders.find((provider) => provider.id === "cursor")
    || availableProviders[0]
    || null;
}

function completedTurnStatus(responses = []) {
  return responses.some((response) => ["error", "unavailable"].includes(cleanString(response.status)))
    ? "completed_with_errors"
    : "done";
}

async function writeTurnToWorkbenchContext(slug, record) {
  const turns = [
    {
      role: "user",
      text: record.message,
      external_id: `${record.turnId}:user`
    },
    ...record.responses
      .filter((response) => response.text || response.error)
      .map((response, index) => ({
        role: response.status === "done" ? "assistant" : "tool",
        text: [
          `${response.label} (${response.status})`,
          response.text || response.error || ""
        ].filter(Boolean).join("\n\n"),
        model: response.meta?.model || response.label,
        external_id: `${record.turnId}:${response.provider}:${index}`
      }))
  ];

  try {
    await fetch(`${COCKPIT_LOOPBACK}/api/workbench/${encodeURIComponent(slug)}/context/ingest`, {
      method: "POST",
      headers: internalContextHeaders(),
      body: JSON.stringify({
        source: "multimodel-chat",
        provider: "beagle",
        client_id: "project-cockpit-multimodel",
        session_id: `multimodel:${slug}`,
        conversation_id: `multimodel:${slug}`,
        request_id: record.turnId,
        tags: ["multimodel-chat", "real-streaming", slug],
        metadata: {
          turnId: record.turnId,
          providers: record.providers.map((provider) => provider.id),
          persistedAt: new Date().toISOString()
        },
        turns
      }),
      signal: AbortSignal.timeout(10000)
    });
  } catch {
    // Stream correctness must not depend on upstream memory availability.
  }
}

function agentTerminalTurnRecord(slug, body = {}) {
  const now = new Date().toISOString();
  const kind = safeSlug(body.kind || body.agentKind || "agent");
  const providerId = cleanString(body.providerId || `agent-terminal:${kind}`);
  const status = ["done", "completed_with_errors", "streaming", "waiting"].includes(cleanString(body.status))
    ? cleanString(body.status)
    : "done";
  const responseStatus = cleanString(body.responseStatus || (status === "completed_with_errors" ? "error" : status === "done" ? "done" : "streaming"));
  const text = boundedText(body.text || body.plainTail || "", 32000);
  const error = boundedText(body.error || "", 4000);
  return {
    schema: "beagle.multimodel-chat-turn.v1",
    projectSlug: slug,
    turnId: cleanString(body.turnId || randomUUID()),
    createdAt: cleanString(body.createdAt || now),
    updatedAt: now,
    completedAt: ["done", "completed_with_errors"].includes(status) ? now : "",
    status,
    message: boundedText(body.message || "", 12000),
    prompt: boundedText(body.message || "", 12000),
    providers: [
      {
        id: providerId,
        label: cleanString(body.label || `${kind} terminal`),
        transport: "shared-agent-pty",
        status: "available",
        model: "",
        nativeSessionId: cleanString(body.podName || ""),
        nativeContinuity: "shared-agent-pty",
        reason: ""
      }
    ],
    responses: [
      {
        provider: providerId,
        label: cleanString(body.label || `${kind} terminal`),
        status: responseStatus,
        text,
        error,
        meta: {
          transport: "shared-agent-pty",
          agentKind: kind,
          state: cleanString(body.state || (text ? "terminal-output-observed" : "sent-to-terminal")),
          ...(body.meta && typeof body.meta === "object" ? body.meta : {})
        },
        durationMs: null,
        stderr: ""
      }
    ],
    truthMode: "observed"
  };
}

export function registerMultimodelChatRoutes(app) {
  app.get("/api/projects/:slug/multimodel/providers", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const providers = await attachProviderProofs(slug, await detectProviders(slug));
      res.json({
        projectSlug: slug,
        providers,
        defaultProviders: defaultProviderIds(providers),
        generatedAt: new Date().toISOString(),
        truthMode: "observed"
      });
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/readiness", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await buildMultimodelReadiness(slug));
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/health", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const minLiveNow = Number(req.query?.minLiveNow || 3);
      const maxContextAgeMs = Number(req.query?.maxContextAgeMs || 30 * 60 * 1000);
      const health = await buildMultimodelHealth(slug, { minLiveNow, maxContextAgeMs });
      res.status(health.ok ? 200 : 503).json(health);
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/setup", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await buildMultimodelSetup(slug, {
        publicBase: cleanString(req.query?.publicBase || req.query?.base_url || "")
      }));
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/public-endpoint", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const publicEndpoint = await resolvePublicEndpointStatus(slug, {
        publicBase: cleanString(req.query?.publicBase || req.query?.base_url || "")
      });
      res.json({
        schema: "beagle.multimodel-public-endpoint-config-status.v1",
        projectSlug: slug,
        publicEndpoint,
        hostedNetworkBlocked: MCP_INBOX_PROVIDERS
          .filter((provider) => ["chatgpt", "grok"].includes(provider.targetClient) && !publicEndpoint.hostedClientReachable)
          .map((provider) => provider.id),
        generatedAt: new Date().toISOString(),
        truthMode: "observed-public-endpoint-config-status"
      });
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/public-endpoint/candidates", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await buildPublicEndpointCandidates(slug));
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/public-endpoint/tailscale-funnel", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const body = req.body || {};
      const apply = body.apply === true || body.confirm === true;
      const plan = await buildTailscaleFunnelActivationPlan(slug, { apply });
      if (apply && plan.ok === false) {
        res.status(409).json(plan);
        return;
      }
      res.json(plan);
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/public-endpoint/tailscale-funnel-path", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const body = req.body || {};
      const apply = body.apply === true || body.confirm === true;
      const pathPrefix = cleanString(body.pathPrefix || body.path || "/api/workbench", "/api/workbench");
      const plan = await buildTailscaleFunnelPathPlan(slug, { apply, pathPrefix });
      if (apply && plan.ok === false) {
        res.status(plan.safeToApply === false ? 409 : 403).json(plan);
        return;
      }
      res.json(plan);
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/public-endpoint", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const body = req.body || {};
      const publicBase = cleanString(body.publicBase || body.public_base || body.url);
      if (!publicBase) {
        res.status(400).json({ ok: false, error: "publicBase is required", truthMode: "invalid-public-endpoint-config" });
        return;
      }
      const status = publicEndpointStatus(publicBase, {
        trustedHosted: body.trustedHosted === true,
        source: "operator-declared"
      });
      if (!status.url || !status.protocol) {
        res.status(400).json({ ok: false, error: "invalid publicBase URL", publicEndpoint: status, truthMode: "invalid-public-endpoint-config" });
        return;
      }
      const config = await writePublicEndpointConfig(slug, {
        publicBase: status.url,
        trustedHosted: body.trustedHosted === true,
        note: cleanString(body.note)
      });
      const publicEndpoint = await resolvePublicEndpointStatus(slug);
      res.json({
        ok: true,
        schema: "beagle.multimodel-public-endpoint-config-write.v1",
        projectSlug: slug,
        config,
        publicEndpoint,
        hostedNetworkBlocked: MCP_INBOX_PROVIDERS
          .filter((provider) => ["chatgpt", "grok"].includes(provider.targetClient) && !publicEndpoint.hostedClientReachable)
          .map((provider) => provider.id),
        generatedAt: new Date().toISOString(),
        truthMode: "observed-public-endpoint-config-write"
      });
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/subscription-clients/doctor", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const doctor = await buildSubscriptionClientDoctor(slug, {
        publicBase: cleanString(req.query?.publicBase || req.query?.base_url || "")
      });
      res.status(doctor.ok ? 200 : 503).json(doctor);
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/subscription-clients/bringup", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const bringup = await buildSubscriptionClientBringup(slug, {
        publicBase: cleanString(req.query?.publicBase || req.query?.base_url || "")
      });
      res.status(bringup.ok ? 200 : 503).json(bringup);
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/subscription-clients/room", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const room = await createSubscriptionRoom(slug, req.body || {});
      res.json(room);
    } catch (error) {
      res.status(error.statusCode || 500).json({
        ok: false,
        error: error.message,
        detail: error.payload || null,
        truthMode: "subscription-room-failed"
      });
    }
  });

  app.get("/api/projects/:slug/multimodel/subscription-clients/:client/connect", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const clientId = cleanString(req.params.client);
      const bringup = await buildSubscriptionClientBringup(slug, {
        publicBase: cleanString(req.query?.publicBase || req.query?.base_url || "")
      });
      const client = (bringup.clients || []).find((item) =>
        item.id === clientId || item.targetClient === clientId
      );
      if (!client) {
        res.status(404).json({
          ok: false,
          error: `subscription client not found: ${clientId}`,
          projectSlug: slug,
          knownClients: (bringup.clients || []).map((item) => item.id),
          truthMode: "observed"
        });
        return;
      }
      res.json({
        schema: "beagle.multimodel-subscription-client-connect.v1",
        ok: true,
        projectSlug: slug,
        client: {
          id: client.id,
          label: client.label,
          targetClient: client.targetClient,
          status: client.status,
          realConnectionObserved: client.realConnectionObserved,
          clientPresence: client.clientPresence,
          clientLatestAt: client.clientLatestAt || "",
          replyGate: client.replyGate
        },
        connect: client.connect,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-real-subscription-client-connect-plan"
      });
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/subscription-clients/:client/live-drill", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const status = await buildSubscriptionLiveDrillStatus(slug, req.params.client, {
        messageId: cleanString(req.query?.message_id || req.query?.messageId || "")
      });
      res.json(status);
    } catch (error) {
      res.status(error.statusCode || 500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/subscription-clients/:client/live-drill", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const result = await createSubscriptionLiveDrill(slug, req.params.client, req.body || {});
      res.json(result);
    } catch (error) {
      res.status(error.statusCode || 500).json({
        ok: false,
        error: error.message,
        detail: error.payload || null,
        truthMode: "stale"
      });
    }
  });

  app.get("/api/projects/:slug/multimodel/turns", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const records = markInterruptedRuntimeTurns(slug, await readTurnRecords(slug, { limit: req.query?.limit }));
      const turns = await reconcileTurnRecordsWithMcpContext(slug, records);
      const activeTurns = activeTurnRecords(slug);
      const includeActive = ["1", "true", "yes"].includes(cleanString(req.query?.includeActive).toLowerCase());
      res.json({
        projectSlug: slug,
        turns: includeActive
          ? [...activeTurns, ...turns.filter((turn) => !activeTurns.some((active) => active.turnId === turn.turnId))]
          : turns,
        activeTurns,
        activeCount: activeTurns.length,
        count: includeActive
          ? turns.length + activeTurns.filter((active) => !turns.some((turn) => turn.turnId === active.turnId)).length
          : turns.length,
        generatedAt: new Date().toISOString(),
        truthMode: "observed"
      });
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/turns/:turnId/evidence", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const turnId = cleanString(req.params.turnId);
      const activeTurns = activeTurnRecords(slug);
      const records = markInterruptedRuntimeTurns(slug, await readTurnRecords(slug, { limit: 100 }));
      const persistedTurns = await reconcileTurnRecordsWithMcpContext(slug, records);
      const turns = [
        ...activeTurns,
        ...persistedTurns.filter((turn) => !activeTurns.some((active) => active.turnId === turn.turnId))
      ];
      const turn = turns.find((item) => cleanString(item.turnId) === turnId);
      if (!turn) {
        res.status(404).json({
          schema: "beagle.multimodel-turn-evidence.v1",
          projectSlug: slug,
          turnId,
          ok: false,
          error: "turn not found",
          activeCount: activeTurns.length,
          generatedAt: new Date().toISOString(),
          truthMode: "observed-persisted-turn-evidence"
        });
        return;
      }
      res.json(turnEvidenceSummary(turn, { activeCount: activeTurns.length }));
    } catch (error) {
      res.status(500).json({ ok: false, error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/turns/agent-terminal", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const record = agentTerminalTurnRecord(slug, req.body || {});
      await appendTurnRecord(slug, record);
      if (["done", "completed_with_errors"].includes(record.status)) {
        await writeTurnToWorkbenchContext(slug, record);
      }
      res.json({
        status: "ok",
        projectSlug: slug,
        turn: record,
        persisted: true,
        contextWritten: ["done", "completed_with_errors"].includes(record.status),
        generatedAt: new Date().toISOString(),
        truthMode: "observed"
      });
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/verify/realtime", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const body = req.body || {};
      const providers = Array.isArray(body.providers) && body.providers.length
        ? body.providers.map(cleanString).filter(Boolean)
        : DEFAULT_PROVIDER_PRIORITY;
      const timeoutMs = Math.max(5000, Math.min(300_000, Number(body.timeoutMs) || 180_000));
      const result = await verifyMultimodelRealtime({
        projectSlug: slug,
        providers,
        apiBase: COCKPIT_LOOPBACK,
        wsBase: COCKPIT_LOOPBACK.replace(/^http/, "ws"),
        timeoutMs,
        minProviders: providers.length
      });
      await appendVerificationRecord(slug, {
        schema: "beagle.multimodel-realtime-verification.v1",
        kind: "realtime",
        ...result,
        generatedAt: new Date().toISOString()
      });
      res.json(result);
    } catch (error) {
      res.status(500).json({
        ok: false,
        error: error.message,
        detail: error.detail || null,
        truthMode: "verification-failed"
      });
    }
  });

  app.get("/api/projects/:slug/multimodel/verify/realtime", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const verifications = await readVerificationRecords(slug, { limit: req.query?.limit || 5, kind: "realtime" });
      res.json({
        projectSlug: slug,
        latest: verifications[0] || null,
        verifications,
        count: verifications.length,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-persisted-verifications"
      });
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/verify/conversation", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const body = req.body || {};
      const providers = Array.isArray(body.providers) && body.providers.length
        ? body.providers.map(cleanString).filter(Boolean)
        : DEFAULT_PROVIDER_PRIORITY;
      const timeoutMs = Math.max(5000, Math.min(300_000, Number(body.timeoutMs) || 180_000));
      const result = await verifyMultimodelConversation({
        projectSlug: slug,
        providers,
        apiBase: COCKPIT_LOOPBACK,
        wsBase: COCKPIT_LOOPBACK.replace(/^http/, "ws"),
        timeoutMs,
        message: cleanString(body.message, "Responda em uma palavra: vivo"),
        minChars: Math.max(1, Number(body.minChars) || 2)
      });
      await appendVerificationRecord(slug, {
        schema: "beagle.multimodel-conversation-verification.v1",
        kind: "conversation",
        ...result,
        generatedAt: new Date().toISOString()
      });
      res.json(result);
    } catch (error) {
      res.status(500).json({
        ok: false,
        error: error.message,
        detail: error.detail || null,
        truthMode: "verification-failed"
      });
    }
  });

  app.get("/api/projects/:slug/multimodel/verify/conversation", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const verifications = await readVerificationRecords(slug, { limit: req.query?.limit || 5, kind: "conversation" });
      res.json({
        projectSlug: slug,
        latest: verifications[0] || null,
        verifications,
        count: verifications.length,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-persisted-verifications"
      });
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/verify/ui-send", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const verifications = await readVerificationRecords(slug, { limit: req.query?.limit || 5, kind: "ui-send" });
      res.json({
        projectSlug: slug,
        latest: verifications[0] || null,
        verifications,
        count: verifications.length,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-persisted-verifications"
      });
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/verify/ui-context", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const verifications = await readVerificationRecords(slug, { limit: req.query?.limit || 5, kind: "ui-context" });
      res.json({
        projectSlug: slug,
        latest: verifications[0] || null,
        verifications,
        count: verifications.length,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-persisted-verifications"
      });
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/verify/reconnect", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const body = req.body || {};
      const providers = Array.isArray(body.providers) && body.providers.length
        ? body.providers.map(cleanString).filter(Boolean)
        : DEFAULT_PROVIDER_PRIORITY;
      const timeoutMs = Math.max(5000, Math.min(300_000, Number(body.timeoutMs) || 180_000));
      const result = await verifyMultimodelReconnect({
        projectSlug: slug,
        providers,
        apiBase: COCKPIT_LOOPBACK,
        wsBase: COCKPIT_LOOPBACK.replace(/^http/, "ws"),
        timeoutMs
      });
      await appendVerificationRecord(slug, {
        schema: "beagle.multimodel-reconnect-verification.v1",
        kind: "reconnect",
        ...result,
        generatedAt: new Date().toISOString()
      });
      res.json(result);
    } catch (error) {
      res.status(500).json({
        ok: false,
        error: error.message,
        detail: error.detail || null,
        truthMode: "verification-failed"
      });
    }
  });

  app.get("/api/projects/:slug/multimodel/verify/reconnect", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const verifications = await readVerificationRecords(slug, { limit: req.query?.limit || 5, kind: "reconnect" });
      res.json({
        projectSlug: slug,
        latest: verifications[0] || null,
        verifications,
        count: verifications.length,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-persisted-verifications"
      });
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/active-turns", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const turns = activeTurnRecords(slug);
      res.json({
        projectSlug: slug,
        turns,
        count: turns.length,
        generatedAt: new Date().toISOString(),
        truthMode: "observed-runtime"
      });
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/sessions", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const state = await readSessionState(slug);
      res.json({
        projectSlug: slug,
        sessions: state.providers || {},
        updatedAt: state.updatedAt || "",
        generatedAt: new Date().toISOString(),
        truthMode: "observed"
      });
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/multimodel/mcp-inbox", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const records = await readWorkbenchContextRecords(slug);
      res.json(buildMcpInboxStatusFromRecords(slug, records, {
        limit: Math.max(1, Math.min(20, Number(req.query?.limit) || 5))
      }));
    } catch (error) {
      res.status(500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/mcp-inbox/:message_id/reply", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      res.json(await replyToMcpInboxHandoff(slug, req.params.message_id, req.body || {}));
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/multimodel/mcp-inbox/:message_id/cancel", async (req, res) => {
    try {
      const slug = safeSlug(req.params.slug);
      const body = req.body || {};
      const payload = await cancelMcpInboxHandoff({
        slug,
        messageId: req.params.message_id,
        providerId: cleanString(body.providerId || body.provider_id || body.provider),
        reason: cleanString(body.reason, "canceled from multimodel chat"),
        clientId: cleanString(body.client_id || body.clientId || body.by || body.source, "beagle-studio"),
        metadata: body.metadata && typeof body.metadata === "object" ? body.metadata : {}
      });
      if (payload?.error) {
        res.status(payload.statusCode || 500).json({ ...payload, truthMode: payload.truthMode || "stale" });
        return;
      }
      res.json({
        schema: "beagle.multimodel-mcp-inbox-cancel.v1",
        status: "ok",
        projectSlug: slug,
        message_id: req.params.message_id,
        cancel: payload,
        generatedAt: new Date().toISOString(),
        truthMode: "observed"
      });
    } catch (error) {
      res.status(error.statusCode || 500).json({ error: error.message, truthMode: "stale" });
    }
  });
}

export function attachMultimodelChatWebSocket(server) {
  const urlPattern = /^\/ws\/projects\/([^/]+)\/multimodel-chat(\?.*)?$/;
  const wss = new WebSocketServer({ noServer: true });

  server.on("upgrade", (req, socket, head) => {
    const urlStr = req.url || "";
    const match = urlStr.match(urlPattern);
    if (!match) return;

    wss.handleUpgrade(req, socket, head, (ws) => {
      const [, slug] = match;
      wss.emit("connection", ws, req, { slug: safeSlug(slug) });
    });
  });

  wss.on("connection", async (socket, req, ctx) => {
    const slug = ctx?.slug || "unknown";
    const runtime = runtimeFor(slug);
    runtime.sockets.add(socket);
    const active = runtime.activeChildren;
    const activeTurns = runtime.activeTurns;
    const earlyMessages = [];
    let liveMessageHandlerAttached = false;
    const captureEarlyMessage = (payload) => {
      if (!liveMessageHandlerAttached) earlyMessages.push(payload);
    };
    socket.on("message", captureEarlyMessage);
    const providers = await attachProviderProofs(slug, await detectProviders(slug));
    const defaultProviders = defaultProviderIds(providers);

    emit(socket, {
      type: "ready",
      projectSlug: slug,
      providers,
      defaultProviders,
      truthMode: "observed"
    });
    for (const state of activeTurns.values()) {
      emit(socket, {
        type: "turn_snapshot",
        turnId: state.turnId,
        turn: decorateActiveTurnRecord(state),
        detached: true,
        reason: "active-reconnect"
      });
    }

    const handleSocketMessage = async (payload) => {
      let message;
      try {
        message = JSON.parse(String(payload));
      } catch {
        emit(socket, { type: "error", error: "invalid JSON message" });
        return;
      }

      if (message.type === "stop") {
        const stoppedTurns = [];
        for (const [turnId, state] of activeTurns) {
          if (message.turnId && cleanString(message.turnId) !== turnId) continue;
          state.cancel("stopped by user");
          stoppedTurns.push(turnId);
        }
        emit(socket, { type: "stopped", turnIds: stoppedTurns });
        return;
      }

      if (message.type !== "chat") return;

      const text = boundedText(message.message || message.text);
      if (!text) {
        emit(socket, { type: "error", error: "message is required" });
        return;
      }

      const latestProviders = await detectProviders(slug);
      const requested = Array.isArray(message.providers) && message.providers.length
        ? message.providers.map(cleanString).filter(Boolean)
        : defaultProviderIds(latestProviders);
      const selected = requested.map((id) => providerById(latestProviders, id)).filter(Boolean);
      const repoRoot = selected.find((provider) => provider.repoRoot)?.repoRoot || process.cwd();
      const turnId = cleanString(message.turnId) || randomUUID();
      const history = Array.isArray(message.history) ? message.history : [];
      const prompt = buildProviderPrompt({ slug, message: text, history });
      const available = selected.filter(isRunnableProvider);
      const unavailable = selected.filter((provider) => !isRunnableProvider(provider));
      const nativeSessions = {};
      for (const provider of available) {
        nativeSessions[provider.id] = await prepareNativeSession(slug, provider);
      }
      const turnRecord = initialTurnRecord({ slug, turnId, text, selected, prompt });
      const turnAbort = new AbortController();
      const turnState = {
        turnId,
        abortController: turnAbort,
        cancelled: false,
        finalized: false,
        startedAtMs: Date.now(),
        lastEventAt: new Date().toISOString(),
        heartbeatTimer: null,
        children: new Set(),
        cancel(reason = "stopped by user") {
          if (this.finalized) return;
          this.cancelled = true;
          this.finalized = true;
          if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
          try { this.abortController.abort(abortError(reason)); } catch { /* already aborted */ }
          for (const child of this.children) {
            try { child.kill("SIGTERM"); } catch { /* already closed */ }
            active.delete(child);
          }
          const now = new Date().toISOString();
          turnRecord.status = "stopped";
          turnRecord.completedAt = now;
          turnRecord.updatedAt = now;
          appendTurnTrace(turnRecord, { type: "turn_stopped", provider: "beagle", label: "stopped", reason }, now);
          for (const response of turnRecord.responses) {
            if (["waiting", "streaming"].includes(response.status)) {
              response.status = "error";
              response.error = response.error || reason;
            }
            if (response.meta?.transport === "workbench-context-mcp-inbox" && response.meta?.message_id) {
              void cancelMcpInboxHandoff({
                slug,
                messageId: response.meta.message_id,
                providerId: response.provider,
                reason
              });
            }
          }
          activeTurns.delete(turnId);
          appendTurnRecord(slug, turnRecord)
            .then(() => writeTurnToWorkbenchContext(slug, turnRecord))
            .catch(() => {});
          broadcast(runtime, { type: "turn_stopped", turnId, reason });
          cleanupRuntime(runtime);
        }
      };
      turnState.turnRecord = turnRecord;
      turnState.heartbeatTimer = setInterval(() => {
        if (turnState.finalized || turnState.cancelled) return;
        broadcast(runtime, turnHeartbeatPayload(turnState));
      }, Math.max(1000, TURN_HEARTBEAT_MS));
      activeTurns.set(turnId, turnState);
      appendTurnRecord(slug, persistedTurnSnapshot(turnRecord, "started")).catch(() => {});
      const recordProviderEvent = (event) => {
        if (turnState.finalized) return;
        updateRecordFromProviderEvent(turnRecord, event);
        turnState.lastEventAt = new Date().toISOString();
        if (shouldPersistProviderEvent(event)) {
          appendTurnRecord(slug, persistedTurnSnapshot(turnRecord, event.type)).catch(() => {});
        }
        broadcast(runtime, event);
        if (event.type === "provider_meta") {
          const sourceProvider = event.sourceProvider || event.meta?.sourceProvider || event.provider;
          if (sourceProvider === "claude" && event.meta?.session_id) {
            const patch = {
              model: event.meta.model || nativeSessions.claude?.model || "",
              nativeContinuity: CLAUDE_SESSION_MODE === "resume"
                ? "claude-code-resume"
                : "claude-code-fresh-session-prompt-history"
            };
            if (CLAUDE_SESSION_MODE === "resume") {
              patch.sessionId = event.meta.session_id;
            } else {
              patch.lastSessionId = event.meta.session_id;
            }
            void updateProviderSession(slug, "claude", patch);
          }
          if (sourceProvider === "codex" && event.meta?.thread_id) {
            void updateProviderSession(slug, "codex", {
              threadId: event.meta.thread_id,
              nativeContinuity: "codex-exec-resume-read-only",
              note: "codex exec resume verified with --strict-config -c sandbox_mode=\"read-only\""
            });
          }
          if (sourceProvider === "cursor" && event.meta?.session_id) {
            const patch = {
              sessionId: event.meta.session_id,
              nativeContinuity: "cursor-agent-resume",
            };
            if (event.meta.model) patch.model = event.meta.model;
            if (event.meta.apiKeySource) patch.apiKeySource = event.meta.apiKeySource;
            if (event.meta.permissionMode) patch.permissionMode = event.meta.permissionMode;
            void updateProviderSession(slug, "cursor", patch);
          }
        }
      };

      broadcast(runtime, {
        type: "turn_snapshot",
        turnId,
        turn: decorateActiveTurnRecord(turnState),
        detached: false,
        reason: "turn-started"
      });
      appendTurnTrace(turnRecord, {
        type: "turn_started",
        provider: "beagle",
        label: "started",
        providerCount: selected.length,
        availableProviders: available.map((provider) => provider.id)
      });
      broadcast(runtime, {
        type: "turn_started",
        turnId,
        projectSlug: slug,
        providers: selected,
        availableProviders: available.map((provider) => provider.id),
        unavailableProviders: unavailable.map((provider) => ({ id: provider.id, reason: provider.reason }))
      });

      for (const provider of unavailable) {
        const unavailableEvent = {
          type: "provider_unavailable",
          turnId,
          provider: provider.id,
          label: provider.label,
          reason: provider.reason
        };
        recordProviderEvent(unavailableEvent);
      }

      let pending = available.length;
      if (pending === 0) {
        activeTurns.delete(turnId);
        turnRecord.status = completedTurnStatus(turnRecord.responses);
        turnRecord.completedAt = new Date().toISOString();
        turnRecord.updatedAt = turnRecord.completedAt;
        appendTurnTrace(turnRecord, { type: "turn_done", provider: "beagle", label: "persisted", status: turnRecord.status }, turnRecord.completedAt);
        appendTurnRecord(slug, turnRecord)
          .then(() => writeTurnToWorkbenchContext(slug, turnRecord))
          .catch(() => {});
        broadcast(runtime, { type: "turn_done", turnId, status: turnRecord.status });
        cleanupRuntime(runtime);
        return;
      }

      const finalizeTurn = () => {
        if (turnState.finalized) return;
        turnState.finalized = true;
        if (turnState.heartbeatTimer) clearInterval(turnState.heartbeatTimer);
        activeTurns.delete(turnId);
        turnRecord.status = completedTurnStatus(turnRecord.responses);
        turnRecord.completedAt = new Date().toISOString();
        turnRecord.updatedAt = turnRecord.completedAt;
        appendTurnTrace(turnRecord, { type: "turn_done", provider: "beagle", label: "persisted", status: turnRecord.status }, turnRecord.completedAt);
        appendTurnRecord(slug, turnRecord)
          .then(() => writeTurnToWorkbenchContext(slug, turnRecord))
          .catch(() => {});
        broadcast(runtime, { type: "turn_done", turnId, status: turnRecord.status });
        cleanupRuntime(runtime);
      };

      const startSynthesis = async () => {
        if (turnState.cancelled || turnState.finalized || turnAbort.signal.aborted) return;
        const shouldSynthesize =
          message.enableSynthesis !== false &&
          available.length >= 2 &&
          turnRecord.responses.some((response) => response.status === "done" && response.text);
        if (!shouldSynthesize) {
          finalizeTurn();
          return;
        }

        const successfulProviderIds = new Set(turnRecord.responses
          .filter((response) => response.status === "done" && cleanString(response.text))
          .map((response) => cleanString(response.provider)));
        const synthesisCandidates = available.filter((provider) => successfulProviderIds.has(provider.id));
        const synthesizer = chooseSynthesisProvider(synthesisCandidates);
        if (!synthesizer) {
          finalizeTurn();
          return;
        }

        nativeSessions[synthesizer.id] = nativeSessions[synthesizer.id] || await prepareNativeSession(slug, synthesizer);
        const synthesisPrompt = buildSynthesisPrompt({
          slug,
          message: text,
          responses: turnRecord.responses
        });
        const eventLabel = `Synthesis (${synthesizer.label})`;
        const runner = startProviderRunner({
          provider: synthesizer,
          providerPrompt: synthesisPrompt,
          eventProvider: SYNTHESIS_RESPONSE_ID,
          eventLabel
        });

        if (!runner) {
          recordProviderEvent({
            type: "provider_error",
            turnId,
            provider: SYNTHESIS_RESPONSE_ID,
            label: eventLabel,
            sourceProvider: synthesizer.id,
            error: "synthesis adapter did not return a process"
          });
        }
        attachRunnerLifecycle(runner, finalizeTurn);
      };

      const markDone = () => {
        if (turnState.cancelled || turnState.finalized || turnAbort.signal.aborted) return;
        pending -= 1;
        if (pending <= 0) {
          void startSynthesis();
        }
      };

      const attachRunnerLifecycle = (runner, onComplete) => {
        if (runner && typeof runner.then === "function") {
          runner
            .then((resolved) => attachRunnerLifecycle(resolved, onComplete))
            .catch(() => onComplete());
          return;
        }
        if (runner) {
          const child = runner;
          active.add(child);
          turnState.children.add(child);
          let settled = false;
          const finish = () => {
            if (settled) return;
            settled = true;
            active.delete(child);
            turnState.children.delete(child);
            onComplete();
          };
          child.on("close", finish);
          child.on("error", finish);
          return;
        }
        onComplete();
      };

      const startProviderRunner = ({ provider, providerPrompt, eventProvider, eventLabel }) => {
        const run = () => runProvider({
          socket: null,
          turnId,
          provider,
          message: text,
          prompt: providerPrompt,
          history,
          repoRoot,
          nativeSession: nativeSessions[provider.id],
          onProviderEvent: recordProviderEvent,
          eventProvider,
          eventLabel,
          slug,
          signal: turnAbort.signal
        });
        const laneKey = singleLaneKey(provider);
        if (!laneKey) return run();

        recordProviderEvent({
          type: "provider_meta",
          turnId,
          provider: eventProvider || provider.id,
          label: eventLabel || provider.label,
          sourceProvider: provider.id,
          meta: {
            transport: provider.transport,
            state: "queued-single-lane",
            lane_key: laneKey
          }
        });
        return enqueueProviderLane(runtime, laneKey, async () => {
          assertNotAborted(turnAbort.signal);
          recordProviderEvent({
            type: "provider_meta",
            turnId,
            provider: eventProvider || provider.id,
            label: eventLabel || provider.label,
            sourceProvider: provider.id,
            meta: {
              transport: provider.transport,
              state: "acquired-single-lane",
              lane_key: laneKey
            }
          });
          return await run();
        });
      };

      for (const provider of available) {
        const runner = startProviderRunner({
          provider,
          providerPrompt: prompt
        });
        if (!runner) {
          recordProviderEvent({
            type: "provider_error",
            turnId,
            provider: provider.id,
            label: provider.label,
            error: "adapter did not return a process"
          });
        }
        attachRunnerLifecycle(runner, markDone);
      }
    };

    liveMessageHandlerAttached = true;
    socket.on("message", handleSocketMessage);
    socket.off("message", captureEarlyMessage);
    for (const payload of earlyMessages.splice(0)) {
      void handleSocketMessage(payload);
    }

    socket.on("close", () => {
      runtime.sockets.delete(socket);
      cleanupRuntime(runtime);
    });
  });

  return wss;
}
