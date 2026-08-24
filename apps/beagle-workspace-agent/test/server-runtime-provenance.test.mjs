import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";

const runtimeEvidence = {
  supervisorRuntime: "sounio-loom-beagle-bridge-v1",
  supervisorProtocol: "beagle-pty-supervisor-v1",
  loomInstanceId: "loom-instance-test",
  generationFingerprint: "loom-generation-test",
  authorityStatus: {
    owner: "loom",
    journalVerified: true,
    semanticJournalHead: "semantic-head-test",
    guardianJournalHead: "guardian-head-test",
    kernelRecoveryCount: 2,
    lineageVerified: true,
    generationLineageHead: "lineage-head-test",
    generationTransition: "pod-resurrected",
    generationTransitionCount: 3,
    podResurrectionCount: 1,
    predecessorInstanceId: "loom-instance-predecessor",
    predecessorSemanticJournalHead: "predecessor-semantic-head-test",
    predecessorGuardianJournalHead: "predecessor-guardian-head-test",
  },
};

function json(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
}

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolve(server.address().port);
    });
  });
}

async function reservePort() {
  const server = http.createServer();
  const port = await listen(server);
  await new Promise((resolve) => server.close(resolve));
  return port;
}

async function waitForReady(url, child) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (child.exitCode !== null) throw new Error(`workspace agent exited with ${child.exitCode}`);
    try {
      const response = await fetch(url);
      if (response.ok) return response.json();
    } catch {
      // The child has not bound its loopback port yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("workspace agent did not become ready");
}

test("Workspace Agent attributes terminal blocks to the Loom runtime", async (t) => {
  const clients = new Set();
  const pane = {
    paneId: "session-runtime:pane-main",
    sessionId: "session-runtime",
    pid: 4242,
    status: "running",
    cwd: process.cwd(),
    cols: 120,
    rows: 34,
    snapshot: "",
    ...runtimeEvidence,
  };

  const supervisor = http.createServer(async (req, res) => {
    const url = new URL(req.url || "/", "http://127.0.0.1");
    if (req.method === "GET" && url.pathname === "/v1/health") {
      json(res, 200, {
        status: "ok",
        supervisor: runtimeEvidence.supervisorRuntime,
        supervisorRuntime: runtimeEvidence.supervisorRuntime,
        supervisorProtocol: runtimeEvidence.supervisorProtocol,
        authority: "loom",
        panes: 1,
      });
      return;
    }
    if (req.method === "POST" && url.pathname === "/v1/spawn") {
      await readJson(req);
      json(res, 200, { pane });
      return;
    }
    if (req.method === "POST" && url.pathname.endsWith("/input")) {
      const body = await readJson(req);
      json(res, 200, { pane });
      const payload = JSON.stringify({
        type: "raw_output",
        paneId: pane.paneId,
        sessionId: pane.sessionId,
        data: String(body.data || ""),
        loomInstanceId: runtimeEvidence.loomInstanceId,
        loomCursor: 64,
      });
      for (const client of clients) client.send(payload);
      return;
    }
    json(res, 404, { error: "not_found" });
  });
  const supervisorWs = new WebSocketServer({ noServer: true });
  supervisor.on("upgrade", (req, socket, head) => {
    supervisorWs.handleUpgrade(req, socket, head, (ws) => {
      clients.add(ws);
      ws.send(JSON.stringify({
        type: "ready",
        paneId: pane.paneId,
        sessionId: pane.sessionId,
        snapshot: "",
        supervisorRuntime: runtimeEvidence.supervisorRuntime,
        supervisorProtocol: runtimeEvidence.supervisorProtocol,
        loomInstanceId: runtimeEvidence.loomInstanceId,
      }));
      ws.on("close", () => clients.delete(ws));
    });
  });
  const supervisorPort = await listen(supervisor);

  const workbenchDir = await fs.mkdtemp(path.join(os.tmpdir(), "beagle-loom-runtime-test-"));
  const agentPort = await reservePort();
  const child = spawn(process.execPath, ["src/server.mjs"], {
    cwd: path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."),
    env: {
      ...process.env,
      BEAGLE_WORKSPACE_AGENT_HOST: "127.0.0.1",
      BEAGLE_WORKSPACE_AGENT_PORT: String(agentPort),
      BEAGLE_WORKSPACE_SLUG: "sounio-runtime-test",
      BEAGLE_WORKBENCH_DIR: workbenchDir,
      BEAGLE_WORKSPACE_ROOT: process.cwd(),
      BEAGLE_PTY_SUPERVISOR_URL: `http://127.0.0.1:${supervisorPort}`,
      BEAGLE_CORE_URL: "http://127.0.0.1:9",
      BEAGLE_OPERATOR_API_TOKEN: "disabled",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  t.after(async () => {
    child.kill("SIGTERM");
    await new Promise((resolve) => child.once("exit", resolve));
    for (const client of clients) client.close();
    await new Promise((resolve) => supervisor.close(resolve));
    await fs.rm(workbenchDir, { recursive: true, force: true });
  });

  const baseUrl = `http://127.0.0.1:${agentPort}`;
  const ready = await waitForReady(`${baseUrl}/v1/ready`, child);
  assert.equal(ready.authority.supervisor.runtime, runtimeEvidence.supervisorRuntime);
  assert.equal(ready.authority.supervisor.protocol, runtimeEvidence.supervisorProtocol);
  assert.equal(ready.authority.supervisor.runtimeAuthority, "loom");

  await fetch(`${baseUrl}/v1/sessions/session-runtime`).then((response) => {
    assert.equal(response.ok, true);
  });

  const observed = await new Promise((resolve, reject) => {
    const ws = new WebSocket(
      `ws://127.0.0.1:${agentPort}/v1/sessions/session-runtime/panes/pane-main/stream`,
    );
    const values = { ready: null, block: null };
    const timer = setTimeout(() => reject(new Error("Workspace Agent stream timed out")), 5000);
    ws.onmessage = (event) => {
      const message = JSON.parse(String(event.data));
      if (message.type === "ready") {
        values.ready = message.data;
        ws.send(JSON.stringify({ type: "input", data: "printf 'LOOM_RUNTIME_PROVENANCE_OK\\n'\n" }));
      }
      if (message.type === "block_started") values.block = message;
      if (message.type === "raw_output" && String(message.data).includes("LOOM_RUNTIME_PROVENANCE_OK")) {
        clearTimeout(timer);
        ws.close();
        resolve(values);
      }
    };
    ws.onerror = reject;
  });

  assert.equal(observed.ready.runtimeAuthority, "loom");
  assert.equal(observed.ready.supervisorRuntime, runtimeEvidence.supervisorRuntime);
  assert.equal(observed.ready.loomInstanceId, runtimeEvidence.loomInstanceId);
  assert.equal(observed.block.provenance.runtime_authority, "loom");
  assert.equal(observed.block.provenance.supervisor_runtime, runtimeEvidence.supervisorRuntime);
  assert.equal(observed.block.provenance.supervisor_protocol, runtimeEvidence.supervisorProtocol);
  assert.equal(observed.block.provenance.loom_instance_id, runtimeEvidence.loomInstanceId);
  assert.equal(observed.block.provenance.generation_fingerprint, runtimeEvidence.generationFingerprint);
  assert.equal(observed.block.provenance.journal_verified, true);
  assert.equal(observed.ready.lineageVerified, true);
  assert.equal(observed.ready.generationTransition, "pod-resurrected");
  assert.equal(observed.block.provenance.lineage_verified, true);
  assert.equal(observed.block.provenance.generation_lineage_head, "lineage-head-test");
  assert.equal(observed.block.provenance.predecessor_instance_id, "loom-instance-predecessor");

  await new Promise((resolve) => setTimeout(resolve, 50));
  const blocks = await fetch(`${baseUrl}/v1/sessions/session-runtime/blocks`).then((response) => response.json());
  assert.equal(blocks.blocks.length, 1);
  assert.equal(blocks.blocks[0].provenance.runtime_authority, "loom");
  assert.equal(blocks.blocks[0].provenance.semantic_journal_head, "semantic-head-test");
  assert.equal(blocks.blocks[0].provenance.guardian_journal_head, "guardian-head-test");
  assert.equal(blocks.blocks[0].provenance.kernel_recovery_count, 2);
  assert.equal(blocks.blocks[0].provenance.generation_transition_count, 3);
  assert.equal(blocks.blocks[0].provenance.pod_resurrection_count, 1);
  assert.equal(blocks.blocks[0].provenance.predecessor_semantic_journal_head, "predecessor-semantic-head-test");
  assert.equal(blocks.blocks[0].provenance.predecessor_guardian_journal_head, "predecessor-guardian-head-test");
});
