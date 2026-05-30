#!/usr/bin/env node

import { appendFile, mkdir, readFile } from "node:fs/promises";
import path from "node:path";

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

async function fetchJson(url) {
  const res = await fetch(url);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${res.status} ${payload?.error || res.statusText}`);
  return payload;
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
const sourcePath = path.resolve(process.cwd(), "src/pages/WorkbenchMirror.jsx");

try {
  const source = await readFile(sourcePath, "utf8");
  const readiness = await fetchJson(`${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/readiness`);
  const defaultProviders = Array.isArray(readiness.defaultProviders)
    ? readiness.defaultProviders
    : readiness.summary?.defaultProviders || [];
  const liveNow = Array.isArray(readiness.liveNow) ? readiness.liveNow : [];

  assert(source.includes("new WebSocket(multimodelWsUrl(projectSlug()))"), "WorkbenchMirror does not open the multimodel WebSocket", { sourcePath });
  assert(source.includes("/ws/projects/"), "WorkbenchMirror is missing the multimodel WebSocket URL helper", { sourcePath });
  assert(source.includes("type: \"chat\""), "WorkbenchMirror does not send chat events to the multimodel socket", { sourcePath });
  assert(source.includes("event.type === \"delta\""), "WorkbenchMirror does not render streaming deltas", { sourcePath });
  assert(source.includes("Não gerei fallback local."), "WorkbenchMirror does not expose an honest no-fallback failure message", { sourcePath });
  assert(!source.includes("fetchContextJson(\"/api/llm/complete\""), "WorkbenchMirror still calls the generic LLM completion route", { sourcePath });
  assert(!source.includes("function fallbackStudioReply"), "WorkbenchMirror still contains the old local conversational fallback", { sourcePath });
  assert(defaultProviders.length >= 2, "multimodel readiness does not expose at least two default real providers", { defaultProviders, liveNow });

  const record = {
    schema: "beagle.workbench-mirror-real-chat-wiring-verification.v1",
    kind: "workbench-mirror-real-chat",
    ok: true,
    projectSlug,
    sourcePath,
    defaultProviders,
    liveNow,
    checks: {
      opensWebSocket: true,
      sendsChatEvent: true,
      rendersDeltas: true,
      noGenericLlmRoute: true,
      noLocalConversationalFallback: true,
      honestFailureMessage: true,
      defaultProviderCount: defaultProviders.length
    },
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-source-wiring-and-runtime-readiness"
  };
  await appendVerificationRecord(projectSlug, record);
  console.log(JSON.stringify(record, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    schema: "beagle.workbench-mirror-real-chat-wiring-verification.v1",
    projectSlug,
    sourcePath,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
