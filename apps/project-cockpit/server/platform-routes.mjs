// platform-routes.mjs — the command deck's control plane (Phase 1: list + kill; attach is the WS).
// Auth: inherits the global /api/mobile/v1/* cockpit-token gate. Only allowlisted sessions.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { SESSION_ALLOWLIST, tmuxControlArgv, buildSessionList } from "./platform-bridge.mjs";
const pexec = promisify(execFile);
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl";
const NS = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";

async function bridgePod() {
  const { stdout } = await pexec(KUBECTL, ["-n", NS, "get", "pod", "-l", "app=platform-bridge",
    "-o", "jsonpath={.items[0].metadata.name}"]);
  if (!stdout.trim()) throw new Error("platform-bridge pod not found");
  return stdout.trim();
}
async function tmuxExec(argv) {
  const pod = await bridgePod();
  const { stdout } = await pexec(KUBECTL, ["-n", NS, "exec", pod, "--", "tmux", ...argv], { timeout: 8000 });
  return stdout;
}

export function registerPlatformRoutes(app) {
  app.get("/api/mobile/v1/platform-state", async (_req, res) => {
    const now = Math.floor(Date.now() / 1000);
    const raw = {};
    for (const kind of Object.keys(SESSION_ALLOWLIST)) {
      try {
        const out = await tmuxExec(tmuxControlArgv(kind, "list"));
        const target = SESSION_ALLOWLIST[kind].target;
        const line = out.split("\n").find((l) => l.startsWith(target + "|"));
        if (line) raw[kind] = line.trim();
      } catch { /* session/socket absent — omit */ }
    }
    res.json({ ok: true, sessions: buildSessionList(raw, now) });
  });

  app.post("/api/mobile/v1/platform-control", async (req, res) => {
    const kind = String(req.body?.kind || "");
    const verb = String(req.body?.verb || "");
    const argv = tmuxControlArgv(kind, verb);
    if (!argv || verb === "list") return res.status(400).json({ ok: false, error: "unsupported" });
    try { await tmuxExec(argv); res.json({ ok: true }); }
    catch (e) { res.status(500).json({ ok: false, error: String(e?.message || e) }); }
  });
}
