// Agent routes — persistent agent pod lifecycle + WebSocket PTY bridge.
//
// Endpoints:
//   GET  /api/projects/:slug/agent/sessions            — list active agent sessions
//   POST /api/projects/:slug/agent/session/start       — spawn agent pod for kind
//   POST /api/projects/:slug/agent/session/:kind/pause — scale StatefulSet to 0
//   POST /api/projects/:slug/agent/session/:kind/stop  — delete StatefulSet + PVC
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
//   AGENT_IMAGE    — the default agent container image (default: beagle-agent:latest)
//   AGENT_NAMESPACE — K8s namespace (default: beagle)

import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { WebSocketServer } from "ws";
import { idempotent } from "./contract.mjs";

const AGENT_NAMESPACE = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";
const AGENT_IMAGE = process.env.PROJECT_COCKPIT_AGENT_IMAGE || "beagle-agent:latest";
const AGENT_KINDS = ["claude-code", "codex", "local-sglang", "custom"];
const MANIFEST_DIR = process.env.PROJECT_COCKPIT_AGENT_MANIFEST_DIR
  || "/home/devsounio/beagle/k8s/agent-pods";

// MCP injection: where the cockpit API is reachable from inside the cluster.
// Agent pods run in-cluster, so they use the ClusterIP service DNS.
const COCKPIT_INTERNAL_URL = process.env.PROJECT_COCKPIT_INTERNAL_URL
  || "http://project-cockpit.beagle.svc.cluster.local";

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
        command: "node",
        args: ["/home/agent/.config/claude-code/cockpit-mcp-server.mjs"],
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
  const labelSelector = `app=beagle-agent,project=${slug}`;
  const raw = await runKubectl([
    "-n", AGENT_NAMESPACE,
    "get", "statefulsets",
    "-l", labelSelector,
    "-o", "json"
  ]);
  const parsed = JSON.parse(raw);
  return parsed.items.map((item) => ({
    kind: item.metadata.labels["agent-kind"],
    name: item.metadata.name,
    replicas: item.spec.replicas,
    readyReplicas: item.status.readyReplicas ?? 0,
    createdAt: item.metadata.creationTimestamp,
    status: (item.status.readyReplicas ?? 0) > 0 ? "running"
          : item.spec.replicas === 0 ? "paused"
          : "pending"
  }));
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
    return {
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
  } catch (e) {
    if (e.message.includes("NotFound") || e.message.includes("not found")) {
      return { kind, status: "idle", name: null, pods: [] };
    }
    throw e;
  }
}

export async function startAgentSession(slug, kind) {
  normKind(kind);

  // 1. Apply MCP ConfigMap first — StatefulSet mount depends on it.
  //    This gives the agent pod instant access to cockpit tools.
  const mcpConfigMap = await applyAgentMCPConfigMap(slug, kind);

  const substitutions = {
    PROJECT_SLUG: slug,
    AGENT_KIND: kind,
    AGENT_IMAGE: AGENT_IMAGE,
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

export async function stopAgentSession(slug, kind, { deletePVC = false, deleteMCPConfig = false } = {}) {
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
      const kind = req.body?.kind || "claude-code";
      const session = await startAgentSession(req.params.slug, kind);
      res.json({ ...session, truthMode: "observed", action: "start", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale", requestId: req.requestId });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/pause", idempotent(), async (req, res) => {
    try {
      const session = await pauseAgentSession(req.params.slug, req.params.kind);
      res.json({ ...session, truthMode: "observed", action: "pause", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale", requestId: req.requestId });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/resume", idempotent(), async (req, res) => {
    try {
      const session = await resumeAgentSession(req.params.slug, req.params.kind);
      res.json({ ...session, truthMode: "observed", action: "resume", requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({ error: e.message, truthMode: "stale", requestId: req.requestId });
    }
  });

  app.post("/api/projects/:slug/agent/session/:kind/stop", idempotent(), async (req, res) => {
    try {
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

    const name = resourceName(slug, kind);
    const podName = `${name}-0`;  // StatefulSet ordinal 0

    console.log(`[agent-ws] attaching slug=${slug} kind=${kind} pod=${podName}`);

    // kubectl exec -i into the helper script that launches the agent.
    // No tmux — kubectl exec already provides a PTY. Session state
    // persists via the PVC, not via a background tmux session.
    const kubectl = spawn(KUBECTL, [
      "-n", AGENT_NAMESPACE,
      "exec", "-i", podName,
      "--",
      "bash", "-c", "exec /home/agent/start-agent.sh"
    ], { stdio: ["pipe", "pipe", "pipe"] });

    const safeSend = (obj) => {
      if (socket.readyState === socket.OPEN) {
        socket.send(JSON.stringify(obj));
      }
    };

    safeSend({ type: "ready", data: { slug, kind, pod: podName } });

    socket.on("message", (data) => {
      try {
        const msg = JSON.parse(data.toString());
        if (msg.type === "input" && kubectl.stdin.writable) {
          kubectl.stdin.write(msg.data);
        }
        // 'resize' messages: kubectl exec doesn't propagate SIGWINCH easily;
        // tmux negotiates its own dimensions. Ignored for now.
      } catch {
        if (kubectl.stdin.writable) kubectl.stdin.write(data);
      }
    });

    kubectl.stdout.on("data", (d) => {
      safeSend({ type: "data", data: d.toString() });
    });
    kubectl.stderr.on("data", (d) => {
      safeSend({ type: "stderr", data: d.toString() });
    });
    kubectl.on("close", (code) => {
      safeSend({ type: "exit", code });
      socket.close();
    });
    kubectl.on("error", (err) => {
      safeSend({ type: "error", data: err.message });
      socket.close();
    });

    socket.on("close", () => {
      try { kubectl.kill("SIGTERM"); } catch { /* already dead */ }
    });
  });

  return wss;
}
