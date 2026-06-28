// SPDX-License-Identifier: AGPL-3.0-only

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { analyzeVtFidelity } from "../renderer/vt-fidelity.mjs";

const root = path.resolve(new URL("../../../", import.meta.url).pathname);
const probe = path.join(root, "apps/warp-workbench/renderer/warp-metal-probe.mjs");
const blockProbe = path.join(root, "apps/warp-workbench/renderer/probe-workbench-block.mjs");

test("renderer probe returns explicit partial status without writing memory", () => {
  const result = spawnSync(process.execPath, [probe, "--check"], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  const payload = JSON.parse(result.stdout);

  assert.equal(payload.schema_version, "beagle-warp-metal-probe-v0.1");
  assert.equal(payload.status, "unsupported_or_partial");
  assert.equal(payload.renderer.promoted, false);
  assert.equal(payload.renderer.hot_path, "beagle-terminal-v1");
  assert.match(payload.fidelity_notes.join("\n"), /No canonical memory write/);
});

test("renderer probe redacts restricted fixture before WarpBlock preview", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "beagle-warp-probe-"));
  const fixture = path.join(dir, "restricted-block.json");
  fs.writeFileSync(fixture, JSON.stringify({
    id: "block-secret",
    sessionId: "session-1",
    paneId: "pane-main",
    title: "Restricted command",
    command: "export TOKEN=super-secret",
    outputPreview: "super-secret output",
    privacyClass: "restricted_local_only",
    memoryStatus: "blocked",
  }));

  const result = spawnSync(process.execPath, [probe, "--fixture", fixture], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stdout, /super-secret/);
  const payload = JSON.parse(result.stdout);

  assert.equal(payload.fixture.restricted_redacted, true);
  assert.equal(payload.vt_fidelity.status, "pass");
  assert.equal(payload.vt_fidelity.mode, "restricted_redaction");
  assert.equal(payload.warp_block.id, "block-secret");
  assert.equal(payload.warp_block.memory_status, "blocked");
});

test("VT fidelity audit preserves terminal escape taxonomy for ANSI fixtures", () => {
  const outputPreview = "printf color\r\n\x1b[31mred\x1b[0m\r\n\x1b]0;title\x07prompt$ ";
  const audit = analyzeVtFidelity({
    terminalBlock: {
      outputPreview,
      privacyClass: "sensitive",
    },
    warpBlock: {
      outputPreview,
    },
  });

  assert.equal(audit.status, "pass");
  assert.equal(audit.expected.csi, 2);
  assert.equal(audit.expected.osc, 1);
  assert.equal(audit.ratios.esc, 1);
});

test("renderer probe can persist derived JSON result to an output directory", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "beagle-warp-probe-out-"));
  const fixture = path.join(dir, "normal-block.json");
  const outDir = path.join(dir, "results");
  fs.writeFileSync(fixture, JSON.stringify({
    id: "block-normal",
    sessionId: "session-2",
    paneId: "pane-main",
    title: "Normal command",
    command: "printf ok",
    outputPreview: "ok",
    privacyClass: "sensitive",
    memoryStatus: "remembered",
  }));

  const result = spawnSync(process.execPath, [
    probe,
    "--fixture",
    fixture,
    "--out-dir",
    outDir,
    "--sample-id",
    "sample/block normal",
  ], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  const payload = JSON.parse(result.stdout);

  assert.equal(payload.fixture.block_id, "block-normal");
  assert.equal(payload.vt_fidelity.status, "partial");
  assert.equal(payload.latency_budget.scope, "probe_conversion_only");
  assert.match(path.basename(payload.result_file), /sample-block-normal/);
  const files = fs.readdirSync(outDir).filter((file) => file.endsWith(".json"));
  assert.equal(files.length, 1);
  const persisted = JSON.parse(fs.readFileSync(path.join(outDir, files[0]), "utf8"));
  assert.equal(persisted.fixture.block_id, "block-normal");
  assert.equal(persisted.renderer.hot_path, "beagle-terminal-v1");
});

test("workbench block probe sanitizes selected block before invoking renderer probe", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "beagle-warp-block-probe-"));
  const blocksFile = path.join(dir, "blocks.json");
  const outDir = path.join(dir, "results");
  fs.writeFileSync(blocksFile, JSON.stringify({
    blocks: [
      {
        id: "block-sensitive",
        sessionId: "session-3",
        paneId: "pane-main",
        title: "Restricted block",
        command: "export TOKEN=secret-block-token",
        outputPreview: "secret-block-token",
        privacyClass: "restricted_local_only",
        memoryStatus: "blocked",
        blockHash: "sha256:block-sensitive",
      },
    ],
  }));

  const result = spawnSync(process.execPath, [
    blockProbe,
    "--blocks-file",
    blocksFile,
    "--project",
    "sounio",
    "--block-id",
    "block-sensitive",
    "--out-dir",
    outDir,
  ], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stdout, /secret-block-token/);
  const payload = JSON.parse(result.stdout);

  assert.equal(payload.fixture.block_id, "block-sensitive");
  assert.equal(payload.fixture.restricted_redacted, true);
  const persistedFiles = fs.readdirSync(outDir).filter((file) => file.endsWith(".json"));
  assert.equal(persistedFiles.length, 1);
});
