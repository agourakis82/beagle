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
  return { res, payload };
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");

try {
  const url = `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/public-endpoint/tailscale-funnel`;
  const dryRun = await fetchJson(url, {
    method: "POST",
    body: { dryRun: true }
  });
  assert(dryRun.res.ok, "dry-run funnel guard did not return ok", dryRun.payload);
  const plan = dryRun.payload || {};
  assert(plan.truthMode === "observed-tailscale-funnel-activation-plan", "unexpected dry-run truth mode", plan);
  assert(plan.mutates === false, "dry-run must not mutate", plan);
  assert(Array.isArray(plan.command) && plan.command.includes("funnel"), "funnel command was not reported", plan);
  assert(typeof plan.safeToApply === "boolean", "safeToApply was not reported", plan);
  assert(Array.isArray(plan.rootConflictRoutes), "root conflict routes were not reported", plan);

  let applyProbeStatus = "not-run";
  if (plan.safeToApply === false && process.env.VERIFY_UNSAFE_FUNNEL_REFUSAL === "1") {
    const applyAttempt = await fetchJson(url, {
      method: "POST",
      body: { apply: true }
    });
    applyProbeStatus = applyAttempt.res.status;
    assert(applyAttempt.res.status === 409, "unsafe apply should be refused with 409", applyAttempt.payload);
    assert(applyAttempt.payload?.mutates === false, "refused apply must not mutate", applyAttempt.payload);
    assert(applyAttempt.payload?.truthMode === "refused-tailscale-funnel-activation", "unexpected refusal truth mode", applyAttempt.payload);
  }

  console.log(JSON.stringify({
    ok: true,
    schema: "beagle.multimodel-tailscale-funnel-guard-verification.v1",
    projectSlug,
    safeToApply: plan.safeToApply,
    rootConflictCount: plan.rootConflictRoutes.length,
    publicBase: plan.publicBase,
    applyProbeStatus,
    verifiedAt: new Date().toISOString(),
    mutates: false,
    truthMode: "observed-tailscale-funnel-guard"
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
