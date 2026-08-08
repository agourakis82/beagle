// oficina.mjs — the dev half of Mission Control. It answers three operational questions and
// refuses to invent answers to any others:
//
//   1. "Está verde?"        → the CI rollup of every open PR, and of main.
//   2. "O que quebrou?"     → the NAMES of the failing checks, not a red dot.
//   3. "Onde eu estou?"     → the repo's branch/head/dirty count.
//
// It never builds, tests, or runs a gate: a souc build costs ~61GiB of RAM and minutes, so the
// Oficina READS verdicts instead of producing them. Every field carries its observation time so
// the UI can mark it stale rather than assert a freshness it does not have.
import { execFile } from "node:child_process";
import { workspaceQueryArgv } from "./platform-bridge.mjs";

/// One check's conclusion → our three-valued verdict. Unknown conclusions are NOT assumed good.
export function checkVerdict(check) {
  const status = String(check?.status || "").toUpperCase();
  const concl = String(check?.conclusion || "").toUpperCase();
  if (status && status !== "COMPLETED") return "pending";
  switch (concl) {
    case "SUCCESS": return "green";
    case "SKIPPED": case "NEUTRAL": return "skipped";
    case "":       return "pending";
    default:       return "red";     // FAILURE, TIMED_OUT, CANCELLED, ACTION_REQUIRED, STARTUP_FAILURE…
  }
}

/// Roll many checks into one verdict. Red dominates; then pending; green only if something
/// actually ran and passed. An all-skipped rollup is NOT green — a gate that never ran proves
/// nothing (a stale hash silently disabled two thirds of the Contracts job for four days).
export function rollupVerdict(checks = []) {
  const verdicts = checks.map(checkVerdict);
  if (verdicts.includes("red")) return "red";
  if (verdicts.includes("pending")) return "pending";
  if (verdicts.includes("green")) return "green";
  return "unknown";
}

/// The failing checks, named — "what broke" must be actionable, never a bare red dot.
export function failingChecks(checks = []) {
  return checks
    .filter((c) => checkVerdict(c) === "red")
    .map((c) => ({
      name: String(c.name || "check"),
      workflow: String(c.workflowName || ""),
      url: String(c.detailsUrl || ""),
    }));
}

/// Reduce `gh pr list --json …` into the Oficina's PR rows.
export function reducePRs(json) {
  let arr;
  try { arr = JSON.parse(json); } catch { return []; }
  if (!Array.isArray(arr)) return [];
  return arr.map((pr) => {
    const checks = Array.isArray(pr.statusCheckRollup) ? pr.statusCheckRollup : [];
    return {
      number: Number(pr.number) || 0,
      title: String(pr.title || ""),
      branch: String(pr.headRefName || ""),
      url: String(pr.url || ""),
      draft: Boolean(pr.isDraft),
      verdict: rollupVerdict(checks),
      failing: failingChecks(checks),
      checksTotal: checks.length,
      checksGreen: checks.filter((c) => checkVerdict(c) === "green").length,
      updatedAt: pr.updatedAt || null,
    };
  }).sort((a, b) => {
    // Red first — the board leads with what needs a human.
    const rank = (v) => ({ red: 0, pending: 1, unknown: 2, green: 3 }[v] ?? 4);
    return rank(a.verdict) - rank(b.verdict) || b.number - a.number;
  });
}

/// Reduce `gh run list --json …` for main into one verdict + the runs behind it.
export function reduceMainCI(json) {
  let arr;
  try { arr = JSON.parse(json); } catch { return { verdict: "unknown", runs: [] }; }
  if (!Array.isArray(arr) || arr.length === 0) return { verdict: "unknown", runs: [] };
  const runs = arr.map((r) => ({
    name: String(r.name || ""),
    verdict: checkVerdict({ status: r.status, conclusion: r.conclusion }),
    url: String(r.url || ""),
    sha: String(r.headSha || "").slice(0, 8),
    createdAt: r.createdAt || null,
  }));
  // Judge only the most recent run per workflow — an old red that has since gone green is history.
  const latest = new Map();
  for (const r of runs) if (!latest.has(r.name)) latest.set(r.name, r);
  return { verdict: rollupVerdict([...latest.values()].map((r) => ({ status: "COMPLETED", conclusion: r.verdict === "green" ? "SUCCESS" : r.verdict === "red" ? "FAILURE" : r.verdict === "pending" ? "" : "NEUTRAL" }))), runs };
}

/// Reduce the git-head probe (branch \n sha\ttimestamp\tsubject \n dirtyCount).
export function reduceGitHead(text) {
  const lines = String(text || "").split("\n").map((l) => l.replace(/\r$/, ""));
  const branch = (lines[0] || "").trim();
  const [sha = "", ts = "", ...rest] = (lines[1] || "").split("\t");
  const dirty = Number((lines[2] || "").trim());
  if (!branch) return null;
  return {
    branch,
    sha: sha.slice(0, 10),
    committedAt: Number(ts) ? new Date(Number(ts) * 1000).toISOString() : null,
    subject: rest.join("\t").trim(),
    dirtyFiles: Number.isFinite(dirty) ? dirty : null,
  };
}

/// Mount `/api/mobile/v1/oficina` (inherits the cockpit-token gate on that prefix).
/// Serves the poller's last observation with its truth mode — `observed` when fresh,
/// `stale` when the sweep failed and the rows are ageing. Never blocks on a live sweep.
export function registerOficinaRoutes(app, poller) {
  app.get("/api/mobile/v1/oficina", (_req, res) => {
    const s = poller.state;
    res.json({
      ok: true,
      data: { prs: s.prs, main: s.main, head: s.head, observedAt: s.observedAt },
      meta: {
        truthMode: s.error ? "stale" : (s.observedAt ? "observed" : "unknown"),
        error: s.error || null,
      },
    });
  });
}

export class OficinaPoller {
  constructor({ kubectl, ns, intervalMs = 60000, execFn = execFile, now = () => Date.now() }) {
    this._kubectl = kubectl; this._ns = ns; this._intervalMs = intervalMs;
    this._exec = execFn; this._now = now;
    this._state = { prs: [], main: { verdict: "unknown", runs: [] }, head: null, observedAt: null, error: null };
    this._timer = null; this._inFlight = false;
  }

  /// Never throws. On failure the previous (ageing) state survives with `error` set — the UI
  /// shows "leitura antiga + porquê" instead of a blank panel.
  get state() { return this._state; }

  start() {
    if (this._timer) return;
    this.poll();
    this._timer = setInterval(() => this.poll(), this._intervalMs);
    this._timer?.unref?.();
  }
  stop() { clearInterval(this._timer); this._timer = null; }

  _run(name) {
    return new Promise((resolve) => {
      const argv = workspaceQueryArgv(this._ns, name);
      if (!argv) return resolve(null);
      this._exec(this._kubectl, argv, { maxBuffer: 8 * 1024 * 1024, timeout: 30000 },
        (err, stdout) => resolve(err && !stdout ? null : String(stdout || "")));
    });
  }

  async poll() {
    if (this._inFlight) return false;
    this._inFlight = true;
    try {
      const [prs, main, head] = await Promise.all([
        this._run("pr-list"), this._run("main-ci"), this._run("git-head"),
      ]);
      const now = this._now();
      if (prs === null && main === null && head === null) {
        this._state = { ...this._state, error: "workspace unreachable" };
        return false;
      }
      this._state = {
        prs: prs === null ? this._state.prs : reducePRs(prs),
        main: main === null ? this._state.main : reduceMainCI(main),
        head: head === null ? this._state.head : reduceGitHead(head),
        observedAt: now,
        error: null,
      };
      return true;
    } finally {
      this._inFlight = false;
    }
  }
}
