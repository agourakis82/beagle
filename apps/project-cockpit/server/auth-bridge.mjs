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
const OPENROUTER_BASE_URL =
  process.env.PROJECT_COCKPIT_OPENROUTER_BASE_URL ||
  "https://openrouter.ai/api/v1";
const SUBSCRIPTION_BRIDGE_URL = cleanValue(
  process.env.PROJECT_COCKPIT_SUBSCRIPTION_BRIDGE_URL ||
  process.env.BEAGLE_SUBSCRIPTION_BRIDGE_URL
);
const SUBSCRIPTION_BRIDGE_TOKEN = cleanValue(
  process.env.PROJECT_COCKPIT_SUBSCRIPTION_BRIDGE_TOKEN ||
  process.env.BEAGLE_SUBSCRIPTION_BRIDGE_TOKEN
);
const DEFAULT_WORKSPACE_SUBSCRIPTION_HOME =
  process.env.PROJECT_COCKPIT_WORKSPACE_SUBSCRIPTION_HOME ||
  "/workspace/.home/openvscode-server";
const DYNAMO_INTERNAL_URL =
  process.env.PROJECT_COCKPIT_DYNAMO_INTERNAL_URL ||
  process.env.PROJECT_COCKPIT_DYNAMO_ENDPOINT ||
  "http://dynamo-control-plane.beagle.svc.cluster.local:8000";
const DYNAMO_MODEL =
  process.env.PROJECT_COCKPIT_DYNAMO_MODEL ||
  process.env.BEAGLE_DYNAMO_MODEL ||
  "qwen2.5-0.5B-Instruct";
const DISCUSSION_LAB_INTERNAL_URL =
  process.env.PROJECT_COCKPIT_DISCUSSION_LAB_INTERNAL_URL ||
  process.env.PROJECT_COCKPIT_DISCUSSION_LAB_ENDPOINT ||
  "http://discussion-lab-serving.beagle.svc.cluster.local:8000";
const DISCUSSION_LAB_MODEL =
  process.env.PROJECT_COCKPIT_DISCUSSION_LAB_MODEL ||
  process.env.BEAGLE_DISCUSSION_LAB_MODEL ||
  "qwen2.5-3b-instruct";
const SGLANG_INTERNAL_URL =
  process.env.PROJECT_COCKPIT_SGLANG_INTERNAL_URL ||
  process.env.PROJECT_COCKPIT_SGLANG_ENDPOINT ||
  "http://sglang-serving.beagle.svc.cluster.local:30000";
const SGLANG_MODEL =
  process.env.PROJECT_COCKPIT_SGLANG_MODEL ||
  process.env.BEAGLE_SGLANG_MODEL ||
  DYNAMO_MODEL;
const LITELLM_ROUTER_URL =
  process.env.PROJECT_COCKPIT_LITELLM_ROUTER_URL ||
  "http://router.llm-router.svc.cluster.local:4000";
const BEAGLE_ALLOWED_PROXY_PREFIXES = [
  "/api/v1/cognitive/",
  "/api/cognitive/deep-think",
  "/api/exocortex/process",
  "/api/fractal/recurse",
  "/api/hyperedges",
  "/api/deep_think"
];

let tokenCache = null;
let tokenCachedAt = 0;
let tokenFetchInFlight = null;
let secretCache = null;
let secretCachedAt = 0;
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

  // Promise coalescing: avoid cache stampede from concurrent requests
  if (tokenFetchInFlight) return tokenFetchInFlight;
  tokenFetchInFlight = _fetchOperatorTokenImpl().finally(() => { tokenFetchInFlight = null; });
  return tokenFetchInFlight;
}

async function _fetchOperatorTokenImpl() {
  const envToken = cleanString(
    process.env.BEAGLE_MEMORY_API_TOKEN ||
    process.env.BEAGLE_OPERATOR_API_TOKEN ||
    process.env.BEAGLE_API_TOKEN
  );
  if (envToken) {
    tokenCache = envToken;
    tokenCachedAt = Date.now();
    return { token: envToken, source: "env", key: "BEAGLE_MEMORY_API_TOKEN" };
  }

  const secretResult = await fetchSecretValue([
    "BEAGLE_OPERATOR_API_TOKEN",
    "BEAGLE_API_TOKEN",
    "operator-token"
  ]);
  if (secretResult.error) {
    return { error: secretResult.error };
  }

  const foundToken = secretResult.value;
  const foundKey = secretResult.key;

  tokenCache = foundToken;
  tokenCachedAt = Date.now();
  return { token: foundToken, source: "fresh", key: foundKey };
}

async function fetchSecretData({
  namespace = NAMESPACE,
  secretName = SECRET_NAME,
  useCache = true
} = {}) {
  const now = Date.now();
  const canUseSharedCache = namespace === NAMESPACE && secretName === SECRET_NAME;
  if (useCache && canUseSharedCache && secretCache && (now - secretCachedAt) < TTL_MS) {
    return { secret: secretCache, source: "cache", age_ms: now - secretCachedAt };
  }

  try {
    const raw = await runKubectl(["-n", namespace, "get", "secret", secretName, "-o", "json"]);
    const secret = JSON.parse(raw);
    if (canUseSharedCache) {
      secretCache = secret;
      secretCachedAt = now;
    }
    return { secret, source: "fresh" };
  } catch (e) {
    return { error: `cannot read secret ${secretName}: ${e.message}` };
  }
}

async function fetchSecretValue(candidateKeys = [], { namespace = NAMESPACE, secretName = SECRET_NAME } = {}) {
  const secretResult = await fetchSecretData({ namespace, secretName, useCache: true });
  if (secretResult.error) {
    return { error: secretResult.error };
  }

  const data = secretResult.secret?.data || {};
  for (const key of candidateKeys) {
    if (data[key]) {
      return {
        key,
        value: Buffer.from(data[key], "base64").toString("utf8"),
        source: secretResult.source
      };
    }
  }

  return {
    error: `no key found in secret ${secretName} (tried: ${candidateKeys.join(", ")})`
  };
}

export async function fetchOpenRouterApiKey() {
  const result = await fetchSecretValue(["OPENROUTER_API_KEY", "OPEN_ROUTER_API_KEY"]);
  if (result.error) {
    return { error: result.error };
  }
  return {
    apiKey: result.value,
    key: result.key,
    source: result.source
  };
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

function cleanValue(value) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed || "";
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).trim();
  }
  return "";
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

function shellSingleQuote(value) {
  return `'${String(value ?? "").replace(/'/g, `'\"'\"'`)}'`;
}

function encodeBase64Utf8(value) {
  return Buffer.from(cleanString(value), "utf8").toString("base64");
}

function buildWorkspaceSubscriptionPrompt(system, prompt) {
  const promptText = cleanString(prompt);
  const systemText = cleanString(system);
  if (!systemText) {
    return promptText;
  }
  return [
    "System guidance:",
    systemText,
    "",
    "User message:",
    promptText
  ].join("\n");
}

function resolveWorkspaceSubscriptionTarget(catalog = {}, requestedSlug = "") {
  const projects = Array.isArray(catalog?.projects) ? catalog.projects : [];
  const normalizedRequested = cleanString(requestedSlug).toLowerCase();
  const candidates = normalizedRequested
    ? projects.filter(
        (project) =>
          cleanString(project?.projectSlug).toLowerCase() === normalizedRequested
      )
    : projects;

  const withWorkspace = candidates.find(
    (project) =>
      cleanString(project?.workspacePod) &&
      cleanString(project?.workspaceContainer) &&
      cleanString(project?.workspaceRoot)
  );
  if (withWorkspace) {
    return {
      slug: cleanString(withWorkspace?.projectSlug),
      namespace: cleanString(withWorkspace?.namespace) || NAMESPACE,
      pod: cleanString(withWorkspace?.workspacePod),
      container: cleanString(withWorkspace?.workspaceContainer),
      workspaceRoot: cleanString(withWorkspace?.workspaceRoot),
      workspaceHome:
        cleanString(withWorkspace?.workspaceHome) || DEFAULT_WORKSPACE_SUBSCRIPTION_HOME
    };
  }

  if (!normalizedRequested) {
    return null;
  }
  return {
    error: `project ${requestedSlug} does not expose a workspace subscription target`
  };
}

function buildWorkspaceSubscriptionScript({ providerId, system, prompt, workspaceRoot, workspaceHome }) {
  const requestB64 = encodeBase64Utf8(buildWorkspaceSubscriptionPrompt(system, prompt));
  const rootQuoted = shellSingleQuote(workspaceRoot || "/workspace");
  const homeQuoted = shellSingleQuote(workspaceHome || DEFAULT_WORKSPACE_SUBSCRIPTION_HOME);
  const requestQuoted = shellSingleQuote(requestB64);
  const promptBuild = [
    `REQUEST_B64=${requestQuoted}`,
    "REQUEST_TEXT=\"$(printf '%s' \"$REQUEST_B64\" | base64 -d)\""
  ].join("\n");

  if (providerId === "claude-code") {
    return [
      "set -eu",
      `cd ${rootQuoted}`,
      `export HOME=${homeQuoted}`,
      "if [ -d /workspace/.home/openvscode-server ]; then export HOME=/workspace/.home/openvscode-server; fi",
      promptBuild,
      "unset ANTHROPIC_API_KEY",
      "claude -p --output-format text \"$REQUEST_TEXT\""
    ].join("\n");
  }

  if (providerId === "codex") {
    return [
      "set -eu",
      `cd ${rootQuoted}`,
      `export HOME=${homeQuoted}`,
      "if [ -d /workspace/.home/openvscode-server ]; then export HOME=/workspace/.home/openvscode-server; fi",
      promptBuild,
      "unset OPENAI_API_KEY",
      "TMP_LAST=\"$(mktemp)\"",
      "trap 'rm -f \"$TMP_LAST\"' EXIT",
      "codex exec --skip-git-repo-check --output-last-message \"$TMP_LAST\" \"$REQUEST_TEXT\" >/dev/null",
      "cat \"$TMP_LAST\""
    ].join("\n");
  }

  return "";
}

async function proxyWorkspaceSubscriptionCompletion({
  prompt,
  system = "",
  provider = "",
  projectSlug = "",
  readCatalog = null
}) {
  const providerId = normalizeSubscriptionBridgeProvider(provider);
  if (!providerId) {
    return {
      status: 400,
      payload: {
        error: `unknown workspace subscription provider: ${provider}`,
        truthMode: "declared",
        source: "workspace-subscription"
      }
    };
  }

  if (typeof readCatalog !== "function") {
    return null;
  }

  let catalog = null;
  try {
    catalog = await readCatalog();
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: `cannot read project catalog: ${err.message}`,
        truthMode: "stale",
        source: "workspace-subscription"
      }
    };
  }

  const target =
    resolveWorkspaceSubscriptionTarget(catalog, projectSlug) ||
    resolveWorkspaceSubscriptionTarget(catalog, "sounio");
  if (!target) {
    return {
      status: 503,
      payload: {
        error: "workspace subscription target unavailable",
        truthMode: "stale",
        source: "workspace-subscription"
      }
    };
  }
  if (target.error) {
    return {
      status: 409,
      payload: {
        error: target.error,
        truthMode: "declared",
        source: "workspace-subscription"
      }
    };
  }

  const promptText = cleanString(prompt);
  if (!promptText) {
    return {
      status: 400,
      payload: {
        error: "prompt is required",
        truthMode: "declared",
        source: "workspace-subscription"
      }
    };
  }

  const script = buildWorkspaceSubscriptionScript({
    providerId,
    system,
    prompt: promptText,
    workspaceRoot: target.workspaceRoot,
    workspaceHome: target.workspaceHome
  });
  if (!script) {
    return {
      status: 400,
      payload: {
        error: `workspace subscription provider not implemented: ${providerId}`,
        truthMode: "declared",
        source: "workspace-subscription"
      }
    };
  }

  try {
    const stdout = await runKubectl(
      [
        "-n",
        target.namespace,
        "exec",
        target.pod,
        "-c",
        target.container,
        "--",
        "sh",
        "-lc",
        script
      ],
      { timeoutMs: 240000 }
    );
    const responseText = cleanString(stdout);
    return {
      status: responseText ? 200 : 503,
      payload: {
        text: responseText,
        response: responseText,
        provider: providerId,
        tier: providerId,
        source: "workspace-subscription",
        truthMode: responseText ? "observed" : "stale",
        applied_discussion_profile: providerId,
        agentKind: providerId,
        podName: target.pod,
        sessionId: `${target.slug || "workspace"}:${providerId}`,
        workspaceRoot: target.workspaceRoot
      }
    };
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: err.message,
        truthMode: "stale",
        source: "workspace-subscription",
        applied_discussion_profile: providerId,
        podName: target.pod,
        sessionId: `${target.slug || "workspace"}:${providerId}`
      }
    };
  }
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

function extractOpenRouterText(payload = {}) {
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
    cleanString(firstChoice?.message?.reasoning) ||
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

// Fetch the latest pinned biography digest from beagle-core memory.
// Used by the Personal space to ground the companion in who the user actually is.
// Best-effort: returns { digest: "" } on any failure so chat is never blocked.
export async function fetchBiographyDigest({ timeoutMs = 8000 } = {}) {
  const tokenResult = await fetchOperatorToken();
  if (tokenResult.error || !tokenResult.token) {
    return { digest: "", error: tokenResult.error || "beagle token unavailable" };
  }
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${BEAGLE_INTERNAL_URL}/api/memory/query`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "content-type": "application/json",
        "X-Beagle-Consumer": "beagle-operator",
        Authorization: `Bearer ${tokenResult.token}`
      },
      // Tag-filtered query reliably surfaces the pinned digest (see docs/exocortex/CONTRACTS.md).
      body: JSON.stringify({
        query: "biografia viva Demetrios quem ele é trabalho recente",
        k: 5,
        tags: ["biography-digest"],
        scope: "biography_digest"
      }),
      signal: ctrl.signal
    });
    if (!res.ok) {
      return { digest: "", error: `memory/query ${res.status}` };
    }
    const payload = parseJsonResponse(await res.text());
    const highlights = Array.isArray(payload?.highlights) ? payload.highlights : [];
    const sorted = highlights
      .filter((h) => cleanString(h?.snippet))
      .sort((a, b) => cleanString(b?.date).localeCompare(cleanString(a?.date)));
    return { digest: cleanString(sorted[0]?.snippet) };
  } catch (err) {
    return { digest: "", error: err.message };
  } finally {
    clearTimeout(timer);
  }
}

// Fetch the latest physiome digest from beagle-core memory.
// Used by the Personal space to ground the companion in the user's current
// body state and environment (HRV, sleep, ambient readings, etc.).
// Best-effort: returns { digest: "" } on any failure so chat is never blocked.
export async function fetchPhysiomeDigest({ timeoutMs = 8000 } = {}) {
  const tokenResult = await fetchOperatorToken();
  if (tokenResult.error || !tokenResult.token) {
    return { digest: "", error: tokenResult.error || "beagle token unavailable" };
  }
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${BEAGLE_INTERNAL_URL}/api/memory/query`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "content-type": "application/json",
        "X-Beagle-Consumer": "beagle-operator",
        Authorization: `Bearer ${tokenResult.token}`
      },
      // Tag-filtered query reliably surfaces the pinned physiome digest.
      body: JSON.stringify({
        query: "estado físico corpo ambiente HRV sono energia recente",
        k: 3,
        tags: ["physiome-digest"]
      }),
      signal: ctrl.signal
    });
    if (!res.ok) {
      return { digest: "", error: `memory/query ${res.status}` };
    }
    const payload = parseJsonResponse(await res.text());
    const highlights = Array.isArray(payload?.highlights) ? payload.highlights : [];
    const sorted = highlights
      .filter((h) => cleanString(h?.snippet))
      .sort((a, b) => cleanString(b?.date).localeCompare(cleanString(a?.date)));
    return { digest: cleanString(sorted[0]?.snippet) };
  } catch (err) {
    return { digest: "", error: err.message };
  } finally {
    clearTimeout(timer);
  }
}

function extractRouterCompletionText(payload = {}) {
  return cleanString(
    payload?.choices?.[0]?.message?.content ||
      payload?.choices?.[0]?.text ||
      payload?.output_text ||
      payload?.text ||
      payload?.response
  );
}

async function routerChat({
  model,
  messages,
  temperature = 0.8,
  stream = false,
  timeoutMs = 120000
}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${LITELLM_ROUTER_URL}/v1/chat/completions`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "content-type": "application/json",
        Authorization: "Bearer noauth"
      },
      body: JSON.stringify({
        model,
        messages,
        temperature,
        stream
      }),
      signal: ctrl.signal
    });
    const raw = await res.text();
    const payload = parseJsonResponse(raw);
    if (!res.ok) {
      throw new Error(
        cleanString(payload?.error?.message || payload?.error || payload?.message) ||
          `router chat failed with HTTP ${res.status}`
      );
    }
    if (stream) {
      throw new Error("routerChat(stream=true) is not supported; use streamChatViaRouter");
    }
    const text = extractRouterCompletionText(payload);
    if (!text) {
      throw new Error(`router returned empty completion for model ${model}`);
    }
    return { text, payload, model: cleanObjectString(payload?.model, model) };
  } finally {
    clearTimeout(timer);
  }
}

export async function streamChatViaRouter({
  model,
  messages,
  temperature = 0.8,
  onToken,
  timeoutMs = 180000
}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  let fullText = "";
  try {
    const res = await fetch(`${LITELLM_ROUTER_URL}/v1/chat/completions`, {
      method: "POST",
      headers: {
        Accept: "text/event-stream, application/json",
        "content-type": "application/json",
        Authorization: "Bearer noauth"
      },
      body: JSON.stringify({
        model,
        messages,
        temperature,
        stream: true
      }),
      signal: ctrl.signal
    });

    if (!res.ok) {
      const payload = parseJsonResponse(await res.text());
      throw new Error(
        cleanString(payload?.error?.message || payload?.error || payload?.message) ||
          `router stream failed with HTTP ${res.status}`
      );
    }

    const contentType = cleanString(res.headers.get("content-type")).toLowerCase();
    if (!contentType.includes("text/event-stream") || !res.body) {
      const payload = parseJsonResponse(await res.text());
      const text = extractRouterCompletionText(payload);
      if (text) {
        fullText = text;
        if (typeof onToken === "function") {
          onToken(text);
        }
        return {
          text: fullText,
          model: cleanObjectString(payload?.model, model),
          usage: payload?.usage || null,
          source: "cluster"
        };
      }
      throw new Error("router stream response was not SSE and had no completion text");
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let resolvedModel = model;
    let usage = null;

    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith("data:")) {
          continue;
        }
        const data = trimmed.slice(5).trim();
        if (!data || data === "[DONE]") {
          continue;
        }
        const payload = parseJsonResponse(data);
        resolvedModel = cleanObjectString(payload?.model, resolvedModel);
        if (payload?.usage) {
          usage = payload.usage;
        }
        // Use the RAW token content — cleanString() trims each delta, which eats the
        // leading spaces streamed with most tokens and collapses the reply into one
        // run-on word. Preserve spaces verbatim.
        const deltaRaw = payload?.choices?.[0]?.delta?.content;
        const textRaw = payload?.choices?.[0]?.text;
        const delta = typeof deltaRaw === "string" && deltaRaw.length > 0
          ? deltaRaw
          : (typeof textRaw === "string" ? textRaw : "");
        if (delta) {
          fullText += delta;
          if (typeof onToken === "function") {
            onToken(delta);
          }
        }
      }
    }

    if (!fullText) {
      throw new Error(`router stream returned empty completion for model ${model}`);
    }

    return {
      text: fullText,
      model: resolvedModel,
      usage,
      source: "cluster"
    };
  } finally {
    clearTimeout(timer);
  }
}

const MUSE_MODEL = process.env.PROJECT_COCKPIT_PERSONAL_MUSE_MODEL || "hunyuan-7b";
const PERSONAL_VOICE_MODEL =
  process.env.PROJECT_COCKPIT_PERSONAL_VOICE_MODEL || "hermes-4";

export async function runMuseVoiceEnsemble({
  prompt,
  system = "",
  voiceModel = PERSONAL_VOICE_MODEL,
  onToken
}) {
  const promptText = cleanString(prompt);
  const systemText = cleanString(system);
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

  const museSystem =
    "Gere 3-5 sementes criativas, provocativas e concretas em pt-BR. " +
    "Não escreva resposta final ao usuário. Apenas bullets curtos com ângulos inesperados.";
  let museSeeds = "";
  try {
    const museResult = await routerChat({
      model: MUSE_MODEL,
      messages: [
        { role: "system", content: museSystem },
        { role: "user", content: promptText }
      ],
      temperature: 0.95,
      stream: false,
      timeoutMs: 90000
    });
    museSeeds = museResult.text;
  } catch (err) {
    museSeeds = "";
  }

  const voiceSystemParts = [systemText];
  if (museSeeds) {
    voiceSystemParts.push(
      "## Sementes internas (integrar sem mencionar, sem listar)",
      museSeeds
    );
  }
  const voiceSystem = voiceSystemParts.filter(Boolean).join("\n\n");

  try {
    const voiceResult = await streamChatViaRouter({
      model: cleanString(voiceModel) || PERSONAL_VOICE_MODEL,
      messages: [
        { role: "system", content: voiceSystem },
        { role: "user", content: promptText }
      ],
      temperature: 0.8,
      onToken
    });

    return {
      status: 200,
      payload: {
        text: voiceResult.text,
        response: voiceResult.text,
        model: voiceResult.model,
        provider: voiceResult.model,
        tier: voiceResult.model,
        source: voiceResult.source || "cluster",
        usage: voiceResult.usage || null,
        muse_model: MUSE_MODEL,
        voice_model: cleanString(voiceModel) || PERSONAL_VOICE_MODEL,
        truthMode: "observed",
        beagle_url: `${LITELLM_ROUTER_URL}/v1/chat/completions`
      },
      beagleUrl: LITELLM_ROUTER_URL
    };
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: err.message,
        truthMode: "stale",
        source: "cluster",
        beagle_url: LITELLM_ROUTER_URL
      },
      beagleUrl: LITELLM_ROUTER_URL
    };
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

  const candidates = [
    { label: "dynamo", endpoint: DYNAMO_INTERNAL_URL, model: DYNAMO_MODEL },
    {
      label: "discussion-lab",
      endpoint: DISCUSSION_LAB_INTERNAL_URL,
      model: DISCUSSION_LAB_MODEL
    },
    { label: "sglang", endpoint: SGLANG_INTERNAL_URL, model: SGLANG_MODEL }
  ];
  let lastFailure = null;

  for (const candidate of candidates) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 120000);
    try {
      const res = await fetch(`${candidate.endpoint}/v1/chat/completions`, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "content-type": "application/json"
        },
        body: JSON.stringify({
          model: candidate.model,
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
      const completionResult = {
        status: res.status,
        payload: {
          text: responseText,
          response: responseText,
          provider: cleanString(payload?.model || candidate.model || candidate.label),
          tier: cleanString(payload?.model || candidate.model || candidate.label),
          source: inferCompletionSource(payload),
          agentKind: cleanString(payload?.agentKind || payload?.agent_kind),
          sessionId: cleanString(payload?.sessionId || payload?.session_id),
          podName: cleanString(payload?.podName || payload?.pod_name),
          usage: payload?.usage || {},
          truthMode: res.ok && responseText ? "observed" : "stale",
          raw: payload
        },
        completionPrompt,
        beagleUrl: candidate.endpoint
      };

      if (res.ok && responseText) {
        return completionResult;
      }
      lastFailure = {
        ...completionResult,
        payload: {
          ...completionResult.payload,
          error:
            cleanString(payload?.error || payload?.message) ||
            `completion backend ${candidate.label} returned HTTP ${res.status}`,
          via: `cockpit-beagle-completion:${candidate.label}`
        }
      };
    } catch (err) {
      lastFailure = {
        status: 503,
        payload: {
          error: err.message,
          truthMode: "stale",
          via: `cockpit-beagle-completion:${candidate.label}`,
          beagle_url: candidate.endpoint
        },
        completionPrompt,
        beagleUrl: candidate.endpoint
      };
    } finally {
      clearTimeout(timer);
    }
  }
  return lastFailure || {
    status: 503,
    payload: {
      error: "no completion backend available",
      truthMode: "stale",
      via: "cockpit-beagle-completion"
    },
    completionPrompt,
    beagleUrl: DYNAMO_INTERNAL_URL
  };
}

function normalizeCheapBridgeProvider(provider) {
  const normalized = cleanString(provider).toLowerCase();
  if (!normalized) {
    return "";
  }
  if (["grok", "grok_fast", "grok-fast"].includes(normalized)) {
    return "grok_fast";
  }
  if (["kimi", "kimi_k2", "kimi-k2", "moonshot"].includes(normalized)) {
    return "kimi";
  }
  return "";
}

export async function proxyCheapProviderCompletion({
  prompt,
  system = "",
  provider = "",
  taskType = "chat_completion"
}) {
  const providerId = normalizeCheapBridgeProvider(provider);
  if (!providerId) {
    return {
      status: 400,
      payload: {
        error: `unknown cheap provider: ${provider}`,
        truthMode: "declared",
        source: "cluster"
      }
    };
  }

  if (providerId === "kimi") {
    return proxyOpenRouterCompletion({
      prompt,
      system,
      model: "moonshotai/kimi-k2.6",
      appliedDiscussionProfile: "kimi"
    });
  }

  const tokenResult = await fetchOperatorToken();
  if (tokenResult.error || !tokenResult.token) {
    return {
      status: 503,
      payload: {
        error: tokenResult.error || "beagle token unavailable",
        truthMode: "stale",
        source: "cluster"
      }
    };
  }

  const promptText = cleanString(prompt);
  const systemText = cleanString(system);
  const input = systemText ? `${systemText}\n\n${promptText}` : promptText;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 120000);
  try {
    const requestId = `mobile-${providerId}-${Date.now()}`;
    const res = await fetch(`${BEAGLE_INTERNAL_URL}/api/darwin/bridge/execute`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "content-type": "application/json",
        "X-Beagle-Consumer": "beagle-operator",
        Authorization: `Bearer ${tokenResult.token}`
      },
      body: JSON.stringify({
        request_id: requestId,
        bridge_kind: "cheap_api",
        bridge_mode: "api_optional",
        provider: providerId,
        task_type: taskType,
        payload: {
          input
        },
        metadata: {
          source: "project-cockpit-mobile-chat"
        }
      }),
      signal: ctrl.signal
    });
    const payload = parseJsonResponse(await res.text());
    const responseText = cleanString(payload?.output?.text || payload?.text || payload?.response);
    const errorText = cleanString(payload?.error || payload?.message);
    const statusText = cleanString(payload?.status).toLowerCase();
    const ok = res.ok && statusText === "success" && responseText;
    return {
      status: ok ? 200 : res.ok ? 503 : res.status,
      payload: {
        text: responseText,
        response: responseText,
        provider: cleanObjectString(payload?.model, providerId),
        tier: providerId,
        source: "cluster",
        usage: payload?.token_usage || null,
        truthMode: ok ? "observed" : "stale",
        beagle_url: `${BEAGLE_INTERNAL_URL}/api/darwin/bridge/execute`,
        error:
          errorText ||
          (statusText && statusText !== "success" ? `bridge returned ${statusText}` : ""),
        applied_discussion_profile: providerId === "grok_fast" ? "grok" : "kimi"
      }
    };
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: err.message,
        truthMode: "stale",
        source: "cluster",
        beagle_url: `${BEAGLE_INTERNAL_URL}/api/darwin/bridge/execute`
      }
    };
  } finally {
    clearTimeout(timer);
  }
}

function normalizeSubscriptionBridgeProvider(provider) {
  const normalized = cleanString(provider).toLowerCase();
  if (!normalized) {
    return "";
  }
  if (["claude", "claude-code", "claudecode", "claude_max", "claude-max"].includes(normalized)) {
    return "claude-code";
  }
  if (["codex", "codex-chat", "codex-pro", "chatgpt-pro"].includes(normalized)) {
    return "codex";
  }
  return "";
}

export async function proxySubscriptionBridgeCompletion({
  prompt,
  system = "",
  provider = "",
  projectSlug = "",
  projectFamily = "",
  publicationScope = "",
  readCatalog = null
}) {
  const providerId = normalizeSubscriptionBridgeProvider(provider);
  if (!providerId) {
    return {
      status: 400,
      payload: {
        error: `unknown subscription bridge provider: ${provider}`,
        truthMode: "declared",
        source: "subscription-bridge"
      }
    };
  }

  const workspaceResult = await proxyWorkspaceSubscriptionCompletion({
    prompt,
    system,
    provider: providerId,
    projectSlug,
    readCatalog
  });
  if (workspaceResult) {
    return workspaceResult;
  }

  if (!SUBSCRIPTION_BRIDGE_URL) {
    return {
      status: 503,
      payload: {
        error: "subscription bridge not configured",
        truthMode: "stale",
        source: "subscription-bridge"
      }
    };
  }

  const promptText = cleanString(prompt);
  const systemText = cleanString(system);
  if (!promptText) {
    return {
      status: 400,
      payload: {
        error: "prompt is required",
        truthMode: "declared",
        source: "subscription-bridge"
      }
    };
  }

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 180000);
  try {
    const headers = {
      Accept: "application/json",
      "content-type": "application/json"
    };
    if (SUBSCRIPTION_BRIDGE_TOKEN) {
      headers.Authorization = `Bearer ${SUBSCRIPTION_BRIDGE_TOKEN}`;
    }
    const res = await fetch(`${SUBSCRIPTION_BRIDGE_URL.replace(/\/$/, "")}/v1/chat`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        provider: providerId,
        prompt: promptText,
        system: systemText,
        project_slug: cleanString(projectSlug),
        project_family: cleanString(projectFamily),
        publication_scope: cleanString(publicationScope)
      }),
      signal: ctrl.signal
    });
    const payload = parseJsonResponse(await res.text());
    const responseText = cleanString(payload?.response || payload?.text || payload?.answer);
    const errorText =
      cleanString(payload?.error?.message) ||
      cleanString(payload?.error) ||
      cleanString(payload?.message);
    const ok = res.ok && responseText;
    return {
      status: ok ? 200 : res.status || 503,
      payload: {
        text: responseText,
        response: responseText,
        provider: cleanObjectString(payload?.model || payload?.provider, providerId),
        tier: providerId,
        source: "subscription-bridge",
        usage: payload?.usage || null,
        truthMode: ok ? "observed" : "stale",
        bridge_url: SUBSCRIPTION_BRIDGE_URL,
        error: errorText,
        applied_discussion_profile: providerId,
        agentKind: cleanString(payload?.agentKind || payload?.agent_kind || providerId),
        sessionId: cleanString(payload?.sessionId || payload?.session_id),
        podName: cleanString(payload?.podName || payload?.pod_name)
      }
    };
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: err.message,
        truthMode: "stale",
        source: "subscription-bridge",
        bridge_url: SUBSCRIPTION_BRIDGE_URL
      }
    };
  } finally {
    clearTimeout(timer);
  }
}

export async function proxyOpenRouterCompletion({
  prompt,
  system = "",
  model = "moonshotai/kimi-k2.6",
  appliedDiscussionProfile = "kimi"
}) {
  const keyResult = await fetchOpenRouterApiKey();
  if (keyResult.error || !keyResult.apiKey) {
    return {
      status: 503,
      payload: {
        error: keyResult.error || "openrouter api key unavailable",
        truthMode: "stale",
        source: "cluster"
      }
    };
  }

  const promptText = cleanString(prompt);
  const systemText = cleanString(system);
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

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 120000);
  try {
    const modelCandidates = Array.from(new Set([
      model,
      "moonshotai/kimi-k2.5",
      "moonshotai/kimi-k2",
      "moonshotai/kimi-k2-0905"
    ]));
    let lastFailure = null;

    for (const candidateModel of modelCandidates) {
      const res = await fetch(`${OPENROUTER_BASE_URL}/chat/completions`, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "content-type": "application/json",
          Authorization: `Bearer ${keyResult.apiKey}`
        },
        body: JSON.stringify({
          model: candidateModel,
          temperature: 0.2,
          max_tokens: 512,
          provider: {
            allow_fallbacks: false
          },
          messages: [
            ...(systemText ? [{ role: "system", content: systemText }] : []),
            { role: "user", content: promptText }
          ]
        }),
        signal: ctrl.signal
      });
      const payload = parseJsonResponse(await res.text());
      const responseText = extractOpenRouterText(payload);
      const errorText =
        cleanString(payload?.error?.message) ||
        cleanString(payload?.error) ||
        cleanString(payload?.message);
      const usage = payload?.usage
        ? {
            input_tokens: Number(payload.usage.prompt_tokens) || 0,
            output_tokens: Number(payload.usage.completion_tokens) || 0,
            total_tokens: Number(payload.usage.total_tokens) || 0
          }
        : null;
      if (res.ok && responseText) {
        return {
          status: 200,
          payload: {
            text: responseText,
            response: responseText,
            provider: cleanObjectString(payload?.model, candidateModel),
            tier: "kimi",
            source: "cluster",
            usage,
            truthMode: "observed",
            beagle_url: `${OPENROUTER_BASE_URL}/chat/completions`,
            error: "",
            applied_discussion_profile: appliedDiscussionProfile
          }
        };
      }
      lastFailure = {
        status: res.status,
        error: errorText || `openrouter returned ${res.status}`,
        provider: cleanObjectString(payload?.model, candidateModel),
        usage
      };
      if (![402, 429, 503].includes(res.status)) {
        break;
      }
    }

    return {
      status: lastFailure?.status || 503,
      payload: {
        text: "",
        response: "",
        provider: cleanObjectString(lastFailure?.provider, model),
        tier: "kimi",
        source: "cluster",
        usage: lastFailure?.usage || null,
        truthMode: "stale",
        beagle_url: `${OPENROUTER_BASE_URL}/chat/completions`,
        error: lastFailure?.error || "openrouter completion failed",
        applied_discussion_profile: appliedDiscussionProfile
      }
    };
  } catch (err) {
    return {
      status: 503,
      payload: {
        error: err.message,
        truthMode: "stale",
        source: "cluster",
        beagle_url: `${OPENROUTER_BASE_URL}/chat/completions`
      }
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
