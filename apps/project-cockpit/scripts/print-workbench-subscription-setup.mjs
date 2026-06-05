#!/usr/bin/env node

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function argValue(name) {
  const prefix = `--${name}=`;
  const match = process.argv.find((arg) => arg.startsWith(prefix));
  return match ? match.slice(prefix.length) : "";
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

const positionals = process.argv.slice(2).filter((arg) => !arg.startsWith("--"));
const projectSlug = cleanString(argValue("project") || process.env.PROJECT_SLUG || positionals[0], "darwin-mfc");
const clientInput = cleanString(argValue("client") || process.env.CLIENT || process.env.SUBSCRIPTION_CLIENT || positionals[1], "all");
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
const publicBase = cleanString(argValue("public-base") || process.env.PROJECT_COCKPIT_PUBLIC_BASE_URL || "");
const jsonMode = process.argv.includes("--json");
const clients = clientInput === "all"
  ? ["claude-desktop", "chatgpt", "grok"]
  : clientInput.split(",").map((item) => cleanString(item)).filter(Boolean);

try {
  const suffix = publicBase ? `?publicBase=${encodeURIComponent(publicBase)}` : "";
  const plans = [];
  for (const client of clients) {
    const plan = await fetchJson(
      `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/subscription-clients/${encodeURIComponent(client)}/connect${suffix}`
    );
    plans.push(plan);
  }

  if (jsonMode) {
    console.log(JSON.stringify({
      ok: true,
      schema: "beagle.workbench-subscription-setup-print.v1",
      projectSlug,
      clients: plans.map((plan) => ({
        id: plan.client?.id || "",
        targetClient: plan.client?.targetClient || "",
        status: plan.client?.status || "",
        realConnectionObserved: plan.client?.realConnectionObserved === true,
        setupText: plan.connect?.setupText || ""
      })),
      generatedAt: new Date().toISOString(),
      truthMode: "observed-subscription-connect-plan-setup-text"
    }, null, 2));
  } else {
    console.log(plans.map((plan) => plan.connect?.setupText || "").filter(Boolean).join("\n\n---\n\n"));
  }
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    client: clientInput,
    error: error.message,
    detail: error.detail || null,
    truthMode: "subscription-setup-print-failed"
  }, null, 2));
  process.exit(1);
}
