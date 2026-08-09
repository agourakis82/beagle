// laneActions.mjs — the Frota stops being a panel and becomes a control surface.
//
// THE BOUNDARY, and the whole security argument for this file:
//
//   one touch = ONE named key from a closed set  ·  arbitrary text = you must be at the terminal
//
// A named key is not a command: `y` here is the same `y` he would press. Anything a lane needs
// TYPED (a real answer to a real question) still goes through the terminal on /ws/loom, where he
// can see what he is answering.
//
// And the refusal lives HERE, not in the client. `laneState.mjs` already computes `approveKey`
// (`"y"` / `"enter"` / `null`); until now that was decoration — no endpoint acted on it, and no
// endpoint enforced it. A client bug, or a second client, must not be able to press Enter at a
// question that needs a sentence.
//
// Every decision is taken against a screen read LESS THAN A SECOND OLD: each action forces a
// fresh sweep first. Deciding from a 12s-old verdict would mean approving whatever happens to be
// on screen now, which is not what he saw when he pressed the button.
import { execFile } from "node:child_process";
import {
  WORKSPACE_LANES, LANE_KEYS, LANE_WT_ROOT,
  laneSendKeyArgv, laneIsolateArgv, laneWorktreeCheckArgv,
} from "./platform-bridge.mjs";

/// States in which typing a `cd` at the lane is sound at all. Necessary, NOT sufficient: see the
/// shell check in `decideIsolate`. Moving a lane also restarts the agent there and loses its
/// context, so it is never automatic.
const ISOLATABLE = new Set(["idle", "exited"]);

/// Pure decision: may this key be delivered to this lane, given the freshest verdict we have?
/// Returns { ok: true } or { status, error } — a REASON, always, because a button that refuses
/// without saying why is worse than no button.
export function decideKey({ lane, key, verdict }) {
  if (!WORKSPACE_LANES.includes(lane)) return { status: 404, error: `lane desconhecida: ${lane}` };
  if (!Object.prototype.hasOwnProperty.call(LANE_KEYS, key)) {
    return { status: 400, error: `tecla não permitida: ${key} (só ${Object.keys(LANE_KEYS).join(", ")})` };
  }
  if (!verdict) return { status: 409, error: "lane nunca observada — não sei o que está na tela dela" };

  // Escape is the interrupt the CLIs themselves advertise ("esc to interrupt"), so it is the one
  // key that also makes sense on a lane that is working. It never confirms anything.
  if (key === "esc") {
    if (verdict.state === "waiting" || verdict.state === "running") return { ok: true };
    return { status: 409, error: `nada para interromper: a lane está ${verdict.state}` };
  }

  if (verdict.state !== "waiting") {
    return { status: 409, error: `a lane está ${verdict.state}, não esperando por você` };
  }
  if (!verdict.approveKey) {
    return { status: 409, error: "essa lane pede uma resposta digitada, não uma tecla — abra o terminal" };
  }
  if (key !== verdict.approveKey) {
    return { status: 409, error: `essa lane espera "${verdict.approveKey}", não "${key}"` };
  }
  return { ok: true };
}

/// Pure decision for moving a lane into its own worktree.
export function decideIsolate({ lane, verdict, worktreeExists }) {
  if (!WORKSPACE_LANES.includes(lane)) return { status: 404, error: `lane desconhecida: ${lane}` };
  if (!verdict) return { status: 409, error: "lane nunca observada — não sei se ela está em repouso" };
  if (!ISOLATABLE.has(verdict.state)) {
    return { status: 409, error: `a lane está ${verdict.state}; mover reinicia o agente e perde o contexto dele` };
  }
  // CAUGHT BEFORE THE FIRST REAL MOVE (2026-08-09): "idle" covers a lane sitting at its AGENT's
  // input box as well as one at a shell. A shell runs `cd /workspace/.wt/<lane>`; an agent CLI
  // would receive that same text as a REQUEST and go do something with it. Isolation types a
  // command, so it may only aim at a shell — the agent has to be closed first.
  if (!verdict.atShell) {
    return {
      status: 409,
      error: "a lane está no prompt do agente, não num shell — feche o agente antes (o `cd` viraria um pedido a ele)",
    };
  }
  if (worktreeExists === false) {
    return { status: 409, error: `worktree ausente: ${LANE_WT_ROOT}/${lane} — rode sounio-lane-worktrees --apply antes` };
  }
  return { ok: true };
}

const run = (bin, argv, exec) => new Promise((resolve) => {
  exec(bin, argv, { timeout: 15000, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
    resolve({ err, stdout: String(stdout || ""), stderr: String(stderr || "") });
  });
});

export function registerLaneActionRoutes(app, {
  poller, kubectl, ns, execFn = execFile,
} = {}) {
  // Read the screen NOW, so the decision is about what is there, not what was there 12s ago.
  // A sweep we could not complete is a 503: refusing is honest, guessing is not.
  async function freshVerdict(lane, res) {
    const ok = await poller.refreshNow();
    if (!ok) {
      res.status(503).json({ ok: false, error: `não consegui ler a tela das lanes agora: ${poller.lastError || "sweep falhou"}` });
      return null;
    }
    return poller.get(lane) || { state: "unknown", approveKey: null };
  }

  app.post("/api/mobile/v1/lanes/:lane/key", async (req, res) => {
    const lane = String(req.params.lane || "");
    const key = String((req.body || {}).key || "");
    if (!WORKSPACE_LANES.includes(lane)) return res.status(404).json({ ok: false, error: `lane desconhecida: ${lane}` });

    const verdict = await freshVerdict(lane, res);
    if (!verdict) return;
    const verdictBefore = { state: verdict.state, detail: verdict.detail || "", approveKey: verdict.approveKey || null };

    const d = decideKey({ lane, key, verdict });
    if (!d.ok) return res.status(d.status).json({ ok: false, error: d.error, data: { verdict: verdictBefore } });

    const argv = laneSendKeyArgv(ns, lane, key);
    if (!argv) return res.status(400).json({ ok: false, error: "ação recusada pelo allowlist" });
    const { err, stderr } = await run(kubectl, argv, execFn);
    if (err) return res.status(502).json({ ok: false, error: `send-keys falhou: ${stderr || err.message}` });

    // Sweep again so the card he is looking at catches up in a beat, not in 12s.
    await poller.refreshNow();
    const after = poller.get(lane);
    res.json({
      ok: true,
      data: {
        lane, key,
        verdictBefore,
        state: after?.state || null, detail: after?.detail || "", observedAt: after?.observedAt || null,
      },
    });
  });

  app.post("/api/mobile/v1/lanes/:lane/isolate", async (req, res) => {
    const lane = String(req.params.lane || "");
    if (!WORKSPACE_LANES.includes(lane)) return res.status(404).json({ ok: false, error: `lane desconhecida: ${lane}` });

    const verdict = await freshVerdict(lane, res);
    if (!verdict) return;

    // Check the destination BEFORE typing: a `cd` into a directory that is not there leaves the
    // lane exactly where it was, and the UI would report a move that never happened.
    const checkArgv = laneWorktreeCheckArgv(ns, lane);
    const check = await run(kubectl, checkArgv, execFn);
    const worktreeExists = /(^|\n)\s*yes\s*(\n|$)/.test(check.stdout);

    const d = decideIsolate({ lane, verdict, worktreeExists });
    if (!d.ok) return res.status(d.status).json({ ok: false, error: d.error, data: { verdict: { state: verdict.state } } });

    const argv = laneIsolateArgv(ns, lane);
    if (!argv) return res.status(400).json({ ok: false, error: "ação recusada pelo allowlist" });
    const { err, stderr } = await run(kubectl, argv, execFn);
    if (err) return res.status(502).json({ ok: false, error: `mover falhou: ${stderr || err.message}` });

    await poller.refreshNow();
    res.json({ ok: true, data: { lane, movedTo: `${LANE_WT_ROOT}/${lane}`, state: poller.get(lane)?.state || null } });
  });
}
