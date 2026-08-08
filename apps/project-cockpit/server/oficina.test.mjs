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

test("the leash allows only named READ-ONLY queries — no build, no test, no gate, no writes", () => {
  assert.deepEqual(Object.keys(WORKSPACE_QUERIES).sort(),
    ["git-head", "lane-cwds", "main-ci", "pr-list", "receipts", "tree-branches"]);
  for (const [name, q] of Object.entries(WORKSPACE_QUERIES)) {
    assert.doesNotMatch(q, /make |cargo |souc |run_sio_test_suite|_gate\.sh/,
      `${name} must never launch a build/test/gate (61GiB, minutes)`);
    // Read-only by construction: nothing here may mutate a tree, a ref, or a remote.
    assert.doesNotMatch(q, /\b(git (add|commit|checkout|switch|reset|clean|push|rebase|merge)|rm |mv |tee |send-keys)\b/,
      `${name} must not mutate anything`);
    // Discarding stderr is fine; writing anywhere else is not.
    const withoutDevNull = q.replace(/\d?>\s*\/dev\/null/g, "");
    assert.doesNotMatch(withoutDevNull, />/, `${name} must not redirect into a file`);
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

// ── Recibos: a saída real desta linguagem ────────────────────────────────────────────────
import { reduceReceipts } from "./oficina.mjs";
import { RECEIPT_DELIM } from "./platform-bridge.mjs";

const receipt = (path, obj) => `${RECEIPT_DELIM}${path}\n${JSON.stringify(obj, null, 2)}\n`;

test("um recibo vira evidência: proposição, medição e o par que prova falsificabilidade", () => {
  // Forma real de artifacts/compiler/madaros_wave15e_global_string_receipt.v1.json
  const out = reduceReceipts(receipt("artifacts/compiler/madaros_wave15e.v1.json", {
    schema: "madaros_wave15e_global_string_receipt.v1",
    status: "pass",
    residual: "module-level string literal BSS init SEGV",
    claim: 'let S: string = "hi"; println(S) prints hi under current-source Madaros',
    gate: "scripts/ci/madaros_global_string_init_gate.sh",
    measured_stdout: ["hi", "yo"],
    pre_fix: { run_rc: 139, rodata_hi: false },
    post_fix: { run_rc: 0, rodata_hi: true },
    git_sha: "3e7ed9f52946349ac2495f90727510c32e1a7004",
  }));
  assert.equal(out.length, 1);
  const r = out[0];
  assert.equal(r.family, "compiler");
  assert.equal(r.status, "pass");
  assert.match(r.claim, /println\(S\) prints hi/);
  assert.equal(r.falsifiable, true, "pre_fix + post_fix = o vermelho era alcançável");
  assert.equal(r.preFix.run_rc, 139);
  assert.equal(r.gitSha, "3e7ed9f529");
});

test("um recibo sem par pre/post NÃO é marcado falsificável", () => {
  const r = reduceReceipts(receipt("artifacts/omega/x.v1.json", {
    schema: "sounio.claude.operational.contract.v1", status: "pass",
  }))[0];
  assert.equal(r.falsifiable, false, "verde sem vermelho alcançável não prova nada");
});

test("status ausente ou estranho é unknown, nunca assumido bom", () => {
  assert.equal(reduceReceipts(receipt("artifacts/gpu/a.v1.json", { schema: "s" }))[0].status, "unknown");
  assert.equal(reduceReceipts(receipt("artifacts/gpu/b.v1.json", { status: "vibing" }))[0].status, "unknown");
  assert.equal(reduceReceipts(receipt("artifacts/gpu/c.v1.json", { status: "pass_full" }))[0].status, "pass");
  assert.equal(reduceReceipts(receipt("artifacts/gpu/d.v1.json", { status: "FAIL" }))[0].status, "fail");
});

test("recibos ilegíveis são descartados, não inventados; os bons ao lado sobrevivem", () => {
  const mixed = `${RECEIPT_DELIM}artifacts/x/quebrado.v1.json\n{ isso não é json\n` +
                receipt("artifacts/stdlib/bom.v1.json", { schema: "ok", status: "pass" });
  const out = reduceReceipts(mixed);
  assert.equal(out.length, 1);
  assert.equal(out[0].family, "stdlib");
  assert.deepEqual(reduceReceipts(""), []);
});

test("novel_claims — o achado científico — sobrevive ao redutor", () => {
  const r = reduceReceipts(receipt("artifacts/omega/n.v1.json", {
    schema: "s", status: "pass",
    novel_claims: ["v2(D[tri3]) = 3(n-j) com cofator ímpar", "tr(A²) injetiva em g"],
    metrics: { pass: 16, fail: 0 },
  }))[0];
  assert.equal(r.novelClaims.length, 2);
  assert.match(r.novelClaims[0], /cofator ímpar/);
  assert.equal(r.metrics.pass, 16);
});
