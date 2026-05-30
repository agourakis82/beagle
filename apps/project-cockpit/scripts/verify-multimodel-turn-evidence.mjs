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

function providersCoverExpected(providers = [], expectedProviders = []) {
  if (!expectedProviders.length) return false;
  const providerSet = new Set((providers || []).map((provider) => cleanString(provider)));
  return expectedProviders.every((provider) => providerSet.has(provider));
}

async function latestVerifiedTurnId({ apiBase, projectSlug, expectedProviders = [] }) {
  const contextPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/verify/ui-context?limit=1`).catch(() => null);
  const contextLatest = contextPayload?.latest || null;
  if (
    contextLatest?.secondTurnId &&
    providersCoverExpected(contextLatest.providers || [], expectedProviders)
  ) {
    return cleanString(contextLatest.secondTurnId);
  }
  const payload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/verify/ui-send?limit=1`);
  return cleanString(payload.latest?.turnId);
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = (process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const requestedTurnId = cleanString(process.env.TURN_ID || process.argv[3]);
const expectedProviders = (process.env.PROVIDERS || process.argv[4] || "")
  .split(",")
  .map((item) => item.trim())
  .filter(Boolean);

try {
  const turnId = requestedTurnId || await latestVerifiedTurnId({ apiBase, projectSlug, expectedProviders });
  assert(turnId, "no turn id supplied and no latest UI-send verification was found");
  const evidence = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns/${encodeURIComponent(turnId)}/evidence`);
  assert(evidence.schema === "beagle.multimodel-turn-evidence.v1", "unexpected evidence schema", evidence);
  assert(evidence.ok === true, "turn evidence is not ok", evidence);
  assert(evidence.checks?.turnStarted === true, "turn evidence is missing turn_started", evidence);
  assert(evidence.checks?.turnDone === true, "turn evidence is missing turn_done", evidence);
  assert(evidence.checks?.providersPresent === true, "turn evidence has no providers", evidence);
  assert(evidence.checks?.allProvidersStarted === true, "not every provider started", evidence);
  assert(evidence.checks?.allProvidersHaveTransport === true, "not every provider has transport evidence", evidence);
  assert(evidence.checks?.allProvidersHaveText === true, "not every provider has response text", evidence);
  assert(evidence.checks?.allProvidersHaveDeltaOrDone === true, "not every provider has delta/done evidence", evidence);
  assert(evidence.checks?.activeTurnsClear === true, "active turns are not clear", evidence);
  assert(Number(evidence.traceCount || 0) > 0, "turn evidence has no trace", evidence);
  for (const provider of expectedProviders) {
    const item = (evidence.providers || []).find((entry) => entry.provider === provider);
    assert(item, `missing evidence for ${provider}`, evidence);
    assert(item.status === "done", `${provider} is not done`, item);
    assert(item.hasStarted === true, `${provider} missing started evidence`, item);
    assert(item.hasTransport === true, `${provider} missing transport evidence`, item);
    assert(item.hasText === true, `${provider} missing text evidence`, item);
    assert(item.hasDeltaOrDone === true, `${provider} missing delta/done evidence`, item);
  }
  console.log(JSON.stringify(evidence, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    turnId: requestedTurnId,
    expectedProviders,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
