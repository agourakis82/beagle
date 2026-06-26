import http from "node:http";
import { randomUUID } from "node:crypto";
import pty from "node-pty";
import { WebSocketServer } from "ws";
import {
  cleanString,
  nowIso,
  safeId,
  stripControl,
} from "./workbench-core.mjs";

const host = process.env.BEAGLE_PTY_SUPERVISOR_HOST || "127.0.0.1";
const port = Number(process.env.BEAGLE_PTY_SUPERVISOR_PORT || 4372);
const defaultWorkspaceRoot = process.env.BEAGLE_WORKSPACE_ROOT || process.env.PROJECT_WORKSPACE_ROOT || "/workspace";
const defaultShell = process.env.SHELL || "/bin/bash";

const panes = new Map();

function json(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (chunks.length === 0) return {};
  const raw = Buffer.concat(chunks).toString("utf8");
  if (!raw.trim()) return {};
  return JSON.parse(raw);
}

function paneStatus(entry) {
  return {
    paneId: entry.paneId,
    sessionId: entry.sessionId,
    pid: entry.proc.pid,
    status: entry.status,
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
    cwd: entry.cwd,
    cols: entry.cols,
    rows: entry.rows,
    snapshot: entry.snapshot.slice(-12000),
    supervisorRuntime: "beagle-pty-supervisor-v1",
  };
}

function broadcast(entry, payload) {
  const data = JSON.stringify(payload);
  for (const client of entry.clients) {
    if (client.readyState === client.OPEN) client.send(data);
  }
}

function spawnPane(body = {}) {
  const paneId = safeId(body.paneId || body.pane_id || `pane-${randomUUID().slice(0, 8)}`);
  const existing = panes.get(paneId);
  if (existing && existing.status === "running") {
    existing.updatedAt = nowIso();
    return existing;
  }

  const cwd = cleanString(body.cwd) || defaultWorkspaceRoot;
  const shell = cleanString(body.shell) || defaultShell;
  const cols = Number(body.cols || 120);
  const rows = Number(body.rows || 34);
  // Provider credentials for an agent-role pane are passed in the spawn body
  // (the role->slot->creds mapping lives in the workspace-agent, not here).
  // Merge string-valued entries only; never log the values.
  const providerEnv = {};
  if (body.providerEnv && typeof body.providerEnv === "object") {
    for (const [key, value] of Object.entries(body.providerEnv)) {
      if (typeof key === "string" && key && typeof value === "string" && value) {
        providerEnv[key] = value;
      }
    }
  }
  const env = {
    ...process.env,
    TERM: "xterm-256color",
    COLORTERM: process.env.COLORTERM || "truecolor",
    BEAGLE_WORKBENCH: "1",
    BEAGLE_PTY_SUPERVISOR: "1",
    WORKSPACE_ROOT: cwd,
    ...providerEnv,
  };

  const proc = pty.spawn(shell, ["-l"], {
    name: "xterm-256color",
    cols,
    rows,
    cwd,
    env,
  });

  const entry = {
    paneId,
    sessionId: cleanString(body.sessionId || body.session_id),
    proc,
    status: "running",
    createdAt: nowIso(),
    updatedAt: nowIso(),
    cwd,
    cols,
    rows,
    snapshot: "",
    clients: new Set(),
  };

  proc.onData((data) => {
    entry.updatedAt = nowIso();
    entry.snapshot = `${entry.snapshot}${data}`.slice(-20000);
    broadcast(entry, {
      type: "raw_output",
      paneId,
      sessionId: entry.sessionId,
      at: nowIso(),
      data,
    });
  });

  proc.onExit(({ exitCode, signal }) => {
    entry.status = "exited";
    entry.updatedAt = nowIso();
    broadcast(entry, {
      type: "exit",
      paneId,
      sessionId: entry.sessionId,
      at: nowIso(),
      exitCode,
      signal: signal || "",
      detail: signal ? `pty exited (${exitCode}, signal ${signal})` : `pty exited (${exitCode})`,
    });
  });

  panes.set(paneId, entry);
  return entry;
}

function signalPane(entry, signal) {
  const normalized = cleanString(signal || "SIGINT");
  if (normalized === "SIGINT") entry.proc.write("\u0003");
  else if (normalized === "SIGTERM") entry.proc.kill();
  else if (normalized === "SIGHUP") entry.proc.kill("SIGHUP");
  else entry.proc.write("\u0003");
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    if (req.method === "GET" && (url.pathname === "/health" || url.pathname === "/v1/health")) {
      json(res, 200, { status: "ok", supervisor: "beagle-pty-supervisor", panes: panes.size });
      return;
    }
    if (req.method === "GET" && url.pathname === "/v1/panes") {
      json(res, 200, { panes: Array.from(panes.values()).map(paneStatus) });
      return;
    }
    if (req.method === "POST" && url.pathname === "/v1/spawn") {
      const entry = spawnPane(await readJson(req));
      json(res, 200, { pane: paneStatus(entry) });
      return;
    }

    const paneMatch = url.pathname.match(/^\/v1\/panes\/([^/]+)\/(input|resize|signal|terminate|snapshot)$/);
    if (paneMatch) {
      const paneId = decodeURIComponent(paneMatch[1]);
      const action = paneMatch[2];
      const entry = panes.get(paneId);
      if (!entry) {
        json(res, 404, { error: "pane_not_found" });
        return;
      }
      if (action === "snapshot" && req.method === "GET") {
        json(res, 200, { pane: paneStatus(entry) });
        return;
      }
      const body = await readJson(req);
      if (action === "input") entry.proc.write(String(body.data || ""));
      if (action === "resize") {
        entry.cols = Number(body.cols || entry.cols || 120);
        entry.rows = Number(body.rows || entry.rows || 34);
        entry.proc.resize(entry.cols, entry.rows);
      }
      if (action === "signal") signalPane(entry, body.signal);
      if (action === "terminate") entry.proc.kill();
      entry.updatedAt = nowIso();
      json(res, 200, { pane: paneStatus(entry) });
      return;
    }

    json(res, 404, { error: "not_found" });
  } catch (error) {
    json(res, 500, { error: error?.message || "supervisor_error" });
  }
});

const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  const match = url.pathname.match(/^\/v1\/panes\/([^/]+)\/stream$/);
  if (!match) {
    socket.destroy();
    return;
  }
  const paneId = decodeURIComponent(match[1]);
  const entry = panes.get(paneId);
  if (!entry) {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    entry.clients.add(ws);
    ws.send(JSON.stringify({
      type: "ready",
      paneId,
      sessionId: entry.sessionId,
      at: nowIso(),
      supervisorRuntime: "beagle-pty-supervisor-v1",
      snapshot: stripControl(entry.snapshot).slice(-12000),
    }));
    ws.on("close", () => entry.clients.delete(ws));
  });
});

server.listen(port, host, () => {
  console.log(`[beagle-pty-supervisor] listening on http://${host}:${port}`);
});
