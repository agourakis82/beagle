const DEFAULT_ALWAYS_ON_ENDPOINT =
  process.env.PROJECT_COCKPIT_ALWAYS_ON_MODEL_ENDPOINT ||
  process.env.PROJECT_COCKPIT_SSM_PROBE_ENDPOINT ||
  "http://ssm-probe-serving.beagle.svc.cluster.local:8002";

const DEFAULT_DYNAMO_ENDPOINT =
  process.env.PROJECT_COCKPIT_DYNAMO_INTERNAL_URL ||
  process.env.PROJECT_COCKPIT_DYNAMO_ENDPOINT ||
  "http://dynamo-control-plane.beagle.svc.cluster.local:8000";

const PROBE_TIMEOUT_MS = Number(
  process.env.PROJECT_COCKPIT_MODEL_REGISTRY_PROBE_TIMEOUT_MS || 1200
);

export const MODEL_LANES = [
  {
    id: "always-on",
    title: "Always-on",
    role: "cheap live agent helper",
    selectedModel: "LiquidAI/LFM2.5-1.2B-Instruct",
    servedModel: "lfm2.5-1.2b-instruct",
    endpoint: DEFAULT_ALWAYS_ON_ENDPOINT,
    endpointKind: "openai-compatible",
    service: "ssm-probe-serving",
    namespace: "beagle",
    gpu: {
      node: "5860-proxmox",
      accelerator: "RTX 4000 Ada",
      vramMiB: {
        idle: 2867,
        postRequest: 2929,
        highWater: 3225
      }
    },
    lastProbe: {
      runId: "ssm-probe-20260522T191525Z",
      summaryPath: "/tmp/sounio-ssm-probe/ssm-probe-20260522T191525Z.summary.json",
      exact: true,
      json: true,
      agentRisk: true,
      longContext: true,
      tokensPerSecond: 72.2
    },
    verdict: "approved-live-light",
    promotion: "default cluster always-on lane until a safer/faster challenger wins",
    intents: ["default", "ideas", "summary", "mobile", "agent-draft"]
  },
  {
    id: "helper",
    title: "Helper",
    role: "cheap summaries, scratchpad text, router drafts",
    selectedModel: "HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF",
    servedModel: "smollm2-1.7b-instruct-q4-k-m",
    endpoint: "",
    endpointKind: "llama.cpp-openai-compatible",
    service: "temporary probe only",
    namespace: "beagle",
    gpu: {
      node: "r770-proxmox",
      accelerator: "NVIDIA L4",
      vramMiB: {
        startup: 2099
      }
    },
    lastProbe: {
      runId: "smollm2-17b-q4-20260523T000335Z",
      summaryPath: "/tmp/sounio-ssm-probe/smollm2-17b-q4-20260523T000335Z.summary.json",
      operatorSummaryPath:
        "/tmp/sounio-ssm-probe/smollm2-17b-q4-20260523T000335Z-operator-safe.summary.json",
      exact: true,
      json: true,
      agentRisk: false,
      longContext: true,
      safeTriage: false,
      tokensPerSecond: 83.9
    },
    verdict: "helper-only-not-operator",
    promotion: "standby candidate; use only behind fallback/policy",
    intents: ["ideas", "summary", "scratchpad", "router"]
  },
  {
    id: "audit",
    title: "Audit",
    role: "open-science comparison and second opinion",
    selectedModel: "bartowski/OLMo-2-1124-7B-Instruct-GGUF",
    servedModel: "olmo2-1124-7b-instruct-q4-k-m",
    endpoint: "",
    endpointKind: "llama.cpp-openai-compatible",
    service: "temporary probe only",
    namespace: "beagle",
    gpu: {
      node: "r770-proxmox",
      accelerator: "NVIDIA L4",
      vramMiB: {
        startup: 6527
      }
    },
    lastProbe: {
      runId: "olmo2-7b-q4-20260523T000605Z",
      summaryPath: "/tmp/sounio-ssm-probe/olmo2-7b-q4-20260523T000605Z.summary.json",
      operatorSummaryPath:
        "/tmp/sounio-ssm-probe/olmo2-7b-q4-20260523T000605Z-operator-safe.summary.json",
      exact: true,
      json: false,
      agentRisk: false,
      longContext: true,
      safeTriage: true,
      tokensPerSecond: 34.5
    },
    verdict: "audit-only-not-operator",
    promotion: "good transparent baseline; not JSON/tool disciplined enough",
    intents: ["audit", "comparison", "review"]
  },
  {
    id: "research",
    title: "Research",
    role: "long-context and exotic architecture experiments",
    selectedModel: "Jamba Mini 1.7 IQ2_M / Kimi Linear Q3",
    servedModel: "research-controlled",
    endpoint: "",
    endpointKind: "temporary research runtime",
    service: "temporary probe only",
    namespace: "beagle",
    gpu: {
      node: "r770-proxmox",
      accelerator: "NVIDIA L4",
      vramMiB: {
        jambaStartup: 15883,
        kimiStartup: 21169
      }
    },
    lastProbe: {
      runId: "jamba17-mini-iq2-20260523T010102Z",
      summaryPath: "/tmp/sounio-ssm-probe/jamba17-mini-iq2-20260523T010102Z.summary.json",
      operatorSummaryPath:
        "/tmp/sounio-ssm-probe/jamba17-mini-iq2-20260523T010102Z-operator-safe.summary.json",
      exact: false,
      json: true,
      agentRisk: true,
      longContext: true,
      safeTriage: false,
      tokensPerSecond: 24.3
    },
    alternatives: [
      {
        model: "moonshotai/Kimi-Linear-48B-A3B-Instruct Q3_K_S",
        runId: "kimi-linear-q3-llamacpp-20260522T230132Z",
        verdict: "strong long-context research lane; unsafe raw operator"
      }
    ],
    verdict: "research-only-never-operator-raw",
    promotion: "controlled experiments only; use grammar/schema before operator retest",
    intents: ["long-context", "architecture-research", "kimi", "jamba"]
  },
  {
    id: "domain",
    title: "Domain",
    role: "biomedical/domain-only assistant experiments",
    selectedModel: "Meditron 7B / OpenBioLLM 8B candidates",
    servedModel: "not-yet-probed",
    endpoint: "",
    endpointKind: "not-admitted",
    service: "none",
    namespace: "beagle",
    gpu: {
      node: "unassigned",
      accelerator: "unassigned",
      vramMiB: {}
    },
    lastProbe: {
      runId: "",
      summaryPath: "",
      exact: false,
      json: false,
      agentRisk: false,
      longContext: false
    },
    verdict: "not-tested-domain-only",
    promotion: "do not route until the domain matrix exists",
    intents: ["biomedical", "domain"]
  },
  {
    id: "operator",
    title: "Operator",
    role: "cluster-action reasoning behind policy wrapper",
    selectedModel: "none approved for raw operator use",
    servedModel: "policy-wrapper-required",
    endpoint: "",
    endpointKind: "policy-gate",
    service: "cockpit-model-policy-v1",
    namespace: "beagle",
    gpu: {
      node: "n/a",
      accelerator: "n/a",
      vramMiB: {}
    },
    lastProbe: {
      runId: "all-current-candidates",
      summaryPath: "/home/devsounio/beagle/k8s/project-cockpit/CLUSTER_MODEL_PROBE_PLAN.md",
      exact: false,
      json: false,
      agentRisk: false,
      longContext: false,
      safeTriage: false
    },
    verdict: "blocked-without-schema-and-policy",
    promotion: "no model may propose cluster mutation directly",
    intents: ["operator", "cluster-action", "rbac", "mutation"]
  }
];

const MUTATION_PATTERNS = [
  /\bkubectl\s+(apply|delete|patch|create|replace|scale|cordon|uncordon|drain|label|annotate|rollout\s+restart)\b/i,
  /\bhelm\s+(install|upgrade|uninstall|rollback)\b/i,
  /\b(clusterrole|clusterrolebinding|rolebinding)\b/i,
  /\b(clusterrole\s*=\s*edit|cluster-admin|system:masters)\b/i,
  /\b(grant|bind|escalat(e|ion)|privileg(e|ed)|admin)\b/i,
  /\b(apt|apt-get)\s+(upgrade|dist-upgrade|full-upgrade|install|remove|purge)\b/i,
  /\b(reboot|shutdown|poweroff|systemctl\s+(restart|stop|disable))\b/i,
  /\b(pvecm|qm|pct)\s+(destroy|delete|stop|shutdown|migrate|set)\b/i
];

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function cleanString(value) {
  if (typeof value === "string") {
    return value.trim();
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return "";
}

async function fetchJson(url, timeoutMs = PROBE_TIMEOUT_MS) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    const text = await res.text();
    const payload = text ? JSON.parse(text) : {};
    return res.ok
      ? { ok: true, status: res.status, payload }
      : { ok: false, status: res.status, payload };
  } catch (error) {
    return { ok: false, status: 0, error: error.message };
  } finally {
    clearTimeout(timer);
  }
}

function normalizeOpenAiModels(payload) {
  const data = Array.isArray(payload?.data)
    ? payload.data
    : Array.isArray(payload?.models)
      ? payload.models
      : [];
  return data
    .map((entry) => {
      if (typeof entry === "string") {
        return { id: entry };
      }
      return {
        id: cleanString(entry?.id || entry?.name || entry?.model),
        ownedBy: cleanString(entry?.owned_by || entry?.ownedBy || entry?.provider)
      };
    })
    .filter((entry) => entry.id);
}

async function observeLane(lane) {
  const observed = clone(lane);
  observed.runtime = {
    configured: Boolean(lane.endpoint),
    reachable: false,
    status: lane.endpoint ? "unreachable" : "standby",
    endpoint: lane.endpoint || "",
    lastError: "",
    observedAt: new Date().toISOString(),
    models: []
  };

  if (!lane.endpoint) {
    return observed;
  }

  const probe = await fetchJson(`${lane.endpoint.replace(/\/+$/, "")}/v1/models`);
  observed.runtime.reachable = Boolean(probe.ok);
  observed.runtime.status = probe.ok ? "ready" : "unreachable";
  observed.runtime.lastError = probe.ok
    ? ""
    : cleanString(probe.error || probe.payload?.error || `HTTP ${probe.status || "0"}`);
  observed.runtime.models = probe.ok ? normalizeOpenAiModels(probe.payload) : [];
  return observed;
}

function includesAny(text, patterns) {
  return patterns.some((pattern) => pattern.test(text));
}

function summarizeReadonlyText(text) {
  const source = cleanString(text);
  const safeLines = source
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => !detectClusterMutationRisk(line).risky);
  const summary = safeLines.join(" ").replace(/\s+/g, " ").trim();
  return summary.slice(0, 700);
}

function operatorDecisionText({ decision, reason, summary = "", blockedTerms = [] }) {
  return JSON.stringify({
    decision,
    reason,
    summary,
    allowed_actions: decision === "readonly" ? ["read-only observation", "ask human before mutation"] : [],
    requires_human: decision !== "readonly",
    commands: [],
    blocked_terms: blockedTerms.slice(0, 12)
  });
}

export function detectClusterMutationRisk(text) {
  const source = cleanString(text);
  const blockedTerms = MUTATION_PATTERNS
    .filter((pattern) => pattern.test(source))
    .map((pattern) => pattern.source);
  return {
    risky: blockedTerms.length > 0,
    blockedTerms
  };
}

export function enforceOperatorPolicy(text, context = {}) {
  const responseText = cleanString(text);
  const risk = detectClusterMutationRisk(responseText);
  const route = cleanString(context.route || context.lane || context.intent);
  const requiresPolicy =
    context.requiresPolicy === true ||
    route === "operator" ||
    cleanString(context.intent) === "operator";
  if (!requiresPolicy && !risk.risky) {
    return {
      decision: "allow",
      wrapper: "cockpit-model-policy-v1",
      route,
      blockedTerms: [],
      text: responseText
    };
  }
  if (risk.risky) {
    const reason =
      "Model output contained cluster mutation, RBAC escalation, package-management, or node-control language.";
    return {
      decision: "blocked",
      wrapper: "cockpit-model-policy-v1",
      route,
      blockedTerms: risk.blockedTerms,
      reason,
      text: operatorDecisionText({
        decision: "blocked",
        reason,
        blockedTerms: risk.blockedTerms
      })
    };
  }
  const reason =
    "Operator route constrained to read-only JSON; mutation requires a human-reviewed Cockpit operator packet.";
  return {
    decision: "readonly",
    wrapper: "cockpit-model-policy-v1",
    route,
    blockedTerms: [],
    reason,
    text: operatorDecisionText({
      decision: "readonly",
      reason,
      summary: summarizeReadonlyText(responseText)
    })
  };
}

export function selectModelRoute(input = {}) {
  const prompt = cleanString(input.prompt);
  const system = cleanString(input.system);
  const requestedIntent = cleanString(input.intent || input.route || "");
  const text = `${requestedIntent}\n${system}\n${prompt}`.toLowerCase();
  const operatorIntent =
    includesAny(text, [
      /\b(operator|cluster|kubernetes|k8s|rbac|serviceaccount|namespace|job|slurm|node|orangefs)\b/i,
      /\b(apply|patch|delete|create|drain|uncordon|reboot|upgrade|grant|forbidden|permission)\b/i
    ]) || detectClusterMutationRisk(text).risky;
  const longContextIntent = includesAny(text, [
    /\b(long[- ]?context|jamba|kimi|linear attention|mamba|ssm|research lane)\b/i
  ]);
  const auditIntent = includesAny(text, [
    /\b(audit|auditoria|compare|comparison|review|verdict|second opinion|forensic)\b/i
  ]);
  const helperIntent = includesAny(text, [
    /\b(idea|ideia|summary|resumo|summarize|scratchpad|router|draft|brainstorm)\b/i
  ]);

  let requestedLane = "always-on";
  let intent = requestedIntent || "default";
  if (operatorIntent) {
    requestedLane = "operator";
    intent = requestedIntent || "operator";
  } else if (longContextIntent) {
    requestedLane = "research";
    intent = requestedIntent || "long-context";
  } else if (auditIntent) {
    requestedLane = "audit";
    intent = requestedIntent || "audit";
  } else if (helperIntent) {
    requestedLane = "helper";
    intent = requestedIntent || "helper";
  }

  const requested = MODEL_LANES.find((lane) => lane.id === requestedLane) || MODEL_LANES[0];
  const alwaysOn = MODEL_LANES.find((lane) => lane.id === "always-on") || MODEL_LANES[0];
  const execution = requested.endpoint ? requested : alwaysOn;
  return {
    intent,
    requestedLane: requested.id,
    executionLane: execution.id,
    model: execution.servedModel || execution.selectedModel,
    displayModel: execution.selectedModel,
    endpoint: execution.endpoint || DEFAULT_DYNAMO_ENDPOINT,
    fallbackEndpoint: DEFAULT_DYNAMO_ENDPOINT,
    requiresPolicy: requested.id === "operator" || operatorIntent,
    reason:
      requested.id === execution.id
        ? `direct ${requested.id} lane`
        : `${requested.id} is standby; executing through ${execution.id}`
  };
}

export async function buildModelRegistry({ projectSlug = "sounio", runtime = null } = {}) {
  const lanes = await Promise.all(MODEL_LANES.map((lane) => observeLane(lane)));
  const alwaysOn = lanes.find((lane) => lane.id === "always-on");
  const helper = lanes.find((lane) => lane.id === "helper");
  const audit = lanes.find((lane) => lane.id === "audit");
  const research = lanes.find((lane) => lane.id === "research");
  const operator = lanes.find((lane) => lane.id === "operator");

  return {
    projectSlug,
    generatedAt: new Date().toISOString(),
    truthMode: lanes.some((lane) => lane.runtime?.reachable) ? "observed" : "declared",
    docsPath: "/home/devsounio/beagle/k8s/project-cockpit/CLUSTER_MODEL_PROBE_PLAN.md",
    runtimeStatus: runtime?.status || "",
    policy: {
      wrapper: "cockpit-model-policy-v1",
      operatorMutation: "blocked-unless-human-reviewed",
      operatorModel: "none-approved-for-raw-cluster-mutation",
      requiredBeforePromotion: [
        "operator-safe matrix",
        "schema or grammar constrained decoding",
        "action ledger review",
        "explicit human confirmation for mutations"
      ]
    },
    routing: [
      { intent: "ideas/resumos curtos", lane: helper?.id, fallback: alwaysOn?.id },
      { intent: "agente/operador", lane: operator?.id, fallback: alwaysOn?.id, policy: "required" },
      { intent: "auditoria/comparacao", lane: audit?.id, fallback: alwaysOn?.id },
      { intent: "long-context experimental", lane: research?.id, fallback: alwaysOn?.id },
      { intent: "default/mobile", lane: alwaysOn?.id, fallback: "dynamo-if-available" }
    ],
    selected: {
      alwaysOn: alwaysOn?.selectedModel || "",
      helper: helper?.selectedModel || "",
      audit: audit?.selectedModel || "",
      research: research?.selectedModel || "",
      operator: operator?.selectedModel || ""
    },
    lanes
  };
}
