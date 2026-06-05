// Agent routes — persistent agent pod lifecycle + WebSocket PTY bridge.
//
// Endpoints:
//   GET  /api/projects/:slug/agent/sessions            — list active agent sessions
//   POST /api/projects/:slug/agent/session/start       — spawn agent pod for kind
//   POST /api/projects/:slug/agent/session/:kind/pause — scale StatefulSet to 0
//   POST /api/projects/:slug/agent/session/:kind/stop  — delete StatefulSet + PVC
//   POST /api/projects/:slug/agent/session/:kind/input — write to the live agent PTY
//   GET  /api/projects/:slug/agent/session/:kind/terminal — snapshot shared PTY state
//   GET  /api/projects/:slug/agent/session/:kind       — session detail
//   WS   /ws/projects/:slug/agent/:kind                — stream tmux via kubectl exec
//
// Supported kinds: claude-code, codex, local-sglang, custom
//
// This module is imported by server/index.mjs. It reuses existing helpers:
//   - runKubectlJson(args) for pod status
//   - runKubectlPty(args) for interactive WebSocket bridging
//
// ENV:
//   AGENT_IMAGE    — the default agent container image
//   AGENT_NAMESPACE — K8s namespace (default: beagle)

import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { access, readFile } from "node:fs/promises";
import path from "node:path";
import pty from "node-pty";
import { WebSocketServer } from "ws";
import { idempotent } from "./contract.mjs";

const AGENT_NAMESPACE = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";
const DEFAULT_AGENT_IMAGE = "192.168.3.207:5003/beagle-agent:claude-codex-model-registry-20260523T2301Z";
const AGENT_IMAGE = process.env.PROJECT_COCKPIT_AGENT_IMAGE || DEFAULT_AGENT_IMAGE;
const LOCAL_AGENT_KINDS = ["desktop-claude", "desktop-codex", "desktop-cursor", "desktop-kimi"];
const AGENT_KINDS = ["claude-code", "codex", "local-sglang", "custom", ...LOCAL_AGENT_KINDS];
const MANIFEST_DIR = process.env.PROJECT_COCKPIT_AGENT_MANIFEST_DIR
  || "/home/devsounio/beagle/k8s/agent-pods";

// MCP injection: where the cockpit API is reachable from inside the cluster.
// Agent pods run in-cluster, so they use the ClusterIP service DNS.
const COCKPIT_INTERNAL_URL = process.env.PROJECT_COCKPIT_INTERNAL_URL
  || "http://project-cockpit.beagle.svc.cluster.local";

const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "kubectl";
const LOCAL_REPO_BASE = process.env.PROJECT_COCKPIT_LOCAL_REPO_BASE || "/home/devsounio";
const AGENT_TERMINAL_IDLE_MS = Math.max(30_000, Number(process.env.PROJECT_COCKPIT_AGENT_TERMINAL_IDLE_MS) || 10 * 60_000);
const AGENT_TERMINAL_PING_MS = Math.max(5000, Number(process.env.PROJECT_COCKPIT_AGENT_TERMINAL_PING_MS) || 15_000);
const AGENT_TERMINAL_SCROLLBACK_LIMIT = Math.max(4000, Number(process.env.PROJECT_COCKPIT_AGENT_TERMINAL_SCROLLBACK_LIMIT) || 80_000);
const agentTerminalRuntimes = new Map();

function normKind(kind) {
  if (!AGENT_KINDS.includes(kind)) {
    const err = new Error(`unknown agent kind: ${kind}`);
    err.statusCode = 400;
    throw err;
  }
  return kind;
}

function requireConfirmed(body, actionLabel) {
  if (body?.confirmed === true) {
    return;
  }
  const err = new Error(`${actionLabel} requires confirmed: true`);
  err.statusCode = 400;
  throw err;
}

function resourceName(slug, kind) {
  return `agent-${slug}-${kind}`;
}

function agentRuntimeKey(slug, kind) {
  return `${slug}:${kind}`;
}

function isLocalAgentKind(kind) {
  return LOCAL_AGENT_KINDS.includes(kind);
}

function shellQuote(value = "") {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function localAgentBinary(kind) {
  if (kind === "desktop-claude") return process.env.PROJECT_COCKPIT_CLAUDE_COMMAND || "claude";
  if (kind === "desktop-codex") return process.env.PROJECT_COCKPIT_CODEX_COMMAND || "codex";
  if (kind === "desktop-cursor") return process.env.PROJECT_COCKPIT_CURSOR_COMMAND || "cursor-agent";
  if (kind === "desktop-kimi") return process.env.PROJECT_COCKPIT_KIMI_COMMAND || "kimi";
  return "";
}

function localAgentLabel(kind) {
  if (kind === "desktop-claude") return "Claude Code desktop";
  if (kind === "desktop-codex") return "Codex desktop";
  if (kind === "desktop-cursor") return "Cursor Agent desktop";
  if (kind === "desktop-kimi") return "Kimi desktop";
  return `${kind} desktop`;
}

function localAgentRuntime(slug, kind) {
  return agentTerminalRuntimes.get(agentRuntimeKey(slug, kind));
}

function loadProjectAgentContextSync(slug) {
  try {
    const catalogPath = path.join(process.cwd(), "public", "project-catalog.json");
    const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
    const project = (catalog.projects || []).find((item) => item.projectSlug === slug) || {};
    return {
      repoUrl: project.repoUrl || "",
      branch: project.branch || project.workspaceBootstrapBranch || "main",
      localRepoRoot: project.localRepoRoot || "",
      workspaceRoot: project.workspaceRoot || `/workspace/${slug}`,
    };
  } catch {
    return {
      repoUrl: "",
      branch: "main",
      localRepoRoot: "",
      workspaceRoot: `/workspace/${slug}`,
    };
  }
}

function resolveLocalRepoRootSync(slug, projectContext) {
  const candidates = [
    projectContext.localRepoRoot,
    repoBasename(projectContext.repoUrl) ? path.join(LOCAL_REPO_BASE, repoBasename(projectContext.repoUrl)) : "",
    path.join(LOCAL_REPO_BASE, slug),
    path.join(LOCAL_REPO_BASE, "projects", slug),
  ].filter(Boolean);

  return candidates.find((candidate) => existsSync(path.join(candidate, ".git")))
    || candidates[0]
    || process.cwd();
}

function localAgentSessionRecord(slug, kind) {
  const runtime = localAgentRuntime(slug, kind);
  const binary = localAgentBinary(kind);
  const context = loadProjectAgentContextSync(slug);
  const repoRoot = resolveLocalRepoRootSync(slug, context);
  return {
    kind,
    name: `local:${kind}`,
    label: localAgentLabel(kind),
    local: true,
    command: binary,
    workspaceMode: "local-desktop-pty",
    workspaceAuthority: `local checkout at ${repoRoot}`,
    replicas: runtime && !runtime.exited ? 1 : 0,
    readyReplicas: runtime && !runtime.exited ? 1 : 0,
    createdAt: runtime?.startedAt || "",
    pods: [],
    status: runtime && !runtime.exited ? "running" : "idle",
    reason: binary ? "" : "local command not configured"
  };
}

function broadcastAgentRuntime(runtime, payload) {
  const message = JSON.stringify(payload);
  for (const socket of runtime.sockets) {
    if (socket.readyState !== 1) {
      runtime.sockets.delete(socket);
      continue;
    }
    try {
      socket.send(message);
    } catch {
      runtime.sockets.delete(socket);
    }
  }
}

function trimScrollback(runtime) {
  if (runtime.scrollback.length > AGENT_TERMINAL_SCROLLBACK_LIMIT) {
    runtime.scrollback = runtime.scrollback.slice(-AGENT_TERMINAL_SCROLLBACK_LIMIT);
  }
}

function stripAnsi(value = "") {
  return String(value)
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1b\][^\x07]*(\x07|\x1b\\)/g, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
}

function terminalStateFromPlainTail(plainTail = "") {
  const compact = String(plainTail || "").replace(/\s+/g, " ").trim();
  const lower = compact.toLowerCase();
  const fused = lower.replace(/[^a-z0-9]+/g, "");
  const readyPrompt = /plan,\s*search,\s*build anything/i.test(compact)
    || /kimi k[0-9.]+\s+~\/darwin-mfc/i.test(lower)
    || /try composer via \/models/i.test(lower)
    || /welcome\s*to\s*opus/i.test(compact)
    || /try"?create\s+a/i.test(compact)
    || /for\s*shortcuts/i.test(compact)
    || fused.includes("plansearchbuildanything")
    || fused.includes("trycomposerviamodels")
    || fused.includes("welcometoopus")
    || fused.includes("trycreatea")
    || fused.includes("forshortcuts");
  const setupPrompt = /migrate\s*subagents/i.test(compact)
    || /proceed\s*with\s*selected/i.test(compact)
    || /skip\s*for\s*now/i.test(compact)
    || fused.includes("migratesubagents")
    || fused.includes("proceedwithselected")
    || fused.includes("skipfornow");
  const trustPrompt = !readyPrompt && !setupPrompt && (/do you trust the contents of this directory/i.test(compact)
    || /quick safety check/i.test(compact)
    || /yes,\s*i trust this folder/i.test(compact)
    || /yes,\s*continue/i.test(compact)
    || /press enter to continue/i.test(compact)
    || fused.includes("doyoutrustthecontentsofthisdirectory")
    || fused.includes("quicksafetycheck")
    || fused.includes("yesitrustthisfolder")
    || fused.includes("yescontinue")
    || fused.includes("pressentertocontinue"));
  return {
    state: readyPrompt ? "ready" : setupPrompt ? "setup-prompt" : trustPrompt ? "trust-prompt" : compact ? "observed" : "empty",
    blockedByTrustPrompt: trustPrompt,
    blockedBySetupPrompt: setupPrompt,
    readyForInput: readyPrompt && !trustPrompt,
    promptAction: setupPrompt ? "choose-setup-option" : trustPrompt ? "press-enter-to-continue" : "",
    trustAction: trustPrompt ? "press-enter-to-continue" : "",
    truthMode: "observed-terminal-tail-classification"
  };
}

function agentTerminalRuntimeSnapshot(runtime, { tailBytes = 4000 } = {}) {
  const bytes = Math.max(200, Math.min(16_000, Number(tailBytes) || 4000));
  const tail = runtime?.scrollback ? runtime.scrollback.slice(-bytes) : "";
  const plainTail = stripAnsi(tail).slice(-bytes);
  return {
    projectSlug: runtime?.slug || "",
    kind: runtime?.kind || "",
    status: runtime && !runtime.exited ? "running" : "idle",
    podName: runtime?.podName || "",
    shared: Boolean(runtime && !runtime.exited),
    attachedSockets: runtime?.sockets?.size || 0,
    startedAt: runtime?.startedAt || "",
    lastInputAt: runtime?.lastInputAt || "",
    lastOutputAt: runtime?.lastOutputAt || "",
    exitCode: runtime?.exitCode ?? null,
    tail,
    plainTail,
    terminalState: terminalStateFromPlainTail(plainTail),
    tailBytes: Buffer.byteLength(tail),
    truthMode: "observed-runtime"
  };
}

function scheduleAgentRuntimeIdleStop(runtime) {
  if (runtime.idleTimer) clearTimeout(runtime.idleTimer);
  runtime.idleTimer = setTimeout(() => {
    if (runtime.sockets.size > 0) return;
    try { runtime.pty.kill(); } catch { /* already gone */ }
  }, AGENT_TERMINAL_IDLE_MS);
}

function ensureAgentTerminalRuntime(slug, kind) {
  normKind(kind);
  const key = agentRuntimeKey(slug, kind);
  const existing = agentTerminalRuntimes.get(key);
  if (existing && !existing.exited) {
    if (existing.idleTimer) {
      clearTimeout(existing.idleTimer);
      existing.idleTimer = null;
    }
    return existing;
  }

  if (isLocalAgentKind(kind)) {
    return ensureLocalAgentTerminalRuntime(slug, kind, key);
  }

  const name = resourceName(slug, kind);
  const podName = `${name}-0`;

  console.log(`[agent-pty] starting shared runtime slug=${slug} kind=${kind} pod=${podName}`);

  const kubectl = pty.spawn(KUBECTL, [
    "-n", AGENT_NAMESPACE,
    "exec", "-it", podName, "-c", "agent",
    "--",
    "bash", "-c", "exec /home/agent/start-agent.sh"
  ], {
    name: "xterm-256color",
    cols: 120,
    rows: 34,
    cwd: process.cwd(),
    env: process.env
  });

  const runtime = {
    key,
    slug,
    kind,
    podName,
    pty: kubectl,
    sockets: new Set(),
    scrollback: "",
    startedAt: new Date().toISOString(),
    lastInputAt: "",
    lastOutputAt: "",
    idleTimer: null,
    pingTimer: null,
    exited: false,
    exitCode: null
  };
  agentTerminalRuntimes.set(key, runtime);
  runtime.pingTimer = setInterval(() => {
    for (const socket of [...runtime.sockets]) {
      if (socket.readyState !== 1 || socket.isAlive === false) {
        runtime.sockets.delete(socket);
        try { socket.terminate(); } catch { /* already closed */ }
        continue;
      }
      socket.isAlive = false;
      try { socket.ping(); } catch { runtime.sockets.delete(socket); }
    }
  }, AGENT_TERMINAL_PING_MS);

  kubectl.onData((data) => {
    runtime.lastOutputAt = new Date().toISOString();
    runtime.scrollback += data;
    trimScrollback(runtime);
    broadcastAgentRuntime(runtime, { type: "data", data });
    broadcastAgentRuntime(runtime, {
      type: "snapshot",
      data: agentTerminalRuntimeSnapshot(runtime, { tailBytes: 2200 })
    });
  });

  kubectl.onExit(({ exitCode }) => {
    runtime.exited = true;
    runtime.exitCode = exitCode;
    if (runtime.idleTimer) clearTimeout(runtime.idleTimer);
    if (runtime.pingTimer) clearInterval(runtime.pingTimer);
    broadcastAgentRuntime(runtime, { type: "exit", code: exitCode });
    for (const socket of runtime.sockets) {
      try { socket.close(); } catch { /* already closed */ }
    }
    runtime.sockets.clear();
    agentTerminalRuntimes.delete(key);
  });

  return runtime;
}

function ensureLocalAgentTerminalRuntime(slug, kind, key = agentRuntimeKey(slug, kind)) {
  const context = loadProjectAgentContextSync(slug);
  const repoRoot = resolveLocalRepoRootSync(slug, context);
  const binary = localAgentBinary(kind);
  const label = localAgentLabel(kind);
  const cockpitApi = process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL
    || process.env.PROJECT_COCKPIT_API_BASE
    || "http://127.0.0.1:4370";
  const script = `
cd ${shellQuote(repoRoot)}
export BEAGLE_WORKBENCH_PROJECT=${shellQuote(slug)}
export COCKPIT_PROJECT=${shellQuote(slug)}
export COCKPIT_API=${shellQuote(cockpitApi)}
export COCKPIT_CLIENT_ID=${shellQuote(kind)}
export COCKPIT_CLIENT_PROVIDER=${shellQuote(kind.replace(/^desktop-/, ""))}
printf '\\033[38;2;170;205;191m%s\\033[0m\\n' ${shellQuote(`${label} attached to ${repoRoot}`)}
if ! command -v ${shellQuote(binary)} >/dev/null 2>&1; then
  printf '\\033[38;2;216;111;102m%s\\033[0m\\n' ${shellQuote(`${binary} not found on PATH; falling back to a local shell.`)}
  exec bash -l
fi
exec ${shellQuote(binary)}
`;

  console.log(`[agent-pty] starting local desktop runtime slug=${slug} kind=${kind} cwd=${repoRoot}`);

  const localPty = pty.spawn("bash", ["-lc", script], {
    name: "xterm-256color",
    cols: 120,
    rows: 34,
    cwd: repoRoot,
    env: {
      ...process.env,
      BEAGLE_WORKBENCH_PROJECT: slug,
      COCKPIT_PROJECT: slug,
      COCKPIT_API: cockpitApi,
      COCKPIT_CLIENT_ID: kind,
      COCKPIT_CLIENT_PROVIDER: kind.replace(/^desktop-/, "")
    }
  });

  const runtime = {
    key,
    slug,
    kind,
    podName: `local:${kind}`,
    pty: localPty,
    sockets: new Set(),
    scrollback: "",
    startedAt: new Date().toISOString(),
    lastInputAt: "",
    lastOutputAt: "",
    idleTimer: null,
    pingTimer: null,
    exited: false,
    exitCode: null,
    local: true,
    repoRoot
  };
  agentTerminalRuntimes.set(key, runtime);
  runtime.pingTimer = setInterval(() => {
    for (const socket of [...runtime.sockets]) {
      if (socket.readyState !== 1 || socket.isAlive === false) {
        runtime.sockets.delete(socket);
        try { socket.terminate(); } catch { /* already closed */ }
        continue;
      }
      socket.isAlive = false;
      try { socket.ping(); } catch { runtime.sockets.delete(socket); }
    }
  }, AGENT_TERMINAL_PING_MS);

  localPty.onData((data) => {
    runtime.lastOutputAt = new Date().toISOString();
    runtime.scrollback += data;
    trimScrollback(runtime);
    broadcastAgentRuntime(runtime, { type: "data", data });
    broadcastAgentRuntime(runtime, {
      type: "snapshot",
      data: agentTerminalRuntimeSnapshot(runtime, { tailBytes: 2200 })
    });
  });

  localPty.onExit(({ exitCode }) => {
    runtime.exited = true;
    runtime.exitCode = exitCode;
    if (runtime.idleTimer) clearTimeout(runtime.idleTimer);
    if (runtime.pingTimer) clearInterval(runtime.pingTimer);
    broadcastAgentRuntime(runtime, { type: "exit", code: exitCode });
    for (const socket of runtime.sockets) {
      try { socket.close(); } catch { /* already closed */ }
    }
    runtime.sockets.clear();
    agentTerminalRuntimes.delete(key);
  });

  return runtime;
}

export function writeAgentTerminalInput(slug, kind, { data = "", text = "", enter = false } = {}) {
  normKind(kind);
  const raw = data || text;
  if (typeof raw !== "string" || raw.length === 0) {
    const err = new Error("input data is required");
    err.statusCode = 400;
    throw err;
  }
  if (raw.length > 16_000) {
    const err = new Error("input data exceeds 16000 characters");
    err.statusCode = 413;
    throw err;
  }
  const runtime = ensureAgentTerminalRuntime(slug, kind);
  const payload = enter && !raw.endsWith("\n") ? `${raw}\n` : raw;
  runtime.pty.write(payload);
  runtime.lastInputAt = new Date().toISOString();
  const snapshot = agentTerminalRuntimeSnapshot(runtime, { tailBytes: 2200 });
  broadcastAgentRuntime(runtime, {
    type: "snapshot",
    data: snapshot
  });
  return {
    projectSlug: slug,
    kind,
    podName: runtime.podName,
    bytes: Buffer.byteLength(payload),
    entered: enter === true,
    attachedSockets: runtime.sockets.size,
    startedAt: runtime.startedAt,
    lastInputAt: runtime.lastInputAt,
    snapshot,
    truthMode: "observed"
  };
}

export function ensureAgentTerminalSession(slug, kind, { tailBytes = 4000 } = {}) {
  normKind(kind);
  const runtime = ensureAgentTerminalRuntime(slug, kind);
  return {
    ...agentTerminalRuntimeSnapshot(runtime, { tailBytes }),
    truthMode: "observed-runtime"
  };
}

export function agentTerminalSnapshot(slug, kind, { tailBytes = 4000 } = {}) {
  normKind(kind);
  const runtime = agentTerminalRuntimes.get(agentRuntimeKey(slug, kind));
  return {
    ...agentTerminalRuntimeSnapshot(runtime, { tailBytes }),
    projectSlug: slug,
    kind,
    podName: runtime?.podName || `${resourceName(slug, kind)}-0`
  };
}

async function loadProjectAgentContext(slug) {
  try {
    const catalogPath = path.join(process.cwd(), "public", "project-catalog.json");
    const catalog = JSON.parse(await readFile(catalogPath, "utf8"));
    const project = (catalog.projects || []).find((item) => item.projectSlug === slug) || {};
    return {
      repoUrl: project.repoUrl || "",
      branch: project.branch || project.workspaceBootstrapBranch || "main",
      localRepoRoot: project.localRepoRoot || "",
      workspaceRoot: project.workspaceRoot || `/workspace/${slug}`,
    };
  } catch {
    return {
      repoUrl: "",
      branch: "main",
      localRepoRoot: "",
      workspaceRoot: `/workspace/${slug}`,
    };
  }
}

async function pathExists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

function repoBasename(repoUrl) {
  try {
    const pathname = new URL(repoUrl).pathname;
    return path.basename(pathname, ".git");
  } catch {
    return "";
  }
}

async function resolveLocalRepoRoot(slug, projectContext) {
  const candidates = [
    projectContext.localRepoRoot,
    repoBasename(projectContext.repoUrl) ? path.join(LOCAL_REPO_BASE, repoBasename(projectContext.repoUrl)) : "",
    path.join(LOCAL_REPO_BASE, slug),
    path.join(LOCAL_REPO_BASE, "projects", slug),
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (await pathExists(path.join(candidate, ".git"))) {
      return candidate;
    }
  }

  const err = new Error(`local repo not found for ${slug}`);
  err.statusCode = 404;
  err.candidates = candidates;
  throw err;
}

async function runLocalShell(script, env = {}, { timeoutMs = 120000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn("bash", ["-lc", script], {
      cwd: process.cwd(),
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error("local sync timeout"));
    }, timeoutMs);
    child.stdout.on("data", (data) => { stdout += data.toString(); });
    child.stderr.on("data", (data) => { stderr += data.toString(); });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code !== 0) {
        reject(new Error(`local sync exit ${code}: ${stderr || stdout}`));
      } else {
        resolve({ stdout, stderr });
      }
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

export async function syncLocalRepoToAgent(slug, kind) {
  normKind(kind);
  const projectContext = await loadProjectAgentContext(slug);
  const localRoot = await resolveLocalRepoRoot(slug, projectContext);
  const session = await getAgentSession(slug, kind);
  if (session.status !== "running") {
    const err = new Error(`agent ${kind} is ${session.status}; sync requires running`);
    err.statusCode = 409;
    throw err;
  }

  const podName = `${resourceName(slug, kind)}-0`;
  const script = `
set -euo pipefail
cd "$LOCAL_ROOT"
changed_count=$({ git diff --name-only --diff-filter=ACMRTUXB; git ls-files --others --exclude-standard; } | sed '/^$/d' | wc -l | tr -d ' ')
deleted_count=$(git diff --name-only --diff-filter=D | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$changed_count" != "0" ]; then
  { git diff --name-only -z --diff-filter=ACMRTUXB; git ls-files --others --exclude-standard -z; } |
    tar --null -T - -cf - |
    "$KUBECTL_BIN" -n "$AGENT_NAMESPACE" exec -i "$POD_NAME" -c agent -- sh -lc 'tar -C "$1" -xf -' sh "$WORKSPACE_ROOT"
fi
if [ "$deleted_count" != "0" ]; then
  git diff --name-only -z --diff-filter=D |
    "$KUBECTL_BIN" -n "$AGENT_NAMESPACE" exec -i "$POD_NAME" -c agent -- sh -lc 'cd "$1" && xargs -0 -r rm -f --' sh "$WORKSPACE_ROOT"
fi
local_status="$(git status --porcelain=v1)"
agent_status="$("$KUBECTL_BIN" -n "$AGENT_NAMESPACE" exec "$POD_NAME" -c agent -- sh -lc 'git -C "$1" status --porcelain=v1' sh "$WORKSPACE_ROOT")"
if [ "$local_status" != "$agent_status" ]; then
  printf 'LOCAL\\n%s\\nAGENT\\n%s\\n' "$local_status" "$agent_status" >&2
  exit 42
fi
printf '{"changedCount":%s,"deletedCount":%s}\\n' "$changed_count" "$deleted_count"
`;
  const result = await runLocalShell(script, {
    LOCAL_ROOT: localRoot,
    WORKSPACE_ROOT: projectContext.workspaceRoot,
    POD_NAME: podName,
    AGENT_NAMESPACE,
    KUBECTL_BIN: KUBECTL,
  });
  const lastLine = result.stdout.trim().split("\n").pop() || "{}";
  const summary = JSON.parse(lastLine);
  return {
    ...summary,
    kind,
    localRoot,
    podName,
    workspaceRoot: projectContext.workspaceRoot,
  };
}

export async function syncAgentRepoToLocal(slug, kind) {
  normKind(kind);
  const projectContext = await loadProjectAgentContext(slug);
  const localRoot = await resolveLocalRepoRoot(slug, projectContext);
  const session = await getAgentSession(slug, kind);
  if (session.status !== "running") {
    const err = new Error(`agent ${kind} is ${session.status}; sync requires running`);
    err.statusCode = 409;
    throw err;
  }

  const podName = `${resourceName(slug, kind)}-0`;
  const script = `
set -euo pipefail
cd "$LOCAL_ROOT"
changed_count=$("$KUBECTL_BIN" -n "$AGENT_NAMESPACE" exec "$POD_NAME" -c agent -- sh -lc 'cd "$1" && { git diff --name-only --diff-filter=ACMRTUXB; git ls-files --others --exclude-standard; } | sed "/^$/d" | wc -l | tr -d " "' sh "$WORKSPACE_ROOT")
deleted_count=$("$KUBECTL_BIN" -n "$AGENT_NAMESPACE" exec "$POD_NAME" -c agent -- sh -lc 'cd "$1" && git diff --name-only --diff-filter=D | sed "/^$/d" | wc -l | tr -d " "' sh "$WORKSPACE_ROOT")
if [ "$changed_count" != "0" ]; then
  "$KUBECTL_BIN" -n "$AGENT_NAMESPACE" exec "$POD_NAME" -c agent -- sh -lc 'cd "$1" && { git diff --name-only -z --diff-filter=ACMRTUXB; git ls-files --others --exclude-standard -z; } | tar --null -T - -cf -' sh "$WORKSPACE_ROOT" |
    tar -C "$LOCAL_ROOT" -xf -
fi
if [ "$deleted_count" != "0" ]; then
  "$KUBECTL_BIN" -n "$AGENT_NAMESPACE" exec "$POD_NAME" -c agent -- sh -lc 'cd "$1" && git diff --name-only -z --diff-filter=D' sh "$WORKSPACE_ROOT" |
    xargs -0 -r -I '{}' rm -f -- "$LOCAL_ROOT/{}"
fi
local_status="$(git status --porcelain=v1)"
agent_status="$("$KUBECTL_BIN" -n "$AGENT_NAMESPACE" exec "$POD_NAME" -c agent -- sh -lc 'git -C "$1" status --porcelain=v1' sh "$WORKSPACE_ROOT")"
if [ "$local_status" != "$agent_status" ]; then
  printf 'LOCAL\\n%s\\nAGENT\\n%s\\n' "$local_status" "$agent_status" >&2
  exit 42
fi
printf '{"changedCount":%s,"deletedCount":%s}\\n' "$changed_count" "$deleted_count"
`;
  const result = await runLocalShell(script, {
    LOCAL_ROOT: localRoot,
    WORKSPACE_ROOT: projectContext.workspaceRoot,
    POD_NAME: podName,
    AGENT_NAMESPACE,
    KUBECTL_BIN: KUBECTL,
  });
  const lastLine = result.stdout.trim().split("\n").pop() || "{}";
  const summary = JSON.parse(lastLine);
  return {
    ...summary,
    kind,
    localRoot,
    podName,
    workspaceRoot: projectContext.workspaceRoot,
  };
}

async function runKubectl(args, { input, timeoutMs = 15000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(KUBECTL, args, { stdio: ["pipe", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error(`kubectl timeout: ${args.join(" ")}`));
    }, timeoutMs);
    child.stdout.on("data", (d) => { stdout += d.toString(); });
    child.stderr.on("data", (d) => { stderr += d.toString(); });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code !== 0) {
        reject(new Error(`kubectl exit ${code}: ${stderr || stdout}`));
      } else {
        resolve(stdout);
      }
    });
    child.on("error", (e) => { clearTimeout(timer); reject(e); });
    if (input !== undefined) {
      child.stdin.write(input);
      child.stdin.end();
    }
  });
}

async function renderManifest(templatePath, substitutions) {
  let content = await readFile(templatePath, "utf8");
  for (const [key, value] of Object.entries(substitutions)) {
    content = content.replaceAll(`\${${key}}`, value);
  }
  return content;
}

// ─── MCP injection ─────────────────────────────────────────────────────

/**
 * Compose the mcp.json that the agent pod's Claude Code will read.
 * Points at the bundled cockpit-mcp-server.mjs running as a stdio MCP server.
 */
function renderMCPConfig(slug) {
  return {
    mcpServers: {
      cockpit: {
        command: "sh",
        args: ["-lc", "exec node /home/agent/.config/claude-code/cockpit-mcp-server.mjs"],
        env: {
          COCKPIT_API: COCKPIT_INTERNAL_URL,
          COCKPIT_PROJECT: slug
        }
      }
    }
  };
}

function mcpConfigMapName(slug) {
  return `agent-${slug}-mcp-config`;
}

/**
 * Apply the per-project agent MCP ConfigMap.
 * Contains mcp.json + the cockpit-mcp-server.mjs source.
 * Mounted into the agent pod at /home/agent/.config/claude-code/
 *
 * Name is per-project so multiple projects in the same namespace don't collide.
 * The StatefulSet template references ${MCP_CONFIGMAP_NAME} which we substitute.
 */
async function applyAgentMCPConfigMap(slug, kind) {
  const mcpJson = JSON.stringify(renderMCPConfig(slug), null, 2);
  const mcpServerSrc = await readFile(
    path.join(MANIFEST_DIR, "cockpit-mcp-server.mjs"),
    "utf8"
  );

  const name = mcpConfigMapName(slug);
  const configMap = {
    apiVersion: "v1",
    kind: "ConfigMap",
    metadata: {
      name,
      namespace: AGENT_NAMESPACE,
      labels: {
        app: "beagle-agent",
        project: slug
      }
    },
    data: {
      "mcp.json": mcpJson,
      "cockpit-mcp-server.mjs": mcpServerSrc
    }
  };

  await runKubectl(
    ["-n", AGENT_NAMESPACE, "apply", "-f", "-"],
    { input: JSON.stringify(configMap) }
  );

  return name;
}

// ─── Lifecycle operations ───────────────────────────────────────────

export async function listAgentSessions(slug) {
  const projectContext = await loadProjectAgentContext(slug);
  const labelSelector = `app=beagle-agent,project=${slug}`;
  let kubernetesSessions = [];
  try {
    const raw = await runKubectl([
      "-n", AGENT_NAMESPACE,
      "get", "statefulsets",
      "-l", labelSelector,
      "-o", "json"
    ]);
    const parsed = JSON.parse(raw);
    kubernetesSessions = parsed.items.map((item) => ({
      kind: item.metadata.labels["agent-kind"],
      name: item.metadata.name,
      workspaceMode: item.spec?.template?.metadata?.labels?.["workspace-mode"] || "isolated-agent-pvc",
      workspaceAuthority: `isolated agent PVC rooted at ${projectContext.workspaceRoot}`,
      replicas: item.spec.replicas,
      readyReplicas: item.status.readyReplicas ?? 0,
      createdAt: item.metadata.creationTimestamp,
      status: (item.status.readyReplicas ?? 0) > 0 ? "running"
            : item.spec.replicas === 0 ? "paused"
            : "pending"
    }));
  } catch {
    kubernetesSessions = [];
  }
  const localSessions = LOCAL_AGENT_KINDS
    .map((kind) => localAgentSessionRecord(slug, kind))
    .filter((session) => session.status === "running");
  return [...kubernetesSessions, ...localSessions];
}

export async function getAgentSession(slug, kind) {
  normKind(kind);
  if (isLocalAgentKind(kind)) {
    return localAgentSessionRecord(slug, kind);
  }
  const projectContext = await loadProjectAgentContext(slug);
  const name = resourceName(slug, kind);
  try {
    const raw = await runKubectl([
      "-n", AGENT_NAMESPACE,
      "get", "statefulset", name,
      "-o", "json"
    ]);
    const ss = JSON.parse(raw);
    const podsRaw = await runKubectl([
      "-n", AGENT_NAMESPACE,
      "get", "pods",
      "-l", `app=beagle-agent,project=${slug},agent-kind=${kind}`,
      "-o", "json"
    ]);
    const pods = JSON.parse(podsRaw).items || [];
    return {
      kind,
      name,
      replicas: ss.spec.replicas,
      readyReplicas: ss.status.readyReplicas ?? 0,
      createdAt: ss.metadata.creationTimestamp,
      workspaceMode: ss.spec?.template?.metadata?.labels?.["workspace-mode"] || "isolated-agent-pvc",
      workspaceAuthority: `isolated agent PVC rooted at ${projectContext.workspaceRoot}`,
      pods: pods.map(p => ({
        name: p.metadata.name,
        phase: p.status.phase,
        ready: p.status.containerStatuses?.every(c => c.ready) ?? false,
        node: p.spec.nodeName
      })),
      status: (ss.status.readyReplicas ?? 0) > 0 ? "running"
            : ss.spec.replicas === 0 ? "paused"
            : "pending"
    };
  } catch (e) {
    if (e.message.includes("NotFound") || e.message.includes("not found")) {
      return { kind, status: "idle", name: null, pods: [] };
    }
    throw e;
  }
}

export async function startAgentSession(slug, kind) {
  normKind(kind);
  if (isLocalAgentKind(kind)) {
    ensureAgentTerminalRuntime(slug, kind);
    return localAgentSessionRecord(slug, kind);
  }
  const projectContext = await loadProjectAgentContext(slug);

  // 1. Apply MCP ConfigMap first — StatefulSet mount depends on it.
  //    This gives the agent pod instant access to cockpit tools.
  const mcpConfigMap = await applyAgentMCPConfigMap(slug, kind);

  const substitutions = {
    PROJECT_SLUG: slug,
    AGENT_KIND: kind,
    AGENT_IMAGE: AGENT_IMAGE,
    PROJECT_REPO_URL: projectContext.repoUrl,
    PROJECT_BRANCH: projectContext.branch,
    PROJECT_WORKSPACE_ROOT: projectContext.workspaceRoot,
    MCP_CONFIGMAP_NAME: mcpConfigMap
  };

  // 2. Apply Service + StatefulSet
  const ssManifest = await renderManifest(
    path.join(MANIFEST_DIR, "statefulset.yaml"),
    substitutions
  );
  const svcManifest = await renderManifest(
    path.join(MANIFEST_DIR, "service.yaml"),
    substitutions
  );

  await runKubectl(["-n", AGENT_NAMESPACE, "apply", "-f", "-"], { input: svcManifest });
  await runKubectl(["-n", AGENT_NAMESPACE, "apply", "-f", "-"], { input: ssManifest });

  const session = await getAgentSession(slug, kind);
  return { ...session, mcpConfigMap };
}

export async function pauseAgentSession(slug, kind) {
  normKind(kind);
  if (isLocalAgentKind(kind)) {
    const runtime = localAgentRuntime(slug, kind);
    if (runtime && !runtime.exited) {
      try { runtime.pty.kill(); } catch { /* already gone */ }
    }
    return localAgentSessionRecord(slug, kind);
  }
  const name = resourceName(slug, kind);
  await runKubectl([
    "-n", AGENT_NAMESPACE,
    "scale", "statefulset", name,
    "--replicas=0"
  ]);
  return await getAgentSession(slug, kind);
}

export async function resumeAgentSession(slug, kind) {
  normKind(kind);
  if (isLocalAgentKind(kind)) {
    ensureAgentTerminalRuntime(slug, kind);
    return localAgentSessionRecord(slug, kind);
  }
  const name = resourceName(slug, kind);
  await runKubectl([
    "-n", AGENT_NAMESPACE,
    "scale", "statefulset", name,
    "--replicas=1"
  ]);
  return await getAgentSession(slug, kind);
}

export async function stopAgentSession(slug, kind, { deletePVC = false, deleteMCPConfig = false } = {}) {
  normKind(kind);
  if (isLocalAgentKind(kind)) {
    const runtime = localAgentRuntime(slug, kind);
    if (runtime && !runtime.exited) {
      try { runtime.pty.kill(); } catch { /* already gone */ }
    }
    return localAgentSessionRecord(slug, kind);
  }
  const name = resourceName(slug, kind);
  try {
    await runKubectl(["-n", AGENT_NAMESPACE, "delete", "statefulset", name, "--ignore-not-found"]);
    await runKubectl(["-n", AGENT_NAMESPACE, "delete", "service", name, "--ignore-not-found"]);
    if (deletePVC) {
      await runKubectl([
        "-n", AGENT_NAMESPACE,
        "delete", "pvc",
        "-l", `app=beagle-agent,project=${slug},agent-kind=${kind}`,
        "--ignore-not-found"
      ]);
    }
    // MCP ConfigMap is per-project (shared across kinds). Only remove if
    // explicitly requested AND no other kinds are still running for this project.
    if (deleteMCPConfig) {
      const others = await listAgentSessions(slug);
      if (others.length === 0) {
        await runKubectl([
          "-n", AGENT_NAMESPACE,
          "delete", "configmap", mcpConfigMapName(slug),
          "--ignore-not-found"
        ]);
      }
    }
  } catch (e) {
    if (!e.message.includes("NotFound") && !e.message.includes("not found")) throw e;
  }
  return { kind, status: "idle", name: null, pods: [] };
}

// ─── Route registration ─────────────────────────────────────────────

/**
 * Register agent routes on an existing Express app.
 * @param {import('express').Application} app
 */
export function registerAgentRoutes(app) {
  app.get("/api/projects/:slug/agent/sessions", async (req, res) => {
    try {
      const sessions = await listAgentSessions(req.params.slug);
      res.json({
        projectSlug: req.params.slug,
        sessions,
        generatedAt: new Date().toISOString(),
        truthMode: "observed"
      });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/agent/session/:kind", async (req, res) => {
    try {
      const session = await getAgentSession(req.params.slug, req.params.kind);
      res.json({ ...session, truthMode: "observed" });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale" });
    }
  });

  // Mutations wrapped with idempotency (X-Request-ID header replays within 60s)
  app.post("/api/projects/:slug/agent/session/start", idempotent(), async (req, res) => {
    try {
      requireConfirmed(req.body, "agent start");
      const kind = req.body?.kind || "claude-code";
      const session = await startAgentSession(req.params.slug, kind);
      res.json({ ...session, truthMode: "observed", action: "start", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale", requestId: req.requestId });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/pause", idempotent(), async (req, res) => {
    try {
      requireConfirmed(req.body, "agent pause");
      const session = await pauseAgentSession(req.params.slug, req.params.kind);
      res.json({ ...session, truthMode: "observed", action: "pause", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale", requestId: req.requestId });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/resume", idempotent(), async (req, res) => {
    try {
      requireConfirmed(req.body, "agent resume");
      const session = await resumeAgentSession(req.params.slug, req.params.kind);
      res.json({ ...session, truthMode: "observed", action: "resume", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale", requestId: req.requestId });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/sync-local", idempotent(), async (req, res) => {
    try {
      requireConfirmed(req.body, "agent local sync");
      const result = await syncLocalRepoToAgent(req.params.slug, req.params.kind);
      res.json({ ...result, truthMode: "observed", action: "sync-local", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({
        error: e.message,
        candidates: e.candidates,
        truthMode: "stale",
        requestId: req.requestId,
      });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/sync-from-agent", idempotent(), async (req, res) => {
    try {
      requireConfirmed(req.body, "agent pull sync");
      const result = await syncAgentRepoToLocal(req.params.slug, req.params.kind);
      res.json({ ...result, truthMode: "observed", action: "sync-from-agent", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({
        error: e.message,
        candidates: e.candidates,
        truthMode: "stale",
        requestId: req.requestId,
      });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/input", idempotent({ ttlMs: 15_000 }), async (req, res) => {
    try {
      requireConfirmed(req.body, "agent terminal input");
      const result = writeAgentTerminalInput(req.params.slug, req.params.kind, {
        data: req.body?.data,
        text: req.body?.text,
        enter: req.body?.enter === true
      });
      res.json({ ...result, action: "agent-input", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({
        error: e.message,
        truthMode: "stale",
        requestId: req.requestId,
      });
    }
  });

  app.get("/api/projects/:slug/agent/session/:kind/terminal", async (req, res) => {
    try {
      const snapshot = agentTerminalSnapshot(req.params.slug, req.params.kind, {
        tailBytes: req.query?.tailBytes
      });
      res.json(snapshot);
    } catch (e) {
      res.status(e.statusCode || 500).json({
        error: e.message,
        truthMode: "stale",
      });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/stop", idempotent(), async (req, res) => {
    try {
      requireConfirmed(req.body, "agent stop");
      const deletePVC = req.body?.deletePVC === true;
      const deleteMCPConfig = req.body?.deleteMCPConfig === true;
      const session = await stopAgentSession(req.params.slug, req.params.kind, { deletePVC, deleteMCPConfig });
      res.json({ ...session, truthMode: "observed", action: "stop", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale", requestId: req.requestId });
    }
  });
}

/**
 * Attach agent WebSocket handler to an existing HTTP server.
 *
 * Creates a WebSocketServer in `noServer: true` mode and hooks the HTTP
 * server's `upgrade` event for URLs matching /ws/projects/:slug/agent/:kind.
 *
 * This coexists with other WebSocket handlers (e.g. the terminal one at
 * /ws/terminal) because it only handles matching paths.
 *
 * @param {import('http').Server} server — the underlying HTTP server
 * @returns {import('ws').WebSocketServer}
 */
export function attachAgentWebSocket(server) {
  const urlPattern = /^\/ws\/projects\/([^/]+)\/agent\/([^/?#]+)(\?.*)?$/;
  const wss = new WebSocketServer({ noServer: true });

  // Route upgrades matching our path pattern into this WSS
  server.on("upgrade", (req, socket, head) => {
    const urlStr = req.url || "";
    const match = urlStr.match(urlPattern);
    if (!match) return;  // not our path — let other handlers deal

    wss.handleUpgrade(req, socket, head, (ws) => {
      const [, slug, kind] = match;
      wss.emit("connection", ws, req, { slug, kind });
    });
  });

  wss.on("connection", (socket, req, ctx) => {
    const { slug, kind } = ctx || {};
    if (!slug || !kind) {
      socket.close(1008, "invalid agent URL");
      return;
    }

    let runtime;
    try {
      runtime = ensureAgentTerminalRuntime(slug, kind);
    } catch (error) {
      socket.send(JSON.stringify({ type: "error", data: error.message }));
      socket.close(1011, "agent runtime error");
      return;
    }

    const safeSend = (obj) => {
      if (socket.readyState === 1) {
        socket.send(JSON.stringify(obj));
      }
    };

    runtime.sockets.add(socket);
    socket.isAlive = true;
    socket.on("pong", () => {
      socket.isAlive = true;
    });
    if (runtime.idleTimer) {
      clearTimeout(runtime.idleTimer);
      runtime.idleTimer = null;
    }

    safeSend({
      type: "ready",
      data: {
        slug,
        kind,
        pod: runtime.podName,
        shared: true,
        startedAt: runtime.startedAt
      }
    });
    if (runtime.scrollback) {
      safeSend({ type: "data", data: runtime.scrollback });
    }
    safeSend({
      type: "snapshot",
      data: agentTerminalRuntimeSnapshot(runtime, { tailBytes: 2200 })
    });

    socket.on("message", (data) => {
      try {
        const msg = JSON.parse(data.toString());
        if (msg.type === "input") {
          runtime.pty.write(msg.data);
          runtime.lastInputAt = new Date().toISOString();
        }
        if (msg.type === "resize") {
          runtime.pty.resize(Number(msg.cols || 120), Number(msg.rows || 34));
        }
      } catch {
        runtime.pty.write(data.toString());
        runtime.lastInputAt = new Date().toISOString();
      }
    });

    socket.on("close", () => {
      runtime.sockets.delete(socket);
      if (runtime.sockets.size === 0 && !runtime.exited) {
        scheduleAgentRuntimeIdleStop(runtime);
      }
    });
  });

  return wss;
}
