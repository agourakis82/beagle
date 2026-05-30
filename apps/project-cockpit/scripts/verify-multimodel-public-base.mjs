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
const publicBaseInput = cleanString(process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL || process.argv[3] || "").replace(/\/$/, "");
const requireHosted = /^(1|true|yes)$/i.test(cleanString(process.env.REQUIRE_HOSTED_REACHABLE || process.argv[4] || ""));

try {
  const doctorUrl = `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/doctor${
    publicBaseInput ? `?publicBase=${encodeURIComponent(publicBaseInput)}` : ""
  }`;
  const doctor = await fetchJson(doctorUrl);
  const endpoint = doctor.publicEndpoint || {};
  const publicBase = publicBaseInput || endpoint.url || apiBase;
  assert(endpoint.url, "public endpoint was not reported", doctor);
  assert(endpoint.loopback !== true || requireHosted === false, "loopback endpoint cannot satisfy hosted clients", doctor);
  assert(endpoint.privateLan !== true || requireHosted === false, "private LAN endpoint cannot satisfy hosted clients", doctor);
  assert(endpoint.tailnet !== true || endpoint.trustedHosted === true || requireHosted === false, "tailnet endpoint needs Funnel/public trust for hosted clients", doctor);
  if (requireHosted) {
    assert(endpoint.hostedClientReachable === true, "public base is not hosted-client reachable", doctor);
    assert(doctor.checks?.allNetworkReady === true, "subscription HTTP clients are still network-blocked", doctor);
  }
  console.log(JSON.stringify({
    ok: true,
    schema: "beagle.multimodel-public-base-verification.v1",
    projectSlug,
    publicBase,
    requireHosted,
    publicEndpoint: endpoint,
    hostedNetworkBlocked: doctor.hostedNetworkBlocked || [],
    waitingClients: doctor.waitingClients || [],
    generatedAt: new Date().toISOString(),
    truthMode: "observed-public-base-doctor"
  }, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    publicBase: publicBaseInput || "",
    requireHosted,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
