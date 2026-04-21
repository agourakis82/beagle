// auth-bridge/server.mjs
//
// Minimal standalone auth bridge — single responsibility, small blast
// radius. Reads the beagle operator token from cluster Secret once, caches
// it 5min, and serves it to MCP / iOS / cockpit / ChatGPT on demand.
//
// Replaces the /api/auth/beagle-token endpoint previously baked into
// cockpit's Express server. Cockpit's version remains as a forwarder for
// backward compat; new clients should hit this host directly.
//
// Endpoints:
//   GET /health                     — liveness (no auth)
//   GET /api/auth/beagle-token      — returns {token, consumer, ...}
//   GET /api/auth/beagle-discover   — endpoint catalog for bootstrap
//
// All endpoints are read-only, no auth required on the bridge itself —
// the service assumes Tailnet / network boundary already enforces trust.
// Scope this pod tightly via RBAC + NetworkPolicy before exposing publicly.

import http from "node:http";
import https from "node:https";
import fs from "node:fs";

const PORT = Number(process.env.PORT || 7070);
const NAMESPACE = process.env.NAMESPACE || "beagle";
const SECRET_NAME = process.env.SECRET_NAME || "beagle-core-secrets";
const TOKEN_TTL_MS = 5 * 60 * 1000;
const BEAGLE_URL =
  process.env.BEAGLE_URL || "http://beagle-core.tail21cbc4.ts.net";
const CLUSTER_URL =
  process.env.BEAGLE_CLUSTER_URL ||
  "http://beagle-core.beagle.svc.cluster.local:8080";

// In-pod paths injected by the Kubernetes ServiceAccount projected volume.
const SA_TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token";
const SA_CA_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
const API_HOST = process.env.KUBERNETES_SERVICE_HOST || "kubernetes.default.svc";
const API_PORT = Number(process.env.KUBERNETES_SERVICE_PORT || 443);

let cached = null;
let cachedAt = 0;
let caPem = null;
try {
  caPem = fs.readFileSync(SA_CA_PATH, "utf8");
} catch (e) {
  console.warn("warning: cannot read SA CA cert:", e.message);
}

function readSaToken() {
  return fs.readFileSync(SA_TOKEN_PATH, "utf8").trim();
}

/**
 * Read a Secret via the Kubernetes API directly — no kubectl subprocess,
 * no memory blow-up. Uses the pod's mounted SA token for auth and the
 * mounted CA cert for TLS.
 */
function kubeGetSecret() {
  return new Promise((resolve, reject) => {
    const saToken = readSaToken();
    const path = `/api/v1/namespaces/${encodeURIComponent(NAMESPACE)}/secrets/${encodeURIComponent(SECRET_NAME)}`;
    const req = https.request(
      {
        host: API_HOST,
        port: API_PORT,
        path,
        method: "GET",
        headers: {
          Authorization: `Bearer ${saToken}`,
          Accept: "application/json"
        },
        ca: caPem,
        timeout: 8000
      },
      (res) => {
        let body = "";
        res.setEncoding("utf8");
        res.on("data", (c) => (body += c));
        res.on("end", () => {
          if (res.statusCode !== 200) {
            reject(new Error(`kube api ${res.statusCode}: ${body.slice(0, 200)}`));
            return;
          }
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            reject(e);
          }
        });
      }
    );
    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy(new Error("kube api timeout"));
    });
    req.end();
  });
}

async function fetchToken() {
  const now = Date.now();
  if (cached && now - cachedAt < TOKEN_TTL_MS) {
    return { token: cached, source: "cache", age_ms: now - cachedAt };
  }
  const secret = await kubeGetSecret();
  const data = secret.data || {};
  const candidateKeys = [
    "BEAGLE_OPERATOR_API_TOKEN",
    "BEAGLE_API_TOKEN",
    "operator-token"
  ];
  let token = null;
  let key = null;
  for (const k of candidateKeys) {
    if (data[k]) {
      token = Buffer.from(data[k], "base64").toString("utf8");
      key = k;
      break;
    }
  }
  if (!token) {
    throw new Error(
      `no token found in secret ${SECRET_NAME} (tried: ${candidateKeys.join(", ")})`
    );
  }
  cached = token;
  cachedAt = now;
  return { token, source: "fresh", key };
}

const server = http.createServer(async (req, res) => {
  // Basic CORS so cockpit UI / iOS webview can call cross-origin.
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-headers", "content-type, authorization");

  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, service: "auth-bridge" }));
    return;
  }

  if (req.url === "/api/auth/beagle-token") {
    try {
      const result = await fetchToken();
      res.writeHead(200, { "content-type": "application/json" });
      res.end(
        JSON.stringify({
          token: result.token,
          consumer: "beagle-operator",
          auth_header_value: `Bearer ${result.token}`,
          consumer_header_name: "X-Beagle-Consumer",
          consumer_header_value: "beagle-operator",
          beagle_url: BEAGLE_URL,
          cluster_internal_url: CLUSTER_URL,
          cached: result.source === "cache",
          cache_ttl_ms: TOKEN_TTL_MS,
          truthMode: "observed",
          issued_at: new Date().toISOString()
        })
      );
    } catch (e) {
      res.writeHead(503, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: e.message, truthMode: "stale" }));
    }
    return;
  }

  if (req.url === "/api/auth/beagle-discover") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(
      JSON.stringify({
        beagle_url: BEAGLE_URL,
        cluster_internal_url: CLUSTER_URL,
        auth: {
          consumer_header: "X-Beagle-Consumer",
          consumer_values: ["beagle-operator", "darwin-research"],
          auth_header: "Authorization",
          auth_format: "Bearer <token>",
          token_endpoint: "/api/auth/beagle-token"
        },
        endpoints: {
          health: "GET /health",
          cognitive_state: "GET /api/v1/cognitive/state",
          cognitive_stream: "GET /api/v1/cognitive/stream",
          phi_of_phi: "GET /api/v1/cognitive/phi_of_phi",
          meta_phi: "GET /api/v1/cognitive/meta_phi",
          tool_rhythm_phi: "GET /api/v1/cognitive/tool_rhythm_phi",
          mcp_tool_call: "POST /api/cognitive/mcp_tool_call",
          exocortex: "POST /api/exocortex/process",
          fractal: "POST /api/fractal/recurse",
          deep_think: "POST /api/cognitive/deep-think",
          void: "POST /dev/void",
          physio: "POST /api/observer/physio"
        },
        truthMode: "observed",
        generated_at: new Date().toISOString()
      })
    );
    return;
  }

  res.writeHead(404, { "content-type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`auth-bridge listening on :${PORT} (namespace=${NAMESPACE}, secret=${SECRET_NAME})`);
});
