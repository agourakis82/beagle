import { test } from "node:test";
import assert from "node:assert/strict";
import { decideKey, decideIsolate, registerLaneActionRoutes } from "./laneActions.mjs";

const waiting = (approveKey) => ({ state: "waiting", approveKey, detail: "Do you want to proceed?" });

// ─── the refusal is the feature ──────────────────────────────────────────────────────────

test("a question that needs a SENTENCE never accepts a keystroke", () => {
  // Measured shape (kimi-cli1): agent asks something open, box empty, nothing running. The
  // classifier already marks approveKey = null; until now nothing enforced it.
  const d = decideKey({ lane: "kimi-cli1", key: "enter", verdict: waiting(null) });
  assert.equal(d.ok, undefined);
  assert.equal(d.status, 409);
  assert.match(d.error, /resposta digitada/);
  assert.match(d.error, /abra o terminal/, "the refusal must say what to do instead");
});

test("the key must be the one the lane actually asked for", () => {
  assert.equal(decideKey({ lane: "codex-2", key: "enter", verdict: waiting("enter") }).ok, true);
  assert.equal(decideKey({ lane: "codex-2", key: "y", verdict: waiting("enter") }).status, 409);
  assert.match(decideKey({ lane: "codex-2", key: "y", verdict: waiting("enter") }).error, /espera "enter"/);
  assert.equal(decideKey({ lane: "claude-1", key: "y", verdict: waiting("y") }).ok, true);
});

test("a lane that is NOT waiting gets nothing confirmed", () => {
  for (const state of ["running", "idle", "stuck", "exited", "unknown"]) {
    const d = decideKey({ lane: "claude-1", key: "y", verdict: { state, approveKey: "y" } });
    assert.equal(d.status, 409, state);
    assert.match(d.error, new RegExp(state));
  }
});

test("esc is the one key that also works on a lane that is working — it confirms nothing", () => {
  // The CLIs advertise it themselves ("esc to interrupt"), so interrupting is a real operator act.
  assert.equal(decideKey({ lane: "claude-1", key: "esc", verdict: { state: "running", approveKey: null } }).ok, true);
  assert.equal(decideKey({ lane: "kimi-cli1", key: "esc", verdict: waiting(null) }).ok, true);
  assert.equal(decideKey({ lane: "repo", key: "esc", verdict: { state: "idle" } }).status, 409);
});

test("never observed is never approved — and unknown lanes/keys are refused up front", () => {
  assert.match(decideKey({ lane: "codex-3", key: "y", verdict: null }).error, /nunca observada/);
  assert.equal(decideKey({ lane: "not-a-lane", key: "y", verdict: waiting("y") }).status, 404);
  assert.equal(decideKey({ lane: "repo", key: "C-c", verdict: waiting("y") }).status, 400);
  assert.match(decideKey({ lane: "repo", key: "rm -rf /", verdict: waiting("y") }).error, /não permitida/);
});

test("isolate only moves a lane at rest, AT A SHELL, and only into a worktree that exists", () => {
  const shell = (state) => ({ state, atShell: true });
  assert.equal(decideIsolate({ lane: "codex-1", verdict: shell("idle"), worktreeExists: true }).ok, true);
  assert.equal(decideIsolate({ lane: "codex-1", verdict: shell("exited"), worktreeExists: true }).ok, true);
  const busy = decideIsolate({ lane: "claude-1", verdict: { state: "running", atShell: false }, worktreeExists: true });
  assert.equal(busy.status, 409);
  assert.match(busy.error, /perde o contexto/, "the cost must be stated, not implied");
  assert.match(decideIsolate({ lane: "claude-1", verdict: { state: "waiting", atShell: false }, worktreeExists: true }).error, /waiting/);

  // The one that nearly went wrong: an agent CLI idling at ITS OWN input box is "idle" too, and
  // `cd /workspace/.wt/codex-1` typed there is not a command — it is a request to the agent.
  const agentIdle = decideIsolate({ lane: "codex-1", verdict: { state: "idle", atShell: false }, worktreeExists: true });
  assert.equal(agentIdle.status, 409);
  assert.match(agentIdle.error, /prompt do agente/);
  assert.match(agentIdle.error, /feche o agente/, "say what unblocks it");

  const missing = decideIsolate({ lane: "codex-1", verdict: shell("idle"), worktreeExists: false });
  assert.match(missing.error, /worktree ausente/);
  assert.match(missing.error, /sounio-lane-worktrees --apply/, "say the command that fixes it");
});

// ─── the routes: decide on a FRESH screen, and never exec on a refusal ───────────────────

function harness({ verdictsByCall = [], refreshOk = true } = {}) {
  const execs = [];
  let sweeps = 0;
  const poller = {
    lastError: null,
    refreshNow: async () => { sweeps++; return refreshOk; },
    get: () => verdictsByCall[Math.min(sweeps - 1, verdictsByCall.length - 1)] ?? null,
  };
  const routes = {};
  const app = { post: (path, h) => { routes[path] = h; } };
  registerLaneActionRoutes(app, {
    poller, kubectl: "kubectl", ns: "beagle",
    execFn: (bin, argv, opts, cb) => { execs.push(argv); cb(null, "yes\n", ""); },
  });
  const call = async (path, params, body) => {
    let code = 200, payload = null;
    const res = { status(c) { code = c; return this; }, json(p) { payload = p; return this; } };
    await routes[path]({ params, body }, res);
    return { code, payload };
  };
  return { call, execs, sweeps: () => sweeps };
}

test("the route re-reads the screen BEFORE deciding — never from a 12s-old verdict", async () => {
  const h = harness({ verdictsByCall: [waiting("y")] });
  const r = await h.call("/api/mobile/v1/lanes/:lane/key", { lane: "codex-2" }, { key: "y" });
  assert.equal(r.code, 200);
  assert.equal(h.sweeps() >= 2, true, "one sweep to decide, one so the card catches up");
  assert.equal(h.execs.length, 1);
  assert.match(h.execs[0].at(-1), / exec tmux send-keys -t codex-2 y$/);
  assert.equal(r.payload.data.verdictBefore.state, "waiting", "report what we acted on");
});

test("a refusal sends NOTHING to the lane", async () => {
  const h = harness({ verdictsByCall: [{ state: "running", approveKey: null }] });
  const r = await h.call("/api/mobile/v1/lanes/:lane/key", { lane: "claude-1" }, { key: "y" });
  assert.equal(r.code, 409);
  assert.equal(h.execs.length, 0, "no exec on a refusal — this is the invariant that matters");
  assert.equal(r.payload.data.verdict.state, "running", "and the card is told why");
});

test("a screen we could not read is a 503, not a guess", async () => {
  const h = harness({ refreshOk: false });
  const r = await h.call("/api/mobile/v1/lanes/:lane/key", { lane: "repo" }, { key: "enter" });
  assert.equal(r.code, 503);
  assert.equal(h.execs.length, 0);
});

test("an unknown lane never reaches the cluster", async () => {
  const h = harness({ verdictsByCall: [waiting("y")] });
  const r = await h.call("/api/mobile/v1/lanes/:lane/key", { lane: "evil" }, { key: "y" });
  assert.equal(r.code, 404);
  assert.equal(h.sweeps(), 0, "not even a sweep");
  assert.equal(h.execs.length, 0);
});

test("isolate checks the destination before typing the cd", async () => {
  const h = harness({ verdictsByCall: [{ state: "idle", approveKey: null, atShell: true }] });
  const r = await h.call("/api/mobile/v1/lanes/:lane/isolate", { lane: "codex-1" }, {});
  assert.equal(r.code, 200);
  assert.equal(h.execs.length, 2, "first the test -d, then the send-keys");
  assert.match(h.execs[0].at(-1), /test -d \/workspace\/\.wt\/codex-1/);
  assert.match(h.execs[1].at(-1), /send-keys -t codex-1 "cd \/workspace\/\.wt\/codex-1" Enter$/);
  assert.equal(r.payload.data.movedTo, "/workspace/.wt/codex-1");
});
