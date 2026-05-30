#!/usr/bin/env node

import { access, chmod, copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import os from "node:os";

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

async function pathExists(file) {
  try {
    await access(file);
    return true;
  } catch {
    return false;
  }
}

async function readJson(file, fallback = {}) {
  try {
    return JSON.parse(await readFile(file, "utf8"));
  } catch {
    return fallback;
  }
}

async function writeJson(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function backupIfPresent(file) {
  if (!(await pathExists(file))) return "";
  const backup = `${file}.beagle-backup-${new Date().toISOString().replace(/[:.]/g, "-")}`;
  await copyFile(file, backup);
  return backup;
}

function serverName(projectSlug) {
  return `beagle-workbench-${projectSlug}`;
}

function installedServerConfig({ installDir, projectSlug, clientId, provider }) {
  return {
    command: path.join(installDir, `beagle-workbench-${projectSlug}-mcp`),
    args: [],
    env: {
      COCKPIT_CLIENT_ID: clientId,
      COCKPIT_CLIENT_PROVIDER: provider || clientId,
      COCKPIT_AUTO_HEARTBEAT: "1"
    }
  };
}

async function mergeMcpServerConfig({ file, projectSlug, config, dryRun }) {
  const current = await readJson(file, {});
  const next = {
    ...current,
    mcpServers: {
      ...(current.mcpServers && typeof current.mcpServers === "object" ? current.mcpServers : {}),
      [serverName(projectSlug)]: config
    }
  };
  const backup = dryRun ? "" : await backupIfPresent(file);
  if (!dryRun) await writeJson(file, next);
  return {
    file,
    status: dryRun ? "planned" : "installed",
    backup,
    serverName: serverName(projectSlug)
  };
}

const projectSlug = process.env.PROJECT_SLUG || process.argv.find((arg) => !arg.startsWith("--") && arg !== process.argv[1] && arg !== process.argv[0]) || "darwin-mfc";
const dryRun = process.argv.includes("--dry-run") || process.env.WORKBENCH_MCP_INSTALL_DRY_RUN === "1";
const writeClientConfigs = process.argv.includes("--write-client-configs") || process.env.WORKBENCH_MCP_INSTALL_CLIENT_CONFIGS === "1";
const home = os.homedir();
const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");
const tokenFile = path.join(DATA_DIR, "workbench-context", `${safeSlug(projectSlug)}.http-mcp-token`);
const kitDir = path.resolve(
  process.env.WORKBENCH_MCP_CLIENT_KIT_DIR ||
    path.join(DATA_DIR, "mcp-client-kit", safeSlug(projectSlug))
);
const installDir = path.resolve(
  process.env.WORKBENCH_MCP_INSTALL_DIR ||
    path.join(home, ".config", "beagle-workbench", "mcp", safeSlug(projectSlug))
);
const bridgePath = path.resolve(process.cwd(), "bin/workbench-context-mcp.mjs");
const kitFiles = [
  "README.md",
  "claude_desktop_config.json",
  "cursor_mcp.json",
  "kimi_mcp.json",
  "generic_stdio_mcp.json",
  "http_mcp.json",
  "http_mcp.redacted.json",
  "hosted_subscription_connection.json",
  "hosted_subscription_connection.redacted.json",
  "connection-pack.json",
  "claude_desktop_subscription_setup.txt",
  "chatgpt_subscription_setup.txt",
  "grok_subscription_setup.txt"
];

try {
  for (const name of kitFiles) {
    const file = path.join(kitDir, name);
    if (!(await pathExists(file))) {
      throw new Error(`client kit file is missing: ${file}`);
    }
  }

  const copied = [];
  if (!dryRun) await mkdir(installDir, { recursive: true });
  for (const name of kitFiles) {
    const from = path.join(kitDir, name);
    const to = path.join(installDir, name);
    if (!dryRun) await copyFile(from, to);
    copied.push(to);
  }

  const launcher = path.join(installDir, `beagle-workbench-${projectSlug}-mcp`);
  const launcherScript = [
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    `export COCKPIT_API="\${COCKPIT_API:-http://127.0.0.1:4370}"`,
    `export COCKPIT_PROJECT="\${COCKPIT_PROJECT:-${projectSlug}}"`,
    `export COCKPIT_MCP_PATH="\${COCKPIT_MCP_PATH:-/api/workbench/${projectSlug}/context/mcp}"`,
    `export COCKPIT_AUTO_HEARTBEAT="\${COCKPIT_AUTO_HEARTBEAT:-1}"`,
    `export PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE="\${PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE:-${tokenFile}}"`,
    `if [ -z "\${COCKPIT_TOKEN:-}" ] && [ -r "\${PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE}" ]; then`,
    `  export COCKPIT_TOKEN="$(tr -d '\\r\\n' < "\${PROJECT_COCKPIT_WORKBENCH_CONTEXT_HTTP_MCP_TOKEN_FILE}")"`,
    `fi`,
    `exec node ${JSON.stringify(bridgePath)} "$@"`,
    ""
  ].join("\n");
  if (!dryRun) {
    await writeFile(launcher, launcherScript, "utf8");
    await chmod(launcher, 0o755);
  }

  const clientTargets = [];
  if (writeClientConfigs) {
    clientTargets.push(await mergeMcpServerConfig({
      file: path.join(home, ".claude", "settings.json"),
      projectSlug,
      config: installedServerConfig({ installDir, projectSlug, clientId: "claude-desktop", provider: "anthropic" }),
      dryRun
    }));
    clientTargets.push(await mergeMcpServerConfig({
      file: path.join(home, ".config", "Claude", "claude_desktop_config.json"),
      projectSlug,
      config: installedServerConfig({ installDir, projectSlug, clientId: "claude-desktop", provider: "anthropic" }),
      dryRun
    }));
    clientTargets.push(await mergeMcpServerConfig({
      file: path.join(home, ".cursor", "mcp.json"),
      projectSlug,
      config: installedServerConfig({ installDir, projectSlug, clientId: "cursor", provider: "cursor" }),
      dryRun
    }));
  }

  const manifest = {
    schema: "beagle.workbench-mcp-client-install.v1",
    projectSlug,
    installedAt: new Date().toISOString(),
    dryRun,
    writeClientConfigs,
    kitDir,
    installDir,
    launcher,
    copied,
    clientTargets,
    serverName: serverName(projectSlug),
    truthMode: dryRun ? "planned-install" : "observed-filesystem-install"
  };
  if (!dryRun) {
    await writeJson(path.join(installDir, "install-manifest.json"), manifest);
  }
  console.log(JSON.stringify(manifest, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    kitDir,
    installDir,
    error: error.message,
    truthMode: "install-failed"
  }, null, 2));
  process.exit(1);
}
