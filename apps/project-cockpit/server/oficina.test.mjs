import { test } from "node:test";
import assert from "node:assert/strict";
import {
  checkVerdict, rollupVerdict, failingChecks,
  reducePRs, reduceMainCI, reduceGitHead, OficinaPoller,
} from "./oficina.mjs";
import { workspaceQueryArgv, WORKSPACE_QUERIES } from "./platform-bridge.mjs";

// Shapes below are real `gh` output from Sounio-lang/sounio (PR #1684, 2026-08-08).
const check = (name, conclusion, status = "COMPLETED") =>
  ({ name, conclusion, status, workflowName: "CI", detailsUrl: `https://gh/${name}` });

test("the leash only allows the three named read-only queries — no build, no gate", () => {
  assert.deepEqual(Object.keys(WORKSPACE_QUERIES).sort(), ["git-head", "main-ci", "pr-list"]);
  for (const q of Object.values(WORKSPACE_QUERIES)) {
    assert.doesNotMatch(q, /make |cargo |souc |run_sio_test_suite|_gate\.sh/,
      "the Oficina must never launch a build/test/gate (61GiB, minutes)");
  }
  // A nested single quote silently truncates the command — it mangled `git-head` in production.
  for (const [name, q] of Object.entries(WORKSPACE_QUERIES)) {
    assert.doesNotMatch(q, /'/, `${name} must not contain a single quote (nested inside sh -c '…')`);
  }
  assert.equal(workspaceQueryArgv("beagle", "rm -rf /"), null);
  assert.equal(workspaceQueryArgv("beagle", "pr-list").includes("sounio-workspace-control-0"), true);
});

test("a check's verdict: unknown conclusions are never assumed good", () => {
  assert.equal(checkVerdict(check("Contracts", "SUCCESS")), "green");
  assert.equal(checkVerdict(check("Contracts", "FAILURE")), "red");
  assert.equal(checkVerdict(check("Contracts", "TIMED_OUT")), "red");
  assert.equal(checkVerdict(check("Contracts", "CANCELLED")), "red");
  assert.equal(checkVerdict(check("Triage", "SKIPPED")), "skipped");
  assert.equal(checkVerdict({ name: "x", status: "IN_PROGRESS", conclusion: "" }), "pending");
  assert.equal(checkVerdict({}), "pending");
});

test("an all-SKIPPED rollup is NOT green — a gate that never ran proves nothing", () => {
  assert.equal(rollupVerdict([check("a", "SKIPPED"), check("b", "NEUTRAL")]), "unknown");
  assert.equal(rollupVerdict([]), "unknown");
  assert.equal(rollupVerdict([check("a", "SKIPPED"), check("b", "SUCCESS")]), "green");
  assert.equal(rollupVerdict([check("a", "SUCCESS"), check("b", "FAILURE")]), "red");
  // Red dominates pending; pending dominates green.
  assert.equal(rollupVerdict([check("a", "", "IN_PROGRESS"), check("b", "FAILURE")]), "red");
  assert.equal(rollupVerdict([check("a", "", "IN_PROGRESS"), check("b", "SUCCESS")]), "pending");
});

test("what broke is NAMED and linked, never a bare red dot", () => {
  const f = failingChecks([check("Contracts", "FAILURE"), check("Impact", "SUCCESS"), check("CI Decision", "FAILURE")]);
  assert.deepEqual(f.map((x) => x.name), ["Contracts", "CI Decision"]);
  assert.match(f[0].url, /^https:\/\//);
  assert.equal(f[0].workflow, "CI");
});

test("reducePRs: real rollup → row, red PRs sorted first", () => {
  const json = JSON.stringify([
    { number: 1684, title: "madaros receipt resync", headRefName: "fix/madaros-receipt-resync",
      isDraft: false, url: "https://gh/1684", updatedAt: "2026-08-08T16:20:00Z",
      statusCheckRollup: [check("Impact", "SUCCESS"), check("Contracts", "SUCCESS"), check("Triage", "SKIPPED")] },
    { number: 1580, title: "ir instruction struct arrays", headRefName: "ir-instruction-struct-arrays",
      isDraft: true, url: "https://gh/1580", updatedAt: "2026-08-08T15:00:00Z",
      statusCheckRollup: [check("Contracts", "FAILURE"), check("Impact", "SUCCESS")] },
  ]);
  const rows = reducePRs(json);
  assert.equal(rows[0].number, 1580, "red first");
  assert.equal(rows[0].verdict, "red");
  assert.deepEqual(rows[0].failing.map((f) => f.name), ["Contracts"]);
  assert.equal(rows[0].draft, true);
  assert.equal(rows[1].verdict, "green");
  assert.equal(rows[1].checksGreen, 2);
  assert.equal(rows[1].checksTotal, 3);
});

test("reducePRs survives garbage without throwing", () => {
  assert.deepEqual(reducePRs("not json"), []);
  assert.deepEqual(reducePRs("{}"), []);
  assert.deepEqual(reducePRs(""), []);
});

test("reduceMainCI judges only the LATEST run per workflow", () => {
  const json = JSON.stringify([
    { name: "CI", status: "COMPLETED", conclusion: "SUCCESS", url: "u1", headSha: "abcdef1234", createdAt: "2026-08-08T16:00:00Z" },
    { name: "CI", status: "COMPLETED", conclusion: "FAILURE", url: "u0", headSha: "0000000000", createdAt: "2026-08-07T16:00:00Z" },
  ]);
  const m = reduceMainCI(json);
  assert.equal(m.verdict, "green", "an older red that has since gone green is history");
  assert.equal(m.runs.length, 2);
  assert.equal(m.runs[0].sha, "abcdef12");
  assert.deepEqual(reduceMainCI("[]"), { verdict: "unknown", runs: [] });
});

test("reduceGitHead parses branch/sha/dirty; rejects empty", () => {
  const h = reduceGitHead("research/zd-fiber\n5c4e950f11aa\t1786200000\tfeat(zd): Tier 94\n7\n");
  assert.equal(h.branch, "research/zd-fiber");
  assert.equal(h.sha, "5c4e950f11");
  assert.equal(h.dirtyFiles, 7);
  assert.match(h.subject, /Tier 94/);
  assert.ok(h.committedAt.startsWith("2026-"));
  assert.equal(reduceGitHead(""), null);
});

test("a failed sweep keeps the previous state ageing, with a stated reason", async () => {
  const good = {
    "pr-list": JSON.stringify([{ number: 1, title: "t", headRefName: "b", statusCheckRollup: [check("CI", "SUCCESS")] }]),
    "main-ci": JSON.stringify([{ name: "CI", status: "COMPLETED", conclusion: "SUCCESS" }]),
    "git-head": "main\nabc\t1786200000\tsubject\n0\n",
  };
  let mode = "ok";
  const execFn = (bin, argv, opts, cb) => {
    const name = Object.keys(WORKSPACE_QUERIES).find((k) => argv.join(" ").includes(WORKSPACE_QUERIES[k]));
    if (mode === "fail") return cb(new Error("workspace gone"), "", "");
    cb(null, good[name] || "", "");
  };
  const p = new OficinaPoller({ kubectl: "kubectl", ns: "beagle", execFn, now: () => 500 });
  assert.equal(await p.poll(), true);
  assert.equal(p.state.prs.length, 1);
  assert.equal(p.state.main.verdict, "green");
  assert.equal(p.state.observedAt, 500);

  mode = "fail";
  assert.equal(await p.poll(), false);
  assert.equal(p.state.prs.length, 1, "previous rows survive");
  assert.equal(p.state.observedAt, 500, "and are visibly not re-observed");
  assert.match(p.state.error, /unreachable/);
});

test("overlapping polls do not stack execs", async () => {
  let calls = 0;
  const p = new OficinaPoller({ kubectl: "k", ns: "n", execFn: () => { calls++; } });
  p.poll(); p.poll();
  assert.equal(calls, 3, "one sweep = 3 queries, and the second poll is refused");
});
