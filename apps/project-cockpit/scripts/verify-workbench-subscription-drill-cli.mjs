#!/usr/bin/env node

import { spawn } from "node:child_process";
import path from "node:path";

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

function runProcess(command, args = [], { timeoutMs = 30_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: process.cwd(),
      env: process.env,
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
      resolve({ code, stdout, stderr });
    });
  });
}

function parseJson(stdout) {
  const text = cleanString(stdout);
  try {
    return JSON.parse(text);
  } catch {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start >= 0 && end > start) return JSON.parse(text.slice(start, end + 1));
    throw Object.assign(new Error("JSON output not found"), { detail: { stdout } });
  }
}

const projectSlug = cleanString(process.env.PROJECT_SLUG || process.argv[2], "darwin-mfc");
const client = cleanString(process.env.CLIENT || process.argv[3], "chatgpt");
const marker = `subscription-drill-cli-verifier-${Date.now().toString(36)}`;

try {
  const run = await runProcess("node", [
    path.join("scripts", "run-workbench-subscription-drill.mjs"),
    "--json",
    "--allow-timeout",
    "--timeout-ms=750",
    "--poll-ms=250",
    `--marker=${marker}`,
    `--project=${projectSlug}`,
    `--client=${client}`
  ], { timeoutMs: 20_000 });
  assert(run.code === 0, "subscription drill CLI verifier command failed", run);
  const result = parseJson(run.stdout);
  assert(result.schema === "beagle.workbench-subscription-drill-cli.v1", "unexpected drill CLI schema", result);
  assert(result.projectSlug === projectSlug, "drill CLI project mismatch", result);
  assert(result.client?.targetClient === client || result.client?.id === client, "drill CLI client mismatch", result);
  assert(result.marker === marker, "drill CLI marker mismatch", result);
  assert(result.messageId && result.messageId.includes(marker.replace(/[^a-zA-Z0-9:_-]/g, "_")), "drill CLI did not create the expected handoff", result);
  assert(result.outcome === "timeout", "drill CLI unexpectedly observed a real subscription reply", result);
  assert(result.canceled === true, "drill CLI did not clean up the timed-out handoff", result);
  assert(result.status?.status === "canceled", "drill CLI final status was not canceled", result);
  assert(result.setupTextPresent === true, "drill CLI did not fetch setup text", result);
  assert(result.activationPromptPresent === true, "drill CLI did not fetch activation prompt", result);
  assert(result.truthMode === "observed-subscription-drill-created-and-watched-no-fake-success", "drill CLI truth mode is too weak", result);
  console.log(JSON.stringify({
    ok: true,
    schema: "beagle.workbench-subscription-drill-cli-verification.v1",
    kind: "subscription-drill-cli-verification",
    projectSlug,
    client,
    marker,
    messageId: result.messageId,
    outcome: result.outcome,
    canceled: result.canceled,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-operator-cli-drill-create-watch-cleanup"
  }, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    client,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
