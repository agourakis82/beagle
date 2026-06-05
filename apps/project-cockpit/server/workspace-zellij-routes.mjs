// workspace-zellij-routes.mjs
//
// Deep zellij transport for workspace habitat tabs.
//
// GET  /api/projects/:slug/workspace/zellij/status
// POST /api/projects/:slug/workspace/zellij/screen  { tab, confirmed: true }
// POST /api/projects/:slug/workspace/zellij/send     { tab, text, confirmed: true, enter?: true }

import { spawn } from "node:child_process";
import { idempotent } from "./contract.mjs";

const SSH_KEY =
  process.env.PROJECT_COCKPIT_ZELLIJ_SSH_KEY ||
  process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_SSH_KEY ||
  "/home/devsounio/.ssh/id_ed25519";
const SSH_PORT =
  process.env.PROJECT_COCKPIT_ZELLIJ_SSH_PORT ||
  process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_SSH_PORT ||
  "2222";
const SSH_USER =
  process.env.PROJECT_COCKPIT_ZELLIJ_SSH_USER ||
  process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_SSH_USER ||
  "openvscode-server";
const SSH_KNOWN_HOSTS =
  process.env.PROJECT_COCKPIT_ZELLIJ_SSH_KNOWN_HOSTS ||
  process.env.PROJECT_COCKPIT_KIMI_ZELLIJ_KNOWN_HOSTS ||
  "/home/devsounio/.ssh/known_hosts";
const TAILNET_SUFFIX =
  process.env.PROJECT_COCKPIT_TAILNET_SUFFIX || ".tail21cbc4.ts.net";

function cleanValue(value) {
  return typeof value === "string" && value.trim() ? value.trim() : "";
}

function validateTabName(tab) {
  const clean = cleanValue(tab);
  if (!clean || !/^[A-Za-z0-9._-]+$/.test(clean)) {
    const error = new Error("tab must be a non-empty alphanumeric name");
    error.statusCode = 400;
    throw error;
  }
  return clean;
}

function requireConfirmed(body, actionLabel) {
  if (body?.confirmed === true) {
    return;
  }
  const error = new Error(`${actionLabel} requires confirmed: true`);
  error.statusCode = 400;
  throw error;
}

function sessionNameFor(project) {
  return (
    cleanValue(project.zellijSession) ||
    cleanValue(project.tmuxSession) ||
    `${project.projectSlug}-dev`
  );
}

function workspaceSshTargets(project) {
  const raw = cleanValue(project.sshHost);
  const hosts = [];

  if (raw) {
    if (raw.includes(".")) {
      hosts.push(raw);
    } else {
      hosts.push(`${raw}-ssh${TAILNET_SUFFIX}`);
      hosts.push(`${raw}${TAILNET_SUFFIX}`);
    }
  }

  return [...new Set(hosts.map((host) => `${SSH_USER}@${host}`))];
}

function workspaceZellijScript({ tab, sendEnter }) {
  const parts = [
    `zellij action go-to-tab-name ${JSON.stringify(tab)} >/dev/null 2>&1 || true`,
    'prompt=$(printf \'%s\' "$1" | base64 -d)',
    'zellij action write-chars "$prompt"'
  ];
  if (sendEnter) {
    parts.push("zellij action send-keys Enter");
  }
  return parts.join("\n");
}

function remoteZellijBootstrap({ sessionName, body }) {
  return [
    "set -euo pipefail",
    'export HOME=/workspace/.home/openvscode-server',
    'export USER=openvscode-server',
    'export LOGNAME=openvscode-server',
    'export SHELL=/usr/bin/zsh',
    'export XDG_CONFIG_HOME="$HOME/.config"',
    'export XDG_DATA_HOME="$HOME/.local/share"',
    'export PATH="/usr/local/bin:$HOME/bin:$HOME/.local/node-v20.20.2-linux-x64/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"',
    `export ZELLIJ_SESSION_NAME=${JSON.stringify(sessionName)}`,
    body
  ].join("\n");
}

function runCommandCapture(command, args, { stdin = "", timeoutMs = 18_000 } = {}) {
  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    let settled = false;
    const child = spawn(command, args, {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"]
    });
    const finish = (result) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve(result);
    };
    const timer = setTimeout(() => {
      try {
        child.kill("SIGTERM");
      } catch {
        /* already closed */
      }
      finish({ code: 124, stdout, stderr: stderr || `timeout after ${timeoutMs}ms` });
    }, timeoutMs);
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("close", (code) => {
      finish({ code, stdout, stderr });
    });
    child.on("error", (error) => {
      finish({ code: 1, stdout, stderr: error.message });
    });
    if (stdin) {
      child.stdin.write(stdin);
    }
    child.stdin.end();
  });
}

function sshArgs(target, extraArgs = []) {
  const host = target.includes("@") ? target.split("@")[1] : target;
  return [
    "-4",
    "-F",
    "/dev/null",
    "-o",
    `UserKnownHostsFile=${SSH_KNOWN_HOSTS}`,
    "-o",
    "UpdateHostKeys=yes",
    "-o",
    "StrictHostKeyChecking=accept-new",
    "-i",
    SSH_KEY,
    "-p",
    SSH_PORT,
    host,
    "bash",
    "-s",
    "--",
    ...extraArgs
  ];
}

async function runWorkspaceSshScript(project, { body, extraArgs = [], timeoutMs = 18_000 }) {
  const targets = workspaceSshTargets(project);
  if (!targets.length) {
    const error = new Error(`project ${project.projectSlug} has no sshHost for zellij`);
    error.statusCode = 409;
    throw error;
  }

  const failures = [];
  for (const target of targets) {
    const result = await runCommandCapture("ssh", sshArgs(target, extraArgs), {
      stdin: body,
      timeoutMs
    });
    if (result.code === 0) {
      return { transport: "ssh", target, stdout: result.stdout, stderr: result.stderr };
    }
    failures.push(`${target}: ${(result.stderr || `exit ${result.code}`).trim()}`);
  }

  const error = new Error(failures.join(" | "));
  error.statusCode = 502;
  error.candidates = targets;
  throw error;
}

async function sendViaWorkspaceSsh(project, { tab, text, sessionName, sendEnter }) {
  const encoded = Buffer.from(text, "utf8").toString("base64");
  const script = remoteZellijBootstrap({
    sessionName,
    body: workspaceZellijScript({ tab, sendEnter })
  });
  return runWorkspaceSshScript(project, { body: script, extraArgs: [encoded] });
}

async function sendViaWorkspacePod(runWorkspaceShell, project, { tab, text, sessionName, sendEnter }) {
  const promptB64 = Buffer.from(text, "utf8").toString("base64");
  const script = workspaceZellijScript({ tab, sendEnter });
  const result = await runWorkspaceShell(
    project,
    {
      WORKSPACE_ROOT: project.workspaceRoot || `/workspace/${project.projectSlug}`,
      PROMPT_B64: promptB64,
      ZELLIJ_SESSION_NAME: sessionName,
      HOME: "/workspace/.home/openvscode-server",
      USER: "openvscode-server",
      LOGNAME: "openvscode-server",
      PATH: [
        "/workspace/.home/openvscode-server/bin",
        "/workspace/.home/openvscode-server/.local/node-v20.20.2-linux-x64/bin",
        "/workspace/.home/openvscode-server/.local/bin",
        "/workspace/.home/openvscode-server/.cargo/bin",
        "/usr/local/sbin",
        "/usr/local/bin",
        "/usr/sbin",
        "/usr/bin",
        "/sbin",
        "/bin"
      ].join(":")
    },
    script,
    { timeoutMs: 18_000 }
  );
  if (result.code !== 0) {
    const error = new Error(result.stderr || `workspace pod zellij send failed (exit ${result.code})`);
    error.statusCode = 502;
    throw error;
  }
  return { transport: "kubectl-exec", target: project.workspacePod, stdout: result.stdout };
}

async function deliverZellij(project, runWorkspaceShell, payload) {
  const targets = workspaceSshTargets(project);
  if (targets.length) {
    try {
      return await sendViaWorkspaceSsh(project, payload);
    } catch (sshError) {
      if (!runWorkspaceShell) {
        throw sshError;
      }
      const podDelivery = await sendViaWorkspacePod(runWorkspaceShell, project, payload);
      return {
        ...podDelivery,
        fallbackFrom: "ssh",
        fallbackReason: sshError.message,
        sshCandidates: targets
      };
    }
  }
  if (runWorkspaceShell) {
    return sendViaWorkspacePod(runWorkspaceShell, project, payload);
  }
  const error = new Error("no workspace zellij transport configured");
  error.statusCode = 503;
  throw error;
}

async function probeZellijStatus(project, runWorkspaceShell) {
  const sessionName = sessionNameFor(project);
  const declaredTabs = Array.isArray(project.zellijTabs) ? project.zellijTabs : [];
  const targets = workspaceSshTargets(project);

  let transport = "none";
  let target = null;
  let zellijPath = "";
  let sessionsRaw = "";
  let probeError = null;

  if (targets.length) {
    try {
      const probe = await runWorkspaceSshScript(project, {
        body: remoteZellijBootstrap({
          sessionName,
          body: [
            'printf "ZELLIJ_PATH:%s\\n" "$(command -v zellij || true)"',
            'printf "SESSIONS_BEGIN\\n"',
            "zellij list-sessions 2>/dev/null || true",
            'printf "SESSIONS_END\\n"'
          ].join("\n")
        }),
        timeoutMs: 8_000
      });
      transport = "ssh";
      target = probe.target;
      const stdout = probe.stdout || "";
      zellijPath = stdout.match(/^ZELLIJ_PATH:(.*)$/m)?.[1]?.trim() || "";
      sessionsRaw = stdout
        .split("SESSIONS_BEGIN\n")[1]
        ?.split("SESSIONS_END")[0]
        ?.trim() || "";
    } catch (error) {
      probeError = error.message;
    }
  }

  if (transport === "none" && runWorkspaceShell) {
    try {
      const result = await runWorkspaceShell(
        project,
        {
          WORKSPACE_ROOT: project.workspaceRoot || `/workspace/${project.projectSlug}`,
          ZELLIJ_SESSION_NAME: sessionName
        },
        'command -v zellij || true; zellij list-sessions 2>/dev/null || true',
        { timeoutMs: 12_000 }
      );
      if (result.code === 0) {
        transport = "kubectl-exec";
        target = project.workspacePod;
        zellijPath = (result.stdout || "").split("\n")[0]?.trim() || "";
        sessionsRaw = (result.stdout || "").split("\n").slice(1).join("\n").trim();
      }
    } catch (error) {
      probeError = probeError || error.message;
    }
  }

  return {
    ok: Boolean(zellijPath) || transport !== "none",
    projectSlug: project.projectSlug,
    sessionName,
    declaredTabs,
    transport,
    target,
    zellijPath: zellijPath || null,
    sessionsRaw: sessionsRaw || null,
    sshCandidates: targets,
    probeError,
    truthMode: transport === "none" ? "stale" : "observed"
  };
}

/**
 * @param {import('express').Application} app
 * @param {{ getProjectOrThrow: (slug: string) => Promise<object>, runWorkspaceShell?: Function }} deps
 */
export function registerWorkspaceZellijRoutes(app, deps) {
  const { getProjectOrThrow, runWorkspaceShell } = deps;

  app.get("/api/projects/:slug/workspace/zellij/status", async (req, res) => {
    try {
      const project = await getProjectOrThrow(req.params.slug);
      const status = await probeZellijStatus(project, runWorkspaceShell);
      res.json({ ...status, requestId: req.requestId });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        error: error.message,
        truthMode: "stale",
        requestId: req.requestId
      });
    }
  });

  app.post(
    "/api/projects/:slug/workspace/zellij/screen",
    idempotent({ ttlMs: 10_000 }),
    async (req, res) => {
      try {
        requireConfirmed(req.body, "workspace zellij screen");
        const project = await getProjectOrThrow(req.params.slug);
        const tab = validateTabName(req.body?.tab);
        const sessionName = sessionNameFor(project);
        const script = remoteZellijBootstrap({
          sessionName,
          body: [
            `zellij action go-to-tab-name ${JSON.stringify(tab)} >/dev/null 2>&1 || true`,
            "zellij action dump-screen --full 2>/dev/null || true"
          ].join("\n")
        });

        let delivery;
        try {
          delivery = await runWorkspaceSshScript(project, { body: script, timeoutMs: 15_000 });
        } catch (sshError) {
          if (!runWorkspaceShell) {
            throw sshError;
          }
          const result = await runWorkspaceShell(project, { ZELLIJ_SESSION_NAME: sessionName }, [
            `zellij action go-to-tab-name ${JSON.stringify(tab)} >/dev/null 2>&1 || true`,
            "zellij action dump-screen --full 2>/dev/null || true"
          ].join(" && "));
          if (result.code !== 0) {
            throw sshError;
          }
          delivery = { transport: "kubectl-exec", target: project.workspacePod, stdout: result.stdout };
        }

        res.json({
          ok: true,
          action: "workspace-zellij-screen",
          projectSlug: project.projectSlug,
          tab,
          sessionName,
          transport: delivery.transport,
          target: delivery.target,
          screen: delivery.stdout || "",
          truthMode: "observed",
          requestId: req.requestId
        });
      } catch (error) {
        res.status(error.statusCode || 500).json({
          error: error.message,
          truthMode: "stale",
          requestId: req.requestId
        });
      }
    }
  );

  app.post(
    "/api/projects/:slug/workspace/zellij/send",
    idempotent({ ttlMs: 15_000 }),
    async (req, res) => {
      try {
        requireConfirmed(req.body, "workspace zellij send");
        const project = await getProjectOrThrow(req.params.slug);
        const tab = validateTabName(req.body?.tab);
        const text = String(req.body?.text ?? req.body?.data ?? "");
        if (!text.trim()) {
          const error = new Error("text is required");
          error.statusCode = 400;
          throw error;
        }

        const declaredTabs = Array.isArray(project.zellijTabs) ? project.zellijTabs : [];
        if (declaredTabs.length > 0 && !declaredTabs.includes(tab)) {
          const error = new Error(`unknown zellij tab for ${project.projectSlug}: ${tab}`);
          error.statusCode = 400;
          throw error;
        }

        const sessionName = sessionNameFor(project);
        const sendEnter = req.body?.enter !== false;
        const delivery = await deliverZellij(project, runWorkspaceShell, {
          tab,
          text,
          sessionName,
          sendEnter
        });

        res.json({
          ok: true,
          action: "workspace-zellij-send",
          projectSlug: project.projectSlug,
          tab,
          sessionName,
          enter: sendEnter,
          transport: delivery.transport,
          target: delivery.target || null,
          fallbackFrom: delivery.fallbackFrom || null,
          fallbackReason: delivery.fallbackReason || null,
          sshCandidates: delivery.sshCandidates || workspaceSshTargets(project),
          truthMode: "observed",
          requestId: req.requestId
        });
      } catch (error) {
        res.status(error.statusCode || 500).json({
          error: error.message,
          truthMode: "stale",
          requestId: req.requestId
        });
      }
    }
  );
}
