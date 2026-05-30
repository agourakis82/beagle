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
const pathPrefix = cleanString(process.env.PROJECT_COCKPIT_MCP_PUBLIC_PATH || process.argv[3] || "/api/workbench");

try {
  const url = `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/public-endpoint/tailscale-funnel-path`;
  const dryRun = await fetchJson(url, {
    method: "POST",
    body: { dryRun: true, pathPrefix }
  });
  assert(dryRun.res.ok, "dry-run path Funnel guard did not return ok", dryRun.payload);
  const plan = dryRun.payload || {};
  assert(plan.truthMode === "observed-tailscale-funnel-path-activation-plan", "unexpected dry-run truth mode", plan);
  assert(plan.mutates === false, "dry-run must not mutate", plan);
  assert(plan.pathPrefix === pathPrefix, "path prefix mismatch", plan);
  assert(Array.isArray(plan.command) && plan.command.includes("--set-path"), "path Funnel command was not reported", plan);
  assert(plan.command.includes(pathPrefix), "path Funnel command does not include path prefix", plan);
  assert(typeof plan.safeToApply === "boolean", "safeToApply was not reported", plan);
  assert(Array.isArray(plan.pathConflictRoutes), "path conflict routes were not reported", plan);
  assert(Array.isArray(plan.rootRoutes), "root routes were not reported", plan);

  let applyProbeStatus = "not-run";
  if (process.env.VERIFY_FUNNEL_PATH_REFUSAL === "1") {
    const applyAttempt = await fetchJson(url, {
      method: "POST",
      body: { apply: true, pathPrefix }
    });
    applyProbeStatus = applyAttempt.res.status;
    assert([403, 409].includes(applyAttempt.res.status), "apply without mutation gate should be refused", applyAttempt.payload);
    assert(applyAttempt.payload?.mutates === false, "refused apply must not mutate", applyAttempt.payload);
    assert(applyAttempt.payload?.truthMode === "refused-tailscale-funnel-path-activation", "unexpected refusal truth mode", applyAttempt.payload);
  }

  console.log(JSON.stringify({
    ok: true,
    schema: "beagle.multimodel-tailscale-funnel-path-guard-verification.v1",
    projectSlug,
    pathPrefix,
    safeToApply: plan.safeToApply,
    applyAllowed: plan.applyAllowed,
    alreadyActive: plan.alreadyActive,
    pathConflictCount: plan.pathConflictRoutes.length,
    rootRouteCount: plan.rootRoutes.length,
    publicBase: plan.publicBase,
    publicMcpBase: plan.publicMcpBase,
    applyProbeStatus,
    verifiedAt: new Date().toISOString(),
    mutates: false,
    truthMode: "observed-tailscale-funnel-path-guard"
  }, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    pathPrefix,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
