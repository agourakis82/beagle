#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";

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
  if (!res.ok) {
    const error = new Error(`${res.status} ${payload?.error || res.statusText}`);
    error.detail = payload;
    throw error;
  }
  return payload;
}

function mentionsSounio(value) {
  return /sounio|sounio-dev|sounio-workspace/i.test(String(value || ""));
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";

try {
  const setup = await fetchJson(`${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/setup`);
  const providers = await fetchJson(`${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/providers`);
  const kimiAction = (setup.actions || []).find((item) => item.id === "kimi");
  const kimiProvider = (providers.providers || []).find((item) => item.id === "kimi");
  assert(kimiAction, "setup is missing Kimi action", setup);
  assert(kimiProvider, "providers endpoint is missing Kimi", providers);
  assert(setup.guards?.noImplicitKimiBridge === true, "Kimi implicit bridge guard is not active", setup.guards);
  assert(!mentionsSounio(kimiAction.bridgeProjectSlug), "Kimi setup points at Sounio", kimiAction);
  assert(!mentionsSounio(kimiProvider.bridgeProjectSlug), "Kimi provider points at Sounio", kimiProvider);
  assert((kimiAction.forbiddenBridgeValues || []).length === 0, "Kimi forbidden bridge values are present", kimiAction);
  assert(kimiAction.bridgeSafety?.safe !== false, "Kimi bridge safety failed", kimiAction.bridgeSafety);

  if (kimiProvider.status === "available") {
    assert(
      ["local-command", "native-project-zellij"].includes(kimiProvider.bridgeMode),
      "Kimi is available through an unsafe bridge mode",
      kimiProvider
    );
  } else {
    assert(
      kimiProvider.bridgeMode === "not-configured" || kimiProvider.reason,
      "Kimi unavailable state does not explain how to configure it",
      kimiProvider
    );
  }

  const startScript = await readFile(path.resolve("scripts/start-darwin-mfc-multimodel-workbench.sh"), "utf8");
  assert(!startScript.includes("PROJECT_COCKPIT_ALLOW_CROSS_PROJECT_KIMI_ZELLIJ:-1"), "start script enables cross-project Kimi by default");
  assert(!startScript.includes("PROJECT_COCKPIT_KIMI_ZELLIJ_PROJECT_SLUG:-sounio"), "start script defaults Kimi project to Sounio");
  assert(!startScript.includes("PROJECT_COCKPIT_KIMI_ZELLIJ_SESSION:-sounio-dev"), "start script defaults Kimi session to Sounio");
  assert(!startScript.includes("sounio-workspace-ssh"), "start script defaults Kimi SSH to Sounio workspace");

  console.log(JSON.stringify({
    ok: true,
    schema: "beagle.multimodel-kimi-bridge-guard-verification.v1",
    projectSlug,
    status: kimiProvider.status,
    bridgeMode: kimiProvider.bridgeMode,
    command: kimiProvider.command || "",
    reason: kimiProvider.reason || "",
    forbiddenBridgeValues: kimiAction.forbiddenBridgeValues || [],
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-runtime-kimi-bridge-guard"
  }, null, 2));
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
