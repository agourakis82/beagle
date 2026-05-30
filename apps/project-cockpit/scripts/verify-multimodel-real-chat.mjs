#!/usr/bin/env node

import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { verifyMultimodelConversation } from "../server/multimodel-conversation-verifier.mjs";

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

function parseProviders(value) {
  return cleanString(value)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

async function fetchJson(url) {
  const res = await fetch(url);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${res.status} ${payload?.error || res.statusText}`);
  return payload;
}

async function defaultProviders({ apiBase, projectSlug }) {
  const explicit = process.env.PROVIDERS || process.argv[3] || "";
  if (explicit) return parseProviders(explicit);
  const payload = await fetchJson(`${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/providers`);
  return Array.isArray(payload.defaultProviders) && payload.defaultProviders.length
    ? payload.defaultProviders
    : ["claude", "codex", "cursor"];
}

function compact(value = "") {
  return cleanString(value).toLowerCase().replace(/[^a-z0-9]+/g, "");
}

function letterCount(value = "") {
  return (cleanString(value).match(/[a-zA-ZÀ-ÿ]/g) || []).length;
}

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

function assertRealAnswer({ provider, text, message, marker, minChars }) {
  const clean = cleanString(text);
  const compactText = compact(clean);
  const compactMessage = compact(message);
  assert(clean.length >= minChars, `${provider} returned too little text for a real-chat proof`, {
    provider,
    chars: clean.length,
    minChars,
    text: clean
  });
  assert(clean.includes(marker), `${provider} did not include the unique real-chat marker`, {
    provider,
    marker,
    text: clean
  });
  assert(!["ok", "vivo", "done", "sim"].includes(compactText), `${provider} returned a ping-style answer, not chat`, {
    provider,
    text: clean
  });
  assert(compactText !== compactMessage, `${provider} echoed the prompt instead of answering`, {
    provider,
    text: clean
  });
  const wordCount = clean.split(/\s+/).filter(Boolean).length;
  assert(wordCount >= 12 || letterCount(clean) >= minChars * 2, `${provider} answer has too little linguistic content to prove conversational output`, {
    provider,
    wordCount,
    letterCount: letterCount(clean),
    text: clean
  });
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
const wsBase = process.env.PROJECT_COCKPIT_WS_BASE || apiBase.replace(/^http/, "ws");
const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 300_000);
const minChars = Number(process.env.VERIFY_MULTIMODEL_REAL_MIN_CHARS || 80);
const marker = `BGL-REAL-${Date.now().toString(36).toUpperCase()}`;
const message = process.env.VERIFY_MULTIMODEL_MESSAGE || [
  `Prova de chat multimodelo real-time para Darwin-MFC. Marcador único: ${marker}.`,
  "Responda em duas frases, em português, dizendo o próximo passo técnico concreto para tornar o chat multimodelo mais real.",
  "Inclua o marcador exatamente uma vez. Não edite arquivos e não rode comandos."
].join(" ");

let providers = [];

try {
  providers = await defaultProviders({ apiBase, projectSlug });
  const result = await verifyMultimodelConversation({
    projectSlug,
    providers,
    apiBase,
    wsBase,
    timeoutMs,
    message,
    minChars
  });

  for (const response of result.responses || []) {
    assertRealAnswer({
      provider: response.provider,
      text: response.text,
      message,
      marker,
      minChars
    });
  }

  const record = {
    schema: "beagle.multimodel-real-chat-verification.v1",
    kind: "real-chat",
    ...result,
    marker,
    minChars,
    generatedAt: new Date().toISOString(),
    truthMode: "observed-substantial-websocket-model-replies-persisted"
  };
  await appendVerificationRecord(projectSlug, record);
  console.log(JSON.stringify(record, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    schema: "beagle.multimodel-real-chat-verification.v1",
    projectSlug,
    providers,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
