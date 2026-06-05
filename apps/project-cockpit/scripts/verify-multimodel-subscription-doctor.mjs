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
  const url = `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/doctor${
    publicBase ? `?publicBase=${encodeURIComponent(publicBase)}` : ""
  }`;
  const doctor = await fetchJson(url);
  assert(doctor.schema === "beagle.multimodel-subscription-client-doctor.v1", "unexpected subscription doctor schema", doctor);
  assert(doctor.ok === true, "subscription doctor infrastructure is not ok", doctor);
  assert(doctor.checks?.allClientsDeclared === true, "not every subscription client is declared", doctor);
  assert(doctor.checks?.allEndpointsDeclared === true, "not every subscription client has an MCP endpoint", doctor);
  assert(doctor.checks?.allHeadersDeclared === true, "not every subscription client has identity headers", doctor);
  assert(doctor.checks?.allKitsComplete === true, "MCP client kit is incomplete", doctor);
  assert(doctor.checks?.noFalseLiveClaims === true, "a subscription client was marked live without a recent heartbeat", doctor);
  for (const id of expected) {
    const client = (doctor.clients || []).find((item) => item.id === id);
    assert(client, `missing subscription doctor client ${id}`, doctor);
    assert(client.checks?.providerDeclared === true, `${id} provider missing`, client);
    assert(client.checks?.mcpEndpointDeclared === true, `${id} MCP endpoint missing`, client);
    assert(client.checks?.mcpHeadersDeclared === true, `${id} MCP headers missing`, client);
    assert(client.checks?.kitComplete === true, `${id} client kit missing`, client);
    assert(client.checks?.notFalselyLive === true, `${id} falsely marked live`, client);
  }
  if (doctor.publicEndpoint?.hostedClientReachable !== true) {
    assert(
      (doctor.hostedNetworkBlocked || []).includes("chatgpt-mcp")
        && (doctor.hostedNetworkBlocked || []).includes("grok-mcp"),
      "hosted ChatGPT/Grok network blockers were not reported",
      doctor
    );
  }
  console.log(JSON.stringify(doctor, null, 2));
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
