#!/usr/bin/env node

import { verifyMultimodelUiStop } from "./verify-multimodel-ui-mcp-cancel.mjs";

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const provider = process.env.PROVIDER || process.argv[3] || "chatgpt-mcp";
const appBase = process.env.PROJECT_COCKPIT_APP_BASE || "http://127.0.0.1:4173";
const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 120_000);

try {
  const result = await verifyMultimodelUiStop({
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
}
