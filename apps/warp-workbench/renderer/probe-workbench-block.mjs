#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
//
// Fetches a real Beagle Workbench block, writes a sanitized transient fixture,
// and runs the isolated Warp Metal probe. This stays inside the AGPL boundary
// and produces only derived probe JSON; it never writes canonical memory.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const boundaryRoot = path.resolve(__dirname, "..");
const probePath = path.join(__dirname, "warp-metal-probe.mjs");

function argValue(name) {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return "";
  return process.argv[idx + 1] || "";
}

function required(name) {
  const value = argValue(name);
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function safeFilePart(value) {
  return String(value || "sample")
    .replace(/[^a-zA-Z0-9_.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 96) || "sample";
}

function blockPrivacy(block = {}) {
  return String(block.privacyClass || block.privacy_class || "sensitive");
}

function sanitizeBlock(block = {}) {
  const privacyClass = blockPrivacy(block);
  const restricted = privacyClass === "restricted" || privacyClass === "restricted_local_only";
  return {
    id: String(block.id || "fixture-block"),
    sessionId: String(block.sessionId || block.session_id || ""),
    paneId: String(block.paneId || block.pane_id || "pane-main"),
    kind: String(block.kind || "command"),
    title: String(block.title || block.command || "Terminal block"),
    command: restricted ? "[restricted command redacted]" : String(block.command || ""),
    outputPreview: restricted ? "[restricted output redacted]" : String(block.outputPreview || block.output_preview || ""),
    outputByteCount: restricted ? 0 : Number(block.outputByteCount || block.output_byte_count || 0),
    startedAt: String(block.startedAt || block.started_at || ""),
    finishedAt: String(block.finishedAt || block.finished_at || ""),
    durationMs: block.durationMs ?? block.duration_ms ?? null,
    exitCode: block.exitCode ?? block.exit_code ?? null,
    status: String(block.status || "finished"),
    privacyClass,
    memoryStatus: String(block.memoryStatus || block.memory_status || "not_saved"),
    tags: Array.isArray(block.tags) ? block.tags : [],
    sourceModel: String(block.sourceModel || block.source_model || "beagle"),
    bridgeVersion: String(block.bridgeVersion || block.bridge_version || "beagle-warp-bridge-v0.2"),
    blockHash: block.blockHash || block.block_hash || null,
    sessionHash: block.sessionHash || block.session_hash || null,
    rendererHint: String(block.rendererHint || block.renderer_hint || "beagle-terminal-v1"),
    restricted,
  };
}

async function fetchBlocks({ baseUrl, project, sessionId }) {
  const url = new URL(
    `/api/workspaces/${encodeURIComponent(project)}/sessions/${encodeURIComponent(sessionId)}/blocks`,
    baseUrl,
  );
  const response = await fetch(url, { headers: { accept: "application/json" } });
  const text = await response.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : {};
  } catch (_error) {
    payload = { raw: text };
  }
  if (!response.ok) {
    throw new Error(payload.error || payload.raw || response.statusText);
  }
  return Array.isArray(payload.blocks) ? payload.blocks : [];
}

async function loadBlocks() {
  const blocksFile = argValue("--blocks-file");
  if (blocksFile) {
    const payload = readJson(blocksFile);
    return Array.isArray(payload) ? payload : payload.blocks || [];
  }
  const baseUrl = argValue("--base-url") || "http://127.0.0.1:4370";
  const project = required("--project");
  const sessionId = required("--session-id");
  return fetchBlocks({ baseUrl, project, sessionId });
}

async function main() {
  const project = argValue("--project") || "sounio";
  const blockId = required("--block-id");
  const outDir = argValue("--out-dir") || path.join(boundaryRoot, "renderer/results", project);
  const fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), "beagle-warp-block-fixture-"));
  const blocks = await loadBlocks();
  const block = blocks.find((candidate) => String(candidate.id || candidate.block_id) === blockId);
  if (!block) {
    throw new Error(`block ${blockId} not found`);
  }
  const sanitized = sanitizeBlock(block);
  const fixturePath = path.join(fixtureDir, `${safeFilePart(blockId)}.json`);
  fs.writeFileSync(fixturePath, `${JSON.stringify(sanitized, null, 2)}\n`, { mode: 0o600 });

  const result = spawnSync(process.execPath, [
    probePath,
    "--fixture",
    fixturePath,
    "--out-dir",
    outDir,
    "--sample-id",
    `${project}-${blockId}`,
  ], {
    cwd: boundaryRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    process.stderr.write(result.stderr || result.stdout);
    process.exit(result.status || 1);
  }
  process.stdout.write(result.stdout);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message || error}\n`);
  process.exit(1);
});
