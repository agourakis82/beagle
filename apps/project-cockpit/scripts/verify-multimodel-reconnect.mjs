#!/usr/bin/env node

import { verifyMultimodelReconnect } from "../server/multimodel-reconnect-verifier.mjs";

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
const wsBase = process.env.PROJECT_COCKPIT_WS_BASE || apiBase.replace(/^http/, "ws");
const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 180_000);
let providers = [];

function parseProviders(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

async function defaultProviders() {
  const explicit = process.env.PROVIDERS || process.argv[3] || "";
  if (explicit) return parseProviders(explicit);
  const res = await fetch(`${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/providers`);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${res.status} ${payload?.error || res.statusText}`);
  return Array.isArray(payload.defaultProviders) && payload.defaultProviders.length
    ? payload.defaultProviders
    : ["claude", "codex", "cursor"];
}

try {
  providers = await defaultProviders();
  const result = await verifyMultimodelReconnect({
    projectSlug,
    providers,
    apiBase,
    wsBase,
    timeoutMs
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
