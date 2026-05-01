import test from "node:test";
import assert from "node:assert/strict";
import {
  agentRegistry,
  foldBlocks,
  hasSecret,
  findAgentRole,
  normalizeSession,
  routeAgentTask,
  shouldAutoRememberBlock,
} from "../src/workbench-core.mjs";

test("foldBlocks preserves restricted state after secret redaction", () => {
  const blocks = foldBlocks([
    {
      type: "block_started",
      blockId: "block-1",
      sessionId: "session-1",
      paneId: "pane-main",
      command: "echo ok",
      at: "2026-04-30T20:00:00Z",
    },
    {
      type: "block_output",
      blockId: "block-1",
      sessionId: "session-1",
      paneId: "pane-main",
      data: "token=redacted",
      at: "2026-04-30T20:00:01Z",
    },
    {
      type: "secret_redacted",
      blockId: "block-1",
      sessionId: "session-1",
      paneId: "pane-main",
      reason: "output_secret_detected",
      at: "2026-04-30T20:00:01Z",
    },
  ]);

  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].privacyClass, "restricted_local_only");
  assert.equal(blocks[0].memoryStatus, "blocked");
  assert.equal(shouldAutoRememberBlock(blocks[0]), false);
});

test("normalizeSession carries authority status without requiring it", () => {
  const legacy = normalizeSession("sounio", { id: "wb-legacy", panes: [] });
  const current = normalizeSession("sounio", {
    id: "wb-agent",
    authorityStatus: {
      authority: "workspace-agent",
      supervisor: { status: "healthy" },
    },
    panes: [{ id: "pane-main", reconnectState: "attached" }],
  });

  assert.equal(legacy.authorityStatus, null);
  assert.equal(current.authorityStatus.authority, "workspace-agent");
  assert.equal(current.panes[0].reconnectState, "attached");
});

test("secret matcher catches common credential shapes", () => {
  assert.equal(hasSecret("Authorization: Bearer abcdefghijklmnopqrstuvwxyz"), true);
  assert.equal(hasSecret("client_secret=do-not-send"), true);
  assert.equal(hasSecret("swift test passed"), false);
});

test("agent registry exposes Sounio/Beagle model ecology roles", () => {
  const registry = agentRegistry();
  const roles = registry.map((entry) => entry.role);
  const visibleRoles = registry.filter((entry) => entry.visible !== false).map((entry) => entry.role);

  assert.ok(roles.includes("primary_builder"));
  assert.ok(roles.includes("code_worker"));
  assert.ok(roles.includes("long_thought_architect"));
  assert.ok(roles.includes("platform_operator"));
  assert.ok(roles.includes("video_memory"));
  assert.deepEqual(visibleRoles, [
    "primary_builder",
    "code_worker",
    "long_thought_architect",
    "maintenance_agent",
    "platform_operator",
    "shell",
  ]);
  assert.equal(findAgentRole("minimax")?.role, "code_worker");
  assert.equal(findAgentRole("kimi")?.role, "long_thought_architect");
});

test("agent router chooses roles by task intent", () => {
  assert.equal(routeAgentTask({ task: "refactor compiler bug and run cargo test" }).chosenRole, "code_worker");
  assert.equal(routeAgentTask({ task: "design Sounio Claim<T> semantics and type effects" }).chosenRole, "long_thought_architect");
  assert.equal(routeAgentTask({ task: "debug Kubernetes rollout and Cloudflare incident" }).chosenRole, "platform_operator");
  assert.equal(routeAgentTask({ task: "summarize huge README docs logs and manifests" }).chosenRole, "global_reader");
  assert.equal(routeAgentTask({ task: "index walkthrough video of the Beagle demo" }).chosenRole, "video_memory");
});

test("Sounio Six agent commands are auto-memory candidates", () => {
  assert.equal(shouldAutoRememberBlock({ command: "minimax refactor compiler module", outputPreview: "" }), true);
  assert.equal(shouldAutoRememberBlock({ command: "qwen-coder run lint loop", outputPreview: "" }), true);
  assert.equal(shouldAutoRememberBlock({ command: "glm-air inspect k8s rollout", outputPreview: "" }), true);
});

test("missing CLI setup noise is not auto-memory", () => {
  assert.equal(
    shouldAutoRememberBlock({
      command: "claude",
      outputPreview: "bash: claude: command not found",
    }),
    false,
  );
  assert.equal(
    shouldAutoRememberBlock({
      command: "cursor",
      outputPreview: "bash: cursor: command not found",
    }),
    false,
  );
});
