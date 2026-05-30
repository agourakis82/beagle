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
import {
  enforceOperatorPolicy,
  MODEL_LANES,
  selectModelRoute
} from "./model-registry.mjs";
import { verifyMultimodelConversation } from "./multimodel-conversation-verifier.mjs";

const NAMESPACE = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "kubectl";
const SECRET_NAME = process.env.PROJECT_COCKPIT_BEAGLE_SECRET || "beagle-core-secrets";
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
const BEAGLE_MULTIMODEL_PROJECT =
  process.env.PROJECT_COCKPIT_MULTIMODEL_PROJECT || "darwin-mfc";
const COCKPIT_LOOPBACK =
  process.env.PROJECT_COCKPIT_LOOPBACK_URL ||
  `http://127.0.0.1:${process.env.PROJECT_COCKPIT_PORT || 4370}`;
const BEAGLE_ALLOWED_PROXY_PREFIXES = [
  "/api/v1/cognitive/",
  "/api/memory/query",
  "/api/memory/ingest_chat",
  "/api/pipeline/start",
  "/api/pipeline/status/",
  "/api/runs/recent",
  "/api/exocortex/process",
  "/api/fractal/recurse",
  "/api/deep_think"
];
const BEAGLE_OPENAI_MODELS = MODEL_LANES.map((lane) => {
  const baseTokens =
    lane.id === "research" ? 131072 :
    lane.id === "always-on" ? 65536 :
    lane.id === "helper" ? 32768 :
    lane.id === "audit" ? 65536 :
    lane.id === "operator" ? 65536 :
    65536;
  return {
    name: `beagle/${lane.id}`,
    display_name: `Beagle ${lane.title}`,
    max_tokens: baseTokens,
    capabilities: {
      tools: false,
      images: false,
      parallel_tool_calls: false,
      prompt_cache_key: false,
      chat_completions: true,
      interleaved_reasoning: false
    }
  };
});

let tokenCache = null;
let tokenCachedAt = 0;
const clusterLocalUrlCache = new Map();
const secretValueCache = new Map();

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

async function resolveClusterLocalUrl(rawUrl) {
  const cleanUrl = typeof rawUrl === "string" ? rawUrl.trim() : "";
  if (!cleanUrl) return cleanUrl;
  let parsed;
  try {
    parsed = new URL(cleanUrl);
  } catch {
    return cleanUrl;
  }
  const match = parsed.hostname.match(/^([a-z0-9-]+)\.([a-z0-9-]+)\.svc\.cluster\.local$/i);
  if (!match) return cleanUrl;

  const cacheKey = `${match[2]}/${match[1]}`;
  if (clusterLocalUrlCache.has(cacheKey)) {
    parsed.hostname = clusterLocalUrlCache.get(cacheKey);
    return parsed.toString().replace(/\/$/, "");
  }

  try {
    const serviceJson = await runKubectl([
      "-n",
      match[2],
      "get",
      "svc",
      match[1],
      "-o",
      "json"
    ]);
    const service = JSON.parse(serviceJson);
    const clusterIp = service?.spec?.clusterIP;
    if (clusterIp && clusterIp !== "None") {
      clusterLocalUrlCache.set(cacheKey, clusterIp);
      parsed.hostname = clusterIp;
      return parsed.toString().replace(/\/$/, "");
    }
  } catch {
    return cleanUrl;
  }
  return cleanUrl;
}

async function fetchSecretValue(key) {
  const cleanKey = typeof key === "string" ? key.trim() : "";
  if (!cleanKey) return "";
  const cached = secretValueCache.get(cleanKey);
  if (cached && (Date.now() - cached.cachedAt) < TTL_MS) {
    return cached.value;
  }
  try {
    const raw = await runKubectl([
      "-n",
      NAMESPACE,
      "get",
      "secret",
      SECRET_NAME,
      "-o",
      "json"
    ]);
    const secret = JSON.parse(raw);
    const encoded = secret?.data?.[cleanKey];
    const value = encoded ? Buffer.from(encoded, "base64").toString("utf8").trim() : "";
    if (value) {
      secretValueCache.set(cleanKey, { value, cachedAt: Date.now() });
    }
    return value;
  } catch {
    return "";
  }
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

function estimateTokens(prompt = "", system = "", response = "") {
  const combined = `${cleanString(system)}\n\n${cleanString(prompt)}\n\n${cleanString(response)}`.trim();
  if (!combined) return 0;
  return Math.max(1, Math.ceil(combined.length / 4));
}

function extractTextFromContent(content) {
  if (typeof content === "string") {
    return cleanString(content);
  }
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === "string") return part;
        if (part && typeof part === "object") {
          if (typeof part.text === "string") return part.text;
          if (typeof part.content === "string") return part.content;
        }
        return "";
      })
      .filter(Boolean)
      .join("\n");
  }
  if (content && typeof content === "object" && typeof content.text === "string") {
    return content.text;
  }
  return "";
}

function extractOpenAiPrompt(messages = []) {
  const system = [];
  const user = [];
  for (const message of Array.isArray(messages) ? messages : []) {
    const role = cleanString(message?.role).toLowerCase();
    const text = extractTextFromContent(message?.content);
    if (!text) continue;
    if (role === "system") {
      system.push(text);
    } else if (role === "user") {
      user.push(text);
    }
  }
  return {
    system: system.join("\n\n"),
    prompt: user.join("\n\n")
  };
}

function openAiModelToIntent(model = "") {
  const normalized = cleanString(model).toLowerCase();
  if (normalized.includes("research")) return "long-context";
  if (normalized.includes("audit")) return "audit";
  if (normalized.includes("operator")) return "operator";
  if (normalized.includes("helper")) return "helper";
  return "default";
}

function buildOpenAiChatCompletion({
  model = "beagle/always-on",
  text = "",
  prompt = "",
  system = ""
} = {}) {
  const created = Math.floor(Date.now() / 1000);
  const responseText = cleanString(text);
  const tokenUsage = {
    prompt_tokens: estimateTokens(prompt, system, ""),
    completion_tokens: estimateTokens("", "", responseText),
    total_tokens: estimateTokens(prompt, system, responseText)
  };
  return {
    id: `chatcmpl-${created}-${Math.random().toString(16).slice(2, 10)}`,
    object: "chat.completion",
    created,
    model: cleanString(model) || "beagle/always-on",
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content: responseText
        },
        finish_reason: "stop"
      }
    ],
    usage: tokenUsage
  };
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

  async function callBeagle(baseUrl) {
    const timeoutMs = method === "POST" ? 120000 : 15000;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetch(`${baseUrl.replace(/\/+$/, "")}${target.path}`, {
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
      return { res, payload, baseUrl };
    } finally {
      clearTimeout(timer);
    }
  }

  try {
    let result;
    try {
      result = await callBeagle(BEAGLE_INTERNAL_URL);
    } catch (internalError) {
      if (BEAGLE_PUBLIC_URL.replace(/\/+$/, "") === BEAGLE_INTERNAL_URL.replace(/\/+$/, "")) {
        throw internalError;
      }
      result = await callBeagle(BEAGLE_PUBLIC_URL);
    }

    const { res, payload, baseUrl } = result;
    const body =
      payload && typeof payload === "object" && !Array.isArray(payload)
        ? {
            ...payload,
            via: payload.via || "cockpit-beagle-proxy",
            proxied_path: target.path,
            beagle_url: baseUrl
          }
        : {
            data: payload,
            via: "cockpit-beagle-proxy",
            proxied_path: target.path,
            beagle_url: baseUrl
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
        beagle_url: BEAGLE_PUBLIC_URL
      }
    };
  }
}

export async function proxyBeagleCompletion({
  prompt,
  system = "",
  requires_math = false,
  requires_high_quality = false,
  offline_required = false,
  intent = "",
  model_provider = "",
  provider = "",
  model = ""
}) {
  const promptText = cleanString(prompt);
  const systemText = cleanString(system);
  const completionPrompt = systemText ? `${systemText}\n\n${promptText}` : promptText;
  const modelRoute = selectModelRoute({
    prompt: promptText,
    system: systemText,
    intent,
    requires_math,
    requires_high_quality,
    offline_required
  });
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
  if (modelRoute.requiresPolicy) {
    behavioralPrompt.push(
      "Cluster operator safety contract: prefer read-only diagnosis. Do not provide RBAC, node, package, scheduler, kubectl write, helm write, or reboot commands. If a mutation could be needed, say that a human-reviewed Cockpit operator packet is required."
    );
  }
  if (behavioralPrompt.length > 0) {
    messages.push({
      role: "system",
      content: behavioralPrompt.join(" ")
    });
  }
  messages.push({ role: "user", content: promptText });

  const completionBody = {
    model: cleanString(model) || modelRoute.model || DYNAMO_MODEL,
    messages,
    temperature: 0.2
  };

  async function callOpenRouter() {
    const apiKey = await fetchSecretValue("OPENROUTER_API_KEY");
    if (!apiKey) {
      return {
        status: 503,
        payload: {
          error: "OPENROUTER_API_KEY unavailable",
          truthMode: "stale"
        },
        completionPrompt,
        beagleUrl: "https://openrouter.ai/api/v1"
      };
    }
    const openRouterModel = cleanString(model) || "openai/gpt-chat-latest";
    const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
        "HTTP-Referer": "http://project-cockpit.local",
        "X-Title": "Beagle Project Cockpit"
      },
      body: JSON.stringify({
        ...completionBody,
        model: openRouterModel
      }),
      signal: AbortSignal.timeout(120000)
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
        provider: openRouterModel,
        tier: "openrouter",
        usage: payload?.usage || {},
        truthMode: res.ok ? "observed" : "stale",
        source: "openrouter",
        raw: payload,
        error: payload?.error?.message || payload?.message
      },
      completionPrompt,
      beagleUrl: "https://openrouter.ai/api/v1"
    };
  }

  const requestedProvider = cleanString(model_provider || provider).toLowerCase();
  if (requestedProvider === "openrouter") {
    return callOpenRouter();
  }

  async function callCompletion(baseUrl) {
    const reachableBaseUrl = await resolveClusterLocalUrl(baseUrl);
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 120000);
    try {
      const res = await fetch(`${reachableBaseUrl.replace(/\/+$/, "")}/v1/chat/completions`, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "content-type": "application/json"
        },
        body: JSON.stringify(completionBody),
        signal: ctrl.signal
      });
      const payload = parseJsonResponse(await res.text());
      return { res, payload, baseUrl: reachableBaseUrl };
    } finally {
      clearTimeout(timer);
    }
  }

  try {
    const primaryUrl = cleanString(modelRoute.endpoint) || DYNAMO_INTERNAL_URL;
    const fallbackUrl = cleanString(modelRoute.fallbackEndpoint);
    let result = await callCompletion(primaryUrl);
    if (
      !result.res.ok &&
      fallbackUrl &&
      fallbackUrl.replace(/\/+$/, "") !== primaryUrl.replace(/\/+$/, "")
    ) {
      result = await callCompletion(fallbackUrl);
    }
    const { res, payload, baseUrl } = result;

    const responseText = cleanString(
      payload?.choices?.[0]?.message?.content ||
        payload?.choices?.[0]?.text ||
        payload?.output_text ||
        payload?.text ||
        payload?.response
    );
    const policy = enforceOperatorPolicy(responseText, {
      route: modelRoute.requestedLane,
      intent: modelRoute.intent,
      requiresPolicy: modelRoute.requiresPolicy
    });
    const deliveredText = policy.decision === "blocked" ? policy.text : responseText;
    return {
      status: res.status,
      payload: {
        text: deliveredText,
        response: deliveredText,
        provider: cleanString(payload?.model || modelRoute.displayModel || DYNAMO_MODEL || "dynamo"),
        tier: cleanString(payload?.model || modelRoute.displayModel || DYNAMO_MODEL || "dynamo"),
        usage: payload?.usage || {},
        truthMode: "observed",
        source: "cluster",
        model_route: modelRoute,
        policy,
        raw: payload
      },
      completionPrompt,
      beagleUrl: baseUrl
    };
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: err.message,
        truthMode: "stale",
        via: "cockpit-beagle-completion",
        beagle_url: modelRoute.endpoint || DYNAMO_INTERNAL_URL,
        model_route: modelRoute
      },
      completionPrompt,
      beagleUrl: modelRoute.endpoint || DYNAMO_INTERNAL_URL
    };
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

  app.get("/api/beagle/v1/models", async (_req, res) => {
    res.json({
      object: "list",
      data: BEAGLE_OPENAI_MODELS.map((model) => ({
        id: model.name,
        object: "model",
        created: Math.floor(Date.now() / 1000),
        owned_by: "beagle",
        permission: [],
        root: model.name,
        parent: null
      }))
    });
  });

  app.post("/api/beagle/v1/chat/completions", async (req, res) => {
    try {
      const { system, prompt } = extractOpenAiPrompt(req.body?.messages);
      const requestedModel = cleanString(req.body?.model) || "beagle/always-on";
      const preferredProvidersByModel = {
        "beagle/always-on": ["claude", "codex", "cursor", "kimi"],
        "beagle/helper": ["claude", "codex", "cursor", "kimi"],
        "beagle/audit": ["claude", "cursor", "codex", "kimi"],
        "beagle/research": ["kimi", "claude", "cursor", "codex"],
        "beagle/operator": ["codex", "claude", "cursor", "kimi"]
      };

      let providers = preferredProvidersByModel[requestedModel] || preferredProvidersByModel["beagle/always-on"];
      try {
        const providersResponse = await fetch(
          `${COCKPIT_LOOPBACK}/api/projects/${encodeURIComponent(BEAGLE_MULTIMODEL_PROJECT)}/multimodel/providers`,
          {
            headers: internalContextHeaders(),
            signal: AbortSignal.timeout(10000)
          }
        );
        const providersPayload = await providersResponse.json().catch(() => ({}));
        const available = new Set(
          (providersPayload.providers || [])
            .filter((item) => item?.status === "available")
            .map((item) => cleanString(item.id))
        );
        const filtered = providers.filter((provider) => available.has(provider));
        if (filtered.length > 0) {
          providers = filtered;
        }
      } catch (error) {
        // Fall through to the local preference list.
        if (process.env.PROJECT_COCKPIT_DEBUG_OPENAI_COMPAT === "1") {
          console.error("[beagle-openai] provider discovery failed", error);
        }
      }

      let conversation = null;
      let lastError = null;
      for (const providerId of providers) {
        try {
          conversation = await verifyMultimodelConversation({
            projectSlug: BEAGLE_MULTIMODEL_PROJECT,
            providers: [providerId],
            apiBase: COCKPIT_LOOPBACK,
            wsBase: COCKPIT_LOOPBACK.replace(/^http/, "ws"),
            timeoutMs: Number(process.env.PROJECT_COCKPIT_OPENAI_COMPAT_TIMEOUT_MS || 180000),
            message: prompt || system || "Responda diretamente.",
            minChars: 1
          });
          if (cleanString(conversation?.responses?.[0]?.text)) {
            lastError = null;
            break;
          }
        } catch (error) {
          lastError = error;
        }
      }

      if (!conversation) {
        throw lastError || new Error("beagle chat completion unavailable");
      }

      const responseText = cleanString(conversation?.responses?.[0]?.text || "");
      const response = buildOpenAiChatCompletion({
        model: requestedModel,
        text: responseText,
        prompt,
        system
      });

      if (req.body?.stream === false) {
        res.json(response);
        return;
      }

      res.status(200);
      res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
      res.setHeader("Cache-Control", "no-cache, no-transform");
      res.setHeader("Connection", "keep-alive");
      res.write(`data: ${JSON.stringify({
        choices: [
          {
            index: 0,
            delta: {
              role: "assistant",
              content: response.choices[0].message.content
            },
            finish_reason: "stop"
          }
        ],
        usage: response.usage
      })}\n\n`);
      res.write("data: [DONE]\n\n");
      res.end();
    } catch (error) {
      res.status(error.statusCode || 503).json({
        error: {
          message: cleanString(error?.message || "beagle chat completion unavailable"),
          detail: error?.detail || null,
          truthMode: "stale"
        }
      });
    }
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
        workbench_context_connect: "GET /api/workbench/:slug/context/connect",
        workbench_context_status: "GET /api/workbench/:slug/context/status",
        workbench_context_doctor: "GET/POST /api/workbench/:slug/context/doctor",
        workbench_context_clients: "GET /api/workbench/:slug/context/clients",
        workbench_context_presence: "GET /api/workbench/:slug/context/presence",
        workbench_context_sessions: "GET /api/workbench/:slug/context/sessions",
        workbench_context_audit: "GET /api/workbench/:slug/context/audit",
        workbench_context_audit_events: "GET /api/workbench/:slug/context/audit/events",
        workbench_context_recent: "GET /api/workbench/:slug/context/recent",
        workbench_context_continuity: "GET /api/workbench/:slug/context/continuity",
        workbench_context_messages: "GET /api/workbench/:slug/context/messages",
        workbench_context_message_board: "GET /api/workbench/:slug/context/messages/board",
        workbench_context_message_inbox: "GET /api/workbench/:slug/context/messages/inbox/:client_id",
        workbench_context_message_send: "POST /api/workbench/:slug/context/messages/send",
        workbench_context_message_ack: "POST /api/workbench/:slug/context/messages/:message_id/ack",
        workbench_context_message_compile: "GET/POST /api/workbench/:slug/context/messages/:message_id/compile",
        workbench_context_message_claim: "POST /api/workbench/:slug/context/messages/:message_id/claim",
        workbench_context_message_complete: "POST /api/workbench/:slug/context/messages/:message_id/complete",
        workbench_context_message_release: "POST /api/workbench/:slug/context/messages/:message_id/release",
        workbench_context_message_cancel: "POST /api/workbench/:slug/context/messages/:message_id/cancel",
        workbench_context_message_reopen: "POST /api/workbench/:slug/context/messages/:message_id/reopen",
        workbench_context_message_heartbeat: "POST /api/workbench/:slug/context/messages/:message_id/heartbeat",
        workbench_context_export: "GET /api/workbench/:slug/context/export",
        workbench_context_import: "POST /api/workbench/:slug/context/import",
        workbench_context_mcp_tools: "GET /api/workbench/:slug/context/mcp/tools",
        workbench_context_mcp_http: "POST /api/workbench/:slug/context/mcp",
        workbench_mcp_http: "POST /api/workbench/:slug/mcp",
        workbench_context_query: "POST /api/workbench/:slug/context/query",
        workbench_context_ingest: "POST /api/workbench/:slug/context/ingest",
        workbench_context_graphrag: "POST /api/workbench/:slug/context/graphrag/query",
        workbench_context_compile: "POST /api/workbench/:slug/context/compiler/compile",
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
