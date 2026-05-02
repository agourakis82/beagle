// SPDX-License-Identifier: AGPL-3.0-only
//
// Dual bridge between Beagle Terminal Protocol v1 and the Warp-derived model.
// This module intentionally lives inside the AGPL workbench boundary.

import { createHash } from "node:crypto";

export const BRIDGE_VERSION = "beagle-warp-bridge-v0.2";
export const WARP_VENDOR_COMMIT = "805b3e2a576e689a1e414f01ed3fc51e9e704d69";
export const WARP_VENDOR_URL = "https://github.com/warpdotdev/Warp.git";

function cleanString(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "boolean") return String(value).trim();
  return "";
}

function rawString(value) {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return "";
}

function hashPayload(payload) {
  return `sha256:${createHash("sha256").update(JSON.stringify(payload)).digest("hex")}`;
}

function normalizeMemoryStatus(status) {
  const value = cleanString(status);
  if (["remembered", "blocked", "queued", "failed", "manual", "not_saved"].includes(value)) {
    return value;
  }
  if (value === "saved") return "remembered";
  return "not_saved";
}

function normalizeAgentState(state) {
  const value = cleanString(state).toLowerCase();
  if (["idle", "thinking", "needs_input", "editing", "running_tests", "approval_wait", "failed", "done"].includes(value)) {
    return value;
  }
  if (value.includes("test")) return "running_tests";
  if (value.includes("approval") || value.includes("confirm")) return "approval_wait";
  if (value.includes("input")) return "needs_input";
  if (value.includes("done") || value.includes("complete")) return "done";
  return "idle";
}

export function bridgeMetadata(sourceModel, payload = {}, rendererHint = "warp-derived") {
  const cleanSource = cleanString(sourceModel) || "warp";
  return {
    sourceModel: cleanSource,
    source_model: cleanSource,
    bridgeVersion: BRIDGE_VERSION,
    bridge_version: BRIDGE_VERSION,
    rendererHint,
    renderer_hint: rendererHint,
    bridgeHash: hashPayload({
      sourceModel: cleanSource,
      rendererHint,
      payload,
    }),
  };
}

export function warpBlockToTerminalBlock(warpBlock = {}) {
  const command = cleanString(warpBlock.command || warpBlock.input);
  const output = rawString(warpBlock.output ?? warpBlock.outputPreview);
  const id = cleanString(warpBlock.id || warpBlock.blockId) || hashPayload({ command, output }).slice(7, 23);
  const metadata = bridgeMetadata("warp", { id, command, output }, "warp-block");
  return {
    id,
    sessionId: cleanString(warpBlock.sessionId || warpBlock.session_id),
    paneId: cleanString(warpBlock.paneId || warpBlock.pane_id || "warp-pane"),
    kind: cleanString(warpBlock.kind || warpBlock.type || "command"),
    title: cleanString(warpBlock.title) || (command.length > 72 ? `${command.slice(0, 69)}...` : command || "Warp Block"),
    command,
    outputPreview: output.slice(0, 12000),
    outputByteCount: Number(warpBlock.outputByteCount || Buffer.byteLength(output)),
    startedAt: cleanString(warpBlock.startedAt || warpBlock.started_at),
    finishedAt: cleanString(warpBlock.finishedAt || warpBlock.finished_at),
    durationMs: Number.isFinite(Number(warpBlock.durationMs || warpBlock.duration_ms))
      ? Number(warpBlock.durationMs || warpBlock.duration_ms)
      : null,
    exitCode: Number.isFinite(Number(warpBlock.exitCode || warpBlock.exit_code))
      ? Number(warpBlock.exitCode || warpBlock.exit_code)
      : null,
    status: cleanString(warpBlock.status || "finished"),
    privacyClass: cleanString(warpBlock.privacyClass || warpBlock.privacy_class || "sensitive"),
    memoryStatus: normalizeMemoryStatus(warpBlock.memoryStatus || warpBlock.memory_status),
    tags: Array.isArray(warpBlock.tags) ? warpBlock.tags : ["workbench", "terminal-block", "source_model:warp"],
    sourceModel: "warp",
    bridgeVersion: metadata.bridgeVersion,
    blockHash: metadata.bridgeHash,
    rendererHint: metadata.rendererHint,
  };
}

export function terminalBlockToWarpBlock(block = {}) {
  const metadata = bridgeMetadata("beagle", block, "beagle-terminal-v1");
  return {
    id: cleanString(block.id),
    sessionId: cleanString(block.sessionId || block.session_id),
    paneId: cleanString(block.paneId || block.pane_id),
    type: cleanString(block.kind || "command"),
    title: cleanString(block.title),
    command: cleanString(block.command),
    outputPreview: rawString(block.outputPreview ?? block.output_preview),
    status: cleanString(block.status || "finished"),
    exitCode: block.exitCode ?? block.exit_code ?? null,
    durationMs: block.durationMs ?? block.duration_ms ?? null,
    memoryStatus: normalizeMemoryStatus(block.memoryStatus || block.memory_status),
    provenance: {
      ...(block.provenance || {}),
      source_model: "beagle",
      bridge_version: BRIDGE_VERSION,
      block_hash: metadata.bridgeHash,
      renderer_hint: "beagle-terminal-v1",
    },
  };
}

export function warpSessionToWorkspaceSession(warpSession = {}) {
  const id = cleanString(warpSession.id || warpSession.sessionId) || "warp-session";
  const panes = Array.isArray(warpSession.panes) ? warpSession.panes : [];
  const metadata = bridgeMetadata("warp", { id, panes }, "warp-session");
  return {
    id,
    projectSlug: cleanString(warpSession.projectSlug || warpSession.project_slug || "beagle"),
    title: cleanString(warpSession.title || "Warp Workbench"),
    status: cleanString(warpSession.status || "active"),
    layout: "notebook",
    createdAt: cleanString(warpSession.createdAt || warpSession.created_at),
    updatedAt: cleanString(warpSession.updatedAt || warpSession.updated_at),
    lastAttachedAt: cleanString(warpSession.lastAttachedAt || warpSession.last_attached_at),
    lastMemoryStatus: warpSession.lastMemoryStatus || null,
    panes,
    sourceModel: "warp",
    bridgeVersion: metadata.bridgeVersion,
    sessionHash: metadata.bridgeHash,
    rendererHint: metadata.rendererHint,
  };
}

export function workspaceSessionToWarpSession(session = {}) {
  const metadata = bridgeMetadata("beagle", session, "beagle-session");
  return {
    id: cleanString(session.id),
    projectSlug: cleanString(session.projectSlug || session.project_slug),
    title: cleanString(session.title),
    status: cleanString(session.status || "active"),
    panes: Array.isArray(session.panes) ? session.panes : [],
    provenance: {
      source_model: "beagle",
      bridge_version: BRIDGE_VERSION,
      session_hash: metadata.bridgeHash,
      renderer_hint: "beagle-session",
    },
  };
}

export function warpAgentStateToAgentRunState(agent = {}) {
  return {
    kind: cleanString(agent.kind || agent.name || "custom"),
    state: normalizeAgentState(agent.state || agent.status),
    summary: cleanString(agent.summary || agent.lastMessage || agent.last_message),
    branch: cleanString(agent.branch),
    commit: cleanString(agent.commit),
    changedFiles: Array.isArray(agent.changedFiles || agent.changed_files)
      ? (agent.changedFiles || agent.changed_files).map(cleanString).filter(Boolean)
      : [],
  };
}

export function agentRunStateToWarpAgentState(agent = {}) {
  return {
    kind: cleanString(agent.kind || "custom"),
    status: normalizeAgentState(agent.state || agent.status),
    summary: cleanString(agent.summary),
    branch: cleanString(agent.branch),
    commit: cleanString(agent.commit),
    changedFiles: Array.isArray(agent.changedFiles || agent.changed_files)
      ? (agent.changedFiles || agent.changed_files).map(cleanString).filter(Boolean)
      : [],
  };
}
