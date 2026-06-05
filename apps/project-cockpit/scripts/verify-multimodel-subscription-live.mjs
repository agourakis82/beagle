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
const clientFilter = cleanString(process.env.CLIENT || process.env.CLIENT_ID || process.argv[3] || "");
const timeoutMs = Number(process.env.TIMEOUT_MS || process.argv[4] || 0);
const deadline = timeoutMs > 0 ? Date.now() + timeoutMs : Date.now();

async function readBringup() {
  return await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/bringup`);
}

try {
  let bringup = await readBringup();
  while (timeoutMs > 0 && Date.now() < deadline) {
    const clients = bringup.clients || [];
    const selected = clientFilter
      ? clients.filter((client) => [client.id, client.targetClient].includes(clientFilter))
      : clients;
    if (selected.length && selected.every((client) => client.realConnectionObserved === true)) break;
    await new Promise((resolve) => setTimeout(resolve, 1000));
    bringup = await readBringup();
  }
  const clients = bringup.clients || [];
  const selected = clientFilter
    ? clients.filter((client) => [client.id, client.targetClient].includes(clientFilter))
    : clients;
  assert(selected.length > 0, "requested subscription client was not declared", { clientFilter, bringup });
  assert(selected.every((client) => client.realConnectionObserved === true), "subscription client is not live from a real fresh heartbeat", {
    clientFilter,
    selected,
    waitingClients: bringup.waitingClients || [],
    nextAction: bringup.nextAction
  });
  console.log(JSON.stringify({
    ok: true,
    schema: "beagle.multimodel-subscription-live-verification.v1",
    projectSlug,
    clients: selected.map((client) => ({
      id: client.id,
      targetClient: client.targetClient,
      clientLatestAt: client.clientLatestAt,
      clientAgeMs: client.clientAgeMs,
      liveProof: client.liveProof
    })),
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-real-subscription-client-live"
  }, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    clientFilter,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
