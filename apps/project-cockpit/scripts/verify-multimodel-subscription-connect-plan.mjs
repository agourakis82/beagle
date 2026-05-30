#!/usr/bin/env node

import { spawn } from "node:child_process";
import { readFile, appendFile, mkdir } from "node:fs/promises";
import path from "node:path";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

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

function runProcess(command, args = [], { timeoutMs = 60_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(Object.assign(new Error(`command timeout after ${timeoutMs}ms`), { detail: { command, args, stdout, stderr } }));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) resolve({ stdout, stderr });
      else reject(Object.assign(new Error(`command exited ${code}`), { detail: { command: [command, ...args].join(" "), stdout, stderr } }));
    });
  });
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

async function runShell(command, options = {}) {
  return runProcess("/bin/bash", ["-lc", command], options);
}

function parseAgentBrowserJson(stdout) {
  const full = stdout.trim();
  if (full.startsWith("{")) {
    try {
      return JSON.parse(full);
    } catch {
      // Fall back to line scanning.
    }
  }
  const lines = stdout.split("\n").map((line) => line.trim()).filter(Boolean);
  for (const line of [...lines].reverse()) {
    try {
      const decoded = line.startsWith("\"") && line.endsWith("\"") ? JSON.parse(line) : line;
      if (typeof decoded === "string" && decoded.startsWith("{")) return JSON.parse(decoded);
      if (decoded && typeof decoded === "object") return decoded;
    } catch {
      // Keep scanning agent-browser output.
    }
  }
  throw Object.assign(new Error("agent-browser JSON result not found"), { detail: { stdout } });
}

async function verifyBrowserUi({ appBase, projectSlug }) {
  const url = `${appBase.replace(/\/$/, "")}/workbench/${encodeURIComponent(projectSlug)}`;
  await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
  await runShell(`agent-browser open ${shellQuote(url)}`, { timeoutMs: 60_000 });
  await runShell("agent-browser wait 1500", { timeoutMs: 10_000 });
  const result = await runProcess("agent-browser", ["eval", `
(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  let snapshot = {};
  for (let i = 0; i < 80; i += 1) {
    const cards = Array.from(document.querySelectorAll('[data-testid="subscription-connect-card"]'));
    const copyButtons = Array.from(document.querySelectorAll('[data-testid="subscription-copy-connect"]'));
    const setupTextButtons = Array.from(document.querySelectorAll('[data-testid="subscription-copy-setup-text"]'));
    const drillButtons = Array.from(document.querySelectorAll('[data-testid="subscription-reply-drill"]'));
    const overlay = document.querySelector('.vite-error-overlay, [data-nextjs-dialog], #webpack-dev-server-client-overlay');
    snapshot = {
      ok: cards.length >= 3 && copyButtons.length >= 3 && setupTextButtons.length >= 3 && drillButtons.length >= 3 && !overlay,
      cardCount: cards.length,
      copyButtonCount: copyButtons.length,
      setupTextButtonCount: setupTextButtons.length,
      drillButtonCount: drillButtons.length,
      hasOverlay: Boolean(overlay),
      bodyChars: document.body.innerText.trim().length,
      body: document.body.innerText.slice(0, 2000)
    };
    if (snapshot.ok) break;
    await sleep(250);
  }
  return snapshot;
})()
  `], { timeoutMs: 30_000 });
  await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
  return parseAgentBrowserJson(result.stdout);
}

async function readToken(tokenFile) {
  if (!tokenFile) return "";
  try {
    return cleanString(await readFile(tokenFile, "utf8"));
  } catch {
    return "";
  }
}

function validateConnectPlan(client) {
  const connect = client.connect || {};
  const calls = connect.firstToolCalls || [];
  const tools = calls.map((call) => cleanString(call.tool));
  assert(connect.mcpServer?.url, "connect plan is missing an MCP server URL", { client });
  assert(connect.mcpServer?.headers?.["x-beagle-client-id"], "connect plan is missing x-beagle-client-id", { client });
  assert(connect.mcpServer?.headers?.["x-beagle-provider"], "connect plan is missing x-beagle-provider", { client });
  assert(connect.registration?.url === connect.mcpServer.url, "registration URL does not match MCP server URL", { client });
  assert(tools.includes("workbench_context_join"), "connect plan is missing join tool", { client, tools });
  assert(tools.includes("workbench_context_client_heartbeat"), "connect plan is missing heartbeat tool", { client, tools });
  assert(tools.includes("workbench_context_inbox"), "connect plan is missing inbox tool", { client, tools });
  assert(
    tools.includes("workbench_context_reply") || tools.includes("cockpit_workbench_context_reply"),
    "connect plan is missing reply tool",
    { client, tools }
  );
  assert(String(connect.setupText || "").includes("Register this MCP server"), "connect plan is missing human setup text", { client });
  assert(String(connect.setupText || "").includes(connect.mcpServer.url), "setup text is missing the MCP URL", { client });
  assert(String(connect.setupText || "").includes("Bearer <workbench-context-token>"), "setup text is missing the bearer placeholder", { client });
  assert(String(connect.setupText || "").includes("workbench_context_join"), "setup text is missing first tool instructions", { client });
  assert(String(connect.operatorPrompt || "").includes(`client_id=${client.targetClient}`), "operator prompt does not bind the target client id", { client });
}

async function main() {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
  const appBase = cleanString(process.env.PROJECT_COCKPIT_APP_BASE || "http://127.0.0.1:4173").replace(/\/$/, "");
  const bringup = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/bringup`);
  const clients = bringup.clients || [];
  const expectedTargets = ["claude-desktop", "chatgpt", "grok"];
  assert(clients.length >= expectedTargets.length, "not enough subscription clients declared", { clients: clients.map((client) => client.id) });
  for (const target of expectedTargets) {
    assert(clients.some((client) => client.targetClient === target || client.id === target), `missing subscription target ${target}`, { clients });
  }
  for (const client of clients) {
    validateConnectPlan(client);
    const perClient = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client.targetClient)}/connect`);
    assert(perClient.ok === true, "per-client connect endpoint did not return ok", { client, perClient });
    assert(perClient.connect?.registration?.client_id === client.targetClient, "per-client connect endpoint returned the wrong client", { client, perClient });
  }

  const token = await readToken(bringup.auth?.tokenFile);
  const serialized = JSON.stringify(bringup);
  assert(!token || token.length < 8 || !serialized.includes(token), "bringup/connect plan leaked the raw Workbench Context token", {
    tokenFile: bringup.auth?.tokenFile
  });
  assert(serialized.includes("Bearer <workbench-context-token>"), "bringup/connect plan is missing the bearer token placeholder", {});

  const browser = await verifyBrowserUi({ appBase, projectSlug });
  assert(browser.ok === true, "subscription connector UI did not render expected controls", browser);

  const result = {
    ok: true,
    schema: "beagle.multimodel-subscription-connect-plan-verification.v1",
    kind: "subscription-connect-plan",
    projectSlug,
    clients: clients.map((client) => ({
      id: client.id,
      targetClient: client.targetClient,
      url: client.connect?.mcpServer?.url || "",
      firstToolCount: (client.connect?.firstToolCalls || []).length,
      realConnectionObserved: client.realConnectionObserved === true
    })),
    tokenPlaceholderOnly: true,
    ui: {
      cardCount: browser.cardCount,
      copyButtonCount: browser.copyButtonCount,
      setupTextButtonCount: browser.setupTextButtonCount,
      drillButtonCount: browser.drillButtonCount
    },
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-subscription-connect-plan-and-ui"
  };
  await appendVerificationRecord(projectSlug, result);
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(JSON.stringify({
    ok: false,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
});
