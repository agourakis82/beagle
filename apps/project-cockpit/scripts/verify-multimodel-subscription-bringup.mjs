#!/usr/bin/env node

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

async function fetchJson(url) {
  const res = await fetch(url);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const error = new Error(`${res.status} ${payload?.error || res.statusText}`);
    error.detail = payload;
    throw error;
  }
  return payload;
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const publicBase = cleanString(process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL || process.argv[3] || "").replace(/\/$/, "");
const expected = ["claude-desktop", "chatgpt-mcp", "grok-mcp"];

try {
  const url = `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/bringup${
    publicBase ? `?publicBase=${encodeURIComponent(publicBase)}` : ""
  }`;
  const bringup = await fetchJson(url);
  assert(bringup.schema === "beagle.multimodel-subscription-client-bringup.v1", "unexpected subscription bringup schema", bringup);
  assert(bringup.ok === true, "subscription bringup infrastructure is not ok", bringup);
  assert(bringup.auth?.required === true, "bringup did not declare MCP auth requirement", bringup);
  assert(bringup.auth?.tokenConfigured === true, "bringup has no configured Workbench Context token", bringup);
  assert(bringup.connectionPacket?.exists === true, "real hosted subscription connection packet is missing", bringup.connectionPacket);
  assert(bringup.connectionPacket?.redactedExists === true, "redacted hosted subscription connection packet is missing", bringup.connectionPacket);
  for (const id of expected) {
    const client = (bringup.clients || []).find((item) => item.id === id);
    assert(client, `missing bringup client ${id}`, bringup);
    assert(client.url?.includes(`/api/workbench/${projectSlug}/context/mcp`), `${id} URL missing project MCP endpoint`, client);
    assert(client.url?.includes(`client_id=${encodeURIComponent(client.targetClient)}`), `${id} URL missing client identity`, client);
    assert(client.headers?.["x-beagle-client-id"] === client.targetClient, `${id} headers missing client identity`, client);
    assert(cleanString(client.headers?.authorization) === "Bearer <workbench-context-token>", `${id} authorization header was not redacted`, client);
    assert(client.connectionPacket?.exists === true, `${id} connection packet is missing`, client);
    assert(client.connectionPacket?.redactedExists === true, `${id} redacted connection packet is missing`, client);
    assert(client.liveProof && !client.liveProof.includes("fixture"), `${id} live proof is missing or fixture-tainted`, client);
    assert(client.verifyCommand?.includes("verify:multimodel:subscription-live"), `${id} missing live verification command`, client);
    assert(client.replyVerifyCommand?.includes("verify:multimodel:subscription-reply-live"), `${id} missing reply-live verification command`, client);
    assert(client.replyGate?.verifyCommand?.includes("verify:multimodel:subscription-reply-live"), `${id} missing reply gate verification command`, client);
    assert(client.replyGate?.proofRequired?.includes("Manual paste"), `${id} reply gate does not reject manual evidence`, client.replyGate);
    assert(client.replyGate?.proofRequired?.includes("direct endpoint"), `${id} reply gate does not reject direct endpoint evidence`, client.replyGate);
    assert(client.replyGate?.rejectedEvidence?.includes("developer-mcp-paste-ui"), `${id} reply gate does not reject developer paste bridge evidence`, client.replyGate);
    assert(client.replyGate?.latestProof && typeof client.replyGate.latestProof === "object", `${id} missing latest real reply proof state`, client.replyGate);
    assert(client.replyGate.latestProof.ok !== true || client.replyGate.latestProof.truthMode === "observed-real-subscription-client-reply", `${id} accepted non-real subscription reply proof`, client.replyGate.latestProof);
    assert(client.replyGate.latestProof.ok !== true || client.replyGate.latestProof.replyTruthMode === "observed-client-reply", `${id} accepted non-client Workbench Context reply proof`, client.replyGate.latestProof);
  }
  console.log(JSON.stringify(bringup, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    publicBase,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
