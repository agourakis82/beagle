#!/usr/bin/env node

import { appendFile, mkdir, readFile } from "node:fs/promises";
import path from "node:path";

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

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");
const tokenFile = path.join(DATA_DIR, "workbench-context", `${safeSlug(projectSlug)}.http-mcp-token`);
const verificationPath = path.join(DATA_DIR, "multimodel-chat", `${safeSlug(projectSlug)}.verifications.jsonl`);

async function appendVerificationRecord(record) {
  await mkdir(path.dirname(verificationPath), { recursive: true });
  await appendFile(verificationPath, `${JSON.stringify(record)}\n`, "utf8");
}

async function readToken() {
  const envToken =
    cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
    cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
  if (envToken) return envToken;
  return cleanString(await readFile(tokenFile, "utf8"));
}

async function fetchStatus(url, headers = {}) {
  const res = await fetch(url, { headers });
  const payload = await res.json().catch(() => ({}));
  return { status: res.status, payload };
}

try {
  const token = await readToken();
  assert(token.length >= 32, "HTTP MCP token is missing or too short", { tokenFile });

  const url = `${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp`;
  const noAuth = await fetchStatus(url);
  const wrongAuth = await fetchStatus(url, { authorization: "Bearer wrong-token" });
  const authorized = await fetchStatus(url, { authorization: `Bearer ${token}` });
  const connect = await fetchStatus(`${apiBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/connect`);

  assert(noAuth.status === 401, "HTTP MCP without auth should be rejected", noAuth);
  assert(wrongAuth.status === 401, "HTTP MCP with wrong auth should be rejected", wrongAuth);
  assert(authorized.status === 200, "HTTP MCP with token should be accepted", authorized);
  assert(authorized.payload?.auth?.required === true, "HTTP MCP did not report auth required", authorized.payload);
  assert(connect.status === 200, "connection pack failed", connect);
  assert(connect.payload?.auth?.required?.http_mcp === true, "connection pack does not mark HTTP MCP auth required", connect.payload);
  assert(connect.payload?.auth?.token_configured === true, "connection pack does not report token configured", connect.payload);

  const result = {
    ok: true,
    schema: "beagle.workbench-http-mcp-auth-verification.v1",
    kind: "http-mcp-auth",
    projectSlug,
    tokenFile,
    noAuthStatus: noAuth.status,
    wrongAuthStatus: wrongAuth.status,
    authorizedStatus: authorized.status,
    authRequired: authorized.payload?.auth?.required === true,
    tokenConfigured: connect.payload?.auth?.token_configured === true,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-http-mcp-bearer-auth"
  };
  await appendVerificationRecord(result);
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
