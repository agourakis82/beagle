#!/usr/bin/env node

import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { verifyMultimodelConversation } from "../server/multimodel-conversation-verifier.mjs";

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

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
}

async function appendVerificationRecord(slug, record) {
  const file = verificationFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
}

export async function verifyMultimodelUiContext({
  projectSlug = "darwin-mfc",
  providers = ["claude", "codex", "cursor"],
  apiBase = "http://127.0.0.1:4370",
  timeoutMs = 220_000,
  secret = `ctx-${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 8)}`
} = {}) {
  const firstMarker = `ui-context-seed-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const secondMarker = `ui-context-recall-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const selectedProviders = providers.map((provider) => cleanString(provider)).filter(Boolean);
  const firstMessage = `Memorize this context token for the next message: ${secret}. Reply briefly that it is stored. (${firstMarker})`;
  const first = await verifyMultimodelConversation({
    projectSlug,
    providers: selectedProviders,
    apiBase,
    timeoutMs,
    message: firstMessage,
    minChars: 2,
    turnId: `verify-ui-context-seed-${Date.now()}`
  });
  const history = [
    { role: "user", text: firstMessage },
    {
      role: "assistant",
      text: first.responses
        .map((response) => `${response.provider}: ${cleanString(response.text)}`)
        .join("\n")
    }
  ];
  const second = await verifyMultimodelConversation({
    projectSlug,
    providers: selectedProviders,
    apiBase,
    timeoutMs,
    message: `Using the immediately previous user message in this same Beagle chat, what was the context token? Reply with only the token. (${secondMarker})`,
    minChars: Math.max(2, secret.length),
    turnId: `verify-ui-context-recall-${Date.now()}`,
    history
  });

  const recalled = (second.persisted || []).map((response) => ({
    provider: response.provider,
    status: response.status,
    recalled: cleanString(response.text).includes(secret),
    text: cleanString(response.text),
    firstDeltaMs: response.firstDeltaMs,
    deltaCount: response.deltaCount,
    streamedChars: response.streamedChars,
    durationMs: response.durationMs
  }));
  const missing = recalled.filter((response) => !response.recalled).map((response) => response.provider);
  if (missing.length) {
    const error = new Error(`provider(s) did not recall context token: ${missing.join(", ")}`);
    error.detail = { secret, first, second, recalled };
    throw error;
  }

  const result = {
    ok: true,
    projectSlug,
    providers: selectedProviders,
    secret,
    firstTurnId: first.turnId,
    secondTurnId: second.turnId,
    firstMarker,
    secondMarker,
    recalled,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-websocket-history-context-persisted"
  };
  await appendVerificationRecord(projectSlug, {
    schema: "beagle.multimodel-ui-context-verification.v1",
    kind: "ui-context",
    ...result,
    generatedAt: new Date().toISOString()
  });
  return result;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const providers = (process.env.PROVIDERS || process.argv[3] || "claude,codex,cursor")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
  const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 220_000);
  const secret = process.env.VERIFY_MULTIMODEL_CONTEXT_SECRET || "";
  try {
    const result = await verifyMultimodelUiContext({
      projectSlug,
      providers,
      apiBase,
      timeoutMs,
      secret: secret || undefined
    });
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error(JSON.stringify({
      ok: false,
      projectSlug,
      providers,
      error: error.message,
      detail: error.detail || null,
      truthMode: "verification-failed"
    }, null, 2));
    process.exit(1);
  }
}
