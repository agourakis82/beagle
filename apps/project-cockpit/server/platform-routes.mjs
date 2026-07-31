// platform-routes.mjs — the command deck's control plane (Phase 1: list + kill; attach is the WS).
// Auth: inherits the global /api/mobile/v1/* cockpit-token gate. Only allowlisted sessions.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { SESSION_ALLOWLIST, deckExec, kubectlArgv, parseDeckSession } from "./platform-bridge.mjs";
const pexec = promisify(execFile);
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl";
const NS = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";

async function bridgePod() {
  const { stdout } = await pexec(KUBECTL, ["-n", NS, "get", "pod", "-l", "app=platform-bridge",
    "-o", "jsonpath={.items[0].metadata.name}"]);
  if (!stdout.trim()) throw new Error("platform-bridge pod not found");
  return stdout.trim();
}
// Resolve "@bridge" → the live bridge pod, then run the kind's action non-interactively.
async function runDeck(kind, action) {
  const spec = deckExec(kind, action);
  if (!spec) throw new Error("unsupported");
  const pod = spec.pod === "@bridge" ? await bridgePod() : spec.pod;
  const { stdout } = await pexec(KUBECTL, kubectlArgv(NS, pod, spec, false), { timeout: 9000 });
  return stdout;
}

export function registerPlatformRoutes(app) {
  app.get("/api/mobile/v1/platform-state", async (_req, res) => {
    const now = Math.floor(Date.now() / 1000);
    const sessions = [];
    for (const kind of Object.keys(SESSION_ALLOWLIST)) {
      try {
        const out = await runDeck(kind, "list");
        const entry = parseDeckSession(kind, out, now);
        if (entry) sessions.push(entry);
      } catch { /* session/pod absent — omit */ }
    }
    // Mobile envelope contract: the iOS fetchMobile reads `data` as the payload.
    res.json({ ok: true, data: sessions, meta: { truthMode: "observed" } });
  });

  app.post("/api/mobile/v1/platform-control", async (req, res) => {
    const kind = String(req.body?.kind || "");
    const verb = String(req.body?.verb || "");
    const ALLOWED = new Set(["kill", "tab-next", "tab-prev"]);   // tab-* = zellij action nav
    if (!ALLOWED.has(verb) || !deckExec(kind, verb)) {
      return res.status(400).json({ ok: false, error: "unsupported" });
    }
    try { await runDeck(kind, verb); res.json({ ok: true, data: { done: true }, meta: { truthMode: "observed" } }); }
    catch (e) { res.status(500).json({ ok: false, error: String(e?.message || e) }); }
  });
}
