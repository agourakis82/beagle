// SPDX-License-Identifier: AGPL-3.0-only

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../../../", import.meta.url).pathname);
const probe = path.join(root, "apps/warp-workbench/renderer/warp-metal-probe.mjs");

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
  assert.equal(payload.warp_block.id, "block-secret");
  assert.equal(payload.warp_block.memory_status, "blocked");
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
  assert.match(path.basename(payload.result_file), /sample-block-normal/);
  const files = fs.readdirSync(outDir).filter((file) => file.endsWith(".json"));
  assert.equal(files.length, 1);
  const persisted = JSON.parse(fs.readFileSync(path.join(outDir, files[0]), "utf8"));
  assert.equal(persisted.fixture.block_id, "block-normal");
  assert.equal(persisted.renderer.hot_path, "beagle-terminal-v1");
});
