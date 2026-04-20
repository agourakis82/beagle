// auth-bridge.mjs
//
// /api/auth/beagle-token — returns the beagle-server consumer token to the
// caller, identified by Tailnet headers (set by Tailscale operator sidecar).
//
// iOS app calls this once on launch (cached in Keychain), uses returned token
// in subsequent calls to `beagle-core.tail21cbc4.ts.net` with:
//   X-Beagle-Consumer: beagle-operator
//   Authorization: Bearer <token>
//
// Source of truth for the token: cluster Secret `beagle-core-secrets`,
// which we read via kubectl on demand (cached 5min).

import { spawn } from "node:child_process";

const NAMESPACE = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl";
const SECRET_NAME = process.env.PROJECT_COCKPIT_BEAGLE_SECRET || "beagle-core-secrets";
const DARWIN_HPC_ADAPTER_NAMESPACE =
  process.env.PROJECT_COCKPIT_DARWIN_HPC_ADAPTER_NAMESPACE || "darwin-platform";
const DARWIN_HPC_ADAPTER_SECRET =
  process.env.PROJECT_COCKPIT_DARWIN_HPC_ADAPTER_SECRET || "darwin-hpc-gateway-adapter";
const DARWIN_HPC_ADAPTER_URL =
  process.env.PROJECT_COCKPIT_DARWIN_HPC_ADAPTER_URL || "http://192.168.3.169:6830";
const TTL_MS = 5 * 60 * 1000;  // 5 min cache
const BEAGLE_PUBLIC_URL =
  process.env.PROJECT_COCKPIT_BEAGLE_URL || "http://beagle-core.tail21cbc4.ts.net";
const BEAGLE_INTERNAL_URL =
  process.env.PROJECT_COCKPIT_BEAGLE_INTERNAL_URL ||
  "http://beagle-core.beagle.svc.cluster.local:8080";
const DYNAMO_INTERNAL_URL =
  process.env.PROJECT_COCKPIT_DYNAMO_INTERNAL_URL ||
  process.env.PROJECT_COCKPIT_DYNAMO_ENDPOINT ||
  "http://dynamo-control-plane.beagle.svc.cluster.local:8000";
const DYNAMO_MODEL =
  process.env.PROJECT_COCKPIT_DYNAMO_MODEL ||
  process.env.BEAGLE_DYNAMO_MODEL ||
  "qwen2.5-0.5B-Instruct";
const BEAGLE_ALLOWED_PROXY_PREFIXES = [
  "/api/v1/cognitive/",
  "/api/exocortex/process",
  "/api/fractal/recurse",
  "/api/deep_think"
];

let tokenCache = null;
let tokenCachedAt = 0;
let adapterTokenCache = null;
let adapterTokenCachedAt = 0;

function runKubectl(args, { timeoutMs = 8000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(KUBECTL, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "", stderr = "";
    const timer = setTimeout(() => { child.kill("SIGKILL"); reject(new Error("kubectl timeout")); }, timeoutMs);
    child.stdout.on("data", d => stdout += d.toString());
    child.stderr.on("data", d => stderr += d.toString());
    child.on("close", code => {
      clearTimeout(timer);
      if (code !== 0) reject(new Error(`kubectl exit ${code}: ${stderr}`));
      else resolve(stdout);
    });
    child.on("error", e => { clearTimeout(timer); reject(e); });
  });
}

export async function fetchOperatorToken() {
  const now = Date.now();
  if (tokenCache && (now - tokenCachedAt) < TTL_MS) {
    return { token: tokenCache, source: "cache", age_ms: now - tokenCachedAt };
  }

  // Try a known set of token keys in the secret
  const candidateKeys = ["BEAGLE_OPERATOR_API_TOKEN", "BEAGLE_API_TOKEN", "operator-token"];
  let raw, secret;
  try {
    raw = await runKubectl(["-n", NAMESPACE, "get", "secret", SECRET_NAME, "-o", "json"]);
    secret = JSON.parse(raw);
  } catch (e) {
    return { error: `cannot read secret ${SECRET_NAME}: ${e.message}` };
  }

  const data = secret.data || {};
  let foundKey, foundToken;
  for (const k of candidateKeys) {
    if (data[k]) {
      foundKey = k;
      foundToken = Buffer.from(data[k], "base64").toString("utf8");
      break;
    }
  }

  if (!foundToken) {
    return { error: `no token found in secret ${SECRET_NAME} (tried: ${candidateKeys.join(", ")})` };
  }

  tokenCache = foundToken;
  tokenCachedAt = now;
  return { token: foundToken, source: "fresh", key: foundKey };
}

export async function fetchDarwinHpcAdapterConfig() {
  const now = Date.now();
  if (adapterTokenCache && (now - adapterTokenCachedAt) < TTL_MS) {
    return {
      url: DARWIN_HPC_ADAPTER_URL,
      token: adapterTokenCache,
      source: "cache",
      age_ms: now - adapterTokenCachedAt
    };
  }

  const candidateKeys = ["adapterToken", "token", "ADAPTER_TOKEN"];
  let raw, secret;
  try {
    raw = await runKubectl([
      "-n",
      DARWIN_HPC_ADAPTER_NAMESPACE,
      "get",
      "secret",
      DARWIN_HPC_ADAPTER_SECRET,
      "-o",
      "json"
    ]);
    secret = JSON.parse(raw);
  } catch (e) {
    return {
      error: `cannot read secret ${DARWIN_HPC_ADAPTER_NAMESPACE}/${DARWIN_HPC_ADAPTER_SECRET}: ${e.message}`
    };
  }

  const data = secret.data || {};
  let foundKey, foundToken;
  for (const k of candidateKeys) {
    if (data[k]) {
      foundKey = k;
      foundToken = Buffer.from(data[k], "base64").toString("utf8");
      break;
    }
  }

  if (!foundToken) {
    return {
      error: `no token found in secret ${DARWIN_HPC_ADAPTER_NAMESPACE}/${DARWIN_HPC_ADAPTER_SECRET} (tried: ${candidateKeys.join(", ")})`
    };
  }

  adapterTokenCache = foundToken;
  adapterTokenCachedAt = now;
  return {
    url: DARWIN_HPC_ADAPTER_URL,
    token: foundToken,
    source: "fresh",
    key: foundKey
  };
}

function deriveCaller(req) {
  // Tailscale operator sidecar injects these on Tailnet routes
  const tsUser = req.header("Tailscale-User-Login")
    || req.header("x-tailscale-user")
    || req.header("X-Auth-Request-User")
    || null;
  const tsName = req.header("Tailscale-User-Name")
    || req.header("x-tailscale-name")
    || null;
  return {
    tailnet_login: tsUser,
    tailnet_name: tsName,
    has_tailnet_identity: !!tsUser
  };
}

function parseJsonResponse(raw) {
  if (!raw) {
    return {};
  }
  try {
    return JSON.parse(raw);
  } catch (_err) {
    return { raw };
  }
}

function cleanString(value) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed ? trimmed : "";
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).trim();
  }
  return "";
}

function inferCompletionSource(payload = {}) {
  const explicit =
    cleanString(payload?.source) ||
    cleanString(payload?.response_source) ||
    cleanString(payload?.provider_source);
  if (explicit) {
    return explicit;
  }
  if (cleanString(payload?.agentKind || payload?.agent_kind || payload?.sessionId || payload?.session_id || payload?.podName || payload?.pod_name)) {
    return "agent";
  }
  return "cluster";
}

function cleanObjectString(value, fallback = "") {
  const cleaned = cleanString(value);
  return cleaned || fallback;
}

function extractDiscussionLabText(payload = {}) {
  const direct =
    cleanString(payload?.text) ||
    cleanString(payload?.response) ||
    cleanString(payload?.answer);
  if (direct) {
    return direct;
  }
  const choices = Array.isArray(payload?.choices) ? payload.choices : [];
  const firstChoice = choices[0] || {};
  return (
    cleanString(firstChoice?.message?.content) ||
    cleanString(firstChoice?.delta?.content) ||
    cleanString(firstChoice?.text)
  );
}

function extractDiscussionLabError(payload = {}) {
  return (
    cleanString(payload?.error?.message) ||
    cleanString(payload?.error) ||
    cleanString(payload?.message)
  );
}

function resolveBeagleProxyPath(req) {
  const requestUrl = new URL(req.originalUrl, "http://project-cockpit.local");
  const proxiedPath = requestUrl.pathname.replace(/^\/api\/beagle/, "");
  const normalizedPath = proxiedPath.startsWith("/") ? proxiedPath : `/${proxiedPath}`;
  const allowed = BEAGLE_ALLOWED_PROXY_PREFIXES.some(
    (prefix) => normalizedPath === prefix || normalizedPath.startsWith(prefix)
  );
  if (!allowed) {
    return {
      error: `beagle proxy path is not allowed: ${normalizedPath}`
    };
  }
  return {
    path: `${normalizedPath}${requestUrl.search}`
  };
}

async function proxyBeagleRequest(method, req) {
  const target = resolveBeagleProxyPath(req);
  if (target.error) {
    return {
      status: 400,
      payload: {
        error: target.error,
        truthMode: "declared",
        via: "cockpit-beagle-proxy"
      }
    };
  }

  const tokenResult = await fetchOperatorToken();
  if (tokenResult.error || !tokenResult.token) {
    return {
      status: 503,
      payload: {
        error: tokenResult.error || "beagle token unavailable",
        truthMode: "stale",
        via: "cockpit-beagle-proxy",
        proxied_path: target.path
      }
    };
  }

  const timeoutMs = method === "POST" ? 120000 : 15000;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${BEAGLE_INTERNAL_URL}${target.path}`, {
      method,
      headers: {
        Accept: "application/json",
        "content-type": "application/json",
        "X-Beagle-Consumer": "beagle-operator",
        Authorization: `Bearer ${tokenResult.token}`
      },
      body: method === "POST" ? JSON.stringify(req.body ?? {}) : undefined,
      signal: ctrl.signal
    });
    const payload = parseJsonResponse(await res.text());
    const body =
      payload && typeof payload === "object" && !Array.isArray(payload)
        ? {
            ...payload,
            via: payload.via || "cockpit-beagle-proxy",
            proxied_path: target.path
          }
        : {
            data: payload,
            via: "cockpit-beagle-proxy",
            proxied_path: target.path
          };
    return {
      status: res.status,
      payload: body
    };
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: err.message,
        truthMode: "stale",
        via: "cockpit-beagle-proxy",
        proxied_path: target.path,
        beagle_url: BEAGLE_INTERNAL_URL
      }
    };
  } finally {
    clearTimeout(timer);
  }
}

export async function proxyBeagleCompletion({
  prompt,
  system = "",
  requires_math = false,
  requires_high_quality = false,
  offline_required = false
}) {
  const promptText = cleanString(prompt);
  const systemText = cleanString(system);
  const completionPrompt = systemText ? `${systemText}\n\n${promptText}` : promptText;
  const messages = [];
  const behavioralPrompt = [];
  if (systemText) {
    messages.push({ role: "system", content: systemText });
  }
  if (requires_math) {
    behavioralPrompt.push("Solve the task carefully and verify any arithmetic.");
  }
  if (requires_high_quality) {
    behavioralPrompt.push("Prioritize accuracy, clarity, and completeness.");
  }
  if (offline_required) {
    behavioralPrompt.push("Answer directly without suggesting external tools or web access.");
  }
  if (behavioralPrompt.length > 0) {
    messages.push({
      role: "system",
      content: behavioralPrompt.join(" ")
    });
  }
  messages.push({ role: "user", content: promptText });

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 120000);
  try {
    const res = await fetch(`${DYNAMO_INTERNAL_URL}/v1/chat/completions`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: DYNAMO_MODEL,
        messages,
        temperature: 0.2
      }),
      signal: ctrl.signal
    });

    const payload = parseJsonResponse(await res.text());
    const responseText = cleanString(
      payload?.choices?.[0]?.message?.content ||
        payload?.choices?.[0]?.text ||
        payload?.output_text ||
        payload?.text ||
        payload?.response
    );
    return {
      status: res.status,
      payload: {
        text: responseText,
        response: responseText,
        provider: cleanString(payload?.model || DYNAMO_MODEL || "dynamo"),
        tier: cleanString(payload?.model || DYNAMO_MODEL || "dynamo"),
        source: inferCompletionSource(payload),
        agentKind: cleanString(payload?.agentKind || payload?.agent_kind),
        sessionId: cleanString(payload?.sessionId || payload?.session_id),
        podName: cleanString(payload?.podName || payload?.pod_name),
        usage: payload?.usage || {},
        truthMode: "observed",
        raw: payload
      },
      completionPrompt,
      beagleUrl: DYNAMO_INTERNAL_URL
    };
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: err.message,
        truthMode: "stale",
        via: "cockpit-beagle-completion",
        beagle_url: DYNAMO_INTERNAL_URL
      },
      completionPrompt,
      beagleUrl: DYNAMO_INTERNAL_URL
    };
  } finally {
    clearTimeout(timer);
  }
}

export async function proxyDiscussionLabCompletion({
  prompt,
  system = "",
  profile
}) {
  const promptText = cleanString(prompt);
  const systemText = cleanString(system);
  const endpoint = cleanString(profile?.endpoint);
  const model = cleanObjectString(
    profile?.runtimeModelId,
    profile?.modelId,
    profile?.model,
    cleanString(profile?.id) || "unknown"
  );
  const profileId = cleanString(profile?.id);

  if (!promptText) {
    return {
      status: 400,
      payload: {
        error: "prompt is required",
        truthMode: "declared",
        source: "cluster"
      }
    };
  }

  if (!endpoint) {
    return {
      status: 503,
      payload: {
        error: `discussion lab profile ${profileId || "unknown"} has no endpoint`,
        truthMode: "declared",
        source: "cluster"
      }
    };
  }

  const ctrl = new AbortController();
  const timeoutMs = 90000;
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${endpoint}/v1/chat/completions`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model,
        stream: false,
        messages: [
          ...(systemText ? [{ role: "system", content: systemText }] : []),
          { role: "user", content: promptText }
        ]
      }),
      signal: ctrl.signal
    });
    const payload = parseJsonResponse(await res.text());
    if (!res.ok) {
      return {
        status: res.status,
        payload: {
          error:
            extractDiscussionLabError(payload) ||
            `discussion lab request failed with HTTP ${res.status}`,
          truthMode: "stale",
          source: "cluster",
          beagle_url: endpoint,
          discussion_profile: profileId
        }
      };
    }

    const responseText = extractDiscussionLabText(payload);
    if (!responseText) {
      return {
        status: 502,
        payload: {
          error: "discussion lab returned an empty completion",
          truthMode: "stale",
          source: "cluster",
          beagle_url: endpoint,
          discussion_profile: profileId
        }
      };
    }

    return {
      status: 200,
      payload: {
        response: responseText,
        model: cleanObjectString(payload?.model, model),
        provider: cleanObjectString(payload?.model, model),
        tier: cleanObjectString(profile?.family, profileId || "discussion-lab"),
        source: "cluster",
        usage: payload?.usage || null,
        beagle_url: endpoint,
        discussion_profile: profileId,
        pod_name: cleanString(profile?.node)
      }
    };
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: err.message,
        truthMode: "stale",
        source: "cluster",
        beagle_url: endpoint,
        discussion_profile: profileId
      }
    };
  } finally {
    clearTimeout(timer);
  }
}

export function registerAuthBridgeRoutes(app) {
  app.get("/api/auth/beagle-token", async (req, res) => {
    const caller = deriveCaller(req);

    // Personal/closed mode: no Tailnet header required (we trust the network).
    // When multi-tenant: require has_tailnet_identity here.
    const result = await fetchOperatorToken();

    if (result.error) {
      return res.status(503).json({
        error: result.error,
        truthMode: "stale",
        caller
      });
    }

    res.json({
      token: result.token,
      consumer: "beagle-operator",
      auth_header_value: `Bearer ${result.token}`,
      consumer_header_name: "X-Beagle-Consumer",
      consumer_header_value: "beagle-operator",
      beagle_url: BEAGLE_PUBLIC_URL,
      cluster_internal_url: BEAGLE_INTERNAL_URL,
      cached: result.source === "cache",
      cache_ttl_ms: TTL_MS,
      caller,
      truthMode: "observed",
      issued_at: new Date().toISOString()
    });
  });

  // Convenience endpoint — full beagle endpoint mapping for iOS to discover
  app.get("/api/auth/beagle-discover", async (_req, res) => {
    res.json({
      beagle_url: BEAGLE_PUBLIC_URL,
      cluster_internal_url: BEAGLE_INTERNAL_URL,
      auth: {
        consumer_header: "X-Beagle-Consumer",
        consumer_values: ["beagle-operator", "darwin-research"],
        auth_header: "Authorization",
        auth_format: "Bearer <token>",
        token_endpoint: "/api/auth/beagle-token (this cockpit)"
      },
      endpoints: {
        health: "GET /health",
        debate: "POST /dev/debate",
        deep_research: "POST /dev/deep-research",
        causal: "POST /dev/causal",
        swarm: "POST /dev/swarm",
        temporal: "POST /dev/temporal",
        parallel: "POST /dev/parallel",
        neurosymbolic: "POST /dev/neurosymbolic",
        void: "POST /dev/void",
        physio: "POST /api/observer/physio (replaces /api/hrv)",
        physio_latest: "GET /api/observer/physio/latest",
        env: "POST /api/observer/env",
        chat_mobile: "POST /api/mobile/v1/chat",
        chat_complete: "POST /api/llm/complete (compatibility alias on cockpit)",
        chat_stream: "private beagle-core only; not published on the cockpit boundary",
        memory_query: "POST /api/memory/query",
        memory_ingest: "POST /api/memory/ingest_chat",
        pipeline_start: "POST /api/pipeline/start",
        pipeline_status: "GET /api/pipeline/status/:run_id",
        runs_recent: "GET /api/runs/recent",
        science_jobs_start: "POST /api/jobs/science/start",
        external_jobs_register: "POST /api/jobs/external/register (cockpit reconciler)",
        external_jobs_complete: "POST /api/jobs/external/complete (cockpit reconciler)",
        cognitive_state: "GET /api/v1/cognitive/state",
        feedback_submit: "POST /api/v1/feedback",
        feedback_query: "GET /api/v1/feedback",
        hpc_jobs_submit: "POST /api/darwin/hpc/jobs/submit",
        hpc_jobs_control: "POST /api/darwin/hpc/control",
        hpc_jobs_profiles: "GET /api/darwin/hpc/profiles",
        hpc_jobs_logs: "GET /api/darwin/hpc/jobs/:job_id/stdout|stderr",
        search_pubmed: "POST /api/search/pubmed",
        search_arxiv: "POST /api/search/arxiv",
        search_all: "POST /api/search/all",
        worldmodel_predict: "POST /api/worldmodel/predict",
        fractal_grow: "POST /api/fractal/grow",
        pcs_reason: "POST /api/pcs/reason"
      },
      truthMode: "observed",
      generated_at: new Date().toISOString()
    });
  });

  app.get("/api/beagle/*", async (req, res) => {
    const result = await proxyBeagleRequest("GET", req);
    res.status(result.status).json(result.payload);
  });

  app.post("/api/beagle/*", async (req, res) => {
    const result = await proxyBeagleRequest("POST", req);
    res.status(result.status).json(result.payload);
  });
}
