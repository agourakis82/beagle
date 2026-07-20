// Agent routes — persistent agent pod lifecycle + WebSocket PTY bridge.
//
// Endpoints:
//   GET  /api/projects/:slug/agent/sessions            — list active agent sessions
//   POST /api/projects/:slug/agent/session/start       — spawn agent pod for kind
//   POST /api/projects/:slug/agent/session/:kind/pause — scale StatefulSet to 0
//   POST /api/projects/:slug/agent/session/:kind/stop  — delete StatefulSet + PVC
//   GET  /api/projects/:slug/agent/session/:kind       — session detail
//   WS   /ws/projects/:slug/agent/:kind                — stream an interactive shell via kubectl exec
//
// Supported kinds: claude-code, codex, local-sglang, custom
//
// This module is imported by server/index.mjs. It reuses existing helpers:
//   - runKubectlJson(args) for pod status
//   - runKubectlPty(args) for interactive WebSocket bridging
//
// ENV:
//   AGENT_IMAGE    — the default agent container image (default: beagle-agent:latest)
//   AGENT_NAMESPACE — K8s namespace (default: beagle)

import { spawn, execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import pty from "node-pty";
import { loadScratchpadEntries } from "./scratchpad-routes.mjs";
import { isT560Kind, deckExec, kubectlArgv } from "./platform-bridge.mjs";

const AGENT_NAMESPACE = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";
const AGENT_IMAGE = process.env.PROJECT_COCKPIT_AGENT_IMAGE || "beagle-agent:latest";
const AGENT_KINDS = ["claude-code", "codex", "local-sglang", "custom"];
const MANIFEST_DIR = process.env.PROJECT_COCKPIT_AGENT_MANIFEST_DIR
  || "/home/devsounio/beagle/k8s/agent-pods";

const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl";

function normKind(kind) {
  if (!AGENT_KINDS.includes(kind)) {
    const err = new Error(`unknown agent kind: ${kind}`);
    err.statusCode = 400;
    throw err;
  }
  return kind;
}

function resourceName(slug, kind) {
  return `agent-${slug}-${kind}`;
}

function cleanString(value) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).trim();
  }
  return "";
}

function latestScratchpadForKind(slug, kind) {
  const targetKind = cleanString(kind).toLowerCase();
  if (!targetKind) return null;
  const entries = loadScratchpadEntries(slug);
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index];
    const author = cleanString(entry?.author).toLowerCase();
    if (!author) continue;
    if (author === targetKind) return entry;
    if (author.includes(targetKind)) return entry;
    if (targetKind === "claude-code" && author.includes("claude")) return entry;
    if (targetKind === "codex" && author.includes("codex")) return entry;
    if (targetKind === "local-sglang" && (author.includes("sglang") || author.includes("local"))) return entry;
  }
  return null;
}

function deriveSessionActivity(slug, session = {}) {
  const latestEntry = latestScratchpadForKind(slug, session.kind);
  const action = cleanString(session.action);
  const scratchpadText = cleanString(latestEntry?.text);
  const normalizedAction = action
    ? action.replaceAll("-", " ").replaceAll("_", " ")
    : "";
  const summary = scratchpadText || normalizedAction || (
    (session.readyReplicas ?? 0) > 0
      ? "Holding the live thread and ready for input."
      : session.replicas === 0
        ? "Paused with its context preserved."
        : "Crossing into the cluster and not ready yet."
  );

  return {
    summary,
    source: scratchpadText ? "scratchpad" : normalizedAction ? "action" : "status",
    updatedAt: cleanString(latestEntry?.created_at || ""),
    author: cleanString(latestEntry?.author || ""),
    excerpt: scratchpadText,
    consciousnessState: latestEntry?.consciousness_state || null,
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

// ─── Lifecycle operations ───────────────────────────────────────────

export async function listAgentSessions(slug) {
  const labelSelector = `app=beagle-agent,project=${slug}`;
  const raw = await runKubectl([
    "-n", AGENT_NAMESPACE,
    "get", "statefulsets",
    "-l", labelSelector,
    "-o", "json"
  ]);
  const parsed = JSON.parse(raw);
  return parsed.items.map((item) => {
    const session = {
      kind: item.metadata.labels["agent-kind"],
      name: item.metadata.name,
      replicas: item.spec.replicas,
      readyReplicas: item.status.readyReplicas ?? 0,
      createdAt: item.metadata.creationTimestamp,
      status: (item.status.readyReplicas ?? 0) > 0 ? "running"
            : item.spec.replicas === 0 ? "paused"
            : "pending"
    };
    return {
      ...session,
      activity: deriveSessionActivity(slug, session)
    };
  });
}

export async function getAgentSession(slug, kind) {
  normKind(kind);
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
    const session = {
      kind,
      name,
      replicas: ss.spec.replicas,
      readyReplicas: ss.status.readyReplicas ?? 0,
      createdAt: ss.metadata.creationTimestamp,
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
    return {
      ...session,
      activity: deriveSessionActivity(slug, session)
    };
  } catch (e) {
    if (e.message.includes("NotFound") || e.message.includes("not found")) {
      const session = { kind, status: "idle", name: null, pods: [] };
      return { ...session, activity: deriveSessionActivity(slug, session) };
    }
    throw e;
  }
}

export async function startAgentSession(slug, kind) {
  normKind(kind);
  const substitutions = {
    PROJECT_SLUG: slug,
    AGENT_KIND: kind,
    AGENT_IMAGE: AGENT_IMAGE
  };

  const ssManifest = await renderManifest(
    path.join(MANIFEST_DIR, "statefulset.yaml"),
    substitutions
  );
  const svcManifest = await renderManifest(
    path.join(MANIFEST_DIR, "service.yaml"),
    substitutions
  );

  await runKubectl(["-n", AGENT_NAMESPACE, "apply", "-f", "-"], { input: ssManifest });
  await runKubectl(["-n", AGENT_NAMESPACE, "apply", "-f", "-"], { input: svcManifest });

  return await getAgentSession(slug, kind);
}

export async function pauseAgentSession(slug, kind) {
  normKind(kind);
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
  const name = resourceName(slug, kind);
  await runKubectl([
    "-n", AGENT_NAMESPACE,
    "scale", "statefulset", name,
    "--replicas=1"
  ]);
  return await getAgentSession(slug, kind);
}

export async function stopAgentSession(slug, kind, { deletePVC = false } = {}) {
  normKind(kind);
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
  } catch (e) {
    // Idempotent — ignore NotFound
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

  app.post("/api/projects/:slug/agent/session/start", async (req, res) => {
    try {
      const kind = req.body?.kind || "claude-code";
      const session = await startAgentSession(req.params.slug, kind);
      res.json({ ...session, truthMode: "observed", action: "start" });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/pause", async (req, res) => {
    try {
      const session = await pauseAgentSession(req.params.slug, req.params.kind);
      res.json({ ...session, truthMode: "observed", action: "pause" });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/resume", async (req, res) => {
    try {
      const session = await resumeAgentSession(req.params.slug, req.params.kind);
      res.json({ ...session, truthMode: "observed", action: "resume" });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale" });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/stop", async (req, res) => {
    try {
      const deletePVC = req.body?.deletePVC === true;
      const session = await stopAgentSession(req.params.slug, req.params.kind, { deletePVC });
      res.json({ ...session, truthMode: "observed", action: "stop" });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale" });
    }
  });
}

/**
 * WebSocket handler — stream an interactive shell from the agent pod.
 * @param {import('ws').WebSocketServer} wss
 */
// Resolve the t560 platform-bridge pod (for tmux attach). Throws if absent.
function bridgePodName() {
  const out = execFileSync(KUBECTL, ["-n", AGENT_NAMESPACE, "get", "pod",
    "-l", "app=platform-bridge", "-o", "jsonpath={.items[0].metadata.name}"], { encoding: "utf8" });
  if (!out.trim()) throw new Error("platform-bridge pod not found");
  return out.trim();
}

// Wire a spawned pty <-> the websocket (shared by the agent-pod and t560 tmux paths).
function wirePtyToSocket(socket, term) {
  socket.on("message", (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.type === "input") term.write(msg.data);
      else if (msg.type === "resize") term.resize(Number(msg.cols) || 120, Number(msg.rows) || 34);
    } catch { term.write(data.toString()); }
  });
  term.onData((d) => socket.send(JSON.stringify({ type: "data", data: d })));
  term.onExit(({ exitCode, signal }) => {
    if (socket.readyState === 1) {
      socket.send(JSON.stringify({ type: "exit", data: signal ? `terminal exited (${exitCode}, signal ${signal})` : `terminal exited (${exitCode})` }));
      socket.close();
    }
  });
  socket.on("close", () => term.kill());
}

export function registerAgentWebSocket(wss, { urlPattern = /^\/ws\/projects\/([^/]+)\/agent\/([^/]+)/ } = {}) {
  wss.on("connection", (socket, req) => {
    // Strip the query string before matching: ([^/]+) would otherwise swallow a trailing
    // ?token=... into the kind capture, breaking isT560Kind / normKind resolution.
    const urlPath = (req.url || "").split("?")[0];
    const match = urlPath.match(urlPattern);
    if (!match) return;
    const [, slug, kind] = match;

    // Command Deck session: attach an allowlisted multiplexer (t560 tmux via the bridge pod,
    // or the sounio workspace zellij via the workspace pod) instead of an agent pod.
    if (isT560Kind(kind)) {
      if (!/^[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$/.test(slug)) { socket.close(); return; }
      const spec = deckExec(kind, "attach");
      if (!spec) { socket.close(); return; }
      let pod;
      try { pod = spec.pod === "@bridge" ? bridgePodName() : spec.pod; } catch { socket.close(); return; }
      const deckTerm = pty.spawn(KUBECTL, kubectlArgv(AGENT_NAMESPACE, pod, spec, true),
        { name: "xterm-256color", cols: 120, rows: 34, cwd: process.cwd(), env: process.env });
      wirePtyToSocket(socket, deckTerm);
      return;
    }

    // Validate slug and kind before kubectl exec
    try { normKind(kind); } catch { socket.close(); return; }
    if (!/^[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$/.test(slug)) { socket.close(); return; }

    const name = resourceName(slug, kind);
    const podName = `${name}-0`;  // StatefulSet pod 0
    const shellCommand = 'WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"; cd "$WORKSPACE_DIR" 2>/dev/null || cd /workspace 2>/dev/null || cd "${HOME:-/tmp}"; if command -v bash >/dev/null 2>&1; then export SHELL="$(command -v bash)"; exec "$SHELL" -li; fi; if command -v sh >/dev/null 2>&1; then export SHELL="$(command -v sh)"; exec "$SHELL" -li; fi; echo "no interactive shell available in agent pod"; exit 127';

    // kubectl exec into the existing pod through a real PTY so kubectl -t works.
    const kubectl = pty.spawn(KUBECTL, [
      "-n", AGENT_NAMESPACE,
      "exec", "-it", podName,
      "--",
      "env",
      "WORKSPACE_DIR=/workspace",
      "sh", "-lc", shellCommand
    ], {
      name: "xterm-256color",
      cols: 120,
      rows: 34,
      cwd: process.cwd(),
      env: process.env
    });

    socket.on("message", (data) => {
      try {
        const msg = JSON.parse(data.toString());
        if (msg.type === "input") {
          kubectl.write(msg.data);
        } else if (msg.type === "resize") {
          const cols = Number(msg.cols) || 120;
          const rows = Number(msg.rows) || 34;
          kubectl.resize(cols, rows);
        }
      } catch {
        // Treat raw data as input
        kubectl.write(data.toString());
      }
    });

    kubectl.onData((data) => {
      socket.send(JSON.stringify({ type: "data", data }));
    });
    kubectl.onExit(({ exitCode, signal }) => {
      if (socket.readyState === 1) {  // WebSocket.OPEN = 1
        const detail = signal ? `terminal exited (${exitCode}, signal ${signal})` : `terminal exited (${exitCode})`;
        socket.send(JSON.stringify({ type: "exit", data: detail }));
        socket.close();
      }
    });

    socket.on("close", () => {
      kubectl.kill();
    });
  });
}
