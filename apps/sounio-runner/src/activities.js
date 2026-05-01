const CORE_URL = (process.env.BEAGLE_CORE_URL || "http://beagle-core.beagle.svc.cluster.local:8080").replace(/\/$/, "");

async function coreRequest(method, path, body) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Number(process.env.SOUNIO_ACTIVITY_TIMEOUT_MS || "30000"));
  try {
    const response = await fetch(`${CORE_URL}${path}`, {
      method,
      headers: { "content-type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal,
    });
    const text = await response.text();
    const payload = text ? JSON.parse(text) : {};
    if (!response.ok) {
      const message = payload?.error || payload?.message || text || response.statusText;
      throw new Error(`core ${method} ${path} failed: ${response.status} ${message}`);
    }
    return payload;
  } finally {
    clearTimeout(timeout);
  }
}

async function compileContext(input) {
  return coreRequest("POST", "/api/exocortex/v1/context/compile", {
    query: input.query,
    scope: "sounio-paperrun",
    surface: "sounio-runner",
    task: input.task || "self-writing-systems-paper",
    max_items: 8,
    token_budget: 16000,
    agent: "sounio-runner",
    session_id: input.paper_run_id,
  });
}

async function loadPaperRun(input) {
  return coreRequest("GET", `/api/exocortex/v1/sounio/paperruns/${encodeURIComponent(input.paper_run_id)}`);
}

async function loadArtifacts(input) {
  return coreRequest("GET", `/api/exocortex/v1/sounio/paperruns/${encodeURIComponent(input.paper_run_id)}/artifacts`);
}

async function recordEffectiveness(input) {
  return coreRequest("POST", "/api/exocortex/v1/memory/effectiveness/events", {
    context_pack_id: input.context_pack_id,
    query: input.query,
    surface: "sounio-runner",
    principal: "sounio-runner",
    session_id: input.paper_run_id,
    strategy_used: "sounio_paperrun_temporal",
    success: Boolean(input.success),
    outcome: input.outcome || "paperrun_step_observed",
    metadata: {
      paper_run_id: input.paper_run_id,
      temporal_workflow_id: input.temporal_workflow_id,
      step_id: input.step_id,
    },
  });
}

module.exports = {
  compileContext,
  loadPaperRun,
  loadArtifacts,
  recordEffectiveness,
};
