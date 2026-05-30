#!/usr/bin/env node

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

async function fetchJson(url, options = {}) {
  const res = await fetch(url, {
    method: options.method || "GET",
    headers: options.body ? { "content-type": "application/json" } : undefined,
    body: options.body ? JSON.stringify(options.body) : undefined
  });
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

try {
  const statusUrl = `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/public-endpoint`;
  const before = await fetchJson(statusUrl);
  const endpoint = before.publicEndpoint || {};
  assert(endpoint.url, "public endpoint status did not include a URL", before);
  assert(typeof endpoint.hostedClientReachable === "boolean", "public endpoint status did not include hosted reachability", before);

  const write = await fetchJson(statusUrl, {
    method: "POST",
    body: {
      publicBase: endpoint.url,
      trustedHosted: endpoint.trustedHosted === true,
      note: endpoint.config?.note || ""
    }
  });
  assert(write.ok === true, "public endpoint config write failed", write);
  assert(write.publicEndpoint?.url === endpoint.url, "public endpoint config write changed the URL unexpectedly", { before, write });
  assert(typeof write.publicEndpoint?.hostedClientReachable === "boolean", "public endpoint write lost hosted reachability", write);

  const after = await fetchJson(statusUrl);
  assert(after.publicEndpoint?.configured === true, "public endpoint config was not persisted", after);
  assert(after.publicEndpoint?.url === endpoint.url, "persisted public endpoint URL mismatch", { before, after });

  console.log(JSON.stringify({
    ok: true,
    schema: "beagle.multimodel-public-endpoint-config-verification.v1",
    projectSlug,
    publicEndpoint: after.publicEndpoint,
    hostedNetworkBlocked: after.hostedNetworkBlocked || [],
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-public-endpoint-config-read-write"
  }, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
