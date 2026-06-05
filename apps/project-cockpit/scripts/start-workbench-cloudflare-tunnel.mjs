#!/usr/bin/env node

import { access, appendFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { execFile } from "node:child_process";
import http from "node:http";
import https from "node:https";
import { Resolver } from "node:dns/promises";
import path from "node:path";

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

function execFileCapture(command, args = [], { timeoutMs = 30_000 } = {}) {
  return new Promise((resolve) => {
    execFile(command, args, { timeout: timeoutMs }, (error, stdout, stderr) => {
      resolve({
        code: error?.code ?? 0,
        signal: error?.signal || "",
        stdout: cleanString(stdout),
        stderr: cleanString(stderr),
        error: error?.message || ""
      });
    });
  });
}

async function fileExists(file, mode = constants.F_OK) {
  try {
    await access(file, mode);
    return true;
  } catch {
    return false;
  }
}

async function fetchJson(url, options = {}) {
  const res = await fetch(url, {
    method: options.method || "GET",
    headers: options.headers || undefined,
    body: options.body === undefined ? undefined : JSON.stringify(options.body)
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const error = new Error(`${res.status} ${payload?.error || res.statusText}`);
    error.detail = payload;
    throw error;
  }
  return payload;
}

function requestJson(url, { method = "GET", headers = {}, body, lookup } = {}) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const client = parsed.protocol === "https:" ? https : http;
    const payload = body === undefined ? "" : JSON.stringify(body);
    const req = client.request(parsed, {
      method,
      headers: {
        ...headers,
        ...(payload ? { "content-length": Buffer.byteLength(payload) } : {})
      },
      lookup
    }, (res) => {
      let raw = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => {
        raw += chunk;
      });
      res.on("end", () => {
        const parsedBody = raw ? JSON.parse(raw) : {};
        if (res.statusCode < 200 || res.statusCode >= 300) {
          const error = new Error(`${res.statusCode} ${parsedBody?.error || res.statusMessage}`);
          error.detail = parsedBody;
          reject(error);
          return;
        }
        resolve(parsedBody);
      });
    });
    req.setTimeout(20_000, () => {
      req.destroy(new Error("request timeout"));
    });
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function requestJsonWithPublicDnsFallback(url, options = {}) {
  try {
    return await requestJson(url, options);
  } catch (error) {
    if (error.code !== "ENOTFOUND" && error.code !== "EAI_AGAIN") throw error;
    const resolver = new Resolver();
    resolver.setServers(["1.1.1.1", "8.8.8.8"]);
    const lookup = async (hostname, _options, callback) => {
      try {
        const addresses = await resolver.resolve4(hostname);
        callback(null, addresses[0], 4);
      } catch (lookupError) {
        callback(lookupError);
      }
    };
    return await requestJson(url, { ...options, lookup });
  }
}

async function readLocalMcpToken({ dataDir, projectSlug }) {
  const envToken =
    cleanString(process.env.COCKPIT_TOKEN) ||
    cleanString(process.env.WORKBENCH_CONTEXT_HTTP_MCP_TOKEN) ||
    cleanString(process.env.PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN);
  if (envToken) return envToken;
  return cleanString(await readFile(path.join(dataDir, "workbench-context", `${safeSlug(projectSlug)}.http-mcp-token`), "utf8"));
}

async function waitForTunnelUrl(logFile, timeoutMs = 45_000) {
  const deadline = Date.now() + timeoutMs;
  let raw = "";
  while (Date.now() < deadline) {
    try {
      raw = await readFile(logFile, "utf8");
    } catch {
      raw = "";
    }
    const match = raw.match(/https:\/\/[-a-z0-9]+\.trycloudflare\.com/i);
    if (match) return { url: match[0].replace(/\/$/, ""), raw };
    await new Promise((resolve) => setTimeout(resolve, 750));
  }
  const error = new Error("cloudflared did not report a trycloudflare URL in time");
  error.detail = { logFile, tail: raw.slice(-4000) };
  throw error;
}

async function waitForPublicDns(hostname, timeoutMs = 45_000) {
  const deadline = Date.now() + timeoutMs;
  let lastResult = null;
  while (Date.now() < deadline) {
    const result = await execFileCapture("dig", ["+short", "@1.1.1.1", hostname, "A"], { timeoutMs: 5000 });
    lastResult = result;
    const addresses = result.stdout
      .split(/\s+/)
      .map((item) => item.trim())
      .filter((item) => /^\d+\.\d+\.\d+\.\d+$/.test(item));
    if (addresses.length) {
      return addresses;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  const error = new Error(`public DNS did not resolve ${hostname} in time`);
  error.detail = { lastResult };
  throw error;
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const dataDir =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");
const cloudflared = path.resolve(
  process.env.CLOUDFLARED_BIN ||
    path.join(dataDir, "tools", "cloudflared")
);
const session = cleanString(
  process.env.PROJECT_COCKPIT_CLOUDFLARED_TMUX_SESSION,
  `project-cockpit-cloudflared-${safeSlug(projectSlug)}`
);
const target = cleanString(process.env.PROJECT_COCKPIT_CLOUDFLARED_TARGET, apiBase);
const logDir = path.join(dataDir, "tunnels");
const logFile = path.join(logDir, `${safeSlug(projectSlug)}.cloudflared.log`);
const stateFile = path.join(logDir, `${safeSlug(projectSlug)}.cloudflared.json`);
const verificationPath = path.join(dataDir, "multimodel-chat", `${safeSlug(projectSlug)}.verifications.jsonl`);

try {
  if (!(await fileExists(cloudflared, constants.X_OK))) {
    throw new Error(`cloudflared is missing or not executable: ${cloudflared}`);
  }
  await mkdir(logDir, { recursive: true });
  await mkdir(path.dirname(verificationPath), { recursive: true });
  await writeFile(logFile, "", "utf8");

  await execFileCapture("tmux", ["kill-session", "-t", session], { timeoutMs: 5000 });
  const command = [
    "cd", JSON.stringify(process.cwd()), "&&",
    JSON.stringify(cloudflared),
    "tunnel",
    "--url", JSON.stringify(target),
    "--no-autoupdate",
    ">>", JSON.stringify(logFile),
    "2>&1"
  ].join(" ");
  const tmux = await execFileCapture("tmux", ["new-session", "-d", "-s", session, command], { timeoutMs: 5000 });
  if (tmux.code !== 0) {
    throw Object.assign(new Error(tmux.stderr || tmux.error || "failed to start cloudflared tmux session"), { detail: tmux });
  }

  const tunnel = await waitForTunnelUrl(logFile);
  const publicBase = tunnel.url;
  await waitForPublicDns(new URL(publicBase).hostname, 120_000);
  const config = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/public-endpoint`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: {
      publicBase,
      trustedHosted: true,
      note: "Cloudflare quick tunnel activated by Project Cockpit for hosted MCP subscription clients."
    }
  });

  const token = await readLocalMcpToken({ dataDir, projectSlug });
  const mcpUrl = `${publicBase}/api/workbench/${encodeURIComponent(projectSlug)}/context/mcp`;
  const mcpInit = await requestJsonWithPublicDnsFallback(mcpUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${token}`
    },
    body: {
      jsonrpc: "2.0",
      id: `cloudflare-tunnel-${Date.now()}`,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "workbench-cloudflare-tunnel-verifier", version: "0.1.0" }
      }
    }
  });
  if (mcpInit.result?.serverInfo?.name !== "beagle-workbench-context") {
    const error = new Error("public MCP endpoint returned an unexpected initialize response");
    error.detail = mcpInit;
    throw error;
  }

  const result = {
    ok: true,
    schema: "beagle.workbench-cloudflare-tunnel.v1",
    kind: "public-cloudflare-tunnel",
    projectSlug,
    session,
    target,
    publicBase,
    mcpUrl,
    hostedClientReachable: config.publicEndpoint?.hostedClientReachable === true,
    publicEndpoint: config.publicEndpoint,
    logFile,
    stateFile,
    verifiedAt: new Date().toISOString(),
    mutates: true,
    truthMode: "observed-cloudflare-quick-tunnel-public-mcp"
  };
  await writeFile(stateFile, `${JSON.stringify(result, null, 2)}\n`, "utf8");
  await appendFile(verificationPath, `${JSON.stringify({ ...result, generatedAt: new Date().toISOString() })}\n`, "utf8");
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    session,
    target,
    cloudflared,
    error: error.message,
    detail: error.detail || null,
    truthMode: "cloudflare-tunnel-failed"
  }, null, 2));
  process.exit(1);
}
