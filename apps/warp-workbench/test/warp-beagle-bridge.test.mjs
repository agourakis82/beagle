// SPDX-License-Identifier: AGPL-3.0-only

import assert from "node:assert/strict";
import test from "node:test";
import {
  BRIDGE_VERSION,
  WARP_VENDOR_COMMIT,
  agentRunStateToWarpAgentState,
  terminalBlockToWarpBlock,
  warpAgentStateToAgentRunState,
  warpBlockToTerminalBlock,
  warpSessionToWorkspaceSession,
  workspaceSessionToWarpSession,
} from "../bridge/warp-beagle-bridge.mjs";

test("Warp vendor pin is explicit", () => {
  assert.equal(WARP_VENDOR_COMMIT, "805b3e2a576e689a1e414f01ed3fc51e9e704d69");
});

test("Warp block converts into Beagle TerminalBlock with bridge metadata", () => {
  const block = warpBlockToTerminalBlock({
    id: "warp-block-1",
    sessionId: "session-1",
    paneId: "pane-1",
    command: "swift test",
    output: "Test Suite passed",
    memoryStatus: "saved",
    durationMs: 42,
  });

  assert.equal(block.id, "warp-block-1");
  assert.equal(block.memoryStatus, "remembered");
  assert.equal(block.sourceModel, "warp");
  assert.equal(block.bridgeVersion, BRIDGE_VERSION);
  assert.match(block.blockHash, /^sha256:/);
  assert.equal(block.rendererHint, "warp-block");
});

test("Beagle TerminalBlock converts into Warp block without losing provenance", () => {
  const block = terminalBlockToWarpBlock({
    id: "block-1",
    sessionId: "session-1",
    paneId: "pane-main",
    kind: "command",
    title: "cargo test",
    command: "cargo test",
    outputPreview: "ok",
    status: "finished",
    memoryStatus: "remembered",
  });

  assert.equal(block.id, "block-1");
  assert.equal(block.type, "command");
  assert.equal(block.memoryStatus, "remembered");
  assert.equal(block.provenance.source_model, "beagle");
  assert.equal(block.provenance.bridge_version, BRIDGE_VERSION);
});

test("Terminal output preview preserves trailing VT line discipline", () => {
  const outputPreview = "cmd\r\n\x1b[32mok\x1b[0m\r\n";
  const warpBlock = terminalBlockToWarpBlock({
    id: "block-vt",
    sessionId: "session-vt",
    paneId: "pane-main",
    kind: "command",
    title: "cmd",
    command: "cmd",
    outputPreview,
    status: "finished",
  });
  const terminalBlock = warpBlockToTerminalBlock({
    id: "warp-vt",
    sessionId: "session-vt",
    paneId: "pane-main",
    command: "cmd",
    output: outputPreview,
    status: "finished",
  });

  assert.equal(warpBlock.outputPreview, outputPreview);
  assert.equal(terminalBlock.outputPreview, outputPreview);
});

test("Sessions and agent states round-trip through the dual bridge", () => {
  const session = warpSessionToWorkspaceSession({
    id: "warp-session",
    projectSlug: "sounio",
    panes: [{ id: "pane-1", kind: "codex" }],
  });
  const warpSession = workspaceSessionToWarpSession(session);
  const agent = warpAgentStateToAgentRunState({
    kind: "codex",
    status: "Running tests",
    changedFiles: ["Sources/Sounio.swift"],
  });
  const warpAgent = agentRunStateToWarpAgentState(agent);

  assert.equal(session.sourceModel, "warp");
  assert.match(session.sessionHash, /^sha256:/);
  assert.equal(warpSession.provenance.source_model, "beagle");
  assert.equal(agent.state, "running_tests");
  assert.equal(warpAgent.status, "running_tests");
});
