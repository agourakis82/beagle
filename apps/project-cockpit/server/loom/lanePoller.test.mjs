import { test } from "node:test";
import assert from "node:assert/strict";
import { LanePoller } from "./lanePoller.mjs";
import { PEEK_DELIM } from "../platform-bridge.mjs";

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

test("overlapping sweeps do not stack execs on a slow cluster", () => {
  let calls = 0;
  const p = new LanePoller({
    kubectl: "kubectl", ns: "beagle",
    execFn: () => { calls++; },       // never calls back → stays in flight
  });
  p.poll(); p.poll(); p.poll();
  assert.equal(calls, 1);
});
