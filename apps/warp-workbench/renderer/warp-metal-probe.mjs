#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
//
// Isolated renderer probe for the Warp-derived Workbench boundary.
// This deliberately emits explicit partial/unsupported states instead of
// pretending that Warp's macOS CAMetalLayer renderer is already portable.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  BRIDGE_VERSION,
  WARP_VENDOR_COMMIT,
  terminalBlockToWarpBlock,
} from "../bridge/warp-beagle-bridge.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const boundaryRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(boundaryRoot, "../..");
const vendorRoot = path.join(boundaryRoot, "vendor/warp");
const metalRendererPath = path.join(
  vendorRoot,
  "crates/warpui/src/platform/mac/rendering/metal/renderer.rs",
);
const metalShaderPath = path.join(
  vendorRoot,
  "crates/warpui/src/platform/mac/rendering/metal/shaders/shaders.metal",
);
const hostViewPath = path.join(
  vendorRoot,
  "crates/warpui/src/platform/mac/objc/host_view.m",
);

function argValue(name) {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return "";
  return process.argv[idx + 1] || "";
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function commandAvailable(command, args = ["--version"]) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  return {
    ok: result.status === 0,
    status: result.status,
    stderr: String(result.stderr || "").trim(),
    stdout: String(result.stdout || "").trim(),
  };
}

function inspectWarpMetalBoundary() {
  const rendererExists = fs.existsSync(metalRendererPath);
  const shaderExists = fs.existsSync(metalShaderPath);
  const hostViewExists = fs.existsSync(hostViewPath);
  const rendererText = rendererExists ? fs.readFileSync(metalRendererPath, "utf8") : "";
  const hostViewText = hostViewExists ? fs.readFileSync(hostViewPath, "utf8") : "";
  return {
    rendererExists,
    shaderExists,
    hostViewExists,
    usesCAMetalLayer: hostViewText.includes("CAMetalLayer"),
    usesMetalCrate: rendererText.includes("metal::"),
    requiresMacOSCfg: rendererText.includes("platform/mac"),
    rendererPath: path.relative(repoRoot, metalRendererPath),
    shaderPath: path.relative(repoRoot, metalShaderPath),
  };
}

function sanitizeTerminalBlock(block = {}) {
  const privacyClass = String(block.privacyClass || block.privacy_class || "sensitive");
  const restricted = privacyClass === "restricted" || privacyClass === "restricted_local_only";
  return {
    id: String(block.id || "fixture-block"),
    sessionId: String(block.sessionId || block.session_id || "fixture-session"),
    paneId: String(block.paneId || block.pane_id || "pane-main"),
    kind: String(block.kind || "command"),
    title: String(block.title || block.command || "Renderer probe fixture"),
    command: restricted ? "[restricted command redacted]" : String(block.command || ""),
    outputPreview: restricted ? "[restricted output redacted]" : String(block.outputPreview || block.output_preview || ""),
    outputByteCount: restricted ? 0 : Number(block.outputByteCount || block.output_byte_count || 0),
    status: String(block.status || "finished"),
    privacyClass,
    memoryStatus: String(block.memoryStatus || block.memory_status || "not_saved"),
    blockHash: block.blockHash || block.block_hash || null,
    rendererHint: block.rendererHint || block.renderer_hint || "beagle-terminal-v1",
    restricted,
  };
}

function makeProbeResult({ fixturePath = "", checkOnly = false } = {}) {
  const started = performance.now();
  const boundary = inspectWarpMetalBoundary();
  const xcrun = os.platform() === "darwin" ? commandAvailable("xcrun", ["-find", "metal"]) : { ok: false };
  const fixture = fixturePath ? sanitizeTerminalBlock(readJson(fixturePath)) : null;
  const warpBlock = fixture ? terminalBlockToWarpBlock(fixture) : null;
  const renderable = os.platform() === "darwin" && boundary.rendererExists && boundary.shaderExists && xcrun.ok;
  const status = renderable ? "unsupported_or_partial" : "unsupported_or_partial";
  const reason = renderable
    ? "Warp Metal sources and xcrun metal are present, but the upstream renderer is coupled to macOS CAMetalLayer/AppKit window state; standalone offscreen rendering is not promoted in this spike."
    : "Warp Metal probe requires macOS, xcrun metal, and vendored Warp Metal sources.";
  const ended = performance.now();

  return {
    schema_version: "beagle-warp-metal-probe-v0.1",
    status,
    platform: os.platform(),
    arch: os.arch(),
    check_only: checkOnly,
    renderer: {
      name: "warp-metal-probe",
      path: "apps/warp-workbench/renderer/warp-metal-probe.mjs",
      boundary: "AGPL-3.0-only",
      hot_path: "beagle-terminal-v1",
      promoted: false,
    },
    bridge: {
      version: BRIDGE_VERSION,
      vendor_commit: WARP_VENDOR_COMMIT,
    },
    boundary,
    fixture: fixture
      ? {
          path: path.relative(repoRoot, path.resolve(fixturePath)),
          block_id: fixture.id,
          privacy_class: fixture.privacyClass,
          restricted_redacted: fixture.restricted,
          output_preview_bytes: Buffer.byteLength(fixture.outputPreview),
        }
      : null,
    warp_block: warpBlock
      ? {
          id: warpBlock.id,
          type: warpBlock.type,
          status: warpBlock.status,
          memory_status: warpBlock.memoryStatus,
          provenance: warpBlock.provenance,
        }
      : null,
    timing_ms: {
      total: Math.round((ended - started) * 100) / 100,
    },
    fidelity_notes: [
      "No canonical memory write occurs in renderer probe.",
      "Restricted fixtures are redacted before WarpBlock preview.",
      reason,
    ],
    artifact_path: null,
  };
}

function main() {
  const fixturePath = argValue("--fixture");
  const result = makeProbeResult({
    fixturePath,
    checkOnly: hasFlag("--check"),
  });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main();
