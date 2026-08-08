import { test } from "node:test";
import assert from "node:assert/strict";
import {
  literalPrefix, globsOverlap, findConflicts, sharedTreeHazards,
  parsePanes, ClaimRegistry, HazardPoller,
} from "./coord.mjs";
import { WORKSPACE_QUERIES, workspaceQueryArgv } from "./platform-bridge.mjs";

test("tmux format specifiers must be double-quoted or the shell eats them", () => {
  // Unquoted, tmux's "|" becomes a pipe and "#" starts a comment — this silently returns nothing.
  for (const [name, q] of Object.entries(WORKSPACE_QUERIES)) {
    if (!q.includes("#{")) continue;
    assert.match(q, /"[^"]*#\{/, `${name}: the -F format must be inside double quotes`);
    assert.doesNotMatch(q, /'/, `${name}: single quotes break inside sh -c '…'`);
  }
});

test("literalPrefix trims to a whole path segment so src/fo can't match src/foo", () => {
  assert.equal(literalPrefix("self-hosted/check/**"), "self-hosted/check/");
  assert.equal(literalPrefix("stdlib/epistemic/*.sio"), "stdlib/epistemic/");
  assert.equal(literalPrefix("src/fo*"), "src/");
  assert.equal(literalPrefix("exact/file.sio"), "exact/file.sio");
  assert.equal(literalPrefix("**"), "");
  assert.equal(literalPrefix("./a/b/*"), "a/b/");
});

test("overlap is conservative — an advisory system must over-warn, never under-warn", () => {
  assert.equal(globsOverlap("self-hosted/check/**", "self-hosted/check/effects.sio"), true);
  assert.equal(globsOverlap("self-hosted/**", "self-hosted/ir/lower.sio"), true);
  assert.equal(globsOverlap("stdlib/**", "self-hosted/**"), false, "distinct subtrees don't collide");
  assert.equal(globsOverlap("**", "anything/at/all.sio"), true, "a repo-wide claim touches everything");
  assert.equal(globsOverlap("src/foo/**", "src/fo/**"), false, "sibling dirs are not overlaps");
});

test("conflicts are between DIFFERENT lanes; a lane renewing its own path is a heartbeat", () => {
  const now = 1000;
  const claims = [
    { lane: "claude-1", globs: ["self-hosted/check/**"], note: "effects", claimedAt: 10, expiresAt: 9999 },
    { lane: "kimi-cli1", globs: ["self-hosted/check/effects.sio"], note: "same file", claimedAt: 20, expiresAt: 9999 },
    { lane: "codex-1", globs: ["stdlib/linalg/**"], note: "elsewhere", claimedAt: 30, expiresAt: 9999 },
    { lane: "claude-1", globs: ["self-hosted/check/**"], note: "dup self", claimedAt: 40, expiresAt: 9999 },
  ];
  const c = findConflicts(claims, now);
  assert.equal(c.length, 2, "claude-1↔kimi-cli1 twice (two claude-1 entries), never claude-1↔claude-1");
  assert.deepEqual(c[0].lanes, ["claude-1", "kimi-cli1"]);
  assert.ok(c.every((x) => x.lanes[0] !== x.lanes[1]));
  assert.equal(findConflicts(claims, now).some((x) => x.lanes.includes("codex-1")), false);
});

test("an expired claim fences nothing — a crashed agent must not block a path forever", () => {
  const claims = [
    { lane: "dead-lane", globs: ["**"], claimedAt: 0, expiresAt: 500 },
    { lane: "claude-1", globs: ["self-hosted/**"], claimedAt: 0, expiresAt: 9999 },
  ];
  assert.equal(findConflicts(claims, 1000).length, 0, "expired repo-wide claim is inert");
  assert.equal(findConflicts(claims, 100).length, 1, "…but it did conflict while alive");
});

test("the measured hazard: lanes sharing one tree+branch are grouped, biggest first", () => {
  const panes = parsePanes(
    "claude-1|/workspace/sounio|claude\nkimi-cli1|/workspace/sounio|kimi-code\n" +
    "codex-1|/workspace/.wt/codex-1|node\nrepo|/workspace/sounio|zsh\n",
    { "/workspace/sounio": "research/zd-fiber", "/workspace/.wt/codex-1": "lane/codex-1/x" },
  );
  assert.equal(panes.length, 4);
  assert.equal(panes[0].branch, "research/zd-fiber");
  const h = sharedTreeHazards(panes);
  assert.equal(h.length, 1, "only the shared tree is a hazard; the lone worktree is not");
  assert.deepEqual(h[0].lanes, ["claude-1", "kimi-cli1", "repo"]);
  assert.equal(h[0].branch, "research/zd-fiber");
});

test("a lane in its OWN worktree is never a hazard (this is what the migration buys)", () => {
  const panes = parsePanes(
    "claude-1|/workspace/.wt/claude-1|claude\nkimi-cli1|/workspace/.wt/kimi-cli1|kimi-code\n",
    { "/workspace/.wt/claude-1": "lane/claude-1/a", "/workspace/.wt/kimi-cli1": "lane/kimi-cli1/b" },
  );
  assert.deepEqual(sharedTreeHazards(panes), []);
});

test("parsePanes ignores junk lines instead of inventing lanes", () => {
  assert.deepEqual(parsePanes("\n  \ngarbage\nx|/p|c\n"), [{ lane: "x", cwd: "/p", command: "c", branch: "" }]);
});

test("registry: claim, report conflicts, renew keeps claimedAt, release frees", () => {
  let t = 1000;
  const reg = new ClaimRegistry({ now: () => t, defaultTtlMs: 60_000 });
  const a = reg.claim({ lane: "claude-1", globs: ["self-hosted/check/**"], note: "effects" });
  assert.equal(a.conflicts.length, 0);
  assert.equal(a.claim.expiresAt, 61_000);

  const b = reg.claim({ lane: "kimi-cli1", globs: ["self-hosted/check/effects.sio"] });
  assert.equal(b.conflicts.length, 1, "the second claimant is TOLD about the first");
  assert.deepEqual(b.conflicts[0].lanes, ["claude-1", "kimi-cli1"]);

  t = 30_000;
  const renew = reg.claim({ lane: "claude-1", globs: ["self-hosted/check/**"] });
  assert.equal(renew.claim.claimedAt, 1000, "renewing preserves when the work actually started");
  assert.equal(renew.claim.expiresAt, 90_000);

  assert.equal(reg.release("kimi-cli1"), true);
  assert.equal(reg.conflicts().length, 0);
  assert.equal(reg.release("nobody"), false);
});

test("registry rejects nonsense and clamps a hostile TTL", () => {
  const reg = new ClaimRegistry({ now: () => 0, maxTtlMs: 3_600_000 });
  assert.match(reg.claim({ lane: "", globs: ["a"] }).error, /lane/);
  assert.match(reg.claim({ lane: "x", globs: [] }).error, /globs/);
  assert.match(reg.claim({ lane: "x", globs: ["  "] }).error, /globs/);
  assert.equal(reg.claim({ lane: "x", globs: ["a/**"], ttlMs: 999_999_999 }).claim.expiresAt, 3_600_000);
  assert.equal(reg.claim({ lane: "y", globs: ["b/**"], ttlMs: 1 }).claim.expiresAt, 60_000);
});

test("claims expire out of active() without needing a sweep", () => {
  let t = 0;
  const reg = new ClaimRegistry({ now: () => t, defaultTtlMs: 60_000 });
  reg.claim({ lane: "claude-1", globs: ["a/**"] });
  assert.equal(reg.active().length, 1);
  t = 61_001;
  assert.equal(reg.active().length, 0);
});

test("hazard poller: joins panes with per-tree branches; failure ages instead of erasing", async () => {
  const outs = {
    "lane-cwds": "claude-1|/workspace/sounio|claude\nkimi-cli1|/workspace/sounio|kimi-code\n",
    "tree-branches": "/workspace/sounio\tresearch/zd-fiber\n",
  };
  let mode = "ok";
  const execFn = (bin, argv, opts, cb) => {
    if (mode === "fail") return cb(new Error("gone"), "", "");
    const name = Object.keys(WORKSPACE_QUERIES).find((k) => argv.join(" ").includes(WORKSPACE_QUERIES[k]));
    cb(null, outs[name] || "", "");
  };
  const p = new HazardPoller({ kubectl: "k", ns: "beagle", execFn, workspaceQueryArgv, now: () => 7 });
  assert.equal(await p.poll(), true);
  assert.equal(p.state.panes.length, 2);
  assert.equal(p.state.panes[0].branch, "research/zd-fiber");
  assert.deepEqual(sharedTreeHazards(p.state.panes)[0].lanes, ["claude-1", "kimi-cli1"]);

  mode = "fail";
  assert.equal(await p.poll(), false);
  assert.equal(p.state.panes.length, 2, "previous reading survives");
  assert.match(p.state.error, /unreachable/);
});
