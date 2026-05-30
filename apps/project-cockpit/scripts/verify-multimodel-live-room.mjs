#!/usr/bin/env node

import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { verifyMultimodelRealtime } from "../server/multimodel-realtime-verifier.mjs";

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

function parseProviders(value) {
  return cleanString(value)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

async function liveNowProviders({ apiBase, projectSlug }) {
  const payload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/readiness`);
  const liveNow = Array.isArray(payload.liveNow) ? payload.liveNow : [];
  return liveNow.filter((provider) =>
    provider === "claude" ||
    provider === "codex" ||
    provider === "cursor" ||
    provider === "kimi" ||
    provider === "agent-terminal:codex" ||
    provider.startsWith("agent-terminal:desktop-")
  );
}

export async function verifyMultimodelLiveRoom({
  projectSlug = "darwin-mfc",
  providers = [],
  apiBase = "http://127.0.0.1:4370",
  wsBase = apiBase.replace(/^http/, "ws"),
  timeoutMs = 300_000
} = {}) {
  const api = apiBase.replace(/\/$/, "");
  const selectedProviders = providers.length
    ? providers
    : await liveNowProviders({ apiBase: api, projectSlug });
  const minProviders = Number(process.env.VERIFY_MULTIMODEL_LIVE_ROOM_MIN_PROVIDERS || selectedProviders.length || 1);
  const result = await verifyMultimodelRealtime({
    projectSlug,
    providers: selectedProviders,
    apiBase: api,
    wsBase: wsBase.replace(/\/$/, ""),
    timeoutMs,
    minProviders,
    turnId: `verify-multimodel-live-room-${Date.now()}`
  });
  const record = {
    schema: "beagle.multimodel-live-room-verification.v1",
    kind: "live-room",
    ...result,
    providerCount: selectedProviders.length,
    generatedAt: new Date().toISOString(),
    truthMode: "observed-single-websocket-turn-all-live-local-providers-persisted"
  };
  await appendVerificationRecord(projectSlug, record);
  return record;
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
const wsBase = process.env.PROJECT_COCKPIT_WS_BASE || apiBase.replace(/^http/, "ws");
const providers = parseProviders(process.env.PROVIDERS || process.argv[3] || "");
const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 300_000);

try {
  const result = await verifyMultimodelLiveRoom({ projectSlug, providers, apiBase, wsBase, timeoutMs });
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    schema: "beagle.multimodel-live-room-verification.v1",
    projectSlug,
    providers,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
