import { test } from "node:test";
import assert from "node:assert/strict";
import { LanePoller } from "./lanePoller.mjs";
import { PEEK_DELIM, ALIVE_DELIM } from "../platform-bridge.mjs";

const aliveBlock = (...lanes) => `${ALIVE_DELIM}\n${lanes.join("\n")}\n`;

const screen = (lane, body) => `${PEEK_DELIM}${lane}\n${body}\n`;
const ASKING = "   A pergunta: quer que eu rode o pré-registro agora?\n ╭────╮\n │ >  │\n ╰────╯\n";
const WORKING = "● lowering the IR\n  ⏵⏵ auto mode on · esc to interrupt · ctrl+t to show tasks\n";
const SHELL = "sounio-workspace-control-0%\n";

function pollerWith(stdout, { err = null, now = () => 1_000_000 } = {}) {
  const calls = [];
  const execFn = (bin, argv, opts, cb) => { calls.push({ bin, argv, opts }); cb(err, stdout, ""); };
  const p = new LanePoller({ kubectl: "kubectl", ns: "beagle", execFn, now });
  return { p, calls };
}

test("one sweep classifies every lane it saw, each stamped with observedAt", async () => {
  const { p, calls } = pollerWith(
    screen("kimi-cli1", ASKING) + screen("claude-1", WORKING) + screen("repo", SHELL),
  );
  await p.poll();
  assert.equal(calls.length, 1, "ONE exec for the whole fleet, not one per lane");
  assert.equal(p.get("kimi-cli1").state, "waiting");
  assert.match(p.get("kimi-cli1").detail, /pré-registro agora\?$/);
  assert.equal(p.get("claude-1").state, "running");
  assert.equal(p.get("repo").state, "idle");
  assert.equal(p.get("kimi-cli1").observedAt, 1_000_000);
  assert.equal(p.get("kimi-cli1").peek.length > 0, true);
});

test("a lane never observed returns null — the board must not invent a state", async () => {
  const { p } = pollerWith(screen("repo", SHELL));
  await p.poll();
  assert.equal(p.get("codex-3"), null);
});

test("a failed sweep keeps the previous verdicts (ageing, not erased)", async () => {
  const { p } = pollerWith(screen("repo", SHELL));
  await p.poll();
  assert.equal(p.get("repo").state, "idle");
  p._exec = (bin, argv, opts, cb) => cb(new Error("cluster unreachable"), "", "");
  const ok = await p.poll();
  assert.equal(ok, false);
  assert.equal(p.get("repo").state, "idle", "old verdict survives");
  assert.match(p.lastError, /unreachable/);
});

test("an unchanged screen does not refresh lastOutputAt (so silence can age into stuck)", async () => {
  let t = 1_000_000;
  const mid = "● building\n  emitting objects\n";
  const { p } = pollerWith(screen("codex-1", mid), { now: () => t });
  await p.poll();
  const first = p.get("codex-1").lastOutputAt;
  t += 700_000;                       // 11+ min later, same screen
  await p.poll();
  assert.equal(p.get("codex-1").lastOutputAt, first, "no new output → age must accumulate");
  assert.equal(p.get("codex-1").state, "stuck");
  assert.equal(p.get("codex-1").observedAt, t, "but the observation itself is fresh");
});

test("a lane tmux does not list is EXITED, not a blank card guessing `unknown`", async () => {
  // Measured 2026-08-09: grok-cli1/2 and codex-3 did not exist, capture-pane failed into stderr
  // (discarded), and the board painted three cards for lanes that were never created.
  const { p } = pollerWith(
    aliveBlock("claude-1", "repo") + screen("claude-1", WORKING) + screen("grok-cli1", "") + screen("repo", SHELL),
  );
  await p.poll();
  assert.equal(p.get("grok-cli1").state, "exited");
  assert.match(p.get("grok-cli1").detail, /não existe no tmux/, "the card must say WHY it is empty");
  assert.equal(p.get("grok-cli1").approveKey, null, "an absent lane offers no action");
  assert.equal(p.get("claude-1").state, "running", "the live lanes are unaffected");
  assert.equal(p.get("repo").state, "idle");
});

test("a read with no liveness block never claims a lane is gone", async () => {
  // Old server, or output truncated before the block: we know nothing about existence, so the
  // screen alone decides — silence about existence must not be read as absence.
  const { p } = pollerWith(screen("claude-1", WORKING));
  await p.poll();
  assert.equal(p.get("claude-1").state, "running");
});

test("refreshNow awaits a sweep already in flight instead of firing a second one", async () => {
  let calls = 0, done;
  const p = new LanePoller({
    kubectl: "k", ns: "n",
    execFn: (bin, argv, opts, cb) => { calls++; done = () => cb(null, screen("repo", SHELL), ""); },
  });
  const a = p.refreshNow();
  const b = p.refreshNow();
  assert.equal(calls, 1, "one exec, not two");
  done();
  assert.deepEqual(await Promise.all([a, b]), [true, true], "both callers get the real result");
});

test("overlapping sweeps do not stack execs on a slow cluster", () => {
  let calls = 0;
  const p = new LanePoller({
    kubectl: "kubectl", ns: "beagle",
    execFn: () => { calls++; },       // never calls back → stays in flight
  });
  p.poll(); p.poll(); p.poll();
  assert.equal(calls, 1);
});
