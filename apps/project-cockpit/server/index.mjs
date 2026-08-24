import express from "express";
import http from "node:http";
import https from "node:https";
import path from "node:path";
import fs from "node:fs/promises";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { spawn, execFile as nodeExecFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";
import pty from "node-pty";
import { registerManifestRoutes } from "./contract.mjs";
import { registerMobileRoutes } from "./mobile-routes.mjs";
import {
  registerAgentRoutes,
  registerAgentWebSocket as attachAgentWebSocket,
} from "./agent-routes.mjs";
import { isT560Kind } from "./platform-bridge.mjs";
import { mountLoom } from "./loom/mount.mjs";
import {
  registerWorkspaceRoutes,
  registerWorkspaceWebSocket as attachWorkspaceWebSocket,
} from "./workspace-routes.mjs";
import { registerScratchpadRoutes } from "./scratchpad-routes.mjs";
import { registerPlatformRoutes } from "./platform-routes.mjs";
import { OficinaPoller, registerOficinaRoutes } from "./oficina.mjs";
import { ClaimRegistry, HazardPoller, registerCoordRoutes } from "./coord.mjs";
import { registerLaneActionRoutes } from "./laneActions.mjs";
import { classifyAuth, wsAuthInputs } from "./auth-gate.mjs";
import { workspaceQueryArgv as coordQueryArgv } from "./platform-bridge.mjs";
import { registerJobRoutes } from "./job-routes.mjs";
import { registerQueueRoutes } from "./queue-routes.mjs";
import { registerAuthBridgeRoutes, fetchOperatorToken, warmCompanionDigests } from "./auth-bridge.mjs";
import { startJobReconciler } from "./job-reconciler.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDirCandidates = [
  cleanValue(process.env.PROJECT_COCKPIT_ROOT_DIR),
  path.resolve(__dirname, ".."),
  path.resolve(__dirname, "..", ".."),
].filter(Boolean);
const rootDir =
  rootDirCandidates.find((candidate) =>
    existsSync(path.join(candidate, "public", "project-catalog.json")) ||
    existsSync(path.join(candidate, "package.json"))
  ) || path.resolve(__dirname, "..");
const runtimeCatalogPath = path.join(__dirname, "project-catalog.json");
const publicCatalogPath = existsSync(runtimeCatalogPath)
  ? runtimeCatalogPath
  : path.join(rootDir, "public", "project-catalog.json");
const distDir = path.join(rootDir, "dist");
const port = Number(process.env.PROJECT_COCKPIT_PORT || 4370);
const host = process.env.PROJECT_COCKPIT_HOST || "0.0.0.0";
const kubectlBin = process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl";
const sessionStatePath =
  process.env.PROJECT_COCKPIT_SESSION_STATE || "/tmp/project-cockpit/session-state.json";
const sessionTtlMs = Number(process.env.PROJECT_COCKPIT_SESSION_TTL_MS || 15 * 60 * 1000);
const memoryCacheTtlMs = Number(process.env.PROJECT_COCKPIT_MEMORY_CACHE_TTL_MS || 10000);
const fastMemoryCacheTtlMs = Number(process.env.PROJECT_COCKPIT_FAST_MEMORY_CACHE_TTL_MS || 5000);
const fastVsixCacheTtlMs = Number(process.env.PROJECT_COCKPIT_FAST_VSIX_CACHE_TTL_MS || 60000);
const fastPublicationCacheTtlMs = Number(
  process.env.PROJECT_COCKPIT_FAST_PUBLICATION_CACHE_TTL_MS || 30000
);
const fastClusterCacheTtlMs = Number(
  process.env.PROJECT_COCKPIT_FAST_CLUSTER_CACHE_TTL_MS || 30000
);
const operationalTruthCacheTtlMs = Number(
  process.env.PROJECT_COCKPIT_OPERATIONAL_TRUTH_CACHE_TTL_MS || 15000
);
const operationalTruthTimeoutMs = Number(
  process.env.PROJECT_COCKPIT_OPERATIONAL_TRUTH_TIMEOUT_MS || 2500
);
const fastGitStatusTimeoutMs = Number(
  process.env.PROJECT_COCKPIT_FAST_GIT_STATUS_TIMEOUT_MS || 5000
);
const fastPrPreviewTimeoutMs = Number(
  process.env.PROJECT_COCKPIT_FAST_PR_PREVIEW_TIMEOUT_MS || 5000
);
const fastPublicationResponseTimeoutMs = Number(
  process.env.PROJECT_COCKPIT_FAST_PUBLICATION_RESPONSE_TIMEOUT_MS || 7000
);
const startupFastPublicationTimeoutMs = Number(
  process.env.PROJECT_COCKPIT_STARTUP_FAST_PUBLICATION_TIMEOUT_MS || 7000
);
const fastMemoryResponseTimeoutMs = Number(
  process.env.PROJECT_COCKPIT_FAST_MEMORY_RESPONSE_TIMEOUT_MS || 20000
);
const startupFastMemoryTimeoutMs = Number(
  process.env.PROJECT_COCKPIT_STARTUP_FAST_MEMORY_TIMEOUT_MS || 25000
);
const catalogExecutiveCacheTtlMs = Number(
  process.env.PROJECT_COCKPIT_CATALOG_EXECUTIVE_CACHE_TTL_MS || 10000
);
const memoryWarmIntervalMs = Number(
  process.env.PROJECT_COCKPIT_MEMORY_WARM_INTERVAL_MS || 20000
);
const disableMemoryWarmers =
  String(process.env.PROJECT_COCKPIT_DISABLE_MEMORY_WARMERS || "")
    .trim()
    .toLowerCase() === "true";
// Dedicated LIGHT warmer for the personal-companion grounding digests — independent of the
// heavier dashboard warmers above (which stay disabled). Keeps the first chat message fast.
const companionWarmEnabled =
  String(process.env.PROJECT_COCKPIT_COMPANION_WARM || "on").trim().toLowerCase() !== "off";
const companionWarmIntervalMs = Number(
  process.env.PROJECT_COCKPIT_COMPANION_WARM_INTERVAL_MS || 240000
);
const datasetMetadataCacheTtlMs = Number(
  process.env.PROJECT_COCKPIT_DATASET_METADATA_CACHE_TTL_MS || 5 * 60 * 1000
);
const inferenceProbeTimeoutMs = Number(
  process.env.PROJECT_COCKPIT_INFERENCE_PROBE_TIMEOUT_MS || 1200
);
const inferenceRuntimeCacheTtlMs = Number(
  process.env.PROJECT_COCKPIT_INFERENCE_RUNTIME_CACHE_TTL_MS || 15000
);
const inferenceWorkloadTimeoutMs = Number(
  process.env.PROJECT_COCKPIT_INFERENCE_WORKLOAD_TIMEOUT_MS || 2500
);
const inferencePrereqCacheTtlMs = Number(
  process.env.PROJECT_COCKPIT_INFERENCE_PREREQ_CACHE_TTL_MS || 30000
);
const scientificWorkflowCheckCacheTtlMs = Number(
  process.env.PROJECT_COCKPIT_SCIENTIFIC_CHECK_CACHE_TTL_MS || 5 * 60 * 1000
);
const rememberedStateConfigMapName =
  process.env.PROJECT_COCKPIT_REMEMBERED_STATE_CONFIGMAP || "project-cockpit-remembered";
const rememberedStateDir =
  process.env.PROJECT_COCKPIT_REMEMBERED_STATE_DIR || "/var/run/project-cockpit-remembered";
const defaultPrometheusBaseUrl =
  process.env.PROJECT_COCKPIT_PROMETHEUS_URL ||
  process.env.DARWIN_OBSERVABILITY_PROMETHEUS_URL ||
  "";
const gpuorangefsAutohealPromPath =
  process.env.PROJECT_COCKPIT_GPUORANGEFS_AUTOHEAL_PROM ||
  "/var/lib/node_exporter/textfile/slurm_gpuorangefs_autoheal.prom";
const researchOperationsPromPath =
  process.env.PROJECT_COCKPIT_RESEARCH_OPERATIONS_PROM ||
  "/var/lib/node_exporter/textfile/sounio_abide_runner.prom";
const inferenceNamespace = process.env.PROJECT_COCKPIT_INFERENCE_NAMESPACE || "beagle";
const sglangDeploymentName = process.env.PROJECT_COCKPIT_SGLANG_DEPLOYMENT || "sglang-serving";
const sglangServiceName = process.env.PROJECT_COCKPIT_SGLANG_SERVICE || "sglang-serving";
const dynamoDeploymentName =
  process.env.PROJECT_COCKPIT_DYNAMO_DEPLOYMENT || "dynamo-control-plane";
const dynamoServiceName = process.env.PROJECT_COCKPIT_DYNAMO_SERVICE || "dynamo-control-plane";
const defaultSglangEndpoint =
  process.env.PROJECT_COCKPIT_SGLANG_ENDPOINT ||
  process.env.BEAGLE_SGLANG_URL ||
  `http://${sglangServiceName}.${inferenceNamespace}.svc.cluster.local:30000`;
const defaultDynamoEndpoint =
  process.env.PROJECT_COCKPIT_DYNAMO_ENDPOINT ||
  process.env.BEAGLE_DYNAMO_URL ||
  `http://${dynamoServiceName}.${inferenceNamespace}.svc.cluster.local:8000`;
const compatVllmEndpoint =
  process.env.PROJECT_COCKPIT_VLLM_ENDPOINT || process.env.BEAGLE_VLLM_URL || "";
const serviceAccountRoot = "/var/run/secrets/kubernetes.io/serviceaccount";
const serviceAccountTokenPath = path.join(serviceAccountRoot, "token");
const serviceAccountCaPath = path.join(serviceAccountRoot, "ca.crt");
const inClusterServer =
  process.env.KUBERNETES_SERVICE_HOST && process.env.KUBERNETES_SERVICE_PORT
    ? `https://${process.env.KUBERNETES_SERVICE_HOST}:${process.env.KUBERNETES_SERVICE_PORT}`
    : "";
const inClusterToken = existsSync(serviceAccountTokenPath)
  ? cleanValue(readFileSync(serviceAccountTokenPath, "utf8"))
  : "";
const inClusterCa = existsSync(serviceAccountCaPath)
  ? readFileSync(serviceAccountCaPath)
  : null;
const inClusterAgent =
  inClusterServer && inClusterToken && inClusterCa
    ? new https.Agent({
        keepAlive: true,
        ca: inClusterCa
      })
    : null;

const clusterDoctorBundle = [
  "workspace-platform-doctor",
  "hpc-route-doctor",
  "slurmdbd-backend-doctor"
];
const workspaceMemoryCache = new Map();
const fastWorkspaceMemoryCache = new Map();
const fastVsixStatusCache = new Map();
const fastPublicationStateCache = new Map();
const fastClusterStateCache = new Map();
const operationalTruthCache = new Map();
const datasetMetadataCache = new Map();
const scientificWorkflowCheckCache = new Map();
const inferenceRuntimeCache = new Map();
const inferencePrereqCache = new Map();
let catalogExecutiveCache = null;
let startupWarmState = {
  status: "booting",
  lastAttemptAt: "",
  lastReadyAt: "",
  lastError: ""
};
let startupWarmPromise = null;
const allowedCorsOrigins = new Set([
  "http://100.107.208.198",
  "http://sounio-cockpit.tail21cbc4.ts.net"
]);

const SUPERCOMPUTING_RESEARCH_BRIEF = {
  generatedAt: "2026-04-09T00:00:00.000Z",
  title: "Sovereign supercomputing playground brief",
  horizon: "exascale + AI + scientific visualization + sovereign provenance",
  pillars: [
    {
      name: "Compute frontier",
      summary: "Exascale systems are operational, so the product should treat simulation, AI, and data movement as one workflow.",
      implication: "Mission control must reason across jobs, models, datasets, and publication state."
    },
    {
      name: "Visualization frontier",
      summary: "Remote and parallel visualization remain canonical, so browser rendering and backend-authoritative viewing should coexist.",
      implication: "Viewer truth must stay explicit instead of assuming the browser is the authority."
    },
    {
      name: "Data substrate",
      summary: "OME-Zarr/NGFF continues to validate multiscale, chunked, transform-aware scientific datasets as the right default target.",
      implication: "Dataset lanes should preserve multiscale metadata, provenance, and runtime truth."
    },
    {
      name: "Runtime strategy",
      summary: "WebGPU is strategically right across web, desktop, and Apple platforms, but runtime truth still matters more than optimistic assumptions.",
      implication: "Renderer state must stay observed/remembered/declared instead of pretending success."
    },
    {
      name: "Cognitive substrate",
      summary: "LLM routing and graph-native provenance belong inside the playground, not bolted on afterward.",
      implication: "Beagle should route agents, preserve lineage, and surface the next executable move."
    }
  ],
  recommendedMoves: [
    "Keep Sounio as the deep proof surface while widening the playground API.",
    "Treat Beagle routing and graph lineage as first-class runtime surfaces.",
    "Keep WebGPU-first rendering honest by publishing runtime diagnostics and provenance alongside scene state."
  ],
  sources: [
    {
      label: "TOP500 lists",
      url: "https://top500.org/lists/top500/"
    },
    {
      label: "LLNL El Capitan fact sheet",
      url: "https://www.llnl.gov/sites/www/files/2024-12/llnl-el-capitan-fact-sheet.pdf"
    },
    {
      label: "NGFF / OME-Zarr",
      url: "https://ngff.openmicroscopy.org/"
    },
    {
      label: "OME-Zarr docs",
      url: "https://ome-zarr.readthedocs.io/en/stable/"
    },
    {
      label: "WebGPU W3C",
      url: "https://www.w3.org/TR/webgpu/"
    }
  ]
};

// Minimal declared fallback — used only if public/project-catalog.json is missing or malformed.
// Keeps the cockpit responsive with truthMode: "declared" instead of 500ing.
const CATALOG_DECLARED_FALLBACK = {
  generatedAt: "2026-01-01T00:00:00.000Z",
  source: "policy-fallback",
  projects: [
    {
      mode: "always-on",
      projectSlug: "sounio",
      namespace: "beagle",
      workspaceRoot: "/workspace/sounio",
      branch: "main",
      preferredPrBase: "integration/sounio-dev-ready-base"
    }
  ]
};

async function loadCatalog() {
  try {
    const raw = await fs.readFile(publicCatalogPath, "utf8");
    const parsed = JSON.parse(raw);
    return {
      ...parsed,
      projects: Array.isArray(parsed.projects)
        ? parsed.projects.map((project) => normalizeProjectCatalogProject(project))
        : []
    };
  } catch (err) {
    console.warn(`[cockpit] catalog load failed (${err.message}), serving declared fallback`);
    return {
      ...CATALOG_DECLARED_FALLBACK,
      projects: CATALOG_DECLARED_FALLBACK.projects.map((p) => normalizeProjectCatalogProject(p))
    };
  }
}

async function getProjectOrThrow(slug) {
  const catalog = await loadCatalog();
  const project = catalog.projects.find((item) => item.projectSlug === slug);
  if (!project) {
    const error = new Error(`unknown project slug: ${slug}`);
    error.statusCode = 404;
    throw error;
  }
  return project;
}

function runCommand(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const child = spawn(command, args, {
      env: { ...process.env, ...(options.env || {}) },
      cwd: options.cwd || process.cwd(),
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    const ignoreBenignPipeError = (error) => {
      if (["ENOTCONN", "EPIPE", "ECONNRESET"].includes(error?.code)) {
        return;
      }
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(error);
      }
    };

    child.stdout.on("error", ignoreBenignPipeError);
    child.stderr.on("error", ignoreBenignPipeError);

    const timer =
      Number(options.timeoutMs || 0) > 0
        ? setTimeout(() => {
            if (settled) {
              return;
            }
            settled = true;
            try {
              child.kill("SIGKILL");
            } catch {
              // ignore
            }
            const error = new Error(`${command} timed out after ${options.timeoutMs}ms`);
            error.stdout = stdout;
            error.stderr = stderr;
            error.code = "ETIMEDOUT";
            reject(error);
          }, Number(options.timeoutMs))
        : null;

    child.on("error", (error) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(error);
      }
    });
    child.on("close", (code) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      if (code === 0) {
        resolve({ stdout, stderr, code });
        return;
      }
      const error = new Error(stderr || stdout || `${command} exited with code ${code}`);
      error.stdout = stdout;
      error.stderr = stderr;
      error.code = code;
      reject(error);
    });
  });
}

function runShell(script, options = {}) {
  return runCommand("/bin/sh", ["-lc", script], options);
}

async function withTimeout(promise, label, timeoutMs = 15000) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => {
          const error = new Error(`${label} timed out after ${timeoutMs}ms`);
          error.statusCode = 504;
          reject(error);
        }, timeoutMs);
      })
    ]);
  } finally {
    clearTimeout(timer);
  }
}

function sanitizePtyOutput(value) {
  return String(value || "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, "")
    .replace(/\u001b][^\u0007]*(?:\u0007|\u001b\\)/g, "");
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\"'\"'`)}'`;
}

function runKubectl(args, options = {}) {
  return runCommand(kubectlBin, args, options);
}

function buildKubectlCliArgs(args) {
  if (!inClusterServer || !existsSync(serviceAccountTokenPath) || !existsSync(serviceAccountCaPath)) {
    return args;
  }

  if (!inClusterToken) {
    return args;
  }

  return [
    "--server",
    inClusterServer,
    "--token",
    inClusterToken,
    "--certificate-authority",
    serviceAccountCaPath,
    "--request-timeout",
    "15s",
    ...args
  ];
}

function runKubectlCli(args, options = {}) {
  const commandLine = [kubectlBin, ...buildKubectlCliArgs(args)].map(shellQuote).join(" ");
  return runCommand("/bin/sh", ["-lc", commandLine], options);
}

function runPtyCommand(command, args, options = {}) {
  const timeoutMs = Number(options.timeoutMs || 20000);
  return new Promise((resolve, reject) => {
    let stdout = "";
    let settled = false;

    const proc = pty.spawn(command, args, {
      name: "xterm-256color",
      cols: Number(options.cols || 120),
      rows: Number(options.rows || 40),
      cwd: options.cwd || process.cwd(),
      env: { ...process.env, ...(options.env || {}) }
    });

    const timer = setTimeout(() => {
      if (settled) {
        return;
      }
      settled = true;
      try {
        proc.kill();
      } catch {
        // ignore
      }
      const error = new Error(`${command} timed out after ${timeoutMs}ms`);
      error.stdout = sanitizePtyOutput(stdout);
      error.stderr = "";
      error.code = "ETIMEDOUT";
      reject(error);
    }, timeoutMs);

    proc.onData((data) => {
      stdout += data;
    });

    proc.onExit(({ exitCode, signal }) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      const cleanStdout = sanitizePtyOutput(stdout);
      if (exitCode === 0) {
        resolve({ stdout: cleanStdout, stderr: "", code: 0, signal });
        return;
      }
      const error = new Error(cleanStdout || `${command} exited with code ${exitCode}`);
      error.stdout = cleanStdout;
      error.stderr = "";
      error.code = exitCode;
      error.signal = signal;
      reject(error);
    });
  });
}

async function runKubectlPty(args, options = {}) {
  return runPtyCommand(kubectlBin, buildKubectlCliArgs(args), options);
}

async function runKubectlJson(args, options = {}) {
  const { stdout } = await runKubectlCli([...args, "-o", "json"], options);
  return JSON.parse(stdout);
}

function kubeRequest(
  pathname,
  { method = "GET", body = null, headers = {}, timeoutMs = 5000 } = {}
) {
  if (!inClusterServer || !inClusterToken || !inClusterAgent) {
    const error = new Error("in-cluster Kubernetes credentials are not available");
    error.statusCode = 500;
    return Promise.reject(error);
  }

  const payload = body ? JSON.stringify(body) : "";

  return new Promise((resolve, reject) => {
    const req = https.request(
      `${inClusterServer}${pathname}`,
      {
        method,
        agent: inClusterAgent,
        headers: {
          Authorization: `Bearer ${inClusterToken}`,
          Accept: "application/json",
          ...(body ? { "Content-Type": "application/json" } : {}),
          ...(payload ? { "Content-Length": Buffer.byteLength(payload) } : {}),
          ...headers
        }
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => {
          data += chunk.toString();
        });
        res.on("end", () => {
          if ((res.statusCode || 500) >= 200 && (res.statusCode || 500) < 300) {
            resolve(data);
            return;
          }
          const error = new Error(data || `kubernetes api request failed: ${res.statusCode}`);
          error.statusCode = res.statusCode || 500;
          error.responseBody = data;
          reject(error);
        });
      }
    );

    req.setTimeout(timeoutMs, () => {
      req.destroy(new Error(`kubernetes api request timed out after ${timeoutMs}ms`));
    });
    req.on("error", reject);
    if (payload) {
      req.write(payload);
    }
    req.end();
  });
}

async function kubeRequestJson(pathname, options = {}) {
  const raw = await kubeRequest(pathname, options);
  return raw ? JSON.parse(raw) : {};
}

function canUseInClusterKubeApi() {
  return Boolean(inClusterServer && inClusterToken && inClusterAgent);
}

async function readKubeJsonWithFallback(pathname, kubectlArgs, options = {}) {
  if (canUseInClusterKubeApi()) {
    try {
      return await kubeRequestJson(pathname, options);
    } catch (error) {
      if (options.allowKubectlFallback === false) {
        throw error;
      }
    }
  }
  return runKubectlJson(kubectlArgs, { timeoutMs: options.timeoutMs || 5000 });
}

function rememberedStateKey(projectSlug) {
  return `${cleanValue(projectSlug || "project") || "project"}.json`;
}

function scientificWorkflowStateKey(projectSlug) {
  return `${cleanValue(projectSlug || "project") || "project"}-scientific-checks.json`;
}

function getServiceEnvBaseUrl(serviceName, defaultPort) {
  const normalizedName = cleanValue(serviceName)
    .replace(/[^A-Za-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .toUpperCase();
  if (!normalizedName) {
    return "";
  }
  const host = cleanValue(process.env[`${normalizedName}_SERVICE_HOST`] || "");
  const port = cleanValue(process.env[`${normalizedName}_SERVICE_PORT`] || String(defaultPort || ""));
  if (!host || !port) {
    return "";
  }
  return normalizeHttpBaseUrl(`http://${host}:${port}`);
}

function resolvePrometheusBaseUrl() {
  return normalizeHttpBaseUrl(
    defaultPrometheusBaseUrl ||
      getServiceEnvBaseUrl("darwin-observability-prometheus", 9090) ||
      "http://darwin-observability-prometheus.darwin-platform.svc.cluster.local:9090"
  );
}

function getCachedOperationalTruth(cacheKey, { allowStale = false } = {}) {
  const cached = operationalTruthCache.get(cacheKey);
  if (!cached) {
    return null;
  }
  const isStale = Date.now() - cached.at > operationalTruthCacheTtlMs;
  if (isStale && !allowStale) {
    return null;
  }
  return { ...cached, isStale };
}

function setCachedOperationalTruth(cacheKey, value, promise = null) {
  operationalTruthCache.set(cacheKey, {
    at: Date.now(),
    value,
    promise
  });
}

function invalidateOperationalTruth(cacheKey) {
  operationalTruthCache.delete(cacheKey);
}

function metricTimestampToIso(value) {
  const numeric = Number(value || 0);
  if (!Number.isFinite(numeric) || numeric <= 0) {
    return "";
  }
  return new Date(numeric * 1000).toISOString();
}

function parsePrometheusLabels(raw = "") {
  const labels = {};
  const pattern = /([A-Za-z_][A-Za-z0-9_]*)="((?:\\.|[^"])*)"/g;
  let match = null;
  while ((match = pattern.exec(raw))) {
    labels[match[1]] = match[2]
      .replace(/\\n/g, "\n")
      .replace(/\\"/g, "\"")
      .replace(/\\\\/g, "\\");
  }
  return labels;
}

function parsePrometheusTextSamples(text = "") {
  return String(text || "")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"))
    .map((line) => {
      const match = line.match(
        /^([A-Za-z_:][A-Za-z0-9_:]*)(?:\{([^}]*)\})?\s+([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|[-+]?Inf|NaN)(?:\s+(\d+))?$/
      );
      if (!match) {
        return null;
      }
      return {
        name: match[1],
        labels: parsePrometheusLabels(match[2] || ""),
        value: Number(match[3]),
        timestamp: Number(match[4] || 0)
      };
    })
    .filter(Boolean);
}

async function readPrometheusTextfileSamples(filePath) {
  if (!existsSync(filePath)) {
    return [];
  }
  const raw = await fs.readFile(filePath, "utf8");
  return parsePrometheusTextSamples(raw);
}

async function queryPrometheusSamples(query, timeoutMs = operationalTruthTimeoutMs) {
  const baseUrl = resolvePrometheusBaseUrl();
  if (!baseUrl) {
    throw new Error("prometheus endpoint is not configured");
  }
  const url = `${baseUrl}/api/v1/query?query=${encodeURIComponent(query)}`;
  const payload = await fetchRemoteJson(url, timeoutMs);
  if (payload?.status !== "success") {
    throw new Error("prometheus query failed");
  }
  return Array.isArray(payload?.data?.result)
    ? payload.data.result.map((entry) => ({
        name: cleanValue(entry?.metric?.__name__ || ""),
        labels: Object.fromEntries(
          Object.entries(entry?.metric || {}).filter(([key]) => key !== "__name__")
        ),
        value: Number(entry?.value?.[1] || 0),
        timestamp: Number(entry?.value?.[0] || 0)
      }))
    : [];
}

function pickMetricSample(samples, metricName) {
  return samples.find((sample) => sample.name === metricName) || null;
}

function pickMetricSamples(samples, metricName) {
  return samples.filter((sample) => sample.name === metricName);
}

function buildOperationalTruthMeta(source = "policy-fallback", at = "") {
  if (source === "prometheus" || source === "textfile") {
    return {
      source,
      truthMode: "observed",
      at
    };
  }
  return {
    source: "policy-fallback",
    truthMode: "declared",
    at: ""
  };
}

function decodePayloadTransferMode(code) {
  const numeric = Number(code);
  if (numeric === 1) {
    return "embedded";
  }
  if (numeric === 2) {
    return "sbcast";
  }
  return "unknown";
}

function decodePersistMode(code) {
  const numeric = Number(code);
  if (numeric === 1) {
    return "orangefs";
  }
  if (numeric === 2) {
    return "worker_local";
  }
  return "unknown";
}

function classifyLatestResearchOperation(ageSeconds) {
  const numeric = Number(ageSeconds);
  if (!Number.isFinite(numeric) || numeric < 0) {
    return "unobserved";
  }
  if (numeric < 30 * 60) {
    return "fresh";
  }
  if (numeric < 6 * 60 * 60) {
    return "recent";
  }
  return "stale";
}

function buildClusterLaneNextSafeMove(status) {
  if (status === "healthy") {
    return "keep the admitted gpuorangefs workers steady and treat new mutations as explicit operator actions";
  }
  if (status === "healing") {
    return "let autoheal finish and avoid pushing the lane harder until the worker set settles again";
  }
  if (status === "degraded") {
    return "re-run the gpuorangefs gate before trusting fresh research submissions on this lane";
  }
  if (status === "planned") {
    return "admit a healthy worker before treating this lane as an execution surface";
  }
  return "observe the lane directly before relying on it for a new research operation";
}

function buildClusterLaneOperatorNote(status) {
  if (status === "healthy") {
    return "cluster truth here is admission-scoped infrastructure truth, not a summary of whichever research job ran last";
  }
  if (status === "healing") {
    return "the lane is mid-repair, so cluster truth is more important than any single job outcome right now";
  }
  if (status === "degraded") {
    return "treat the worker pool as suspect until the gate passes again";
  }
  return "cluster truth is present but not yet strong enough to ground a mission-control claim";
}

function buildResearchOperationArtifacts(runId = "", persistMode = "") {
  const safeRunId = cleanValue(runId);
  if (!safeRunId || safeRunId === "unknown") {
    return {
      destinationDir: "",
      recoveryCommand: ""
    };
  }

  const destinationDir = `/home/devsounio/sounio/artifacts/research/abide/${safeRunId}`;
  const normalizedPersistMode = cleanValue(persistMode);
  const fetchScript =
    normalizedPersistMode === "orangefs"
      ? "/home/devsounio/sounio/scripts/gpu/fetch_abide_campaign_from_orangefs.sh"
      : "/home/devsounio/sounio/scripts/gpu/fetch_abide_campaign_by_run_id.sh";

  return {
    destinationDir,
    recoveryCommand: `${fetchScript} --run-id ${safeRunId} --dest-dir ${destinationDir}`
  };
}

function buildResearchOperationNextSafeMove(status, latestOperation) {
  if (!latestOperation?.runId) {
    return "submit the next research run only after the cluster lane you want to use is healthy";
  }
  if (status === "fresh") {
    return "inspect the active run before launching another one, unless you are intentionally parallelizing research lanes";
  }
  if (status === "recent") {
    return "recover the latest run bundle, read the result packet, and then decide whether the next move is another submit or analysis";
  }
  if (status === "stale") {
    return "treat the last run as historical context, recover its artifacts if needed, and submit a fresh run only if the current question still stands";
  }
  return "use the latest observed run as an operation packet, not as a permanent property of the cluster";
}

function buildResearchOperationOperatorNote(status, latestOperation) {
  if (!latestOperation?.runId) {
    return "research operations are ephemeral mission packets; if nothing is observed, the cockpit should say so plainly";
  }
  if (status === "fresh" || status === "recent") {
    return "this run is recent enough to guide the next move, but it still belongs to the research lane rather than the cluster lane";
  }
  if (status === "stale") {
    return "the last observed run is useful context, but it should not be mistaken for current cluster truth";
  }
  return "treat research jobs as observed operations with recovery paths, not as infrastructure facts";
}

function buildProjectPostureSummary(mode) {
  if (mode === "always-on") {
    return "continuous sovereign habitat";
  }
  if (mode === "warm") {
    return "persistent sovereign habitat kept on standby";
  }
  if (mode === "cold") {
    return "cataloged sovereign habitat activated intentionally";
  }
  return "undeclared sovereign habitat posture";
}

function buildProjectPostureOperatorNote(mode) {
  if (mode === "always-on") {
    return "this project keeps a continuously live habitat, but its research jobs still remain run-shaped and ephemeral";
  }
  if (mode === "warm") {
    return "this project has a first-class sovereign surface with retained continuity, but it should not be mistaken for a permanently running habitat";
  }
  if (mode === "cold") {
    return "this project remains cataloged and reproducible, but activation should be intentional rather than assumed";
  }
  return "project posture should be declared explicitly before cluster and research lanes are interpreted";
}

function buildProjectPostureNextSafeMove(mode) {
  if (mode === "always-on") {
    return "treat the habitat as continuously live, but keep research runs separate from the project surface itself";
  }
  if (mode === "warm") {
    return "activate the habitat only when work needs it, and keep the PVC and sovereign identity intact between activations";
  }
  if (mode === "cold") {
    return "keep the habitat cataloged and reproducible until the project needs a warmer operational lane";
  }
  return "declare a project posture before promoting this surface into regular operations";
}

function buildProjectAuthoritySummary(project) {
  const slug = cleanValue(project?.projectSlug || "");
  if (slug === "sounio") {
    return {
      summary: "Sounio is the language substrate and primary sovereign project surface",
      boundary:
        "Beagle is the platform and exocortical integration layer around Sounio, not the language authority itself"
    };
  }
  if (slug === "hyperbolic-semantic-networks") {
    return {
      summary: "Hyperbolic Semantic Networks is a separate sovereign research surface",
      boundary:
        "Beagle provides the workspace/platform layer, but Sounio identity and research conclusions must not bleed into this surface"
    };
  }
  return {
    summary: `${slug || "project"} is treated as its own sovereign project surface`,
    boundary:
      "cluster truth, research operations, and habitat continuity should stay distinct even when they share the same platform"
  };
}

function buildProjectPostureWhy(project) {
  const slug = cleanValue(project?.projectSlug || "");
  const mode = cleanValue(project?.mode || "undeclared");
  if (slug === "sounio" && mode === "always-on") {
    return "always-on because it is the daily language substrate and the primary continuously live sovereign habitat on this machine";
  }
  if (slug === "hyperbolic-semantic-networks" && mode === "warm") {
    return "warm because code, datasets, operator state, and Claude continuity are reconciled on K8s, but 24/7 habitat continuity has not been declared";
  }
  if (mode === "always-on") {
    return "always-on because this project requires continuous sovereign habitat continuity";
  }
  if (mode === "warm") {
    return "warm because this project needs a retained sovereign habitat without implying a permanently live daily lane";
  }
  if (mode === "cold") {
    return "cold because this surface should remain reproducible and intentional rather than continuously active";
  }
  return "posture should be declared explicitly before the cockpit treats this surface as continuously live";
}

function buildProjectSourceDocs(project) {
  const slug = cleanValue(project?.projectSlug || "");
  const docs = [
    {
      label: "machine README",
      path: "/home/devsounio/README.md",
      presentOnServer: existsSync("/home/devsounio/README.md")
    },
    {
      label: "projects registry",
      path: "/home/devsounio/PROJECTS.md",
      presentOnServer: existsSync("/home/devsounio/PROJECTS.md")
    },
    {
      label: "project posture policy",
      path: "/home/devsounio/projects/PROJECT_POSTURE_POLICY.md",
      presentOnServer: existsSync("/home/devsounio/projects/PROJECT_POSTURE_POLICY.md")
    },
    {
      label: `${slug} README`,
      path: `/home/devsounio/projects/${slug}/README.md`,
      presentOnServer: existsSync(`/home/devsounio/projects/${slug}/README.md`)
    },
    {
      label: `${slug} PLAN`,
      path: `/home/devsounio/projects/${slug}/PLAN.md`,
      presentOnServer: existsSync(`/home/devsounio/projects/${slug}/PLAN.md`)
    }
  ];
  if (slug === "hyperbolic-semantic-networks") {
    docs.push({
      label: `${slug} GPU execution`,
      path: `/home/devsounio/projects/${slug}/GPU_EXECUTION.md`,
      presentOnServer: existsSync(`/home/devsounio/projects/${slug}/GPU_EXECUTION.md`)
    });
  }
  return docs;
}

function normalizeGitHubRepoUrl(repoUrl) {
  return cleanValue(repoUrl).replace(/\.git$/i, "");
}

function buildGitHubBranchUrl(repoUrl, branch) {
  const normalizedRepoUrl = normalizeGitHubRepoUrl(repoUrl);
  const normalizedBranch = cleanValue(branch);
  if (!normalizedRepoUrl || !normalizedBranch) {
    return "";
  }
  return `${normalizedRepoUrl}/tree/${encodeURIComponent(normalizedBranch)}`;
}

function buildSovereignHabitatSummary(project, clusterState = null, ide = null) {
  const workspacePod = clusterState?.workspacePod || null;
  const workspaceWorkload = clusterState?.workspaceWorkload || null;
  const browserUrl = cleanValue(project?.workspacePublicUrl || project?.workspaceBrowserUrl || "");
  if (workspacePod?.name) {
    const live = workspacePod.phase === "Running" && workspacePod.ready;
    return {
      status: live ? "live" : "recovering",
      summary: live
        ? `workspace habitat live on ${workspacePod.nodeName || "unknown node"}`
        : `workspace habitat observed as ${workspacePod.phase || "Unknown"}`,
      workspaceId: cleanValue(project?.workspaceId || ""),
      workloadName: cleanValue(workspaceWorkload?.name || inferWorkspaceStatefulSetName(project)),
      podName: cleanValue(workspacePod.name || ""),
      nodeName: cleanValue(workspacePod.nodeName || ""),
      browserUrl,
      sshHost: cleanValue(project?.sshHost || ""),
      workspaceRoot: cleanValue(project?.workspaceRoot || ""),
      ideStatus: cleanValue(ide?.status || ""),
      ready: Boolean(workspacePod.ready)
    };
  }
  if (cleanValue(project?.mode || "") === "warm") {
    return {
      status: "standby",
      summary: "workspace habitat is cataloged with retained continuity and can be activated intentionally",
      workspaceId: cleanValue(project?.workspaceId || ""),
      workloadName: inferWorkspaceStatefulSetName(project),
      podName: "",
      nodeName: "",
      browserUrl,
      sshHost: cleanValue(project?.sshHost || ""),
      workspaceRoot: cleanValue(project?.workspaceRoot || ""),
      ideStatus: cleanValue(ide?.status || ""),
      ready: false
    };
  }
  return {
    status: "declared",
    summary: "workspace habitat is declared from catalog/policy, not currently observed as a live pod",
    workspaceId: cleanValue(project?.workspaceId || ""),
    workloadName: inferWorkspaceStatefulSetName(project),
    podName: "",
    nodeName: "",
    browserUrl,
    sshHost: cleanValue(project?.sshHost || ""),
    workspaceRoot: cleanValue(project?.workspaceRoot || ""),
    ideStatus: cleanValue(ide?.status || ""),
    ready: false
  };
}

function buildProjectSovereignSurface(project, { clusterState = null, ide = null } = {}) {
  const posture = cleanValue(project?.mode || "undeclared");
  const authority = buildProjectAuthoritySummary(project);
  const habitat = buildSovereignHabitatSummary(project, clusterState, ide);
  const repoUrl = normalizeGitHubRepoUrl(project?.repoUrl || "");
  const branch = cleanValue(project?.branch || "");
  const preferredBase = cleanValue(project?.preferredPrBase || "");
  return {
    generatedAt: new Date().toISOString(),
    lane: "sovereign-project-surface",
    projectSlug: cleanValue(project?.projectSlug || "unknown"),
    title: `${cleanValue(project?.projectSlug || "project")} sovereign surface`,
    summary: `${buildProjectPostureSummary(posture)} · ${authority.summary}`,
    posture: {
      name: posture,
      summary: buildProjectPostureSummary(posture),
      why: buildProjectPostureWhy(project),
      nextSafeMove: buildProjectPostureNextSafeMove(posture)
    },
    authority,
    habitat,
    git: {
      repoUrl,
      branch,
      preferredBase,
      branchUrl: buildGitHubBranchUrl(repoUrl, branch),
      preferredBaseUrl: buildGitHubBranchUrl(repoUrl, preferredBase)
    },
    boundaries: [
      "workspace habitat != research job",
      "cluster truth stays infrastructure-shaped",
      "research operations remain run-shaped and ephemeral"
    ],
    sourceDocs: buildProjectSourceDocs(project),
    routes: {
      packet: `/api/projects/${project?.projectSlug || "unknown"}/sovereign-surface`,
      cockpit: `/projects/${project?.projectSlug || "unknown"}`,
      missionControl: `/api/projects/${project?.projectSlug || "unknown"}/mission-control`,
      workspace: cleanValue(project?.workspacePublicUrl || project?.workspaceBrowserUrl || ""),
      githubRepo: repoUrl,
      githubBranch: buildGitHubBranchUrl(repoUrl, branch),
      githubPreferredBase: buildGitHubBranchUrl(repoUrl, preferredBase)
    }
  };
}

function buildProjectOperatingPosture(project, clusterLaneTruth, researchOperations) {
  const projectPosture = cleanValue(project?.mode || "undeclared");
  const clusterStatus = cleanValue(clusterLaneTruth?.status || "unobserved");
  const researchStatus = cleanValue(researchOperations?.status || "unobserved");
  const latestOperation = researchOperations?.latestObservedOperation || null;
  const runId = cleanValue(latestOperation?.runId || "");

  return {
    projectSlug: project?.projectSlug || "unknown",
    lane: "research-supercomputing",
    project: {
      posture: projectPosture,
      summary: buildProjectPostureSummary(projectPosture),
      nextSafeMove: buildProjectPostureNextSafeMove(projectPosture),
      operatorNote: buildProjectPostureOperatorNote(projectPosture),
      workspaceId: cleanValue(project?.workspaceId || ""),
      stableService: cleanValue(project?.workspaceBrowserUrl || project?.workspacePublicUrl || "")
    },
    summary:
      runId && runId !== "unknown"
        ? `${projectPosture} project posture · ${clusterStatus} cluster lane · ${researchStatus} research lane · ${runId}`
        : `${projectPosture} project posture · ${clusterStatus} cluster lane · ${researchStatus} research lane`,
    cluster: {
      status: clusterStatus,
      admittedNodes: Number(clusterLaneTruth?.admittedNodes || 0),
      healthyNodes: Number(clusterLaneTruth?.healthyNodes || 0),
      nextSafeMove:
        clusterLaneTruth?.nextSafeMove || buildClusterLaneNextSafeMove(clusterStatus),
      operatorNote:
        clusterLaneTruth?.operatorNote || buildClusterLaneOperatorNote(clusterStatus)
    },
    research: {
      status: researchStatus,
      latestObservedOperation: latestOperation,
      nextSafeMove:
        researchOperations?.nextSafeMove ||
        buildResearchOperationNextSafeMove(researchStatus, latestOperation),
      operatorNote:
        researchOperations?.operatorNote ||
        buildResearchOperationOperatorNote(researchStatus, latestOperation)
    },
    routes: {
      clusterLaneTruth: `/api/projects/${project?.projectSlug || "unknown"}/cluster/lane-truth`,
      researchOperations: `/api/projects/${project?.projectSlug || "unknown"}/research/operations`,
      goWorkNow: `/api/projects/${project?.projectSlug || "unknown"}/go-work-now`,
      missionControl: `/api/projects/${project?.projectSlug || "unknown"}/mission-control`,
      viewer: `/projects/${project?.projectSlug || "unknown"}/viewer`,
      visionControlRoom: "/public/vision/control-room",
      sovereignPreview: `/public/projects/${project?.projectSlug || "unknown"}/sovereign-cockpit-preview`
    }
  };
}

function deriveWorkspaceControllerName(project) {
  const workloadName = cleanValue(project?.workspaceWorkloadName || "");
  if (workloadName) {
    return workloadName;
  }
  const workspaceId = cleanValue(project?.workspaceId || "");
  if (workspaceId) {
    return workspaceId;
  }
  const pod = cleanValue(project?.workspacePod || "");
  if (pod.endsWith("-0")) {
    return pod.slice(0, -2);
  }
  return cleanValue(project?.workspaceId || "workspace");
}

function buildGoWorkNowPacket(project, operatingPosture = null, clusterState = null) {
  const namespace = cleanValue(project?.namespace || "beagle");
  const workspaceController = deriveWorkspaceControllerName(project);
  const workspacePod = cleanValue(project?.workspacePod || `${workspaceController}-0`);
  const workspaceContainer = cleanValue(project?.workspaceContainer || "workspace-ide");
  const workspacePublicUrl = cleanValue(project?.workspacePublicUrl || "");
  const workspaceInternalUrl = cleanValue(project?.workspaceBrowserUrl || "");
  const cockpitRoute = `/projects/${project?.projectSlug || "unknown"}`;
  const publicShowcaseRoute = `/public/projects/${project?.projectSlug || "unknown"}`;
  const viewerRoute = `/projects/${project?.projectSlug || "unknown"}/viewer`;
  const missionControlRoute =
    operatingPosture?.routes?.missionControl ||
    `/api/projects/${project?.projectSlug || "unknown"}/mission-control`;
  const clusterLaneTruthRoute =
    operatingPosture?.routes?.clusterLaneTruth ||
    `/api/projects/${project?.projectSlug || "unknown"}/cluster/lane-truth`;
  const researchOperationsRoute =
    operatingPosture?.routes?.researchOperations ||
    `/api/projects/${project?.projectSlug || "unknown"}/research/operations`;
  const posture = cleanValue(operatingPosture?.project?.posture || project?.mode || "undeclared");
  const postureSummary =
    operatingPosture?.project?.summary ||
    (posture === "always-on"
      ? "continuous sovereign habitat"
      : posture === "warm"
        ? "persistent sovereign habitat kept on standby"
        : "cataloged sovereign habitat activated intentionally");
  const activateHabitat =
    posture === "always-on"
      ? `kubectl -n ${namespace} rollout status statefulset/${workspaceController} --timeout=300s`
      : `kubectl -n ${namespace} scale statefulset/${workspaceController} --replicas=1
kubectl -n ${namespace} rollout status statefulset/${workspaceController} --timeout=300s`;
  const attachTmux = project?.tmuxSession
    ? `kubectl -n ${namespace} exec -it ${workspacePod} -c ${workspaceContainer} -- sh -lc 'TMUX_SOCKET_DIR="${project.workspaceRoot}/.tmux"; TMUX_SOCKET="${project.workspaceRoot}/.tmux/${project.tmuxSession}.sock"; mkdir -p "$TMUX_SOCKET_DIR"; chmod 700 "$TMUX_SOCKET_DIR"; exec tmux -S "$TMUX_SOCKET" new-session -A -s ${project.tmuxSession}'`
    : `kubectl -n ${namespace} exec -it ${workspacePod} -c ${workspaceContainer} -- sh`;
  const standbyHabitat =
    posture === "always-on"
      ? "always-on surface: no standby scale-down recommended"
      : `kubectl -n ${namespace} scale statefulset/${workspaceController} --replicas=0`;
  const latestOperation = operatingPosture?.research?.latestObservedOperation || null;
  const workspaceState = buildSovereignHabitatSummary(project, clusterState, null);
  const lines = [
    `project: ${cleanValue(project?.projectSlug || "unknown")}`,
    `posture: ${posture}`,
    `posture summary: ${postureSummary}`,
    `workspace state: ${workspaceState.status} · ${workspaceState.summary}`,
    `cockpit: ${cockpitRoute}`,
    `mission control: ${missionControlRoute}`,
    `viewer: ${viewerRoute}`,
    `workspace public: ${workspacePublicUrl || "not published"}`,
    `workspace internal: ${workspaceInternalUrl || "not declared"}`,
    "",
    "activate habitat:",
    activateHabitat,
    "",
    "attach shell/tmux:",
    attachTmux,
    "",
    "return to standby:",
    standbyHabitat
  ];
  if (latestOperation?.artifactRecoveryCommand) {
    lines.push(
      "",
      "recover latest artifact:",
      `destination: ${latestOperation.artifactDestinationDir || "unknown"}`,
      latestOperation.artifactRecoveryCommand
    );
  }

  return {
    generatedAt: new Date().toISOString(),
    lane: "project-go-work-now",
    summary: `go work now packet for ${cleanValue(project?.projectSlug || "unknown")}`,
    project: {
      slug: cleanValue(project?.projectSlug || "unknown"),
      posture,
      postureSummary,
      workspaceId: cleanValue(project?.workspaceId || ""),
      workstreamId: cleanValue(project?.workstreamId || ""),
      namespace
    },
    workspace: {
      controller: workspaceController,
      pod: workspacePod,
      container: workspaceContainer,
      sshHost: cleanValue(project?.sshHost || ""),
      tmuxSession: cleanValue(project?.tmuxSession || ""),
      root: cleanValue(project?.workspaceRoot || ""),
      publicUrl: workspacePublicUrl,
      internalUrl: workspaceInternalUrl
    },
    workspaceState,
    routes: {
      cockpit: cockpitRoute,
      publicShowcase: publicShowcaseRoute,
      viewer: viewerRoute,
      missionControl: missionControlRoute,
      clusterLaneTruth: clusterLaneTruthRoute,
      researchOperations: researchOperationsRoute
    },
    commands: {
      activateHabitat,
      attachTmux,
      standbyHabitat,
      artifactRecovery: latestOperation?.artifactRecoveryCommand || ""
    },
    latestObservedOperation: latestOperation
      ? {
          runId: cleanValue(latestOperation.runId || ""),
          jobId: cleanValue(latestOperation.jobId || ""),
          artifactDestinationDir: cleanValue(latestOperation.artifactDestinationDir || "")
        }
      : null,
    copyText: lines.join("\n")
  };
}

function buildDefaultClusterLaneTruth() {
  return {
    surface: "gpuorangefs",
    status: "unobserved",
    observationScope: {
      mode: "admission-scope",
      selector: "sounio.dev/slurm-worker-gpuorangefs=true",
      description: "reflects only workers currently admitted to the gpuorangefs lane"
    },
    admittedNodes: 0,
    healthyNodes: 0,
    quarantinedNodes: 0,
    repairedNodes: 0,
    deferredNodes: 0,
    failedNodes: 0,
    lastRun: {
      success: null,
      at: "",
      ageSeconds: null,
      durationSeconds: null
    },
    operatorNote: buildClusterLaneOperatorNote("unobserved"),
    nextSafeMove: buildClusterLaneNextSafeMove("unobserved"),
    nodes: [],
    truth: buildOperationalTruthMeta()
  };
}

function buildDefaultResearchOperations(project) {
  const status = project?.projectSlug === "sounio" ? "unobserved" : "not-configured";
  return {
    surface: "research-operations",
    status,
    latestObservedOperation: null,
    recentObservedOperations: [],
    operatorNote: buildResearchOperationOperatorNote(status, null),
    nextSafeMove: buildResearchOperationNextSafeMove(status, null),
    truth: buildOperationalTruthMeta()
  };
}

function buildClusterLaneTruthFromSamples(samples, source) {
  if (!Array.isArray(samples) || samples.length === 0) {
    return buildDefaultClusterLaneTruth();
  }

  const getValue = (metricName) => Number(pickMetricSample(samples, metricName)?.value || 0);
  const lastRunUnix = getValue("darwin_slurm_gpuorangefs_autoheal_last_run_unixtime");
  const nowUnix = Math.floor(Date.now() / 1000);
  const admittedNodes = getValue("darwin_slurm_gpuorangefs_autoheal_admitted_nodes");
  const healthyNodes = getValue("darwin_slurm_gpuorangefs_autoheal_healthy_nodes");
  const quarantinedNodes = getValue("darwin_slurm_gpuorangefs_autoheal_quarantined_nodes");
  const repairedNodes = getValue("darwin_slurm_gpuorangefs_autoheal_repaired_nodes");
  const deferredNodes = getValue("darwin_slurm_gpuorangefs_autoheal_deferred_nodes");
  const failedNodes = getValue("darwin_slurm_gpuorangefs_autoheal_failed_nodes");
  const lastRunSuccess = getValue("darwin_slurm_gpuorangefs_autoheal_last_run_success");
  const workerSamples = pickMetricSamples(samples, "darwin_slurm_gpuorangefs_worker_state_code");
  const latestTimestamp = Math.max(
    ...samples.map((sample) => Number(sample.timestamp || 0)).filter((value) => value > 0),
    0
  );
  const truthAt = metricTimestampToIso(latestTimestamp || lastRunUnix);
  const nodes = workerSamples
    .map((sample) => ({
      name: cleanValue(sample.labels?.exported_node || sample.labels?.node || "unknown"),
      status: cleanValue(sample.labels?.status || "unknown"),
      code: Number(sample.value || 0)
    }))
    .sort((left, right) => left.name.localeCompare(right.name));

  const status =
    admittedNodes === 0
      ? "planned"
      : failedNodes > 0
        ? "degraded"
        : deferredNodes > 0 || repairedNodes > 0
          ? "healing"
          : healthyNodes >= admittedNodes && lastRunSuccess === 1
            ? "healthy"
            : "degraded";

  return {
    surface: "gpuorangefs",
    status,
    observationScope: {
      mode: "admission-scope",
      selector: "sounio.dev/slurm-worker-gpuorangefs=true",
      description: "reflects only workers currently admitted to the gpuorangefs lane"
    },
    admittedNodes,
    healthyNodes,
    quarantinedNodes,
    repairedNodes,
    deferredNodes,
    failedNodes,
    lastRun: {
      success: lastRunSuccess === 1,
      at: metricTimestampToIso(lastRunUnix),
      ageSeconds: lastRunUnix > 0 ? Math.max(0, nowUnix - lastRunUnix) : null,
      durationSeconds: getValue("darwin_slurm_gpuorangefs_autoheal_last_run_duration_seconds")
    },
    operatorNote: buildClusterLaneOperatorNote(status),
    nextSafeMove: buildClusterLaneNextSafeMove(status),
    nodes,
    truth: buildOperationalTruthMeta(source, truthAt)
  };
}

function buildResearchOperationsFromSamples(samples, source, project) {
  if (!Array.isArray(samples) || samples.length === 0) {
    return buildDefaultResearchOperations(project);
  }

  const getValue = (metricName) => Number(pickMetricSample(samples, metricName)?.value || 0);
  const submitInfo = pickMetricSample(samples, "darwin_sounio_abide_runner_last_submit_info");
  const manifestInfo = pickMetricSample(samples, "darwin_sounio_abide_runner_last_manifest_info");
  const latestTimestamp = Math.max(
    ...samples.map((sample) => Number(sample.timestamp || 0)).filter((value) => value > 0),
    0
  );
  const submitAtUnix = getValue("darwin_sounio_abide_runner_last_submit_unixtime");
  const ageSeconds = getValue("darwin_sounio_abide_runner_last_submit_age_seconds");
  const runId = cleanValue(submitInfo?.labels?.run_id || "");
  const hasObservedRun = Boolean(runId && runId !== "unknown");
  const recentInfoSamples = pickMetricSamples(samples, "darwin_sounio_abide_runner_recent_submit_info");
  const recentUnixSamples = pickMetricSamples(samples, "darwin_sounio_abide_runner_recent_submit_unixtime");
  const recentTimestampByRunId = new Map(
    recentUnixSamples.map((sample) => [
      cleanValue(sample.labels?.run_id || ""),
      Number(sample.value || 0)
    ])
  );
  const recentObservedOperations = recentInfoSamples
    .map((sample) => {
      const sampleRunId = cleanValue(sample.labels?.run_id || "");
      const sampleUnix = recentTimestampByRunId.get(sampleRunId) || 0;
      const nowUnix = Math.floor(Date.now() / 1000);
      const payloadTransferMode = cleanValue(sample.labels?.payload_transfer_mode || "");
      const persistMode = cleanValue(sample.labels?.persist_mode || "");
      const artifacts = buildResearchOperationArtifacts(sampleRunId, persistMode);
      return {
        slot: Number(cleanValue(sample.labels?.slot || "0") || 0),
        lane: "research/supercomputing",
        kind: "abide-campaign",
        observation: "recent-submit",
        runId: sampleRunId,
        jobId: cleanValue(sample.labels?.job_id || ""),
        payloadTransferMode,
        persistMode,
        sbatchNodelist: cleanValue(sample.labels?.sbatch_nodelist || ""),
        sbatchExclude: cleanValue(sample.labels?.sbatch_exclude || ""),
        namespace: cleanValue(sample.labels?.namespace || ""),
        loginPod: cleanValue(sample.labels?.login_pod || ""),
        stageRoot: cleanValue(sample.labels?.stage_root || ""),
        resultsDir: cleanValue(sample.labels?.results_dir || ""),
        manifestPath: cleanValue(sample.labels?.manifest_path || ""),
        submittedAt: metricTimestampToIso(sampleUnix),
        submitAgeSeconds: sampleUnix > 0 ? Math.max(0, nowUnix - sampleUnix) : null,
        artifactDestinationDir: artifacts.destinationDir,
        artifactRecoveryCommand: artifacts.recoveryCommand
      };
    })
    .filter((entry) => entry.runId && entry.runId !== "unknown")
    .sort((left, right) => {
      if (left.slot > 0 && right.slot > 0) {
        return left.slot - right.slot;
      }
      return (left.submitAgeSeconds || 0) - (right.submitAgeSeconds || 0);
    });

  const status = hasObservedRun ? classifyLatestResearchOperation(ageSeconds) : "unobserved";
  const latestObservedOperation = hasObservedRun
    ? (() => {
        const payloadTransferMode =
          cleanValue(submitInfo?.labels?.payload_transfer_mode || "") ||
          decodePayloadTransferMode(
            getValue("darwin_sounio_abide_runner_last_payload_transfer_mode_code")
          );
        const persistMode =
          cleanValue(submitInfo?.labels?.persist_mode || "") ||
          decodePersistMode(getValue("darwin_sounio_abide_runner_last_persist_mode_code"));
        const artifacts = buildResearchOperationArtifacts(runId, persistMode);
        return {
          lane: "research/supercomputing",
          kind: "abide-campaign",
          observation: "latest-submit",
          runId,
          jobId: cleanValue(submitInfo?.labels?.job_id || ""),
          payloadTransferMode,
          persistMode,
          sbatchNodelist: cleanValue(submitInfo?.labels?.sbatch_nodelist || ""),
          sbatchExclude: cleanValue(submitInfo?.labels?.sbatch_exclude || ""),
          namespace: cleanValue(submitInfo?.labels?.namespace || ""),
          loginPod: cleanValue(submitInfo?.labels?.login_pod || ""),
          stageRoot: cleanValue(manifestInfo?.labels?.stage_root || ""),
          resultsDir: cleanValue(manifestInfo?.labels?.results_dir || ""),
          manifestPath: cleanValue(manifestInfo?.labels?.manifest_path || ""),
          submittedAt: metricTimestampToIso(submitAtUnix),
          submitAgeSeconds: Number.isFinite(ageSeconds) ? ageSeconds : null,
          artifactDestinationDir: artifacts.destinationDir,
          artifactRecoveryCommand: artifacts.recoveryCommand
        };
      })()
    : null;

  return {
    surface: "research-operations",
    status,
    latestObservedOperation,
    recentObservedOperations,
    operatorNote: buildResearchOperationOperatorNote(status, latestObservedOperation),
    nextSafeMove: buildResearchOperationNextSafeMove(status, latestObservedOperation),
    truth: buildOperationalTruthMeta(source, metricTimestampToIso(latestTimestamp || submitAtUnix))
  };
}

async function readClusterLaneTruth() {
  try {
    const [scalarSamples, workerSamples] = await Promise.all([
      queryPrometheusSamples(
        '{__name__=~"darwin_slurm_gpuorangefs_autoheal_(last_run_success|last_run_unixtime|last_run_duration_seconds|admitted_nodes|healthy_nodes|quarantined_nodes|repaired_nodes|deferred_nodes|failed_nodes)"}'
      ),
      queryPrometheusSamples("darwin_slurm_gpuorangefs_worker_state_code")
    ]);
    const merged = [...scalarSamples, ...workerSamples];
    if (merged.length > 0) {
      return buildClusterLaneTruthFromSamples(merged, "prometheus");
    }
  } catch {
    // fallback to local textfile below
  }

  const samples = await readPrometheusTextfileSamples(gpuorangefsAutohealPromPath);
  if (samples.length > 0) {
    return buildClusterLaneTruthFromSamples(samples, "textfile");
  }
  return buildDefaultClusterLaneTruth();
}

async function readResearchOperations(project) {
  if (project?.projectSlug !== "sounio") {
    return buildDefaultResearchOperations(project);
  }

  try {
    const [scalarSamples, infoSamples, recentInfoSamples, recentUnixSamples] = await Promise.all([
      queryPrometheusSamples(
        '{__name__=~"darwin_sounio_abide_runner_(metrics_last_emit_unixtime|last_submit_unixtime|last_submit_age_seconds|last_payload_transfer_mode_code|last_persist_mode_code)"}'
      ),
      queryPrometheusSamples(
        '{__name__=~"darwin_sounio_abide_runner_(last_(submit_info|manifest_info))"}'
      ),
      queryPrometheusSamples("last_over_time(darwin_sounio_abide_runner_recent_submit_info[24h])"),
      queryPrometheusSamples(
        "last_over_time(darwin_sounio_abide_runner_recent_submit_unixtime[24h])"
      )
    ]);
    const merged = [...scalarSamples, ...infoSamples, ...recentInfoSamples, ...recentUnixSamples];
    if (merged.length > 0) {
      return buildResearchOperationsFromSamples(merged, "prometheus", project);
    }
  } catch {
    // fallback to local textfile below
  }

  const samples = await readPrometheusTextfileSamples(researchOperationsPromPath);
  if (samples.length > 0) {
    return buildResearchOperationsFromSamples(samples, "textfile", project);
  }
  return buildDefaultResearchOperations(project);
}

async function resolveOperationalTruth(project) {
  const cacheKey = project?.projectSlug || "project";
  const cached = getCachedOperationalTruth(cacheKey, { allowStale: true });
  if (cached?.value) {
    if (cached.isStale && !cached.promise) {
      const refresh = Promise.all([
        readClusterLaneTruth(),
        readResearchOperations(project)
      ])
        .then(([clusterLaneTruth, researchOperations]) => {
          const value = { clusterLaneTruth, researchOperations };
          setCachedOperationalTruth(cacheKey, value, null);
          return value;
        })
        .catch(() => {
          const current = getCachedOperationalTruth(cacheKey, { allowStale: true });
          if (current?.value) {
            setCachedOperationalTruth(cacheKey, current.value, null);
            return current.value;
          }
          invalidateOperationalTruth(cacheKey);
          throw new Error("operational truth refresh failed");
        });
      setCachedOperationalTruth(cacheKey, cached.value, refresh);
    }
    return cached.value;
  }
  if (cached?.promise) {
    return cached.promise;
  }

  const pending = Promise.all([readClusterLaneTruth(), readResearchOperations(project)])
    .then(([clusterLaneTruth, researchOperations]) => {
      const value = { clusterLaneTruth, researchOperations };
      setCachedOperationalTruth(cacheKey, value, null);
      return value;
    })
    .catch((error) => {
      invalidateOperationalTruth(cacheKey);
      throw error;
    });

  setCachedOperationalTruth(cacheKey, null, pending);
  return pending;
}

async function attachOperationalTruth(project, memory) {
  if (!memory) {
    return memory;
  }
  const observed = await withTimeout(
    resolveOperationalTruth(project),
    "operational control truth",
    operationalTruthTimeoutMs
  ).catch(() => null);
  if (!observed) {
    return memory;
  }
  return {
    ...memory,
    resumePacket: {
      ...(memory.resumePacket || {}),
      clusterLaneTruth: observed.clusterLaneTruth,
      researchOperations: observed.researchOperations
    }
  };
}

function summarizeRememberedWorkspaceMemory(projectSlug, value) {
  if (!value) {
    return null;
  }
  const resume = value.resumePacket || {};
  const publication = value.publication || {};
  const workspace = value.workspace || {};
  const truthSummary = resume.truthSummary || {};
  const ide = value.ide || {};
  const checkpoint = resume.publicationCheckpoint || {};

  return {
    projectSlug,
    rememberedAt: new Date().toISOString(),
    workspace: {
      liveBranch: cleanValue(workspace.liveBranch || publication.branch || ""),
      branchContract: cleanValue(workspace.branchContract || ""),
      contextDrift: workspace.contextDrift || null
    },
    publication: {
      branch: cleanValue(publication.branch || ""),
      dirtyCount:
        typeof publication.dirtyCount === "number" ? publication.dirtyCount : null,
      publishableDirtyCount:
        typeof publication.publishableDirtyCount === "number"
          ? publication.publishableDirtyCount
          : null,
      memoryLocalDirtyCount:
        typeof publication.memoryLocalDirtyCount === "number"
          ? publication.memoryLocalDirtyCount
          : null
    },
    ide: {
      pack: cleanValue(ide.pack || ""),
      status: cleanValue(ide.status || ""),
      installedExtensions: Array.isArray(ide.installedExtensions) ? ide.installedExtensions : [],
      missingRequired: Array.isArray(ide.missingRequired) ? ide.missingRequired : [],
      requiredReady: typeof ide.requiredReady === "boolean" ? ide.requiredReady : false,
      source: cleanValue(ide.source || ""),
      truthMode: cleanValue(ide.truthMode || "")
    },
    publicationCheckpoint: {
      prUrl: cleanValue(checkpoint.prUrl || resume.existingPrUrl || ""),
      prTitle: cleanValue(checkpoint.prTitle || resume.existingPrTitle || ""),
      prBase: cleanValue(checkpoint.prBase || resume.existingPrBase || ""),
      prHead: cleanValue(checkpoint.prHead || resume.existingPrHead || ""),
      reviewStep: cleanValue(checkpoint.reviewStep || resume.lastReviewStep || ""),
      reviewUrl: cleanValue(checkpoint.reviewUrl || resume.lastReviewUrl || ""),
      mergeReadiness: cleanValue(checkpoint.mergeReadiness || resume.lastMergeReadiness || ""),
      publicationStage: cleanValue(checkpoint.publicationStage || resume.publicationStage || "")
    },
    truthSummary: {
      ide: truthSummary.ide || null,
      publication: truthSummary.publication || null,
      review: truthSummary.review || null,
      cluster: truthSummary.cluster || null
    }
  };
}

function summarizeScientificWorkflowRun(projectSlug, value) {
  if (!value) {
    return null;
  }

  const results = Array.isArray(value.results)
    ? value.results.map((result) => ({
        id: cleanValue(result?.id || ""),
        label: cleanValue(result?.label || ""),
        contractPath: cleanValue(result?.contractPath || ""),
        command: cleanValue(result?.command || ""),
        status: cleanValue(result?.status || "unknown"),
        exitCode: typeof result?.exitCode === "number" ? result.exitCode : null,
        durationMs: typeof result?.durationMs === "number" ? result.durationMs : null,
        checkedAt: cleanValue(result?.checkedAt || ""),
        outputPreview: cleanValue(result?.outputPreview || "")
      }))
    : [];

  return {
    projectSlug,
    checkedAt: cleanValue(value.checkedAt || new Date().toISOString()),
    status: cleanValue(value.status || "unknown"),
    checkCount: results.length,
    passedCount: results.filter((result) => result.status === "passed").length,
    failedCount: results.filter((result) => result.status !== "passed").length,
    results
  };
}

async function readRememberedWorkspaceMemory(projectSlug) {
  const key = rememberedStateKey(projectSlug);
  const filePath = path.join(rememberedStateDir, key);
  try {
    const raw = cleanValue(await fs.readFile(filePath, "utf8"));
    if (raw) {
      return safeJsonParse(raw, null);
    }
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
  }
  try {
    const { stdout } = await runKubectlCli(
      [
        "-n",
        "beagle",
        "get",
        "configmap",
        rememberedStateConfigMapName,
        "-o",
        `jsonpath={.data.${key.replace(/\./g, "\\.")}}`
      ],
      { timeoutMs: 7000 }
    );
    const raw = cleanValue(stdout);
    return safeJsonParse(raw, null);
  } catch (error) {
    const message = cleanValue(error?.stderr || error?.stdout || error?.message || "");
    if (error?.statusCode === 404 || /NotFound/i.test(message)) {
      return null;
    }
    throw error;
  }
}

function getCachedScientificWorkflowRun(projectSlug, { allowStale = false } = {}) {
  const cached = scientificWorkflowCheckCache.get(projectSlug);
  if (!cached?.value) {
    return null;
  }
  if (allowStale) {
    return cached.value;
  }
  if (Date.now() - cached.cachedAt <= scientificWorkflowCheckCacheTtlMs) {
    return cached.value;
  }
  return null;
}

function setCachedScientificWorkflowRun(projectSlug, value) {
  scientificWorkflowCheckCache.set(projectSlug, {
    cachedAt: Date.now(),
    value
  });
}

async function readScientificWorkflowRun(projectSlug) {
  const cached = getCachedScientificWorkflowRun(projectSlug);
  if (cached) {
    return cached;
  }

  const key = scientificWorkflowStateKey(projectSlug);
  const filePath = path.join(rememberedStateDir, key);
  try {
    const raw = cleanValue(await fs.readFile(filePath, "utf8"));
    if (raw) {
      const parsed = safeJsonParse(raw, null);
      if (parsed) {
        setCachedScientificWorkflowRun(projectSlug, parsed);
      }
      return parsed;
    }
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
  }

  try {
    const { stdout } = await runKubectlCli(
      [
        "-n",
        "beagle",
        "get",
        "configmap",
        rememberedStateConfigMapName,
        "-o",
        `jsonpath={.data.${key.replace(/\./g, "\\.")}}`
      ],
      { timeoutMs: 7000 }
    );
    const raw = cleanValue(stdout);
    const parsed = safeJsonParse(raw, null);
    if (parsed) {
      setCachedScientificWorkflowRun(projectSlug, parsed);
    }
    return parsed;
  } catch (error) {
    const message = cleanValue(error?.stderr || error?.stdout || error?.message || "");
    if (error?.statusCode === 404 || /NotFound/i.test(message)) {
      return null;
    }
    throw error;
  }
}

async function writeRememberedWorkspaceMemory(projectSlug, value) {
  const remembered = summarizeRememberedWorkspaceMemory(projectSlug, value);
  if (!remembered) {
    return;
  }
  const key = rememberedStateKey(projectSlug);
  const serialized = JSON.stringify(remembered);
  try {
    await runKubectlCli(
      [
        "-n",
        "beagle",
        "patch",
        "configmap",
        rememberedStateConfigMapName,
        "--type",
        "merge",
        "-p",
        JSON.stringify({
          data: {
            [key]: serialized
          }
        })
      ],
      { timeoutMs: 7000 }
    );
    return;
  } catch (error) {
    const message = cleanValue(error?.stderr || error?.stdout || error?.message || "");
    if (!/NotFound/i.test(message)) {
      throw error;
    }
  }

  await runKubectlCli(
    [
      "-n",
      "beagle",
      "create",
      "configmap",
      rememberedStateConfigMapName,
      `--from-literal=${key}=${serialized}`
    ],
    { timeoutMs: 7000 }
  );
}

async function writeScientificWorkflowRun(projectSlug, value) {
  const summarized = summarizeScientificWorkflowRun(projectSlug, value);
  if (!summarized) {
    return null;
  }

  setCachedScientificWorkflowRun(projectSlug, summarized);
  const key = scientificWorkflowStateKey(projectSlug);
  const serialized = JSON.stringify(summarized);
  try {
    await runKubectlCli(
      [
        "-n",
        "beagle",
        "patch",
        "configmap",
        rememberedStateConfigMapName,
        "--type",
        "merge",
        "-p",
        JSON.stringify({
          data: {
            [key]: serialized
          }
        })
      ],
      { timeoutMs: 7000 }
    );
    const persisted = {
      ...summarized,
      persisted: true,
      persistenceError: ""
    };
    setCachedScientificWorkflowRun(projectSlug, persisted);
    return persisted;
  } catch (error) {
    const message = cleanValue(error?.stderr || error?.stdout || error?.message || "");
    if (!/NotFound/i.test(message)) {
      const degraded = {
        ...summarized,
        persisted: false,
        persistenceError: message || "remembered scientific workflow persistence failed"
      };
      setCachedScientificWorkflowRun(projectSlug, degraded);
      return degraded;
    }
  }

  try {
    await runKubectlCli(
      [
        "-n",
        "beagle",
        "create",
        "configmap",
        rememberedStateConfigMapName,
        `--from-literal=${key}=${serialized}`
      ],
      { timeoutMs: 7000 }
    );
    const created = {
      ...summarized,
      persisted: true,
      persistenceError: ""
    };
    setCachedScientificWorkflowRun(projectSlug, created);
    return created;
  } catch (error) {
    const degraded = {
      ...summarized,
      persisted: false,
      persistenceError:
        cleanValue(error?.stderr || error?.stdout || error?.message || "") ||
        "remembered scientific workflow persistence failed"
    };
    setCachedScientificWorkflowRun(projectSlug, degraded);
    return degraded;
  }
}

function cleanValue(value) {
  return String(value || "").trim();
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => {
    switch (char) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      case "'":
        return "&#39;";
      default:
        return char;
    }
  });
}

function previewOutput(value, maxLines = 12) {
  const lines = cleanValue(value)
    .split("\n")
    .map((line) => line.trimEnd())
    .filter(Boolean)
    .slice(0, maxLines);
  return lines.join("\n");
}

function cleanDelimitedList(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => cleanValue(entry)).filter(Boolean);
  }
  return cleanValue(value)
    .split(",")
    .map((entry) => cleanValue(entry))
    .filter(Boolean);
}

function normalizeBranchName(value) {
  return cleanValue(value)
    .replace(/^refs\/heads\//, "")
    .replace(/\s+/g, "-");
}

function firstHeader(req, names) {
  for (const name of names) {
    const value =
      typeof req.get === "function"
        ? req.get(name)
        : req.headers?.[String(name).toLowerCase()];
    if (value) {
      return cleanValue(Array.isArray(value) ? value[0] : value);
    }
  }
  return "";
}

function deriveViewer(req, aliasOverride = "") {
  const login = firstHeader(req, [
    "tailscale-user-login",
    "x-auth-request-email",
    "x-forwarded-email"
  ]);
  const displayName = firstHeader(req, [
    "tailscale-user-name",
    "x-forwarded-user",
    "x-auth-request-user"
  ]);
  const deviceName = firstHeader(req, [
    "tailscale-device-name",
    "tailscale-node-name",
    "x-forwarded-host"
  ]);
  const avatarUrl = firstHeader(req, [
    "tailscale-user-profile-pic",
    "x-user-avatar-url"
  ]);
  const alias = cleanValue(aliasOverride) || displayName || login || deviceName || "anonymous viewer";
  const authSource = login || displayName || avatarUrl ? "tailscale" : "cockpit-local";

  return {
    alias,
    login,
    displayName: displayName || alias,
    deviceName,
    avatarUrl,
    authSource
  };
}

function detectAiLaneFromCommand(command) {
  const normalized = cleanValue(command);
  if (!normalized) {
    return "";
  }
  const first = normalized.split(/\s+/)[0];
  return ["claude", "codex", "kimi", "agent-browser"].includes(first) ? first : "";
}

function isLauncherOnlyCommand(command) {
  const normalized = cleanValue(command);
  if (!normalized) {
    return false;
  }

  const launcherPatterns = [
    /^claude(?:\s|$)/,
    /^codex(?:\s|$)/,
    /^kimi(?:\s|$)/,
    /^agent-browser(?:\s|$)/,
    /^tmux attach\b/,
    /^tmux new\b/,
    /^ssh\s+\S+\s*$/,
    /^cd\s+\S+\s*$/,
    /^open\s+\S+/,
    /^clear\s*$/,
    /^reset\s*$/
  ];

  return launcherPatterns.some((pattern) => pattern.test(normalized));
}

function summarizeUsefulOutputHint(command, project, git = {}) {
  const normalized = cleanValue(command);
  if (!normalized) {
    return "";
  }
  if (/^git status\b/.test(normalized)) {
    return git.dirtyCount > 0
      ? `${git.dirtyCount} dirty entries on ${git.branch || "current branch"}`
      : `working tree clean on ${git.branch || "current branch"}`;
  }
  if (/^git diff --stat\b/.test(normalized)) {
    return git.diffStat || "diff stat requested";
  }
  if (/^git diff\b/.test(normalized)) {
    return git.diffStat || "diff requested";
  }
  if (/^git log\b/.test(normalized)) {
    return git.recentCommits?.split("\n")[0] || "recent commits requested";
  }
  if (/^kubectl get pods\b/.test(normalized)) {
    return `inspect pods in namespace ${project.namespace}`;
  }
  if (/^kubectl get svc\b/.test(normalized)) {
    return `inspect services in namespace ${project.namespace}`;
  }
  if (/^agent-browser\b/.test(normalized)) {
    return `browser automation launched for ${project.browserAutomationUrl || project.workspacePublicUrl || project.workspaceBrowserUrl || "workspace surface"}`;
  }
  return "";
}

function extractCommitSha(stdout) {
  const text = String(stdout || "");
  const explicit = text.match(/\[\S+\s+([0-9a-f]{7,40})\]/i);
  if (explicit) {
    return explicit[1];
  }
  const created = text.match(/^\[([0-9a-f]{7,40})\]/im);
  if (created) {
    return created[1];
  }
  return "";
}

function firstNonEmptyLine(text) {
  return String(text || "")
    .split("\n")
    .map((line) => line.trim())
    .find(Boolean) || "";
}

function getCachedWorkspaceMemory(projectSlug, { allowStale = false } = {}) {
  const cached = workspaceMemoryCache.get(projectSlug);
  if (!cached) {
    return null;
  }
  const isStale = Date.now() - cached.at > memoryCacheTtlMs;
  if (isStale && !allowStale) {
    return null;
  }
  return { ...cached, isStale };
}

function setCachedWorkspaceMemory(projectSlug, value, promise = null) {
  workspaceMemoryCache.set(projectSlug, {
    at: Date.now(),
    value,
    promise
  });
}

function invalidateWorkspaceMemory(projectSlug) {
  workspaceMemoryCache.delete(projectSlug);
}

function getCachedFastWorkspaceMemory(projectSlug, { allowStale = false } = {}) {
  const cached = fastWorkspaceMemoryCache.get(projectSlug);
  if (!cached) {
    return null;
  }
  const isStale = Date.now() - cached.at > fastMemoryCacheTtlMs;
  if (isStale && !allowStale) {
    return null;
  }
  return { ...cached, isStale };
}

function setCachedFastWorkspaceMemory(projectSlug, value, promise = null) {
  fastWorkspaceMemoryCache.set(projectSlug, {
    at: Date.now(),
    value,
    promise
  });
}

function invalidateFastWorkspaceMemory(projectSlug) {
  fastWorkspaceMemoryCache.delete(projectSlug);
}

function getCachedInferenceRuntime(projectSlug, { allowStale = false } = {}) {
  const cached = inferenceRuntimeCache.get(projectSlug);
  if (!cached) {
    return null;
  }
  const isStale = Date.now() - cached.at > inferenceRuntimeCacheTtlMs;
  if (isStale && !allowStale) {
    return null;
  }
  return { ...cached, isStale };
}

function setCachedInferenceRuntime(projectSlug, value, promise = null) {
  inferenceRuntimeCache.set(projectSlug, {
    at: Date.now(),
    value,
    promise
  });
}

function invalidateInferenceRuntime(projectSlug) {
  inferenceRuntimeCache.delete(projectSlug);
}

function getCachedInferencePrereqs() {
  const cached = inferencePrereqCache.get("cluster");
  if (!cached) {
    return null;
  }
  const isStale = Date.now() - cached.at > inferencePrereqCacheTtlMs;
  if (isStale) {
    return null;
  }
  return cached.value;
}

function setCachedInferencePrereqs(value) {
  inferencePrereqCache.set("cluster", {
    at: Date.now(),
    value
  });
}

function isWeakFastWorkspaceMemory(project, value) {
  if (!value || project?.projectSlug !== "sounio") {
    return false;
  }

  const expectedIdePack = inferIdePolicy(project)?.pack || "";
  const ide = value?.ide || {};
  const ideSource = value?.ide?.source || "";
  const ideTruthMode = value?.ide?.truthMode || "";
  const installedExtensions = Array.isArray(ide.installedExtensions) ? ide.installedExtensions.length : 0;
  const hasIdeStatus = Boolean(ide.status);
  const publication = value?.resumePacket?.truthSummary?.publication || {};
  const review = value?.resumePacket?.truthSummary?.review || {};
  const branch = value?.publication?.branch || "";
  const existingPrUrl = value?.resumePacket?.existingPrUrl || "";
  const publicationStage = value?.resumePacket?.publicationStage || "";
  const branchLooksCold =
    !branch ||
    branch === "main" ||
    branch === project.branch ||
    branch === value?.workspace?.branchContract;
  const weakPublicationTruth =
    publication.source === "policy-fallback" || publication.truthMode === "declared";
  const weakReviewTruth = review.source === "policy-fallback" || review.truthMode === "declared";
  const missingSocialSurface = !existingPrUrl && !publicationStage;

  return (
    (Boolean(expectedIdePack) &&
      (!ide.pack ||
        ide.pack !== expectedIdePack ||
        ideSource === "policy-fallback" ||
        ideTruthMode === "declared" ||
        (!hasIdeStatus && installedExtensions === 0))) ||
    (weakPublicationTruth && weakReviewTruth && branchLooksCold && missingSocialSurface)
  );
}

function isStartupAcceptableFastWorkspaceMemory(project, value) {
  if (!value || project?.projectSlug !== "sounio") {
    return Boolean(value);
  }

  if (!isWeakFastWorkspaceMemory(project, value)) {
    return true;
  }

  const truthSummary = value?.resumePacket?.truthSummary || {};
  const publication = truthSummary.publication || {};
  const review = truthSummary.review || {};
  const publicationStage = value?.resumePacket?.publicationStage || "";
  const existingPrUrl = value?.resumePacket?.existingPrUrl || "";
  const branch = value?.publication?.branch || "";
  const preferredBase = value?.resumePacket?.preferredBase || project.preferredPrBase || project.branch || "main";
  const hasLiveBranch = Boolean(branch) && branch !== "main" && branch !== project.branch && branch !== preferredBase;
  const rememberedPublication =
    publication.truthMode === "remembered" || publication.truthMode === "observed";
  const rememberedReview = review.truthMode === "remembered" || review.truthMode === "observed";
  const hasSocialSurface = Boolean(existingPrUrl || publicationStage);

  return hasLiveBranch && hasSocialSurface && (rememberedPublication || rememberedReview);
}

function normalizeDatasetBaseUrl(url) {
  return cleanValue(url).replace(/\/(zarr\.json|\.zattrs)$/, "").replace(/\/+$/, "");
}

function normalizeHttpBaseUrl(url) {
  return cleanValue(url).replace(/\/+$/, "");
}

function remoteRequest(url, { timeoutMs = 12000, accept = "*/*" } = {}) {
  const parsed = new URL(url);
  const client = parsed.protocol === "https:" ? https : http;

  return new Promise((resolve, reject) => {
    const req = client.request(
      parsed,
      {
        method: "GET",
        family: 4,
        headers: {
          Accept: accept
        }
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => {
          data += chunk.toString();
        });
        res.on("end", () => {
          if ((res.statusCode || 500) >= 200 && (res.statusCode || 500) < 300) {
            resolve(data);
            return;
          }
          const error = new Error(data || `remote fetch failed: ${res.statusCode}`);
          error.statusCode = res.statusCode || 500;
          error.responseBody = data;
          reject(error);
        });
      }
    );

    req.setTimeout(timeoutMs, () => {
      req.destroy(new Error(`remote request timed out after ${timeoutMs}ms`));
    });
    req.on("error", reject);
    req.end();
  });
}

async function fetchRemoteText(url, timeoutMs = 12000) {
  return remoteRequest(url, {
    timeoutMs,
    accept: "text/plain, application/json;q=0.9, */*;q=0.1"
  });
}

async function fetchRemoteJson(url, timeoutMs = 12000) {
  const raw = await remoteRequest(url, {
    timeoutMs,
    accept: "application/json, text/plain;q=0.9, */*;q=0.1"
  });
  return raw ? JSON.parse(raw) : {};
}

function summarizeOmeZarrMetadata(metadata = {}) {
  const ome = metadata?.ome || metadata;
  const multiscales = Array.isArray(ome?.multiscales)
    ? ome.multiscales
    : Array.isArray(metadata?.multiscales)
      ? metadata.multiscales
      : [];
  const firstScale = multiscales[0] || {};
  const axes = Array.isArray(firstScale.axes) ? firstScale.axes.map((axis) => axis.name || axis.type || "?") : [];
  const datasets = Array.isArray(firstScale.datasets) ? firstScale.datasets.length : 0;
  return {
    omeVersion: ome?.version || metadata?.version || "",
    multiscaleCount: multiscales.length,
    axes,
    datasetLevels: datasets
  };
}

function buildContextDriftSummary({
  contractBranch = "",
  contextBranch = "",
  liveBranch = "",
  bootstrapStatus = "",
  bootstrapReason = "",
  contextMode = ""
} = {}) {
  const normalizedContract = cleanValue(contractBranch);
  const normalizedContext = cleanValue(contextBranch);
  const normalizedLive = cleanValue(liveBranch);
  const hasDrift =
    Boolean(normalizedLive) &&
    ((normalizedContext && normalizedContext !== normalizedLive) ||
      (normalizedContract && normalizedContract !== normalizedLive));
  return {
    hasDrift,
    contractBranch: normalizedContract,
    contextBranch: normalizedContext,
    liveBranch: normalizedLive,
    bootstrapStatus: cleanValue(bootstrapStatus),
    bootstrapReason: cleanValue(bootstrapReason),
    contextMode: cleanValue(contextMode)
  };
}

function parseGitHubRepo(repoUrl) {
  const raw = cleanValue(repoUrl);
  const match = raw.match(/github\.com[:/]+([^/]+)\/([^/.]+?)(?:\.git)?$/i);
  if (!match) {
    return null;
  }
  return {
    owner: match[1],
    repo: match[2]
  };
}

async function readPublicGitHubPrPreview(project, base, branch) {
  const parsed = parseGitHubRepo(project?.repoUrl || "");
  if (!parsed || !branch || !base) {
    return null;
  }
  const url = new URL(`https://api.github.com/repos/${parsed.owner}/${parsed.repo}/pulls`);
  url.searchParams.set("head", `${parsed.owner}:${branch}`);
  url.searchParams.set("base", base);
  url.searchParams.set("state", "open");
  url.searchParams.set("per_page", "1");
  const response = await fetch(url, {
    headers: {
      Accept: "application/vnd.github+json",
      "User-Agent": "project-cockpit"
    }
  });
  if (!response.ok) {
    throw new Error(`public github pr preview failed: ${response.status}`);
  }
  const rows = await response.json();
  const item = Array.isArray(rows) ? rows[0] : null;
  if (!item) {
    return null;
  }
  return {
    branch,
    base,
    ahead: 0,
    behind: 0,
    branchCommits: [],
    existingPr: {
      number: item.number,
      url: item.html_url,
      title: item.title,
      state: item.state?.toUpperCase?.() || String(item.state || "").toUpperCase(),
      isDraft: Boolean(item.draft),
      headRefName: item.head?.ref || branch,
      baseRefName: item.base?.ref || base,
      reviewDecision: item.mergeable_state === "clean" ? "MERGEABLE" : "",
      mergeStateStatus: item.mergeable_state ? String(item.mergeable_state).toUpperCase() : ""
    }
  };
}

async function readPublicGitHubOpenPrByBase(project, base) {
  const parsed = parseGitHubRepo(project?.repoUrl || "");
  if (!parsed || !base) {
    return null;
  }
  const url = new URL(`https://api.github.com/repos/${parsed.owner}/${parsed.repo}/pulls`);
  url.searchParams.set("base", base);
  url.searchParams.set("state", "open");
  url.searchParams.set("sort", "updated");
  url.searchParams.set("direction", "desc");
  url.searchParams.set("per_page", "20");
  const response = await fetch(url, {
    headers: {
      Accept: "application/vnd.github+json",
      "User-Agent": "project-cockpit"
    }
  });
  if (!response.ok) {
    throw new Error(`public github open pr lookup failed: ${response.status}`);
  }
  const rows = await response.json();
  const item = Array.isArray(rows)
    ? rows.find((entry) => cleanValue(entry?.head?.ref) && cleanValue(entry?.base?.ref) === base)
    : null;
  if (!item) {
    return null;
  }
  const branch = cleanValue(item.head?.ref);
  return {
    branch,
    base,
    ahead: 0,
    behind: 0,
    branchCommits: [],
    existingPr: {
      number: item.number,
      url: item.html_url,
      title: item.title,
      state: item.state?.toUpperCase?.() || String(item.state || "").toUpperCase(),
      isDraft: Boolean(item.draft),
      headRefName: branch,
      baseRefName: item.base?.ref || base,
      reviewDecision: item.mergeable_state === "clean" ? "MERGEABLE" : "",
      mergeStateStatus: item.mergeable_state ? String(item.mergeable_state).toUpperCase() : ""
    }
  };
}

async function probeDatasetMetadata(dataset, _depth = 0) {
  if (_depth > 1) return null;  // guard: never recurse more than one level
  const baseUrl = normalizeDatasetBaseUrl(dataset?.omeZarrUrl || dataset?.manifestRef || "");
  if (!baseUrl || !String(dataset?.sourceKind || "").match(/^(real|manifest)$/)) {
    return null;
  }
  const cacheKey = baseUrl;
  const cached = getCachedDatasetMetadata(cacheKey, { allowStale: true });
  // If a fetch is already in-flight, return it to avoid duplicate probes
  if (cached?.promise) return cached.promise;
  if (cached?.value) {
    if (cached.isStale && !cached.promise) {
      const refresh = (async () => {
        const value = await probeDatasetMetadata({ ...dataset, omeZarrUrl: baseUrl, _noCache: true }, _depth + 1);
        setCachedDatasetMetadata(cacheKey, value, null);
        return value;
      })().catch(() => {
        const current = getCachedDatasetMetadata(cacheKey, { allowStale: true });
        if (current?.value) {
          setCachedDatasetMetadata(cacheKey, current.value, null);
          return current.value;
        }
        invalidateCachedDatasetMetadata(cacheKey);
        return null;
      });
      setCachedDatasetMetadata(cacheKey, cached.value, refresh);
    }
      return {
        ...cached.value,
        source: cached.value?.ok ? (cached.isStale ? "cached" : "live") : "policy-fallback",
        truthMode: cached.value?.ok ? (cached.isStale ? "remembered" : "observed") : "declared"
      };
  }

  if (dataset?._noCache) {
    const candidates = [`${baseUrl}/zarr.json`, `${baseUrl}/.zattrs`];
    let lastError = "";
    for (const candidate of candidates) {
      try {
        const metadata = await fetchRemoteJson(candidate, 6000);
        return {
          ok: true,
          baseUrl,
          metadataUrl: candidate,
          observedAt: new Date().toISOString(),
          summary: summarizeOmeZarrMetadata(metadata)
        };
      } catch (error) {
        lastError = error.message;
      }
    }
    return {
      ok: false,
      baseUrl,
      observedAt: new Date().toISOString(),
      error: lastError || "metadata probe failed"
    };
  }

  const pending = probeDatasetMetadata({ ...dataset, omeZarrUrl: baseUrl, _noCache: true }, _depth + 1)
    .then((value) => {
      setCachedDatasetMetadata(cacheKey, value, null);
      return {
        ...value,
        source: value?.ok ? "live" : "policy-fallback",
        truthMode: value?.ok ? "observed" : "declared"
      };
    })
    .catch((error) => {
      invalidateCachedDatasetMetadata(cacheKey);
      throw error;
    });
  setCachedDatasetMetadata(cacheKey, null, pending);
  return pending;
}

async function resolveDatasetCatalog(project) {
  const catalog = Array.isArray(project?.datasetCatalog) ? project.datasetCatalog : [];
  const resolved = await Promise.all(
    catalog.map(async (dataset) => {
      const baseUrl = normalizeDatasetBaseUrl(dataset?.omeZarrUrl || "");
      if (!baseUrl || !String(dataset?.sourceKind || "").match(/^(real|manifest)$/)) {
        return dataset;
      }
      try {
        const probe = await probeDatasetMetadata(dataset);
        if (!probe?.ok) {
          return {
            ...dataset,
            omeZarrUrl: baseUrl,
            truth: {
              source: probe?.source || "declared",
              truthMode: probe?.truthMode || "declared",
              at: probe?.observedAt || ""
            },
            datasetSummary: probe?.summary || null,
            metadataUrl: probe?.metadataUrl || "",
            metadataError: probe?.error || "metadata probe failed"
          };
        }
        return {
          ...dataset,
          omeZarrUrl: baseUrl,
          truth: {
            source: probe.source || "live",
            truthMode: probe.truthMode || "observed",
            at: probe.observedAt || ""
          },
          datasetSummary: probe.summary || null,
          metadataUrl: probe.metadataUrl || ""
        };
      } catch (error) {
        return {
          ...dataset,
          omeZarrUrl: baseUrl,
          truth: {
            source: "declared",
            truthMode: "declared",
            at: ""
          },
          metadataError: error.message
        };
      }
    })
  );
  return resolved;
}

function buildDefaultDatasetCatalog(project) {
  const projectSlug = project?.projectSlug || "project";
  if (projectSlug === "sounio") {
    return [
      {
        id: "idr0062A-6001240-image",
        label: "IDR 0062A image volume",
        kind: "ome-zarr-multiscale",
        sourceKind: "real",
        omeZarrUrl: "https://uk1s3.embassy.ebi.ac.uk/idr/zarr/v0.4/idr0062A/6001240.zarr",
        manifestRef: "official:idr0062A:6001240:image",
        provenance: {
          project: "idr",
          artifactRef: "idr0062A/6001240",
          generationPath: "openmicroscopy-idr"
        },
        truth: {
          source: "declared",
          truthMode: "declared"
        }
      },
      {
        id: "idr0062A-6001240-labels",
        label: "IDR 0062A labels",
        kind: "ome-zarr-overlay",
        sourceKind: "real",
        omeZarrUrl: "https://uk1s3.embassy.ebi.ac.uk/idr/zarr/v0.5/idr0062A/6001240_labels.zarr",
        manifestRef: "official:idr0062A:6001240:labels",
        provenance: {
          project: "idr",
          artifactRef: "idr0062A/6001240_labels",
          generationPath: "openmicroscopy-idr"
        },
        truth: {
          source: "declared",
          truthMode: "declared"
        }
      },
      {
        id: "sounio-training-run",
        label: "Training provenance view",
        kind: "run-provenance",
        sourceKind: "stub",
        omeZarrUrl: "",
        manifestRef: "stub:sounio:training-run",
        provenance: {
          project: "sounio",
          artifactRef: "run-preview",
          generationPath: "training-provenance"
        },
        truth: {
          source: "declared",
          truthMode: "declared"
        }
      }
    ];
  }

  return [
    {
      id: `${projectSlug}-playground-stub`,
      label: `${projectSlug} declared dataset`,
      kind: "manifest",
      sourceKind: "stub",
      omeZarrUrl: "",
      manifestRef: `stub:${projectSlug}:default`,
      provenance: {
        project: projectSlug,
        artifactRef: "default",
        generationPath: "catalog-declared"
      },
      truth: {
        source: "declared",
        truthMode: "declared"
      }
    }
  ];
}

function buildDefaultViewerDefaults(project) {
  return {
    entryDatasetId:
      Array.isArray(project?.datasetCatalog) && project.datasetCatalog[0]?.id
        ? project.datasetCatalog[0].id
        : buildDefaultDatasetCatalog(project)[0]?.id || "",
    camera: project?.projectSlug === "sounio" ? "semantic-overview" : "overview",
    laneLayout: "viewer-first",
    defaultChannel: "signal",
    defaultScale: "auto"
  };
}

function buildDefaultPlaygroundClass(project) {
  if (project?.projectSlug === "sounio") {
    return "webgpu-first";
  }
  if (String(project?.projectSlug || "").startsWith("sounio")) {
    return "dataset-ready";
  }
  return "mission-control";
}

function normalizeProjectCatalogProject(project) {
  const runtimeCapabilities = project?.runtimeCapabilities || {};
  const datasetCatalog =
    Array.isArray(project?.datasetCatalog) && project.datasetCatalog.length
      ? project.datasetCatalog
      : buildDefaultDatasetCatalog(project);
  const viewerDefaults = {
    ...buildDefaultViewerDefaults({ ...project, datasetCatalog }),
    ...(project?.viewerDefaults || {})
  };
  return {
    ...project,
    runtimeCapabilities,
    datasetCatalog,
    viewerDefaults,
    playgroundClass: project?.playgroundClass || buildDefaultPlaygroundClass(project)
  };
}

function getCachedFastVsixStatus(projectSlug, { allowStale = false } = {}) {
  const cached = fastVsixStatusCache.get(projectSlug);
  if (!cached) {
    return null;
  }
  const isStale = Date.now() - cached.at > fastVsixCacheTtlMs;
  if (isStale && !allowStale) {
    return null;
  }
  return { ...cached, isStale };
}

function setCachedFastVsixStatus(projectSlug, value, promise = null) {
  fastVsixStatusCache.set(projectSlug, {
    at: Date.now(),
    value,
    promise
  });
}

function invalidateFastVsixStatus(projectSlug) {
  fastVsixStatusCache.delete(projectSlug);
}

function getCachedFastPublicationState(projectSlug, { allowStale = false } = {}) {
  const cached = fastPublicationStateCache.get(projectSlug);
  if (!cached) {
    return null;
  }
  const isStale = Date.now() - cached.at > fastPublicationCacheTtlMs;
  if (isStale && !allowStale) {
    return null;
  }
  return { ...cached, isStale };
}

function setCachedFastPublicationState(projectSlug, value, promise = null) {
  fastPublicationStateCache.set(projectSlug, {
    at: Date.now(),
    value,
    promise
  });
}

function invalidateFastPublicationState(projectSlug) {
  fastPublicationStateCache.delete(projectSlug);
}

function getCachedFastClusterState(projectSlug, { allowStale = false } = {}) {
  const cached = fastClusterStateCache.get(projectSlug);
  if (!cached) {
    return null;
  }
  const isStale = Date.now() - cached.at > fastClusterCacheTtlMs;
  if (isStale && !allowStale) {
    return null;
  }
  return { ...cached, isStale };
}

function setCachedFastClusterState(projectSlug, value, promise = null) {
  fastClusterStateCache.set(projectSlug, {
    at: Date.now(),
    value,
    promise
  });
}

function invalidateFastClusterState(projectSlug) {
  fastClusterStateCache.delete(projectSlug);
}

function getCachedDatasetMetadata(cacheKey, { allowStale = false } = {}) {
  const cached = datasetMetadataCache.get(cacheKey);
  if (!cached) {
    return null;
  }
  const isStale = Date.now() - cached.at > datasetMetadataCacheTtlMs;
  if (isStale && !allowStale) {
    return null;
  }
  return { ...cached, isStale };
}

function setCachedDatasetMetadata(cacheKey, value, promise = null) {
  datasetMetadataCache.set(cacheKey, {
    at: Date.now(),
    value,
    promise
  });
}

function invalidateCachedDatasetMetadata(cacheKey) {
  datasetMetadataCache.delete(cacheKey);
}

function describeCacheState(cached, ttlMs) {
  if (!cached) {
    return {
      cacheState: "miss",
      stale: false,
      ageMs: null
    };
  }
  const ageMs = Date.now() - cached.at;
  return {
    cacheState: ageMs > ttlMs ? "stale" : "warm",
    stale: ageMs > ttlMs,
    ageMs
  };
}

function cacheTimestamp(cached) {
  return cached?.at ? new Date(cached.at).toISOString() : "";
}

function getCachedCatalogExecutiveState({ allowStale = false } = {}) {
  if (!catalogExecutiveCache) {
    return null;
  }
  const isStale = Date.now() - catalogExecutiveCache.at > catalogExecutiveCacheTtlMs;
  if (isStale && !allowStale) {
    return null;
  }
  return { ...catalogExecutiveCache, isStale };
}

function setCachedCatalogExecutiveState(value, promise = null) {
  catalogExecutiveCache = {
    at: Date.now(),
    value,
    promise
  };
}

function invalidateCatalogExecutiveState() {
  catalogExecutiveCache = null;
}

async function readSessionStore() {
  try {
    const raw = await fs.readFile(sessionStatePath, "utf8");
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : { sessions: {} };
  } catch {
    return { sessions: {} };
  }
}

async function writeSessionStore(state) {
  await fs.mkdir(path.dirname(sessionStatePath), { recursive: true });
  await fs.writeFile(sessionStatePath, JSON.stringify(state, null, 2));
}

function isSessionActive(session, now = Date.now()) {
  return now - new Date(session.lastSeenAt).getTime() <= sessionTtlMs;
}

function pruneSessions(sessionMap) {
  const now = Date.now();
  const nextEntries = Object.entries(sessionMap).filter(([, session]) => {
    const ageMs = now - new Date(session.lastSeenAt).getTime();
    return ageMs <= 7 * 24 * 60 * 60 * 1000;
  });
  return Object.fromEntries(nextEntries);
}

async function touchSession(projectSlug, clientSessionId, viewer, patch = {}) {
  const state = await readSessionStore();
  const key = `${projectSlug}:${clientSessionId}`;
  const existing = state.sessions[key] || {};
  const now = new Date().toISOString();

  const nextSession = {
    projectSlug,
    clientSessionId,
    viewer,
    lastSeenAt: now,
    firstSeenAt: existing.firstSeenAt || now,
    route: patch.route || existing.route || "",
    currentAction: patch.currentAction || existing.currentAction || "viewing-cockpit",
    lastTerminalAttachAt: patch.lastTerminalAttachAt || existing.lastTerminalAttachAt || "",
    lastAiLane: patch.lastAiLane || existing.lastAiLane || "",
    lastAiLaneAt: patch.lastAiLaneAt || existing.lastAiLaneAt || "",
    lastCommand: patch.lastCommand || existing.lastCommand || "",
    lastCommandAt: patch.lastCommandAt || existing.lastCommandAt || "",
    lastUsefulCommand: patch.lastUsefulCommand || existing.lastUsefulCommand || "",
    lastUsefulCommandAt: patch.lastUsefulCommandAt || existing.lastUsefulCommandAt || "",
    lastUsefulOutputHint: patch.lastUsefulOutputHint || existing.lastUsefulOutputHint || "",
    lastMutationAt: patch.lastMutationAt || existing.lastMutationAt || "",
    lastMutationLabel: patch.lastMutationLabel || existing.lastMutationLabel || "",
    lastCommitSha: patch.lastCommitSha || existing.lastCommitSha || "",
    lastCommitMessage: patch.lastCommitMessage || existing.lastCommitMessage || "",
    lastCommitAt: patch.lastCommitAt || existing.lastCommitAt || "",
    lastPushBranch: patch.lastPushBranch || existing.lastPushBranch || "",
    lastPushAt: patch.lastPushAt || existing.lastPushAt || "",
    lastPrUrl: patch.lastPrUrl || existing.lastPrUrl || "",
    lastPrAt: patch.lastPrAt || existing.lastPrAt || "",
    lastPrTitle: patch.lastPrTitle || existing.lastPrTitle || "",
    lastPrBase: patch.lastPrBase || existing.lastPrBase || "",
    lastPrHead: patch.lastPrHead || existing.lastPrHead || "",
    lastReviewStep: patch.lastReviewStep || existing.lastReviewStep || "",
    lastReviewStepAt: patch.lastReviewStepAt || existing.lastReviewStepAt || "",
    lastReviewUrl: patch.lastReviewUrl || existing.lastReviewUrl || "",
    lastMergeReadiness: patch.lastMergeReadiness || existing.lastMergeReadiness || "",
    lastChecksPass: patch.lastChecksPass || existing.lastChecksPass || "",
    lastChecksPassAt: patch.lastChecksPassAt || existing.lastChecksPassAt || "",
    lastChecksUrl: patch.lastChecksUrl || existing.lastChecksUrl || "",
    lastCommentsReview: patch.lastCommentsReview || existing.lastCommentsReview || "",
    lastCommentsReviewAt: patch.lastCommentsReviewAt || existing.lastCommentsReviewAt || "",
    lastMergeDecision: patch.lastMergeDecision || existing.lastMergeDecision || "",
    lastMergeDecisionAt: patch.lastMergeDecisionAt || existing.lastMergeDecisionAt || "",
    lastMergeAction: patch.lastMergeAction || existing.lastMergeAction || "",
    lastMergeActionAt: patch.lastMergeActionAt || existing.lastMergeActionAt || "",
    lastViewerDatasetId: patch.lastViewerDatasetId || existing.lastViewerDatasetId || "",
    lastViewerChannel: patch.lastViewerChannel || existing.lastViewerChannel || "",
    lastViewerScale: patch.lastViewerScale || existing.lastViewerScale || "",
    lastViewerCamera: patch.lastViewerCamera || existing.lastViewerCamera || "",
    lastViewerRendererStatus:
      patch.lastViewerRendererStatus || existing.lastViewerRendererStatus || "",
    lastViewerRendererMessage:
      patch.lastViewerRendererMessage || existing.lastViewerRendererMessage || "",
    lastViewerRendererSource:
      patch.lastViewerRendererSource || existing.lastViewerRendererSource || "",
    lastViewerRendererTruthMode:
      patch.lastViewerRendererTruthMode || existing.lastViewerRendererTruthMode || "",
    lastViewerRendererRuntime:
      patch.lastViewerRendererRuntime || existing.lastViewerRendererRuntime || "",
    lastViewerRendererBackend:
      patch.lastViewerRendererBackend || existing.lastViewerRendererBackend || "",
    lastViewerRendererAdapter:
      patch.lastViewerRendererAdapter || existing.lastViewerRendererAdapter || "",
    lastViewerRendererFormat:
      patch.lastViewerRendererFormat || existing.lastViewerRendererFormat || "",
    lastViewerRendererFeatures:
      patch.lastViewerRendererFeatures || existing.lastViewerRendererFeatures || "",
    lastViewerRendererLimits:
      patch.lastViewerRendererLimits || existing.lastViewerRendererLimits || "",
    lastViewerRendererObservedAt:
      patch.lastViewerRendererObservedAt || existing.lastViewerRendererObservedAt || "",
    lastViewerSceneAt: patch.lastViewerSceneAt || existing.lastViewerSceneAt || "",
    lastMemorySyncAt: patch.lastMemorySyncAt || existing.lastMemorySyncAt || "",
    lastMemorySyncState: patch.lastMemorySyncState || existing.lastMemorySyncState || "",
    lastDelegationAt: patch.lastDelegationAt || existing.lastDelegationAt || "",
    lastDelegationState: patch.lastDelegationState || existing.lastDelegationState || "",
    lastDelegationAgentKind:
      patch.lastDelegationAgentKind || existing.lastDelegationAgentKind || "",
    lastDelegationSessionId:
      patch.lastDelegationSessionId || existing.lastDelegationSessionId || "",
    lastDelegationPodName:
      patch.lastDelegationPodName || existing.lastDelegationPodName || "",
    projectFamily: patch.projectFamily || existing.projectFamily || "",
    publicationScope: patch.publicationScope || existing.publicationScope || "",
    promotionState: patch.promotionState || existing.promotionState || "",
    workspaceTarget: patch.workspaceTarget || existing.workspaceTarget || "",
    publicationStage: patch.publicationStage || existing.publicationStage || "",
    notes: patch.notes || existing.notes || ""
  };

  state.sessions = pruneSessions({
    ...state.sessions,
    [key]: nextSession
  });
  await writeSessionStore(state);
  const cachedDeep = getCachedWorkspaceMemory(projectSlug, { allowStale: true });
  if (cachedDeep?.value) {
    workspaceMemoryCache.set(projectSlug, {
      at: 0,
      value: cachedDeep.value,
      promise: null
    });
  }
  invalidateFastWorkspaceMemory(projectSlug);

  return nextSession;
}

function sortTimelineEntries(entries) {
  return entries
    .filter((entry) => entry && entry.at)
    .sort((left, right) => new Date(right.at).getTime() - new Date(left.at).getTime())
    .slice(0, 8);
}

function inferTimelinePhase(kind) {
  if (["terminal", "ai-lane", "useful-command", "mutation"].includes(kind)) {
    return "work";
  }
  if (["commit", "push", "pr", "publication-stage"].includes(kind)) {
    return "publish";
  }
  if (["review-step", "checks", "comments"].includes(kind)) {
    return "review";
  }
  if (["merge-decision", "merge-action"].includes(kind)) {
    return "merge";
  }
  return "work";
}

function buildContinuityTimeline(latestSession, fallback = {}) {
  const checkpoint = fallback.publicationCheckpoint || {};
  const defaultAt = latestSession?.lastSeenAt || new Date().toISOString();
  return sortTimelineEntries([
    latestSession?.lastTerminalAttachAt
      ? {
          kind: "terminal",
          label: "terminal reattached",
          detail: latestSession?.viewer?.displayName || latestSession?.viewer?.alias || "",
          at: latestSession.lastTerminalAttachAt || defaultAt
        }
      : null,
    latestSession?.lastAiLane
      ? {
          kind: "ai-lane",
          label: `${latestSession.lastAiLane} lane active`,
          detail: latestSession?.lastCommand || "",
          at: latestSession.lastAiLaneAt || latestSession.lastCommandAt || defaultAt
        }
      : null,
    latestSession?.lastUsefulCommand
      ? {
          kind: "useful-command",
          label: latestSession.lastUsefulCommand,
          detail: latestSession.lastUsefulOutputHint || "",
          at: latestSession.lastUsefulCommandAt || latestSession.lastCommandAt || defaultAt
        }
      : null,
    latestSession?.lastCommitSha || checkpoint.commitSha
      ? {
          kind: "commit",
          label: latestSession?.lastCommitMessage || checkpoint.commitMessage || "commit recorded",
          detail: latestSession?.lastCommitSha || checkpoint.commitSha || "",
          at: latestSession?.lastCommitAt || checkpoint.commitAt || defaultAt
        }
      : null,
    latestSession?.lastPushBranch || checkpoint.pushBranch
      ? {
          kind: "push",
          label: `pushed ${latestSession?.lastPushBranch || checkpoint.pushBranch}`,
          detail: latestSession?.lastPrUrl || checkpoint.prUrl || "",
          at: latestSession?.lastPushAt || checkpoint.pushAt || defaultAt
        }
      : null,
    latestSession?.lastPrUrl || checkpoint.prUrl
      ? {
          kind: "pr",
          label: latestSession?.lastPrTitle || checkpoint.prTitle || "draft PR open",
          detail: latestSession?.lastPrUrl || checkpoint.prUrl || "",
          at:
            latestSession?.lastPrAt ||
            checkpoint.prAt ||
            latestSession?.lastPushAt ||
            checkpoint.pushAt ||
            defaultAt
        }
      : null,
    checkpoint.publicationStage
      ? {
          kind: "publication-stage",
          label: `stage: ${checkpoint.publicationStage}`,
          detail: checkpoint.mergeReadiness || checkpoint.mergeDecision || "",
          at:
            checkpoint.mergeActionAt ||
            checkpoint.mergeDecisionAt ||
            checkpoint.reviewStepAt ||
            checkpoint.prAt ||
            defaultAt
        }
      : null,
    latestSession?.lastReviewStep || checkpoint.reviewStep
      ? {
          kind: "review-step",
          label: latestSession?.lastReviewStep || checkpoint.reviewStep,
          detail: latestSession?.lastReviewUrl || checkpoint.reviewUrl || "",
          at: latestSession?.lastReviewStepAt || checkpoint.reviewStepAt || defaultAt
        }
      : null,
    latestSession?.lastChecksPass || checkpoint.checksPass
      ? {
          kind: "checks",
          label: latestSession?.lastChecksPass || checkpoint.checksPass,
          detail: latestSession?.lastChecksUrl || checkpoint.checksUrl || "",
          at: latestSession?.lastChecksPassAt || checkpoint.checksPassAt || defaultAt
        }
      : null,
    latestSession?.lastCommentsReview || checkpoint.commentsReview
      ? {
          kind: "comments",
          label: latestSession?.lastCommentsReview || checkpoint.commentsReview,
          detail: latestSession?.lastReviewUrl || checkpoint.reviewUrl || "",
          at: latestSession?.lastCommentsReviewAt || checkpoint.commentsReviewAt || defaultAt
        }
      : null,
    latestSession?.lastMergeDecision || checkpoint.mergeDecision
      ? {
          kind: "merge-decision",
          label: latestSession?.lastMergeDecision || checkpoint.mergeDecision,
          detail:
            latestSession?.lastMergeReadiness ||
            checkpoint.mergeReadiness ||
            checkpoint.publicationStage ||
            "",
          at: latestSession?.lastMergeDecisionAt || checkpoint.mergeDecisionAt || defaultAt
        }
      : null,
    latestSession?.lastMergeAction || checkpoint.mergeAction
      ? {
          kind: "merge-action",
          label: latestSession?.lastMergeAction || checkpoint.mergeAction,
          detail:
            latestSession?.lastMergeDecision ||
            checkpoint.mergeDecision ||
            latestSession?.lastMergeReadiness ||
            checkpoint.mergeReadiness ||
            "",
          at: latestSession?.lastMergeActionAt || checkpoint.mergeActionAt || defaultAt
        }
      : null,
    latestSession?.lastMutationLabel
      ? {
          kind: "mutation",
          label: latestSession.lastMutationLabel,
          detail: latestSession.lastMutationAt ? `at ${latestSession.lastMutationAt}` : "",
          at: latestSession.lastMutationAt || ""
        }
      : null
  ]).map((entry) => ({
    ...entry,
    phase: inferTimelinePhase(entry.kind)
  }));
}

async function listProjectSessions(projectSlug) {
  const state = await readSessionStore();
  const now = Date.now();
  const sessions = Object.values(state.sessions)
    .filter((session) => session.projectSlug === projectSlug)
    .sort((left, right) => new Date(right.lastSeenAt).getTime() - new Date(left.lastSeenAt).getTime());

  const active = sessions.filter((session) => isSessionActive(session, now));
  const recent = sessions.slice(0, 8);

  return {
    active,
    recent
  };
}

function kubectlArgs(project, commandArgs, { tty = false } = {}) {
  const args = ["-n", project.namespace, "exec"];
  if (tty) {
    args.push("-it");
  }
  args.push(project.workspacePod, "-c", project.workspaceContainer, "--", ...commandArgs);
  return args;
}

async function runWorkspaceShell(project, envMap, script, { timeoutMs = 12000 } = {}) {
  const envExport = Object.entries(envMap)
    .map(([key, value]) => `export ${key}=${shellQuote(value)}`)
    .join("\n");
  const remoteScript = `${envExport}\n${script}\n`;
  const { stdout, stderr, code } = await runKubectlCli(
    kubectlArgs(project, ["sh", "-lc", remoteScript], { tty: false }),
    { timeoutMs }
  );
  return {
    stdout: sanitizePtyOutput(stdout),
    stderr: sanitizePtyOutput(stderr),
    code
  };
}

function parseSection(stdout, label, nextLabel) {
  const startMarker = `__${label}__`;
  const start = stdout.indexOf(startMarker);
  if (start === -1) {
    return "";
  }

  let slice = stdout.slice(start + startMarker.length);
  if (slice.startsWith("\n")) {
    slice = slice.slice(1);
  }

  if (nextLabel) {
    const nextMarker = `__${nextLabel}__`;
    const end = slice.indexOf(nextMarker);
    if (end !== -1) {
      slice = slice.slice(0, end);
    }
  }

  return slice.trim();
}

async function readFastWorkspaceBootstrap(project, { timeoutMs = 9000 } = {}) {
  const script =
    'cd "$WORKSPACE_ROOT" && ' +
    'echo "__BRANCH__" && (git branch --show-current 2>/dev/null || true) && ' +
    'echo "__PACKET__" && (sed -n "1,120p" .beagle/context/current-context-packet.json 2>/dev/null || true) && ' +
    'echo "__VSIX__" && (sed -n "1,220p" .beagle/context/vsix-pack-status.json 2>/dev/null || true)';

  const workspaceShell = await runWorkspaceShell(
    project,
    { WORKSPACE_ROOT: project.workspaceRoot },
    script,
    { timeoutMs }
  );

  return {
    branch: cleanValue(parseSection(workspaceShell.stdout, "BRANCH", "PACKET")),
    packet: safeJsonParse(parseSection(workspaceShell.stdout, "PACKET", "VSIX"), {}),
    vsix: safeJsonParse(parseSection(workspaceShell.stdout, "VSIX"), {})
  };
}

function inferIdePolicy(project) {
  const defaultAiIdeAgents = [
    { name: "codex", mode: "vsix-first", status: "runtime-unverified" },
    { name: "claude-code", mode: "hybrid", status: "hybrid-ready" }
  ];

  if (project.projectSlug === "sounio") {
    return {
      substrate: "openvscode-server",
      pack: "sounio",
      packVersion: "sov-v1",
      requiredExtensions: [
        "eamodio.gitlens",
        "GitHub.vscode-pull-request-github",
        "redhat.vscode-yaml",
        "ms-python.python",
        "ms-toolsai.jupyter",
        "rust-lang.rust-analyzer",
        "llvm-vs-code-extensions.vscode-clangd"
      ],
      recommendedExtensions: [
        "EditorConfig.EditorConfig",
        "tamasfe.even-better-toml",
        "ms-vscode.makefile-tools",
        "yzhang.markdown-all-in-one",
        "ms-vscode.cpptools",
        "ocamllabs.ocaml-platform",
        "leanprover.lean4"
      ],
      experimentalExtensions: [],
      aiIdeAgents: defaultAiIdeAgents,
      recommendedEnabled: true,
      experimentalEnabled: false
    };
  }
  if (project.projectSlug === "beagle") {
    return {
      substrate: "openvscode-server",
      pack: "beagle",
      packVersion: "sov-v1",
      requiredExtensions: [],
      recommendedExtensions: [],
      experimentalExtensions: [],
      aiIdeAgents: defaultAiIdeAgents,
      recommendedEnabled: true,
      experimentalEnabled: false
    };
  }
  if (project.projectSlug === "darwin-pbpk") {
    return {
      substrate: "openvscode-server",
      pack: "pbpk-omics",
      packVersion: "sov-v1",
      requiredExtensions: [
        "ms-python.python",
        "ms-toolsai.jupyter",
        "redhat.vscode-yaml"
      ],
      recommendedExtensions: ["REditorSupport.r"],
      experimentalExtensions: [],
      aiIdeAgents: defaultAiIdeAgents,
      recommendedEnabled: true,
      experimentalEnabled: false
    };
  }
  if (project.projectSlug.startsWith("sounio")) {
    return {
      substrate: "openvscode-server",
      pack: "sounio",
      packVersion: "sov-v1",
      requiredExtensions: [
        "rust-lang.rust-analyzer",
        "llvm-vs-code-extensions.vscode-clangd",
        "ms-python.python",
        "redhat.vscode-yaml"
      ],
      recommendedExtensions: [
        "ms-vscode.cpptools",
        "GitHub.vscode-pull-request-github",
        "ocamllabs.ocaml-platform",
        "leanprover.lean4"
      ],
      experimentalExtensions: [],
      aiIdeAgents: defaultAiIdeAgents,
      recommendedEnabled: true,
      experimentalEnabled: false
    };
  }
  return {
    substrate: "openvscode-server",
    pack: "core-sovereign",
    packVersion: "sov-v1",
    requiredExtensions: [],
    recommendedExtensions: [],
    experimentalExtensions: [],
    aiIdeAgents: defaultAiIdeAgents,
    recommendedEnabled: true,
    experimentalEnabled: false
  };
}

function mergeAiIdeAgents(liveAgents, policyAgents) {
  const policyByName = new Map(
    (Array.isArray(policyAgents) ? policyAgents : []).map((agent) => [agent.name, agent])
  );
  if (!Array.isArray(liveAgents) || liveAgents.length === 0) {
    return Array.isArray(policyAgents) ? policyAgents : [];
  }
  return liveAgents.map((agent) => {
    const policy = policyByName.get(agent.name) || {};
    return {
      ...policy,
      ...agent,
      status: agent.status || policy.status || ""
    };
  });
}

function buildIdeTruth(source) {
  if (source === "live") {
    return { source: "live", truthMode: "observed" };
  }
  if (source === "cached") {
    return { source: "cached", truthMode: "remembered" };
  }
  return { source: "policy-fallback", truthMode: "declared" };
}

function humanizePublicationStageLabel(value) {
  const map = {
    working: "working",
    published: "published",
    "under-review": "under review",
    "merge-ready": "merge-ready",
    "merged-later": "merged later"
  };
  return map[value] || value || "working";
}

function humanizeMergeReadinessLabel(value) {
  const map = {
    "no-pr": "no PR yet",
    draft: "draft PR open",
    closed: "PR closed",
    "review-required": "review required",
    "changes-requested": "changes requested",
    "dirty-habitat": "dirty habitat",
    "merge-ready-ish": "merge-ready-ish",
    "pushed-awaiting-pr": "pushed, awaiting PR"
  };
  return map[value] || value || "unknown";
}

function buildMissionControlSummary(resumePacket = {}) {
  const checkpoint = resumePacket.publicationCheckpoint || {};
  return {
    nextSafeMove: resumePacket.nextSafeMove || "hydrate sovereign memory for next move",
    currentPr: checkpoint.prUrl || resumePacket.existingPrUrl || "none",
    publicationStage: humanizePublicationStageLabel(
      resumePacket.publicationStage || checkpoint.publicationStage || "working"
    ),
    mergeReadiness: humanizeMergeReadinessLabel(
      checkpoint.mergeReadiness || resumePacket.lastMergeReadiness || "no-pr"
    ),
    truthSummary: resumePacket.truthSummary || {
      ide: { source: "policy-fallback", truthMode: "declared" },
      publication: { source: "policy-fallback", truthMode: "declared" },
      review: { source: "policy-fallback", truthMode: "declared" },
      cluster: { source: "policy-fallback", truthMode: "declared" }
    }
  };
}

function pickRoutingRecommendation({ project, truthSummary, ide, missionControl, viewerState, runtimeCapabilities }) {
  const hasObservedDataset = viewerState?.selectedDataset?.truth?.truthMode === "observed";
  const hasViewerRoute = Boolean(runtimeCapabilities?.web?.humanRoute);
  const hasDraftPr =
    missionControl?.currentPr &&
    missionControl.currentPr !== "none" &&
    /draft/i.test(missionControl?.mergeReadiness || "");
  const agentNames = new Set(
    Array.isArray(ide?.aiIdeAgents) ? ide.aiIdeAgents.map((agent) => String(agent?.name || "").toLowerCase()) : []
  );

  if (hasObservedDataset && hasViewerRoute) {
    return {
      recommendedAgent: "claude-code",
      mode: "hybrid",
      lane: "viewer",
      rationale: "viewer lane has real dataset/provenance truth and benefits from deep multi-step interpretation"
    };
  }

  if (hasDraftPr || truthSummary?.publication?.truthMode === "remembered") {
    return {
      recommendedAgent: agentNames.has("codex") ? "codex" : "claude-code",
      mode: agentNames.has("codex") ? "vsix-first" : "hybrid",
      lane: "publication",
      rationale: "publication and review truth are live enough to support surgical patching and PR work"
    };
  }

  return {
    recommendedAgent: agentNames.has("codex") ? "codex" : "kimi",
    mode: agentNames.has("codex") ? "vsix-first" : "external-second-opinion",
    lane: project?.playgroundClass === "webgpu-first" ? "knowledge-graph" : "workspace",
    rationale: "routing defaults to the most structured agent lane available for the current project surface"
  };
}

function buildBeagleSubstrateSummary({
  project,
  truthSummary,
  missionControl,
  ide,
  runtimeCapabilities,
  datasetCatalog,
  viewerState,
  workspace
}) {
  const routingTruth =
    truthSummary?.ide?.truthMode === "observed" || truthSummary?.publication?.truthMode === "observed"
      ? { source: "cached", truthMode: "remembered" }
      : { source: "declared", truthMode: "declared" };
  const datasetTruth = viewerState?.selectedDataset?.truth || { source: "declared", truthMode: "declared" };
  const graphTruth =
    datasetTruth.truthMode === "observed" || truthSummary?.publication?.truthMode === "remembered"
      ? { source: "cached", truthMode: "remembered" }
      : { source: "declared", truthMode: "declared" };
  const recommendation = pickRoutingRecommendation({
    project,
    truthSummary,
    ide,
    missionControl,
    viewerState,
    runtimeCapabilities
  });
  const currentPr = missionControl?.currentPr && missionControl.currentPr !== "none" ? missionControl.currentPr : "";
  const selectedDatasetId = viewerState?.currentDatasetId || "";
  const graphAnchors = [
    `project:${project?.projectSlug || "unknown"}`,
    workspace?.liveBranch ? `branch:${workspace.liveBranch}` : "",
    currentPr ? `pr:${currentPr}` : "",
    selectedDatasetId ? `dataset:${selectedDatasetId}` : "",
    viewerState?.provenance?.artifactRef ? `artifact:${viewerState.provenance.artifactRef}` : "",
    recommendation.lane ? `lane:${recommendation.lane}` : ""
  ].filter(Boolean);
  const publicationBranch = workspace?.liveBranch || missionControl?.currentBranch || project?.branch || "";
  const publicationPr = currentPr || "";
  const currentDatasetLabel = viewerState?.selectedDataset?.label || selectedDatasetId || "current dataset";
  const sounioScientificContract = buildSounioScientificContractPacket(project, selectedDatasetId);
  const sounioContractPack = buildSounioScientificContractPack(project, selectedDatasetId);
  const taskPlan =
    recommendation.lane === "viewer"
      ? [
          {
            label: "Inspect dataset provenance",
            agent: recommendation.recommendedAgent,
            lane: "viewer",
            objective: `trace ${currentDatasetLabel} back to artifact, generation path, and current branch`
          },
          {
            label: "Check renderer readiness",
            agent: recommendation.recommendedAgent,
            lane: "viewer",
            objective: "verify WebGPU/runtime truth before deeper visual analysis"
          },
          {
            label: "Relate scene to publication state",
            agent: "codex",
            lane: "publication",
            objective: "connect the current viewer scene to the open PR and dirty branch state"
          }
        ]
      : recommendation.lane === "publication"
        ? [
            {
              label: "Review branch drift",
              agent: recommendation.recommendedAgent,
              lane: "publication",
              objective: `inspect ${publicationBranch || "current branch"} against the persisted sovereign context`
            },
            {
              label: "Stabilize current PR",
              agent: recommendation.recommendedAgent,
              lane: "publication",
              objective: publicationPr
                ? `tighten review/publication flow around ${publicationPr}`
                : "prepare a coherent PR-ready publication packet"
            },
            {
              label: "Escalate to deep reasoning if needed",
              agent: "claude-code",
              lane: "knowledge-graph",
              objective: "pull graph context if patching alone is not enough to explain the system state"
            }
          ]
        : [
            {
              label: "Hydrate graph context",
              agent: recommendation.recommendedAgent,
              lane: recommendation.lane || "workspace",
              objective: "assemble the minimal project, dataset, and publication anchors needed for the next move"
            },
            {
              label: "Verify substrate truth",
              agent: "claude-code",
              lane: "knowledge-graph",
              objective: "check whether current truth is observed, remembered, or only declared before acting"
            },
            {
              label: "Prepare execution lane",
              agent: "codex",
              lane: "workspace",
              objective: "stand up the most structured edit/runtime lane once truth is good enough"
            }
          ];
  const graphQueries = [
    `project:${project?.projectSlug || "unknown"} -> branch:${workspace?.liveBranch || project?.branch || "unknown"}`,
    currentPr ? `pr:${currentPr} -> review/publication state` : "publication -> no-pr-yet",
    selectedDatasetId ? `dataset:${selectedDatasetId} -> artifact/provenance` : "dataset -> none-selected",
    `lane:${recommendation.lane || "workspace"} -> agent:${recommendation.recommendedAgent || "unknown"}`
  ];
  const graphEdges = [
    {
      from: `project:${project?.projectSlug || "unknown"}`,
      relation: "tracks-branch",
      to: workspace?.liveBranch ? `branch:${workspace.liveBranch}` : ""
    },
    {
      from: workspace?.liveBranch ? `branch:${workspace.liveBranch}` : "",
      relation: "backs-pr",
      to: currentPr ? `pr:${currentPr}` : ""
    },
    {
      from: selectedDatasetId ? `dataset:${selectedDatasetId}` : "",
      relation: "materializes-artifact",
      to: viewerState?.provenance?.artifactRef ? `artifact:${viewerState.provenance.artifactRef}` : ""
    },
    {
      from: selectedDatasetId ? `dataset:${selectedDatasetId}` : "",
      relation: "inspected-in",
      to: recommendation.lane ? `lane:${recommendation.lane}` : "lane:viewer"
    },
    {
      from: recommendation.lane ? `lane:${recommendation.lane}` : "lane:viewer",
      relation: "routed-to",
      to: recommendation.recommendedAgent ? `agent:${recommendation.recommendedAgent}` : ""
    }
  ].filter((edge) => edge.from && edge.to);
  const scientificWorkflow = {
    headline: "Scientific workflow packet",
    lane: "viewer",
    route: `/projects/${project?.projectSlug || "unknown"}/viewer`,
    objective: `Carry ${currentDatasetLabel} from scene inspection through provenance and publication context without losing branch truth.`,
    steps: [
      `Open dataset ${selectedDatasetId || "current"} in the viewer lane`,
      `Verify renderer truth and multiscale metadata for ${currentDatasetLabel}`,
      viewerState?.provenance?.artifactRef
        ? `Trace artifact ${viewerState.provenance.artifactRef} back to generation path`
        : "Trace the current scene back to its artifact or upstream generator",
      currentPr
        ? `Relate the scene to PR ${currentPr} and current branch state`
        : `Relate the scene to branch ${publicationBranch || "current"} and prepare publication context`,
      `Hand off the next safe move to ${recommendation.recommendedAgent || "the routed agent"}`
    ],
    contractChecks: sounioContractPack
      ? sounioContractPack.contracts.map((entry) => ({
          id: entry.id,
          label: entry.label,
          contractPath: entry.contractPath,
          command: entry.command
        }))
      : [],
    contractRoutes: sounioContractPack
      ? {
          pack: `/api/projects/${project?.projectSlug || "unknown"}/sounio/contracts`,
          executionPacket: `/api/projects/${project?.projectSlug || "unknown"}/execution/packets/sounioWorkflowCheck`
        }
      : null
  };
  const researchPacket = {
    headline: "Supercomputing research packet",
    lane: "research",
    objective:
      SUPERCOMPUTING_RESEARCH_BRIEF.recommendedMoves?.[0] ||
      "Keep sovereign truth explicit while widening the playground.",
    focus: SUPERCOMPUTING_RESEARCH_BRIEF.horizon,
    sources: SUPERCOMPUTING_RESEARCH_BRIEF.sources || [],
    pillars: (SUPERCOMPUTING_RESEARCH_BRIEF.pillars || []).map((pillar) => pillar.name)
  };
  scientificWorkflow.contractIds = sounioContractPack
    ? sounioContractPack.contracts.map((entry) => entry.id)
    : [];
  const inferenceRuntime = buildInferenceRuntimeSummary(project);
  const executionPackets = {
    claudeCode: {
      headline: "Deep reasoning packet",
      lane: recommendation.lane || "workspace",
      prompt:
        recommendation.lane === "viewer"
          ? `Analyze ${currentDatasetLabel} in the viewer lane, connect scene/provenance to ${publicationBranch || "the current branch"}, and explain the safest next move.`
          : `Explain the current sovereign state for ${project?.projectSlug || "this project"}, including branch drift, PR/publication state, and the safest next move.`,
      command:
        recommendation.lane === "viewer"
          ? `open /projects/${project?.projectSlug || "unknown"}/viewer and inspect dataset ${selectedDatasetId || "current"}`
          : `open /projects/${project?.projectSlug || "unknown"} and inspect mission control + memory truth`
    },
    codex: {
      headline: "Surgical execution packet",
      lane: recommendation.lane === "viewer" ? "publication" : recommendation.lane || "workspace",
      prompt: currentPr
        ? `Work against ${publicationBranch || "the current branch"} with PR ${currentPr}. Keep truth strong and prefer the smallest safe mutation.`
        : `Work against ${publicationBranch || "the current branch"} and prepare a coherent publication packet before opening a PR.`,
      command:
        recommendation.lane === "viewer"
          ? `focus publication lane for ${project?.projectSlug || "unknown"} and connect viewer provenance to the open PR`
          : `focus ${recommendation.lane || "workspace"} lane for ${project?.projectSlug || "unknown"}`
    },
    kimi: {
      headline: "Second-opinion packet",
      lane: "knowledge-graph",
      prompt: `Give a second-opinion on routing/provenance for ${project?.projectSlug || "this project"} using anchors: ${graphAnchors.join(", ")}`,
      command: `review graph anchors and challenge the current routing recommendation`
    },
    scientificViewer: {
      headline: "Scientific viewer packet",
      lane: "viewer",
      prompt: `Inspect dataset ${selectedDatasetId || "current"} in the ${project?.projectSlug || "current"} playground. Verify renderer truth, multiscale metadata, axes, provenance, and whether the current scene is publication-relevant.`,
      command: `open /projects/${project?.projectSlug || "unknown"}/viewer and inspect dataset ${selectedDatasetId || "current"} with provenance ${viewerState?.provenance?.artifactRef || "none"}`
    },
    scientificWorkflow: {
      headline: scientificWorkflow.headline,
      lane: scientificWorkflow.lane,
      prompt: scientificWorkflow.objective,
      command: scientificWorkflow.steps.join(" -> ")
    },
    researchPacket: {
      headline: researchPacket.headline,
      lane: researchPacket.lane,
      prompt: researchPacket.objective,
      command: `review ${researchPacket.pillars.length} pillars and anchor ${researchPacket.sources.length} primary sources`
    },
    inferenceFabric: {
      headline: "Inference fabric packet",
      lane: "inference",
      prompt: inferenceRuntime.objective,
      command: `inspect ${inferenceRuntime.route}, ${inferenceRuntime.workloadRoute}, and ${inferenceRuntime.modelsRoute} before enabling the private inference fabric`
    },
    sglangServing: {
      headline: "SGLang runtime packet",
      lane: "inference",
      prompt: `Bring the SGLang engine online for ${project?.projectSlug || "this project"} and verify that ${inferenceRuntime.engine?.modelsUrl || inferenceRuntime.modelsRoute} exposes the expected open-model surface.`,
      command: `${inferenceRuntime.engine?.bootstrapCommand || inferenceRuntime.clusterApplyCommand} && ${inferenceRuntime.engine?.rolloutCommand || inferenceRuntime.rolloutCommand}`.trim()
    },
    dynamoControlPlane: {
      headline: "Dynamo control-plane packet",
      lane: "inference",
      prompt: `Stand up the Dynamo frontend for ${project?.projectSlug || "this project"} so the inference fabric exposes one OpenAI-compatible entrypoint on top of the SGLang engine.`,
      command: `${inferenceRuntime.controlPlane?.bootstrapCommand || inferenceRuntime.clusterApplyCommand} && ${inferenceRuntime.controlPlane?.rolloutCommand || inferenceRuntime.rolloutCommand}`.trim()
    },
    ...(inferenceRuntime.compat?.vllm
      ? {
          compatVllm: {
            headline: "Compatibility vLLM packet",
            lane: "inference",
            prompt:
              "Keep the legacy vLLM path visible only as an optional compatibility surface while SGLang + Dynamo remain the primary inference fabric.",
            command: `inspect ${inferenceRuntime.compat.vllm.endpoint || "legacy-vllm"} as a fallback-only route`
          }
        }
      : {}),
    ...(sounioContractPack
      ? {
          sounioWorkflowCheck: {
            headline: "Sounio workflow check packet",
            lane: "sounio",
            objective: `Run the full Sounio contract pack for ${currentDatasetLabel} before promoting the scientific workflow.`,
            contracts: sounioContractPack.contracts,
            route: `/api/projects/${project?.projectSlug || "unknown"}/workflows/scientific/checks/run`,
            command: `curl -X POST /api/projects/${project?.projectSlug || "unknown"}/workflows/scientific/checks/run`
          }
        }
      : {}),
    ...(sounioContractPack
      ? {
          sounioContractPack: {
            headline: sounioContractPack.headline,
            lane: sounioContractPack.lane,
            objective: sounioContractPack.objective,
            contracts: sounioContractPack.contracts,
            command: sounioContractPack.contracts.map((entry) => entry.command).join(" && ")
          }
        }
      : {}),
    ...(sounioScientificContract
      ? {
          sounioScientificContract: {
            headline: sounioScientificContract.headline,
            lane: sounioScientificContract.lane,
            objective: sounioScientificContract.objective,
            contractPath: sounioScientificContract.contractPath,
            prompt: sounioScientificContract.prompt,
            command: sounioScientificContract.command
          }
        }
      : {})
  };

  return {
    routing: {
      status: recommendation.recommendedAgent ? "ready" : "planned",
      recommendedAgent: recommendation.recommendedAgent,
      mode: recommendation.mode,
      lane: recommendation.lane,
      rationale: recommendation.rationale,
      alternatives: [
        { name: "claude-code", mode: "hybrid", status: "ready" },
        { name: "codex", mode: "vsix-first", status: "runtime-unverified" },
        { name: "kimi", mode: "external-second-opinion", status: "planned" }
      ],
      truth: routingTruth
    },
    knowledgeGraph: {
      status: graphAnchors.length >= 3 ? "anchored" : "planned",
      anchorCount: graphAnchors.length,
      primaryAnchors: graphAnchors,
      graphEdges,
      suggestedQueries: graphQueries,
      provenanceMode: graphAnchors.includes(`dataset:${selectedDatasetId}`) ? "dataset-linked" : "project-linked",
      truth: graphTruth
    },
    agentLedger: {
      activeCount: Array.isArray(ide?.aiIdeAgents) ? ide.aiIdeAgents.length : 0,
      activeAgents: Array.isArray(ide?.aiIdeAgents)
        ? ide.aiIdeAgents.map((agent) => ({
            name: agent?.name || "unknown",
            mode: agent?.mode || "unknown",
            status: agent?.status || "planned"
          }))
        : [],
      recentLane: recommendation.lane || "workspace",
      truth: routingTruth
    },
    taskPlan,
    scientificWorkflow,
    researchPacket,
    inferenceRuntime,
    sounioContractPack,
    sounioScientificContract,
    executionPackets
  };
}

function buildViewerStateSummary(project, latestSession, datasetCatalog = []) {
  const defaultDatasetId =
    project?.viewerDefaults?.entryDatasetId ||
    (Array.isArray(datasetCatalog) && datasetCatalog[0]?.id ? datasetCatalog[0].id : "");
  const selectedDatasetId = latestSession?.lastViewerDatasetId || defaultDatasetId || "";
  const selectedDataset =
    datasetCatalog.find((dataset) => dataset.id === selectedDatasetId) || datasetCatalog[0] || null;
  const sceneTruth =
    latestSession?.lastViewerSceneAt && latestSession?.lastViewerDatasetId
      ? { source: "cached", truthMode: "remembered", at: latestSession.lastViewerSceneAt }
      : selectedDataset?.truth || { source: "declared", truthMode: "declared", at: "" };
  const rendererTruth =
    latestSession?.lastViewerRendererStatus
      ? {
          source: latestSession?.lastViewerRendererSource || "cached",
          truthMode: latestSession?.lastViewerRendererTruthMode || "remembered",
          at: latestSession?.lastViewerSceneAt || ""
        }
      : { source: "declared", truthMode: "declared", at: "" };

  return {
    currentDatasetId: selectedDatasetId,
    selectedDataset,
    scene: {
      datasetId: selectedDatasetId,
      channel: latestSession?.lastViewerChannel || project?.viewerDefaults?.defaultChannel || "signal",
      scale: latestSession?.lastViewerScale || project?.viewerDefaults?.defaultScale || "auto",
      camera: latestSession?.lastViewerCamera || project?.viewerDefaults?.camera || "overview",
      truth: sceneTruth
    },
    renderer: {
      status: latestSession?.lastViewerRendererStatus || "booting",
      message: latestSession?.lastViewerRendererMessage || "viewer runtime not observed yet",
      truth: rendererTruth,
      runtime: {
        api: latestSession?.lastViewerRendererRuntime || "webgpu",
        backend: latestSession?.lastViewerRendererBackend || "unknown",
        adapter: latestSession?.lastViewerRendererAdapter || "unknown",
        format: latestSession?.lastViewerRendererFormat || "unknown",
        features: cleanDelimitedList(latestSession?.lastViewerRendererFeatures),
        limits: cleanDelimitedList(latestSession?.lastViewerRendererLimits),
        observedAt: latestSession?.lastViewerRendererObservedAt || latestSession?.lastViewerSceneAt || ""
      }
    },
    provenance: selectedDataset?.provenance || {}
  };
}

function buildRuntimeCapabilitySummary(project) {
  const declared = project?.runtimeCapabilities || {};
  const humanRoute =
    project.browserAutomationPublicUrl ||
    project.workspacePublicUrl ||
    project.workspaceBrowserUrl ||
    "";
  const automationRoute = project.browserAutomationUrl || "";

  return {
    web: {
      ...declared.web,
      humanRoute,
      automationRoute,
      automationRuntime: "vip-for-chrome-automation",
      status: declared.web?.status || (humanRoute ? "ready" : "partial"),
      truth: {
        source: "declared",
        truthMode: "declared"
      }
    },
    desktop: {
      ...declared.desktop,
      status: declared.desktop?.status || "planned",
      shells: declared.desktop?.shells || ["windows", "macos"],
      rendering: declared.desktop?.rendering || "webgpu-target",
      truth: {
        source: "declared",
        truthMode: "declared"
      }
    },
    ios: {
      ...declared.ios,
      status: declared.ios?.status || "planned",
      shell: declared.ios?.shell || "ios-native",
      interaction: declared.ios?.interaction || "touch-first",
      rendering: declared.ios?.rendering || "webgpu-target",
      layoutMode: declared.ios?.layoutMode || "single-pane",
      truth: {
        source: "declared",
        truthMode: "declared"
      }
    },
    vision: {
      ...declared.vision,
      status: declared.vision?.status || "planned",
      shell: declared.vision?.shell || "visionos-native",
      interaction: declared.vision?.interaction || "spatial-control-room",
      layoutMode: declared.vision?.layoutMode || "multi-panel",
      rendering: declared.vision?.rendering || "webgpu-target",
      target: declared.vision?.target || "control-room-first",
      truth: {
        source: "declared",
        truthMode: "declared"
      }
    }
  };
}

function buildSounioScientificContractPacket(project, selectedDatasetId = "") {
  if (project?.projectSlug !== "sounio") {
    return null;
  }
  const datasetLabel = selectedDatasetId || "the current dataset";
  return {
    headline: "Sounio scientific contract",
    lane: "sounio",
    objective:
      `Express provenance, confidence gates, and workflow acceptance for ${datasetLabel} in Sounio instead of scattering those semantics across UI code.`,
    contractPath: "examples/playground_scientific_contract.sio",
    prompt:
      `Use Sounio as the language of the scientific/provenance lane: define a contract for ${datasetLabel}, encode confidence/provenance assumptions, and make the acceptance rule explicit.`,
    command:
      "cd /home/devsounio/sounio && ./bin/souc check examples/playground_scientific_contract.sio"
  };
}

function buildSounioScientificContractPack(project, selectedDatasetId = "") {
  if (project?.projectSlug !== "sounio") {
    return null;
  }

  const datasetLabel = selectedDatasetId || "the current dataset";
  return {
    lane: "sounio",
    headline: "Sounio contract pack",
    objective:
      `Use Sounio as the language of the scientific/provenance lane for ${datasetLabel}, covering scene acceptance, provenance linkage, and publication readiness.`,
    contracts: [
      {
        id: "scientific-contract",
        label: "Scientific scene contract",
        contractPath: "examples/playground_scientific_contract.sio",
        objective:
          `Encode the main scientific acceptance rule for ${datasetLabel} with remembered/observed truth made explicit.`,
        command:
          "cd /home/devsounio/sounio && ./bin/souc check examples/playground_scientific_contract.sio"
      },
      {
        id: "provenance-gate",
        label: "Provenance gate contract",
        contractPath: "examples/playground_provenance_gate.sio",
        objective:
          `Require dataset, artifact, and generation-path linkage before the viewer state can claim provenance for ${datasetLabel}.`,
        command:
          "cd /home/devsounio/sounio && ./bin/souc check examples/playground_provenance_gate.sio"
      },
      {
        id: "publication-gate",
        label: "Publication gate contract",
        contractPath: "examples/playground_publication_gate.sio",
        objective:
          "Make the scientific publication gate explicit so review/publication state can be validated without scattering the rule across UI code.",
        command:
          "cd /home/devsounio/sounio && ./bin/souc check examples/playground_publication_gate.sio"
      }
    ]
  };
}

function buildInferenceRuntimeSummary(project) {
  const declared = project?.inferenceCapabilities || {};
  const fabric = declared?.fabric || {};
  const sglang = declared?.sglang || {};
  const dynamo = declared?.dynamo || {};
  const compatVllm = declared?.compat?.vllm || {};
  const models = Array.isArray(sglang.models)
    ? sglang.models
    : Array.isArray(fabric.models)
      ? fabric.models
      : [];
  const engineEndpoint = normalizeHttpBaseUrl(
    getServiceEnvBaseUrl(sglangServiceName, 30000) || sglang.endpoint || defaultSglangEndpoint
  );
  const controlPlaneEndpoint = normalizeHttpBaseUrl(
    getServiceEnvBaseUrl(dynamoServiceName, 8000) || dynamo.endpoint || defaultDynamoEndpoint
  );
  const endpoint = controlPlaneEndpoint || engineEndpoint;
  const docsPath =
    fabric.docsPath || "/home/devsounio/beagle/docs/INFERENCE_FABRIC_SGLANG_DYNAMO.md";
  return {
    provider: "inference-fabric",
    primaryFabric: fabric.primaryFabric || "sglang+dynamo",
    status: fabric.status || "prototype",
    surface: fabric.surface || declared.surface || "private",
    target: fabric.target || declared.target || "cluster-inference-fabric",
    compatibility:
      fabric.compatibility ||
      declared.compatibility ||
      "openai-compatible via dynamo frontend",
    objective:
      fabric.objective ||
      declared.objective ||
      "Route private open-model inference through a Dynamo control plane backed by an SGLang GPU runtime.",
    endpoint,
    deliveryMode: fabric.deliveryMode || "cluster-gpu-inference-fabric",
    docsPath,
    clusterApplyCommand:
      fabric.clusterApplyCommand ||
      "/home/devsounio/beagle/scripts/infrastructure/deploy_sglang_dynamo_fabric.sh beagle",
    rolloutCommand:
      fabric.rolloutCommand ||
      `kubectl -n ${inferenceNamespace} rollout status deployment/${sglangDeploymentName} --timeout=15m && kubectl -n ${inferenceNamespace} rollout status deployment/${dynamoDeploymentName} --timeout=15m`,
    logsCommand:
      fabric.logsCommand ||
      `kubectl -n ${inferenceNamespace} logs deploy/${sglangDeploymentName} -f && kubectl -n ${inferenceNamespace} logs deploy/${dynamoDeploymentName} -f`,
    testCommand:
      fabric.testCommand ||
      `curl -fsS ${controlPlaneEndpoint || engineEndpoint}/v1/models && curl -fsS ${engineEndpoint || controlPlaneEndpoint}/v1/models`,
    route: `/api/projects/${project?.projectSlug || "unknown"}/inference/runtime`,
    modelsRoute: `/api/projects/${project?.projectSlug || "unknown"}/inference/models`,
    bootstrapRoute: `/api/projects/${project?.projectSlug || "unknown"}/inference/bootstrap`,
    workloadRoute: `/api/projects/${project?.projectSlug || "unknown"}/inference/workload`,
    models,
    engine: {
      provider: "sglang",
      role: "engine",
      status: sglang.status || "planned",
      target: sglang.target || "gpu-runtime",
      endpoint: engineEndpoint,
      healthPath: sglang.healthPath || "/health",
      modelsPath: sglang.modelsPath || "/v1/models",
      completionsPath: sglang.completionsPath || "/v1/completions",
      chatCompletionsPath: sglang.chatCompletionsPath || "/v1/chat/completions",
      docsPath: sglang.docsPath || docsPath,
      startupScript: sglang.startupScript || "cluster-managed",
      tmuxSession: sglang.tmuxSession || "cluster-managed",
      bootstrapCommand:
        sglang.bootstrapCommand ||
        "/home/devsounio/beagle/scripts/infrastructure/deploy_sglang_dynamo_fabric.sh beagle",
      rolloutCommand:
        sglang.rolloutCommand ||
        `kubectl -n ${inferenceNamespace} rollout status deployment/${sglangDeploymentName} --timeout=15m`,
      logsCommand:
        sglang.logsCommand ||
        `kubectl -n ${inferenceNamespace} logs deploy/${sglangDeploymentName} -f`,
      testCommand: sglang.testCommand || `curl -fsS ${engineEndpoint}/v1/models`,
      models
    },
    controlPlane: {
      provider: "dynamo",
      role: "control-plane",
      status: dynamo.status || "planned",
      target: dynamo.target || "openai-compatible-routing-frontend",
      endpoint: controlPlaneEndpoint,
      healthPath: dynamo.healthPath || "/health",
      modelsPath: dynamo.modelsPath || "/v1/models",
      completionsPath: dynamo.completionsPath || "/v1/completions",
      chatCompletionsPath: dynamo.chatCompletionsPath || "/v1/chat/completions",
      docsPath: dynamo.docsPath || docsPath,
      startupScript: dynamo.startupScript || "cluster-managed",
      tmuxSession: dynamo.tmuxSession || "cluster-managed",
      bootstrapCommand:
        dynamo.bootstrapCommand ||
        "/home/devsounio/beagle/scripts/infrastructure/deploy_sglang_dynamo_fabric.sh beagle",
      rolloutCommand:
        dynamo.rolloutCommand ||
        `kubectl -n ${inferenceNamespace} rollout status deployment/${dynamoDeploymentName} --timeout=15m`,
      logsCommand:
        dynamo.logsCommand ||
        `kubectl -n ${inferenceNamespace} logs deploy/${dynamoDeploymentName} -f`,
      testCommand: dynamo.testCommand || `curl -fsS ${controlPlaneEndpoint}/v1/models`
    },
    compat: compatVllm?.endpoint || compatVllmEndpoint
      ? {
          vllm: {
            provider: "vllm",
            status: compatVllm.status || "legacy",
            endpoint: normalizeHttpBaseUrl(compatVllm.endpoint || compatVllmEndpoint),
            role: "compatibility"
          }
        }
      : {},
    candidateEndpoints: [
      controlPlaneEndpoint,
      engineEndpoint,
      normalizeHttpBaseUrl(compatVllm.endpoint || compatVllmEndpoint),
      `http://${dynamoServiceName}.${inferenceNamespace}.svc.cluster.local:8000`,
      `http://${sglangServiceName}.${inferenceNamespace}.svc.cluster.local:30000`,
      `http://${dynamoServiceName}:8000`,
      `http://${sglangServiceName}:30000`,
      "http://10.100.100.2:8000",
      "http://10.100.100.2:30000",
      "http://localhost:8000",
      "http://127.0.0.1:8000",
      "http://localhost:30000",
      "http://127.0.0.1:30000"
    ]
      .filter(Boolean)
      .filter((value, index, items) => items.indexOf(value) === index),
    truth: {
      source: "declared",
      truthMode: "declared"
    }
  };
}

async function readInferenceComponentWorkload({ deploymentName, serviceName, port, label }) {
  const [deployment, service, pods] = await Promise.all([
    readKubeJsonWithFallback(
      `/apis/apps/v1/namespaces/${encodeURIComponent(inferenceNamespace)}/deployments/${encodeURIComponent(deploymentName)}`,
      ["-n", inferenceNamespace, "get", "deployment", deploymentName],
      { timeoutMs: 3500, allowKubectlFallback: false }
    ).catch((error) => {
      const message = cleanValue(error?.stderr || error?.stdout || error?.message || "");
      if (error?.statusCode === 404 || /NotFound/i.test(message)) {
        return null;
      }
      throw error;
    }),
    readKubeJsonWithFallback(
      `/api/v1/namespaces/${encodeURIComponent(inferenceNamespace)}/services/${encodeURIComponent(serviceName)}`,
      ["-n", inferenceNamespace, "get", "service", serviceName],
      { timeoutMs: 3500, allowKubectlFallback: false }
    ).catch((error) => {
      const message = cleanValue(error?.stderr || error?.stdout || error?.message || "");
      if (error?.statusCode === 404 || /NotFound/i.test(message)) {
        return null;
      }
      throw error;
    }),
    readKubeJsonWithFallback(
      `/api/v1/namespaces/${encodeURIComponent(inferenceNamespace)}/pods?labelSelector=${encodeURIComponent(`app.kubernetes.io/name=${label}`)}`,
      ["-n", inferenceNamespace, "get", "pods", "-l", `app.kubernetes.io/name=${label}`],
      { timeoutMs: 3500, allowKubectlFallback: false }
    ).catch(() => ({ items: [] }))
  ]);

  const podItems = Array.isArray(pods?.items) ? pods.items : [];
  const podSummaries = podItems.map((pod) => {
    const statuses = Array.isArray(pod?.status?.containerStatuses) ? pod.status.containerStatuses : [];
    const restartCount = statuses.reduce(
      (sum, status) => sum + Number(status?.restartCount || 0),
      0
    );
    return {
      name: cleanValue(pod?.metadata?.name || ""),
      phase: cleanValue(pod?.status?.phase || "Unknown"),
      nodeName: cleanValue(pod?.spec?.nodeName || ""),
      podIP: cleanValue(pod?.status?.podIP || ""),
      ready: statuses.some((status) => status?.ready),
      restartCount
    };
  });

  const servicePort = Array.isArray(service?.spec?.ports) ? service.spec.ports[0] || null : null;
  const readyPod = podSummaries.find((pod) => pod.ready && pod.podIP);
  const internalUrl =
    readyPod && (servicePort || port)
      ? `http://${readyPod.podIP}:${servicePort?.port || port}`
      : service && (servicePort || port)
        ? `http://${service.metadata.name}.${service.metadata.namespace}.svc.cluster.local:${servicePort?.port || port}`
        : "";
  const availableReplicas = Number(deployment?.status?.availableReplicas || 0);
  const readyReplicas = Number(deployment?.status?.readyReplicas || 0);

  return {
    deploymentName,
    serviceName,
    label,
    status:
      availableReplicas > 0
        ? "ready"
        : deployment
          ? "starting"
          : "not-deployed",
    replicas: Number(deployment?.spec?.replicas || 0),
    readyReplicas,
    availableReplicas,
    internalUrl,
    deploymentCreatedAt: cleanValue(deployment?.metadata?.creationTimestamp || ""),
    pods: podSummaries,
    service: service
      ? {
          clusterIP: cleanValue(service?.spec?.clusterIP || ""),
          port: Number(servicePort?.port || port || 0),
          targetPort: Number(servicePort?.targetPort || 0)
        }
      : null
  };
}

async function readInferenceFabricPrereqs() {
  const cached = getCachedInferencePrereqs();
  if (cached) {
    return cached;
  }

  const secretName = "ai-dynamo-pull-secret";
  const platformNamespace = "dynamo-system";
  const [dynamoPullSecretPresent, platformNamespacePresent, dynamoCrds, platformDeployments] =
    await Promise.all([
      readKubeJsonWithFallback(
        `/api/v1/namespaces/${encodeURIComponent(inferenceNamespace)}/secrets/${encodeURIComponent(secretName)}`,
        ["-n", inferenceNamespace, "get", "secret", secretName],
        { timeoutMs: 2500, allowKubectlFallback: false }
      )
        .then(() => true)
        .catch((error) => {
          const message = cleanValue(error?.stderr || error?.stdout || error?.message || "");
          if (error?.statusCode === 404 || /NotFound/i.test(message)) {
            return false;
          }
          return false;
        }),
      readKubeJsonWithFallback(
        `/api/v1/namespaces/${encodeURIComponent(platformNamespace)}`,
        ["get", "namespace", platformNamespace],
        { timeoutMs: 2500, allowKubectlFallback: false }
      )
        .then(() => true)
        .catch(() => false),
      readKubeJsonWithFallback(
        "/apis/apiextensions.k8s.io/v1/customresourcedefinitions",
        ["get", "crd"],
        { timeoutMs: 2500, allowKubectlFallback: false }
      )
        .then((payload) => {
          const items = Array.isArray(payload?.items) ? payload.items : [];
          return items
            .map((item) => cleanValue(item?.metadata?.name || ""))
            .filter((name) => /dynamo/i.test(name));
        })
        .catch(() => []),
      readKubeJsonWithFallback(
        `/apis/apps/v1/namespaces/${encodeURIComponent(platformNamespace)}/deployments`,
        ["-n", platformNamespace, "get", "deployment"],
        { timeoutMs: 2500, allowKubectlFallback: false }
      )
        .then((payload) => {
          const items = Array.isArray(payload?.items) ? payload.items : [];
          return items
            .map((item) => cleanValue(item?.metadata?.name || ""))
            .filter(Boolean);
        })
        .catch(() => [])
    ]);

  const crdsPresent = dynamoCrds.length > 0;
  const operatorPresent =
    platformDeployments.some((name) => /operator|controller-manager/i.test(name)) ||
    platformDeployments.some((name) => /dynamo/i.test(name));
  const status =
    platformNamespacePresent && crdsPresent && operatorPresent
      ? "platform-ready"
      : "platform-missing";
  const missing = [
    platformNamespacePresent ? "" : platformNamespace,
    crdsPresent ? "" : "dynamo-platform-crds",
    operatorPresent ? "" : "dynamo-operator"
  ].filter(Boolean);

  const value = {
    dynamo: {
      platformNamespace,
      pullSecretName: secretName,
      pullSecretPresent: dynamoPullSecretPresent,
      platformNamespacePresent,
      crdsPresent,
      crdNames: dynamoCrds,
      operatorPresent,
      deploymentNames: platformDeployments,
      status,
      lastError: missing.length ? `${missing.join(", ")} missing` : ""
    }
  };
  setCachedInferencePrereqs(value);
  return value;
}

async function readInferenceWorkload() {
  const [engine, controlPlane] = await Promise.all([
    readInferenceComponentWorkload({
      deploymentName: sglangDeploymentName,
      serviceName: sglangServiceName,
      port: 30000,
      label: "sglang-serving"
    }),
    readInferenceComponentWorkload({
      deploymentName: dynamoDeploymentName,
      serviceName: dynamoServiceName,
      port: 8000,
      label: "dynamo-control-plane"
    })
  ]);

  const ready = engine.status === "ready" && controlPlane.status === "ready";
  const anyPresent =
    engine.status !== "not-deployed" || controlPlane.status !== "not-deployed";

  return {
    namespace: inferenceNamespace,
    status: ready ? "ready" : anyPresent ? "starting" : "not-deployed",
    primaryEndpoint: controlPlane.internalUrl || engine.internalUrl || "",
    engine,
    controlPlane,
    compat: compatVllmEndpoint
      ? {
          vllm: {
            status: "legacy",
            endpoint: normalizeHttpBaseUrl(compatVllmEndpoint)
          }
        }
      : {}
  };
}

async function readInferenceWorkerMetadata() {
  const payload = await readKubeJsonWithFallback(
    `/apis/nvidia.com/v1alpha1/namespaces/${encodeURIComponent(inferenceNamespace)}/dynamoworkermetadatas`,
    ["-n", inferenceNamespace, "get", "dynamoworkermetadatas.nvidia.com"],
    { timeoutMs: 2500, allowKubectlFallback: false }
  ).catch(() => ({ items: [] }));

  const items = Array.isArray(payload?.items) ? payload.items : [];
  const models = [];
  const backendTransports = [];
  const namespaces = new Set();

  for (const item of items) {
    const modelCards = item?.spec?.data?.model_cards || {};
    for (const entry of Object.values(modelCards)) {
      const namespace = cleanValue(entry?.namespace || "");
      if (namespace) {
        namespaces.add(namespace);
      }
      const card = entry?.card_json || {};
      const id =
        cleanValue(card?.display_name || "") ||
        cleanValue(card?.slug || "") ||
        cleanValue(card?.source_path || "");
      if (id) {
        models.push({
          id,
          family: "sglang",
          provider: "dynamo-worker-metadata",
          status: "registered"
        });
      }
      const transport = cleanValue(card?.runtime_config?.disaggregated_endpoint?.bootstrap_host || "");
      const port = Number(card?.runtime_config?.disaggregated_endpoint?.bootstrap_port || 0);
      if (transport && port > 0) {
        backendTransports.push(`tcp://${transport}:${port}`);
      }
    }

    const endpoints = item?.spec?.data?.endpoints || {};
    for (const entry of Object.values(endpoints)) {
      const namespace = cleanValue(entry?.namespace || "");
      if (namespace) {
        namespaces.add(namespace);
      }
      const tcpTransport = cleanValue(entry?.transport?.tcp || "");
      if (tcpTransport) {
        backendTransports.push(`tcp://${tcpTransport}`);
      }
    }
  }

  return {
    status: models.length || backendTransports.length ? "registered" : "unavailable",
    models,
    backendTransports: Array.from(new Set(backendTransports)),
    namespaces: Array.from(namespaces)
  };
}

async function probeInferenceEndpoint({ endpoint, healthPath, modelsPath, family }) {
  if (!endpoint) {
    return {
      reachable: false,
      status: "unconfigured",
      lastError: "No endpoint configured",
      healthUrl: "",
      modelsUrl: "",
      models: []
    };
  }

  const healthUrl = `${endpoint}${healthPath}`;
  const modelsUrl = `${endpoint}${modelsPath}`;
  let reachable = false;
  let status = "unreachable";
  let lastError = "";
  let models = [];

  try {
    await fetchRemoteText(healthUrl, inferenceProbeTimeoutMs);
    reachable = true;
    status = "ready";
  } catch (error) {
    lastError = cleanValue(error?.message || "health probe failed");
  }

  try {
    const payload = await fetchRemoteJson(modelsUrl, inferenceProbeTimeoutMs);
    models = Array.isArray(payload?.data)
      ? payload.data.map((entry) => ({
          id: cleanValue(entry?.id || "unknown-model"),
          family: cleanValue(entry?.owned_by || family || "open-model"),
          status: "ready"
        }))
      : [];
    if (models.length) {
      reachable = true;
      status = "ready";
      lastError = "";
    }
  } catch (error) {
    if (!lastError) {
      lastError = cleanValue(error?.message || "models probe failed");
    }
  }

  return { reachable, status, lastError, healthUrl, modelsUrl, models };
}

async function resolveInferenceRuntime(project) {
  const declared = buildInferenceRuntimeSummary(project);
  const [workload, prereqs, workerMetadata] = await Promise.all([
    withTimeout(
      readInferenceWorkload(),
      "inference workload",
      inferenceWorkloadTimeoutMs
    ).catch((error) => ({
      status: "unknown",
      lastError: cleanValue(error?.message || "workload probe failed"),
        engine: { status: "unknown", pods: [] },
        controlPlane: { status: "unknown", pods: [] }
    })),
    readInferenceFabricPrereqs().catch(() => ({
      dynamo: {
        pullSecretPresent: false,
        status: "unknown",
        lastError: ""
      }
    })),
    readInferenceWorkerMetadata().catch(() => ({
      status: "unavailable",
      models: [],
      backendTransports: [],
      namespaces: []
    }))
  ]);

  const effectiveControlPlaneEndpoint =
    workload?.controlPlane?.internalUrl || declared.controlPlane?.endpoint || "";
  const effectiveEngineEndpoint =
    workload?.engine?.internalUrl || declared.engine?.endpoint || "";

  const [controlPlaneProbe, engineProbe] = await Promise.all([
    probeInferenceEndpoint({
      endpoint: effectiveControlPlaneEndpoint,
      healthPath: declared.controlPlane?.healthPath || "/health",
      modelsPath: declared.controlPlane?.modelsPath || "/v1/models",
      family: "dynamo"
    }),
    probeInferenceEndpoint({
      endpoint: effectiveEngineEndpoint,
      healthPath: declared.engine?.healthPath || "/health",
      modelsPath: declared.engine?.modelsPath || "/v1/models",
      family: "sglang"
    })
  ]);

  const controlPlaneReachable = controlPlaneProbe.reachable;
  const engineReachable = engineProbe.reachable;
  const engineRegistered = Array.isArray(workerMetadata?.models) && workerMetadata.models.length > 0;
  const controlPlanePublishedModels =
    Array.isArray(controlPlaneProbe.models) && controlPlaneProbe.models.length > 0;
  const publishedViaControlPlane = controlPlaneReachable && engineRegistered;
  const controlPlanePlatformMissing =
    !controlPlaneReachable &&
    prereqs?.dynamo?.status === "platform-missing";
  const effectiveControlPlaneStatus = controlPlanePlatformMissing
    ? "platform-missing"
    : controlPlaneProbe.status;
  const effectiveControlPlaneError =
    controlPlaneReachable
      ? ""
      : controlPlanePlatformMissing
        ? prereqs?.dynamo?.lastError || "Dynamo platform prerequisites missing"
        : controlPlaneProbe.lastError;
  const observedModels =
    controlPlaneProbe.models.length > 0
      ? controlPlaneProbe.models
      : engineProbe.models.length > 0
        ? engineProbe.models
        : workerMetadata?.models || [];
  const reachable = controlPlaneReachable || engineReachable || engineRegistered;
  const engineAccessMode =
    publishedViaControlPlane
      ? "published-via-control-plane"
      : engineReachable
        ? "direct"
        : engineRegistered
          ? "registered-only"
          : "unpublished";
  const engineStatus = publishedViaControlPlane
    ? "published-via-control-plane"
    : engineReachable
      ? engineProbe.status
      : engineRegistered
        ? "registered"
        : engineProbe.status;
  const effectiveEngineError =
    publishedViaControlPlane || engineReachable
      ? ""
      : engineRegistered
        ? ""
        : engineProbe.lastError;
  const status =
    controlPlaneReachable && (engineReachable || controlPlanePublishedModels || engineRegistered)
      ? "ready"
      : engineReachable && controlPlanePlatformMissing
        ? "engine-ready-control-plane-missing"
      : reachable
        ? "partial-ready"
        : controlPlanePlatformMissing
          ? "platform-missing"
        : "prototype-unreachable";
  const endpoint =
    publishedViaControlPlane || controlPlaneReachable || !controlPlanePlatformMissing
      ? effectiveControlPlaneEndpoint || effectiveEngineEndpoint || declared.endpoint
      : effectiveEngineEndpoint || declared.endpoint;
  const effectiveEngineHealthUrl =
    publishedViaControlPlane || !effectiveEngineEndpoint
      ? ""
      : engineProbe.healthUrl;
  const effectiveEngineModelsUrl =
    publishedViaControlPlane || !effectiveEngineEndpoint
      ? ""
      : engineProbe.modelsUrl;

  return {
    ...declared,
    configured: Boolean(declared.endpoint || declared.engine?.endpoint || declared.controlPlane?.endpoint),
    reachable,
    status,
    truthMode: reachable ? "observed" : "declared",
    healthStatus: effectiveControlPlaneStatus,
    lastError:
      status === "ready"
        ? ""
        : effectiveControlPlaneError ||
          effectiveEngineError ||
          workload?.lastError ||
          "",
    models: observedModels.length ? observedModels : declared.models,
    workload,
    controlPlane: {
      ...declared.controlPlane,
      endpoint: effectiveControlPlaneEndpoint || declared.controlPlane?.endpoint || "",
      ...controlPlaneProbe,
      status: effectiveControlPlaneStatus,
      lastError: effectiveControlPlaneError,
      platform: prereqs?.dynamo || null
    },
    engine: {
      ...declared.engine,
      endpoint: effectiveEngineEndpoint || declared.engine?.endpoint || "",
      ...engineProbe,
      status: engineStatus,
      accessMode: engineAccessMode,
      lastError: effectiveEngineError,
      healthUrl: effectiveEngineHealthUrl,
      modelsUrl: effectiveEngineModelsUrl,
      backendTransports: workerMetadata?.backendTransports || [],
      discoveryNamespaces: workerMetadata?.namespaces || []
    },
    endpoint,
    healthUrl:
      (publishedViaControlPlane || controlPlaneReachable || !controlPlanePlatformMissing
        ? controlPlaneProbe.healthUrl
        : "") || engineProbe.healthUrl,
    modelsUrl:
      (publishedViaControlPlane || controlPlaneReachable || !controlPlanePlatformMissing
        ? controlPlaneProbe.modelsUrl
        : "") || engineProbe.modelsUrl,
    completionsUrl: publishedViaControlPlane || controlPlaneReachable || !controlPlanePlatformMissing
      ? effectiveControlPlaneEndpoint
        ? `${effectiveControlPlaneEndpoint}${declared.controlPlane.completionsPath}`
        : ""
      : effectiveEngineEndpoint
        ? `${effectiveEngineEndpoint}${declared.engine.completionsPath}`
        : "",
    chatCompletionsUrl: publishedViaControlPlane || controlPlaneReachable || !controlPlanePlatformMissing
      ? effectiveControlPlaneEndpoint
        ? `${effectiveControlPlaneEndpoint}${declared.controlPlane.chatCompletionsPath}`
        : ""
      : effectiveEngineEndpoint
        ? `${effectiveEngineEndpoint}${declared.engine.chatCompletionsPath}`
        : "",
    truth: {
      source: reachable ? "live" : "declared",
      truthMode: reachable ? "observed" : "declared"
    },
    fabricPrereqs: prereqs,
    controlPlaneMissing: controlPlanePlatformMissing
  };
}

async function readResolvedInferenceRuntime(project, { preferStale = false } = {}) {
  const cached = getCachedInferenceRuntime(project.projectSlug, { allowStale: preferStale });
  if (cached?.value) {
    if (preferStale && cached.isStale && !cached.promise) {
      const refresh = resolveInferenceRuntime(project)
        .then((value) => {
          setCachedInferenceRuntime(project.projectSlug, value, null);
          return value;
        })
        .catch(() => {
          const current = getCachedInferenceRuntime(project.projectSlug, { allowStale: true });
          if (current?.value) {
            setCachedInferenceRuntime(project.projectSlug, current.value, null);
            return current.value;
          }
          invalidateInferenceRuntime(project.projectSlug);
          throw new Error("inference runtime refresh failed");
        });
      setCachedInferenceRuntime(project.projectSlug, cached.value, refresh);
    }
    return cached.value;
  }
  if (cached?.promise) {
    return cached.promise;
  }

  const pending = resolveInferenceRuntime(project)
    .then((value) => {
      setCachedInferenceRuntime(project.projectSlug, value, null);
      return value;
    })
    .catch((error) => {
      invalidateInferenceRuntime(project.projectSlug);
      throw error;
    });

  setCachedInferenceRuntime(project.projectSlug, null, pending);
  return pending;
}

function buildInferenceBootstrapResponse(project) {
  const runtime = buildInferenceRuntimeSummary(project);
  return {
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    surface: "private",
    provider: runtime.provider,
    primaryFabric: runtime.primaryFabric,
    target: runtime.target,
    deliveryMode: runtime.deliveryMode,
    objective: runtime.objective,
    endpoint: runtime.endpoint,
    candidateEndpoints: runtime.candidateEndpoints || [],
    bootstrapCommand: runtime.clusterApplyCommand,
    clusterApplyCommand: runtime.clusterApplyCommand,
    rolloutCommand: runtime.rolloutCommand,
    logsCommand: runtime.logsCommand,
    testCommand: runtime.testCommand,
    docsPath: runtime.docsPath,
    controlPlane: {
      provider: runtime.controlPlane?.provider || "dynamo",
      endpoint: runtime.controlPlane?.endpoint || "",
      startupScript: runtime.controlPlane?.startupScript || "cluster-managed",
      tmuxSession: runtime.controlPlane?.tmuxSession || "cluster-managed",
      bootstrapCommand: runtime.controlPlane?.bootstrapCommand || "",
      rolloutCommand: runtime.controlPlane?.rolloutCommand || "",
      logsCommand: runtime.controlPlane?.logsCommand || "",
      testCommand: runtime.controlPlane?.testCommand || "",
      healthUrl:
        runtime.controlPlane?.endpoint && runtime.controlPlane?.healthPath
          ? `${runtime.controlPlane.endpoint}${runtime.controlPlane.healthPath}`
          : "",
      modelsUrl:
        runtime.controlPlane?.endpoint && runtime.controlPlane?.modelsPath
          ? `${runtime.controlPlane.endpoint}${runtime.controlPlane.modelsPath}`
          : ""
    },
    engine: {
      provider: runtime.engine?.provider || "sglang",
      endpoint: runtime.engine?.endpoint || "",
      startupScript: runtime.engine?.startupScript || "cluster-managed",
      tmuxSession: runtime.engine?.tmuxSession || "cluster-managed",
      bootstrapCommand: runtime.engine?.bootstrapCommand || "",
      rolloutCommand: runtime.engine?.rolloutCommand || "",
      logsCommand: runtime.engine?.logsCommand || "",
      testCommand: runtime.engine?.testCommand || "",
      healthUrl:
        runtime.engine?.endpoint && runtime.engine?.healthPath
          ? `${runtime.engine.endpoint}${runtime.engine.healthPath}`
          : "",
      modelsUrl:
        runtime.engine?.endpoint && runtime.engine?.modelsPath
          ? `${runtime.engine.endpoint}${runtime.engine.modelsPath}`
          : ""
    },
    compat: runtime.compat || {}
  };
}

function buildPlaygroundExecutiveSummary({ project, datasetCatalog, viewerState, runtimeCapabilities }) {
  const datasets = Array.isArray(datasetCatalog) ? datasetCatalog : [];
  const realCount = datasets.filter((entry) => entry?.sourceKind === "real").length;
  const observedCount = datasets.filter((entry) => entry?.truth?.truthMode === "observed").length;
  const multiscaleCount = datasets.filter(
    (entry) => Number(entry?.datasetSummary?.multiscaleCount || 0) > 0
  ).length;
  const selected = viewerState?.selectedDataset || datasets[0] || null;
  const axes = Array.isArray(selected?.datasetSummary?.axes) ? selected.datasetSummary.axes : [];
  const datasetTruth = selected?.truth || { source: "declared", truthMode: "declared" };
  const rendererTruth = viewerState?.renderer?.truth || runtimeCapabilities?.web?.truth || {
    source: "declared",
    truthMode: "declared"
  };

  return {
    status: project?.playgroundClass === "webgpu-first" ? "scientific-ready" : "declared",
    totalDatasets: datasets.length,
    realDatasets: realCount,
    observedDatasets: observedCount,
    multiscaleDatasets: multiscaleCount,
    selectedDatasetId: selected?.id || "",
    selectedDatasetLabel: selected?.label || "none",
    selectedDatasetKind: selected?.kind || "unknown",
    selectedAxes: axes,
    selectedLevels: Number(selected?.datasetSummary?.datasetLevels || 0),
    rendererStatus: viewerState?.renderer?.status || "booting",
    rendererApi: viewerState?.renderer?.runtime?.api || "webgpu",
    rendererBackend: viewerState?.renderer?.runtime?.backend || "unknown",
    rendererFeatureCount: Array.isArray(viewerState?.renderer?.runtime?.features)
      ? viewerState.renderer.runtime.features.length
      : 0,
    renderingTarget:
      runtimeCapabilities?.web?.status === "ready" ? "webgpu-first" : runtimeCapabilities?.web?.status || "planned",
    datasetTruth,
    rendererTruth
  };
}

async function buildCatalogExecutiveEntry(
  project,
  memory = null,
  memoryStatus = "unavailable",
  operationalTruth = null,
  clusterState = null
) {
  const policyIde = inferIdePolicy(project);
  const runtimeCapabilities = buildRuntimeCapabilitySummary(project);
  const datasetCatalog = await resolveDatasetCatalog(project);
  const viewerDefaults = project?.viewerDefaults || {};
  const playgroundClass = project?.playgroundClass || "mission-control";
  const effectiveIde = memory?.ide || {
    ...policyIde,
    ...buildIdeTruth("policy-fallback")
  };
  const truthSummary =
    memory?.resumePacket?.truthSummary || {
      ide: {
        source: effectiveIde.source || "policy-fallback",
        truthMode: effectiveIde.truthMode || "declared"
      },
      publication: { source: "policy-fallback", truthMode: "declared" },
      review: { source: "policy-fallback", truthMode: "declared" },
      cluster: { source: "policy-fallback", truthMode: "declared" }
    };
  const missionControl =
    memory?.resumePacket?.missionControl ||
    buildMissionControlSummary({
      nextSafeMove: "hydrate sovereign memory for next move",
      publicationStage: "working",
      lastMergeReadiness: "no-pr",
      truthSummary
    });
  const viewerState = buildViewerStateSummary(project, (memory?.sessions?.recent || [])[0] || null, datasetCatalog);
  const beagleSubstrate = buildBeagleSubstrateSummary({
    project,
    truthSummary,
    missionControl,
    ide: effectiveIde,
    runtimeCapabilities,
    datasetCatalog,
    viewerState,
    workspace: memory?.workspace || null
  });
  const playgroundExecutive = buildPlaygroundExecutiveSummary({
    project,
    datasetCatalog,
    viewerState,
    runtimeCapabilities
  });
  const clusterLaneTruth = operationalTruth?.clusterLaneTruth || buildDefaultClusterLaneTruth();
  const researchOperations =
    operationalTruth?.researchOperations || buildDefaultResearchOperations(project);
  const operatingPosture = buildProjectOperatingPosture(
    project,
    clusterLaneTruth,
    researchOperations
  );
  const sovereignSurface = buildProjectSovereignSurface(project, {
    clusterState,
    ide: effectiveIde
  });
  const goWorkNow = buildGoWorkNowPacket(project, operatingPosture, clusterState);

  return {
    projectSlug: project.projectSlug,
    mode: project?.mode || "undeclared",
    memoryStatus,
    workspace: memory?.workspace || null,
    publication: memory?.publication || null,
    continuityTimeline: Array.isArray(memory?.resumePacket?.continuityTimeline)
      ? memory.resumePacket.continuityTimeline
      : [],
    ide: {
      substrate: effectiveIde.substrate || policyIde.substrate || "openvscode-server",
      pack: effectiveIde.pack || policyIde.pack || "",
      status: effectiveIde.status || "unknown",
      requiredReady: Boolean(effectiveIde.requiredReady),
      installedCount: Array.isArray(effectiveIde.installedExtensions)
        ? effectiveIde.installedExtensions.length
        : 0,
      missingRequiredCount: Array.isArray(effectiveIde.missingRequired)
        ? effectiveIde.missingRequired.length
        : 0,
      aiIdeAgents: Array.isArray(effectiveIde.aiIdeAgents) ? effectiveIde.aiIdeAgents : [],
      source: effectiveIde.source || "policy-fallback",
      truthMode: effectiveIde.truthMode || "declared"
    },
    truthSummary,
    missionControl,
    beagleSubstrate,
    playgroundExecutive,
    operatingPosture,
    sovereignSurface,
    goWorkNow,
    runtimeCapabilities,
    datasetCatalog,
    viewerDefaults,
    playgroundClass,
    viewerState
  };
}

async function buildBeagleSubstrateResponse(project, depth = "fast") {
  const response =
    depth === "deep"
      ? await buildDeepMemoryResponse(project)
      : await buildFastMemoryResponse(project);
  const memory = response?.memory || {};
  const resumePacket = memory?.resumePacket || {};
  return {
    projectSlug: project.projectSlug,
    depth: response?.depth || depth,
    generatedAt: new Date().toISOString(),
    workspace: memory?.workspace || {},
    viewer: memory?.viewer || {},
    truthSummary: resumePacket.truthSummary || {},
    missionControl: resumePacket.missionControl || {},
    beagleSubstrate: resumePacket.beagleSubstrate || {},
    clusterLaneTruth: resumePacket.clusterLaneTruth || buildDefaultClusterLaneTruth(),
    researchOperations: resumePacket.researchOperations || buildDefaultResearchOperations(project)
  };
}

async function buildPlaygroundExecutiveResponse(project, depth = "fast") {
  const response =
    depth === "deep"
      ? await buildDeepMemoryResponse(project)
      : await buildFastMemoryResponse(project);
  const memory = response?.memory || {};
  const policyIde = inferIdePolicy(project);
  const effectiveIde = memory?.ide || {
    ...policyIde,
    ...buildIdeTruth("policy-fallback")
  };
  const runtimeCapabilities = buildRuntimeCapabilitySummary(project);
  const datasetCatalog = await resolveDatasetCatalog(project);
  const viewerDefaults = project?.viewerDefaults || buildDefaultViewerDefaults({ ...project, datasetCatalog });
  const fastCluster = await readCachedFastClusterState(project, { preferStale: true }).catch(() => null);
  const clusterState = fastCluster?.value || null;
  const playgroundExecutive = buildPlaygroundExecutiveSummary({
    project,
    datasetCatalog,
    viewerState: memory?.viewer || buildViewerStateSummary(project, null, datasetCatalog),
    runtimeCapabilities
  });

  return {
    projectSlug: project.projectSlug,
    depth: response?.depth || depth,
    generatedAt: new Date().toISOString(),
    playgroundClass: project?.playgroundClass || "mission-control",
    runtimeCapabilities,
    datasetCatalog,
    viewerDefaults,
    viewer: memory?.viewer || {},
    playgroundExecutive,
    sovereignSurface: buildProjectSovereignSurface(project, {
      clusterState,
      ide: effectiveIde
    }),
    beagleSubstrate: memory?.resumePacket?.beagleSubstrate || {},
    clusterLaneTruth:
      memory?.resumePacket?.clusterLaneTruth || buildDefaultClusterLaneTruth(),
    researchOperations:
      memory?.resumePacket?.researchOperations || buildDefaultResearchOperations(project)
  };
}

async function buildTruthSummaryResponse(project, depth = "fast") {
  const response =
    depth === "deep"
      ? await buildDeepMemoryResponse(project)
      : await buildFastMemoryResponse(project);
  const memory = response?.memory || {};
  const resumePacket = memory?.resumePacket || {};
  return {
    projectSlug: project.projectSlug,
    depth: response?.depth || depth,
    generatedAt: new Date().toISOString(),
    workspace: memory?.workspace || {},
    publication: memory?.publication || {},
    truthSummary: resumePacket.truthSummary || {}
  };
}

async function buildMissionControlResponse(project, depth = "fast") {
  const response =
    depth === "deep"
      ? await buildDeepMemoryResponse(project)
      : await buildFastMemoryResponse(project);
  const memory = response?.memory || {};
  const resumePacket = memory?.resumePacket || {};
  return {
    projectSlug: project.projectSlug,
    depth: response?.depth || depth,
    generatedAt: new Date().toISOString(),
    workspace: memory?.workspace || {},
    publication: memory?.publication || {},
    missionControl: resumePacket.missionControl || buildMissionControlSummary({}),
    publicationCheckpoint: resumePacket.publicationCheckpoint || {},
    continuityTimeline: Array.isArray(resumePacket.continuityTimeline) ? resumePacket.continuityTimeline : [],
    clusterLaneTruth: resumePacket.clusterLaneTruth || buildDefaultClusterLaneTruth(),
    researchOperations: resumePacket.researchOperations || buildDefaultResearchOperations(project)
  };
}

async function buildClusterLaneTruthResponse(project, depth = "fast") {
  try {
    const { clusterLaneTruth } = await resolveOperationalTruth(project);
    return {
      projectSlug: project.projectSlug,
      depth: "operational",
      generatedAt: new Date().toISOString(),
      clusterLaneTruth: clusterLaneTruth || buildDefaultClusterLaneTruth()
    };
  } catch {
    const response =
      depth === "deep"
        ? await buildDeepMemoryResponse(project)
        : await buildFastMemoryResponse(project);
    const memory = response?.memory || {};
    return {
      projectSlug: project.projectSlug,
      depth: response?.depth || depth,
      generatedAt: new Date().toISOString(),
      clusterLaneTruth:
        memory?.resumePacket?.clusterLaneTruth || buildDefaultClusterLaneTruth()
    };
  }
}

async function buildResearchOperationsResponse(project, depth = "fast") {
  try {
    const { researchOperations } = await resolveOperationalTruth(project);
    return {
      projectSlug: project.projectSlug,
      depth: "operational",
      generatedAt: new Date().toISOString(),
      researchOperations:
        researchOperations || buildDefaultResearchOperations(project)
    };
  } catch {
    const response =
      depth === "deep"
        ? await buildDeepMemoryResponse(project)
        : await buildFastMemoryResponse(project);
    const memory = response?.memory || {};
    return {
      projectSlug: project.projectSlug,
      depth: response?.depth || depth,
      generatedAt: new Date().toISOString(),
      researchOperations:
        memory?.resumePacket?.researchOperations || buildDefaultResearchOperations(project)
    };
  }
}

async function buildSovereignSurfaceResponse(project, depth = "fast") {
  const response =
    depth === "deep"
      ? await buildDeepMemoryResponse(project)
      : await buildFastMemoryResponse(project);
  const memory = response?.memory || {};
  const policyIde = inferIdePolicy(project);
  const effectiveIde = memory?.ide || {
    ...policyIde,
    ...buildIdeTruth("policy-fallback")
  };
  const fastCluster = await readCachedFastClusterState(project, { preferStale: true }).catch(() => null);
  const clusterState = fastCluster?.value || null;
  return {
    projectSlug: project.projectSlug,
    depth: response?.depth || depth,
    generatedAt: new Date().toISOString(),
    sovereignSurface: buildProjectSovereignSurface(project, {
      clusterState,
      ide: effectiveIde
    })
  };
}

async function buildGoWorkNowResponse(project, depth = "fast") {
  const response =
    depth === "deep"
      ? await buildDeepMemoryResponse(project)
      : await buildFastMemoryResponse(project);
  const fastCluster = await readCachedFastClusterState(project, { preferStale: true }).catch(() => null);
  const clusterState = fastCluster?.value || null;
  const operationalTruth = await resolveOperationalTruth(project).catch(() => null);
  const clusterLaneTruth = operationalTruth?.clusterLaneTruth || buildDefaultClusterLaneTruth();
  const researchOperations =
    operationalTruth?.researchOperations || buildDefaultResearchOperations(project);
  const operatingPosture = buildProjectOperatingPosture(
    project,
    clusterLaneTruth,
    researchOperations
  );
  return {
    projectSlug: project.projectSlug,
    depth: response?.depth || depth,
    generatedAt: new Date().toISOString(),
    goWorkNow: buildGoWorkNowPacket(project, operatingPosture, clusterState),
    operatingPosture
  };
}

async function runGoWorkNowAction(project, actionId) {
  const workspaceStatefulSetName = inferWorkspaceStatefulSetName(project);
  const namespace = cleanValue(project.namespace || "beagle");
  let label = "";
  let output = "";

  if (actionId === "activate-habitat") {
    label = `activate-habitat:${workspaceStatefulSetName}`;
    if (cleanValue(project.mode) === "always-on") {
      const { stdout } = await runKubectlPty([
        "-n",
        namespace,
        "rollout",
        "status",
        `statefulset/${workspaceStatefulSetName}`,
        "--timeout=300s"
      ]);
      output = stdout;
    } else {
      const result = await runPtyCommand(
        "/bin/sh",
        [
          "-lc",
          `${shellQuote(kubectlBin)} -n ${shellQuote(namespace)} scale statefulset/${shellQuote(
            workspaceStatefulSetName
          )} --replicas=1 && ` +
            `${shellQuote(kubectlBin)} -n ${shellQuote(namespace)} rollout status statefulset/${shellQuote(
              workspaceStatefulSetName
            )} --timeout=300s`
        ],
        { timeoutMs: 330000 }
      );
      output = sanitizePtyOutput(result.stdout);
    }
    return { label, output };
  }

  if (actionId === "standby-habitat") {
    if (cleanValue(project.mode) === "always-on") {
      const error = new Error("always-on habitats should not be scaled down from go-work-now");
      error.statusCode = 400;
      throw error;
    }
    label = `standby-habitat:${workspaceStatefulSetName}`;
    const { stdout } = await runKubectlPty([
      "-n",
      namespace,
      "scale",
      `statefulset/${workspaceStatefulSetName}`,
      "--replicas=0"
    ]);
    output = stdout;
    for (let attempt = 0; attempt < 30; attempt += 1) {
      const pod = await safeReadPod(namespace, project.workspacePod);
      if (pod?.phase === "NotFound") {
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
    return { label, output };
  }

  const error = new Error(`unknown go-work-now action: ${actionId}`);
  error.statusCode = 404;
  throw error;
}

async function buildGraphLineageResponse(project, depth = "fast") {
  const payload = await buildBeagleSubstrateResponse(project, depth);
  const graph = payload?.beagleSubstrate?.knowledgeGraph || {};
  return {
    projectSlug: project.projectSlug,
    depth: payload.depth,
    generatedAt: new Date().toISOString(),
    workspace: payload.workspace || {},
    missionControl: payload.missionControl || {},
    lineage: {
      status: graph.status || "planned",
      anchorCount: graph.anchorCount || 0,
      primaryAnchors: graph.primaryAnchors || [],
      graphEdges: graph.graphEdges || [],
      suggestedQueries: graph.suggestedQueries || [],
      provenanceMode: graph.provenanceMode || "project-linked",
      truth: graph.truth || { source: "declared", truthMode: "declared" }
    }
  };
}

async function buildScientificWorkflowResponse(project, depth = "fast") {
  const payload = await buildBeagleSubstrateResponse(project, depth);
  const workflow = payload?.beagleSubstrate?.scientificWorkflow || {};
  const packets = payload?.beagleSubstrate?.executionPackets || {};
  const latestCheckRun = await readScientificWorkflowRun(project.projectSlug);
  return {
    projectSlug: project.projectSlug,
    depth: payload.depth,
    generatedAt: new Date().toISOString(),
    missionControl: payload.missionControl || {},
    viewer: payload.viewer || {},
    workflow: {
      headline: workflow.headline || "Scientific workflow packet",
      lane: workflow.lane || "viewer",
      route: workflow.route || `/projects/${project.projectSlug}/viewer`,
      objective: workflow.objective || "",
      steps: Array.isArray(workflow.steps) ? workflow.steps : [],
      contractIds: Array.isArray(workflow.contractIds) ? workflow.contractIds : [],
      contractChecks: Array.isArray(workflow.contractChecks) ? workflow.contractChecks : [],
      contractRoutes: {
        ...(workflow.contractRoutes || {}),
        latestRun: `/api/projects/${project.projectSlug}/workflows/scientific/checks`,
        runChecks: `/api/projects/${project.projectSlug}/workflows/scientific/checks/run`
      }
    },
    latestCheckRun,
    packets: {
      scientificViewer: packets.scientificViewer || null,
      scientificWorkflow: packets.scientificWorkflow || null,
      inferenceFabric: packets.inferenceFabric || null,
      sglangServing: packets.sglangServing || null,
      dynamoControlPlane: packets.dynamoControlPlane || null,
      compatVllm: packets.compatVllm || null,
      researchPacket: packets.researchPacket || null,
      sounioScientificContract: packets.sounioScientificContract || null,
      sounioWorkflowCheck: packets.sounioWorkflowCheck || null,
      sounioContractPack: packets.sounioContractPack || null,
      codex: packets.codex || null,
      claudeCode: packets.claudeCode || null,
      kimi: packets.kimi || null
    }
  };
}

async function runScientificWorkflowChecks(project) {
  const selectedDatasetId =
    project?.viewerDefaults?.entryDatasetId ||
    (Array.isArray(project?.datasetCatalog) ? project.datasetCatalog[0]?.id || "" : "");
  const contractPack = buildSounioScientificContractPack(project, selectedDatasetId);
  const contracts = Array.isArray(contractPack?.contracts) ? contractPack.contracts : [];
  const results = [];

  for (const contract of contracts) {
    const started = Date.now();
    try {
      const { stdout, stderr } = await runShell(contract.command, {
        cwd: "/home/devsounio",
        timeoutMs: 30000
      });
      results.push({
        id: contract.id,
        label: contract.label,
        contractPath: contract.contractPath,
        command: contract.command,
        status: "passed",
        exitCode: 0,
        durationMs: Date.now() - started,
        checkedAt: new Date().toISOString(),
        outputPreview: previewOutput(stdout || stderr || "souc check passed")
      });
    } catch (error) {
      results.push({
        id: contract.id,
        label: contract.label,
        contractPath: contract.contractPath,
        command: contract.command,
        status: "failed",
        exitCode: typeof error?.code === "number" ? error.code : 1,
        durationMs: Date.now() - started,
        checkedAt: new Date().toISOString(),
        outputPreview: previewOutput(
          error?.stderr || error?.stdout || error?.message || "souc check failed"
        )
      });
    }
  }

  const summary = {
    projectSlug: project.projectSlug,
    checkedAt: new Date().toISOString(),
    status: results.every((result) => result.status === "passed") ? "passed" : "failed",
    results
  };

  return writeScientificWorkflowRun(project.projectSlug, summary);
}

async function buildScientificWorkflowChecksResponse(project) {
  return {
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    latestRun: await readScientificWorkflowRun(project.projectSlug)
  };
}

async function buildExecutionPacketsResponse(project, depth = "fast") {
  const payload = await buildBeagleSubstrateResponse(project, depth);
  const packets = payload?.beagleSubstrate?.executionPackets || {};
  return {
    projectSlug: project.projectSlug,
    depth: payload.depth,
    generatedAt: new Date().toISOString(),
    missionControl: payload.missionControl || {},
    routing: payload?.beagleSubstrate?.routing || null,
    taskPlan: payload?.beagleSubstrate?.taskPlan || [],
    packetCount: Object.keys(packets).length,
    packets
  };
}

async function buildExecutionPacketDetailResponse(project, packetName, depth = "fast") {
  const payload = await buildExecutionPacketsResponse(project, depth);
  const packet = payload?.packets?.[packetName] || null;
  return {
    projectSlug: project.projectSlug,
    depth: payload.depth,
    generatedAt: new Date().toISOString(),
    routing: payload.routing,
    taskPlan: payload.taskPlan,
    packetName,
    found: Boolean(packet),
    headline: packet?.headline || "",
    lane: packet?.lane || "",
    objective: packet?.objective || "",
    contractPath: packet?.contractPath || "",
    prompt: packet?.prompt || "",
    command: packet?.command || "",
    packet,
    availablePackets: Object.keys(payload.packets || {})
  };
}

async function buildDatasetCatalogResponse(project) {
  const viewerPayload = await readViewerState(project);
  const datasetCatalog = Array.isArray(viewerPayload.datasetCatalog) ? viewerPayload.datasetCatalog : [];
  return {
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    selectedDatasetId: viewerPayload.viewerState?.currentDatasetId || "",
    totalDatasets: datasetCatalog.length,
    realDatasets: datasetCatalog.filter((entry) => entry?.sourceKind === "real").length,
    observedDatasets: datasetCatalog.filter((entry) => entry?.truth?.truthMode === "observed").length,
    datasets: datasetCatalog
  };
}

async function buildViewerRuntimeResponse(project) {
  const viewerPayload = await readViewerState(project);
  const runtimeCapabilities = viewerPayload.runtimeCapabilities || buildRuntimeCapabilitySummary(project);
  const renderer = viewerPayload.viewerState?.renderer || {};
  return {
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    runtimeCapabilities,
    renderer: {
      status: renderer.status || "booting",
      message: renderer.message || "viewer runtime not observed yet",
      truth: renderer.truth || { source: "declared", truthMode: "declared", at: "" },
      runtime: renderer.runtime || {
        api: "webgpu",
        backend: "unknown",
        adapter: "unknown",
        format: "unknown",
        features: [],
        limits: [],
        observedAt: ""
      }
    }
  };
}

async function buildPlaygroundResumeResponse(project, depth = "fast") {
  const [truth, mission, beagle, executive, datasets, viewerRuntime, viewerState] = await Promise.all([
    buildTruthSummaryResponse(project, depth),
    buildMissionControlResponse(project, depth),
    buildBeagleSubstrateResponse(project, depth),
    buildPlaygroundExecutiveResponse(project, depth),
    buildDatasetCatalogResponse(project),
    buildViewerRuntimeResponse(project),
    readViewerState(project)
  ]);

  return {
    projectSlug: project.projectSlug,
    depth,
    generatedAt: new Date().toISOString(),
    playgroundClass: executive.playgroundClass || project?.playgroundClass || "mission-control",
    routes: {
      cockpit: `/projects/${project.projectSlug}`,
      viewer: `/projects/${project.projectSlug}/viewer`,
      publicPortal: "/public",
      publicShowcase: `/public/projects/${project.projectSlug}`,
      truthSummary: `/api/projects/${project.projectSlug}/truth/summary`,
      missionControl: `/api/projects/${project.projectSlug}/mission-control`,
      sovereignSurface: `/api/projects/${project.projectSlug}/sovereign-surface`,
      clusterLaneTruth: `/api/projects/${project.projectSlug}/cluster/lane-truth`,
      researchOperations: `/api/projects/${project.projectSlug}/research/operations`,
      beagleSubstrate: `/api/projects/${project.projectSlug}/beagle/substrate`,
      playgroundExecutive: `/api/projects/${project.projectSlug}/playground/executive`,
      datasetsCatalog: `/api/projects/${project.projectSlug}/datasets/catalog`,
      viewerRuntime: `/api/projects/${project.projectSlug}/viewer/runtime`,
      viewerState: `/api/projects/${project.projectSlug}/viewer/state`,
      sounioContracts: `/api/projects/${project.projectSlug}/sounio/contracts`,
      scientificWorkflowChecks: `/api/projects/${project.projectSlug}/workflows/scientific/checks`,
      scientificWorkflowRun: `/api/projects/${project.projectSlug}/workflows/scientific/checks/run`,
      inferenceWorkload: `/api/projects/${project.projectSlug}/inference/workload`,
      inferenceBootstrap: `/api/projects/${project.projectSlug}/inference/bootstrap`,
      executionPackets: `/api/projects/${project.projectSlug}/execution/packets`,
      resumePlayground: `/api/projects/${project.projectSlug}/resume/playground`
    },
    truthSummary: truth.truthSummary || {},
    missionControl: mission.missionControl || {},
    publicationCheckpoint: mission.publicationCheckpoint || {},
    continuityTimeline: mission.continuityTimeline || [],
    beagleSubstrate: beagle.beagleSubstrate || {},
    playgroundExecutive: executive.playgroundExecutive || {},
    sovereignSurface: executive.sovereignSurface || {},
    inferenceRuntime: buildInferenceRuntimeSummary(project),
    sounioContractPack: beagle.beagleSubstrate?.sounioContractPack || null,
    runtimeCapabilities: executive.runtimeCapabilities || {},
    viewerDefaults: executive.viewerDefaults || {},
    datasetCatalog: datasets.datasets || [],
    datasetSummary: {
      totalDatasets: datasets.totalDatasets || 0,
      realDatasets: datasets.realDatasets || 0,
      observedDatasets: datasets.observedDatasets || 0,
      selectedDatasetId: datasets.selectedDatasetId || ""
    },
    viewerRuntime: viewerRuntime.renderer || {},
    viewerState: viewerState.viewerState || {},
    workspace: truth.workspace || {},
    publication: truth.publication || {}
  };
}

async function buildRuntimeManifestResponse(project, depth = "fast") {
  const resume = await buildPlaygroundResumeResponse(project, depth);
  const runtimeCapabilities = resume.runtimeCapabilities || {};
  const viewerRoute = resume.routes?.viewer || `/projects/${project.projectSlug}/viewer`;
  const cockpitRoute = resume.routes?.cockpit || `/projects/${project.projectSlug}`;
  const resumeRoute = resume.routes?.resumePlayground || `/api/projects/${project.projectSlug}/resume/playground`;
  const publicPortalRoute = resume.routes?.publicPortal || "/public";
  const publicShowcaseRoute = resume.routes?.publicShowcase || `/public/projects/${project.projectSlug}`;
  const selectedDatasetId =
    resume.datasetSummary?.selectedDatasetId ||
    resume.playgroundExecutive?.selectedDatasetId ||
    resume.viewerDefaults?.entryDatasetId ||
    "";

  return {
    projectSlug: project.projectSlug,
    depth,
    surface: "private",
    generatedAt: new Date().toISOString(),
    selectedDatasetId,
    publicPortalRoute,
    publicShowcaseRoute,
    renderingTarget:
      resume.playgroundExecutive?.renderingTarget ||
      runtimeCapabilities?.web?.status ||
      "webgpu-target",
    runtimes: {
      web: {
        ...runtimeCapabilities.web,
        launchIntent: {
          route: viewerRoute,
          resumeRoute,
          automationRoute: runtimeCapabilities.web?.automationRoute || "",
          humanRoute: runtimeCapabilities.web?.humanRoute || "",
          target: "browser"
        }
      },
      desktop: {
        ...runtimeCapabilities.desktop,
        launchIntent: {
          route: viewerRoute,
          resumeRoute,
          target: "native-shell",
          shells: runtimeCapabilities.desktop?.shells || ["windows", "macos"]
        }
      },
      ios: {
        ...runtimeCapabilities.ios,
        launchIntent: {
          route: viewerRoute,
          resumeRoute,
          target: "ios-native",
          interaction: runtimeCapabilities.ios?.interaction || "touch-first"
        }
      },
      vision: {
        ...runtimeCapabilities.vision,
        shell: runtimeCapabilities.vision?.shell || "visionos-native",
        target: "control-room-first",
        interactionMode: runtimeCapabilities.vision?.interaction || "spatial-control-room",
        layoutMode: runtimeCapabilities.vision?.layoutMode || "multi-panel",
        resumeRoute,
        viewerRoute,
        controlRoomRoute: "/public/vision",
        publicPortalRoute,
        publicShowcaseRoute,
        selectedDatasetId,
        rendering: runtimeCapabilities.vision?.rendering || "webgpu-target",
        capabilities: [
          "spatial-mission-control",
          "graph-lineage",
          "execution-packets",
          "scientific-viewport"
        ],
        launchIntent: {
          route: cockpitRoute,
          viewerRoute,
          resumeRoute,
          publicPortalRoute,
          publicShowcaseRoute,
          publicVisionControlRoomRoute: "/public/vision",
          selectedDatasetId,
          target: "visionos-spatial-shell",
          interactionMode: runtimeCapabilities.vision?.interaction || "spatial-control-room",
          layoutMode: runtimeCapabilities.vision?.layoutMode || "multi-panel",
          intent: "resume-playground"
        }
      }
    },
    inference: {
      fabric: buildInferenceRuntimeSummary(project)
    },
    routes: {
      cockpit: cockpitRoute,
      viewer: viewerRoute,
      publicPortal: publicPortalRoute,
      publicShowcase: publicShowcaseRoute,
      resumePlayground: resumeRoute,
      viewerRuntime: resume.routes?.viewerRuntime || `/api/projects/${project.projectSlug}/viewer/runtime`,
      viewerState: resume.routes?.viewerState || `/api/projects/${project.projectSlug}/viewer/state`,
      clusterLaneTruth:
        resume.routes?.clusterLaneTruth || `/api/projects/${project.projectSlug}/cluster/lane-truth`,
      researchOperations:
        resume.routes?.researchOperations || `/api/projects/${project.projectSlug}/research/operations`,
      inferenceRuntime: `/api/projects/${project.projectSlug}/inference/runtime`,
      inferenceWorkload: `/api/projects/${project.projectSlug}/inference/workload`,
      inferenceModels: `/api/projects/${project.projectSlug}/inference/models`,
      inferenceBootstrap: `/api/projects/${project.projectSlug}/inference/bootstrap`,
      sounioContracts: `/api/projects/${project.projectSlug}/sounio/contracts`,
      scientificWorkflowChecks: `/api/projects/${project.projectSlug}/workflows/scientific/checks`,
      scientificWorkflowRun: `/api/projects/${project.projectSlug}/workflows/scientific/checks/run`,
      publicVisionControlRoom: "/public/vision"
    }
  };
}

function buildPublicVisionRuntimeResponse() {
  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    target: "visionos-spatial-shell",
    focus: "control-room-first",
    route: "/public/vision",
    showcaseRoute: "/public/projects/sounio",
    privateCockpitRoute: "/projects/sounio",
    privateViewerRoute: "/projects/sounio/viewer",
    manifestRoute: "/api/projects/sounio/runtime/manifest",
    resumeRoute: "/api/projects/sounio/resume/playground",
    controlRoomRoute: "/api/public/vision/control-room",
    runtime: {
      shell: "visionos-native",
      target: "visionos-spatial-shell",
      focus: "control-room-first",
      interactionMode: "spatial-control-room",
      layoutMode: "multi-panel",
      rendering: "webgpu-first",
      route: "/public/vision",
      showcaseRoute: "/public/projects/sounio"
    },
    narrative: {
      headline: "Apple Vision control room",
      summary:
        "Vision is treated as a spatial control-room shell for mission control, graph lineage, execution packets, and a pinned scientific viewer lane.",
      publicUseCases: [
        "spatial mission control",
        "scientific viewer showcase",
        "graph lineage walkthrough",
        "runtime vision briefing"
      ]
    }
  };
}

async function buildPublicVisionInferenceSnapshot(projectSlug = "sounio") {
  try {
    const project = await getProjectOrThrow(projectSlug);
    const cached = getCachedInferenceRuntime(projectSlug, { allowStale: true });
    let runtime = cached?.value || null;

    if (!runtime) {
      if (!cached?.promise) {
        const refresh = resolveInferenceRuntime(project)
          .then((value) => {
            setCachedInferenceRuntime(projectSlug, value, null);
            return value;
          })
          .catch(() => {
            const current = getCachedInferenceRuntime(projectSlug, { allowStale: true });
            if (current?.value) {
              setCachedInferenceRuntime(projectSlug, current.value, null);
              return current.value;
            }
            invalidateInferenceRuntime(projectSlug);
            return null;
          });
        setCachedInferenceRuntime(projectSlug, null, refresh);
      }

      const declared = buildInferenceRuntimeSummary(project);
      const [controlPlaneProbe, engineProbe] = await Promise.all([
        probeInferenceEndpoint({
          endpoint: declared.controlPlane?.endpoint || "",
          healthPath: declared.controlPlane?.healthPath || "/health",
          modelsPath: declared.controlPlane?.modelsPath || "/v1/models",
          family: "dynamo"
        }),
        probeInferenceEndpoint({
          endpoint: declared.engine?.endpoint || "",
          healthPath: declared.engine?.healthPath || "/health",
          modelsPath: declared.engine?.modelsPath || "/v1/models",
          family: "sglang"
        })
      ]);
      const directlyObserved =
        controlPlaneProbe.reachable || engineProbe.reachable;

      if (directlyObserved) {
        const observedModels =
          controlPlaneProbe.models.length > 0 ? controlPlaneProbe.models : engineProbe.models;
        const controlPlanePublishedModels = controlPlaneProbe.models.length > 0;
        runtime = {
          ...declared,
          status:
            controlPlaneProbe.reachable && (engineProbe.reachable || controlPlanePublishedModels)
              ? "ready"
              : controlPlaneProbe.reachable || engineProbe.reachable
                ? "partial-ready"
                : declared.status || "prototype",
          truthMode: "observed",
          endpoint:
            (controlPlaneProbe.reachable ? declared.controlPlane?.endpoint : "") ||
            (engineProbe.reachable ? declared.engine?.endpoint : "") ||
            declared.endpoint,
          models: observedModels.length
            ? observedModels.map((entry) => ({
                id: cleanValue(entry?.id || ""),
                provider: cleanValue(entry?.family || entry?.provider || "")
              }))
            : declared.models,
          engine: {
            ...declared.engine,
            status: engineProbe.status,
            endpoint: declared.engine?.endpoint || ""
          },
          controlPlane: {
            ...declared.controlPlane,
            status: controlPlaneProbe.status,
            endpoint: declared.controlPlane?.endpoint || ""
          }
        };
      } else {
      const [workload, prereqs, workerMetadata] = await Promise.all([
        withTimeout(readInferenceWorkload(), "vision inference workload", 4500).catch(() => null),
        withTimeout(readInferenceFabricPrereqs(), "vision inference prereqs", 3000).catch(() => null),
        withTimeout(readInferenceWorkerMetadata(), "vision inference worker metadata", 2500).catch(() => null)
      ]);
      const engineWorkload = workload?.engine || {};
      const controlPlaneWorkload = workload?.controlPlane || {};
      const platform = prereqs?.dynamo || null;
      const registeredModels = Array.isArray(workerMetadata?.models) ? workerMetadata.models : [];
      const engineRegistered = registeredModels.length > 0;
      const controlPlanePublishedModels = Array.isArray(declared.models)
        ? declared.models.length > 0
        : false;
      const controlPlaneStatus =
        controlPlaneWorkload.status ||
        (platform?.status === "platform-missing"
          ? "platform-missing"
          : declared.controlPlane?.status || "planned");
      const engineStatus =
        engineWorkload.status === "ready"
          ? "ready"
          : engineRegistered
            ? "registered"
            : engineWorkload.status || declared.engine?.status || "planned";
      const status =
        (engineStatus === "ready" || controlPlanePublishedModels) && controlPlaneStatus === "ready"
          ? "ready"
          : engineStatus === "registered" && controlPlaneStatus === "ready"
            ? "control-plane-ready-backend-registered"
          : engineStatus === "ready" && controlPlaneStatus === "platform-missing"
            ? "engine-ready-control-plane-missing"
            : workload?.status === "starting"
              ? "starting"
              : declared.status || "prototype";

      runtime = {
        ...declared,
        status,
        truthMode: workload ? "observed" : "declared",
        endpoint:
          controlPlaneWorkload.internalUrl ||
          engineWorkload.internalUrl ||
          declared.endpoint,
        models: registeredModels.length
          ? registeredModels.map((entry) => ({
              id: cleanValue(entry?.id || ""),
              provider: cleanValue(entry?.provider || entry?.family || "")
            }))
          : declared.models,
        engine: {
          ...declared.engine,
          status: engineStatus,
          endpoint: engineWorkload.internalUrl || declared.engine?.endpoint || "",
          backendTransports: workerMetadata?.backendTransports || [],
          discoveryNamespaces: workerMetadata?.namespaces || []
        },
        controlPlane: {
          ...declared.controlPlane,
          status: controlPlaneStatus,
          endpoint:
            controlPlaneWorkload.internalUrl || declared.controlPlane?.endpoint || "",
          platform
        },
        workload: workload || null
      };

      const candidateModelsUrl =
        (controlPlaneWorkload.status === "ready" && controlPlaneWorkload.internalUrl
          ? `${controlPlaneWorkload.internalUrl}${declared.controlPlane?.modelsPath || "/v1/models"}`
          : "") ||
        (engineWorkload.status === "ready" && engineWorkload.internalUrl
          ? `${engineWorkload.internalUrl}${declared.engine?.modelsPath || "/v1/models"}`
          : "");

      if (candidateModelsUrl) {
        try {
          const payload = await fetchRemoteJson(
            candidateModelsUrl,
            Math.min(inferenceProbeTimeoutMs, 900)
          );
          const observedModels = Array.isArray(payload?.data)
            ? payload.data
                .map((entry) => ({
                  id: cleanValue(entry?.id || "unknown-model"),
                  provider: cleanValue(entry?.owned_by || "")
                }))
                .filter((entry) => entry.id)
            : [];
          if (observedModels.length) {
            runtime.models = observedModels;
          }
        } catch {
          // Keep the lightweight Vision snapshot fast; model inventory can fall back
          // to the declared catalog when a short observed probe misses.
        }
      }
      }
    }
    const engine = runtime.engine || {};
    const controlPlane = runtime.controlPlane || {};
    const models = Array.isArray(runtime.models) ? runtime.models : [];
    const normalizedEngineStatus =
      engine.status === "unreachable" &&
      controlPlane.status === "ready" &&
      models.length > 0
        ? "published-via-control-plane"
        : engine.status || "planned";

    return {
      projectSlug,
      route: `/api/projects/${projectSlug}/inference/runtime`,
      workloadRoute: `/api/projects/${projectSlug}/inference/workload`,
      modelsRoute: `/api/projects/${projectSlug}/inference/models`,
      bootstrapRoute: `/api/projects/${projectSlug}/inference/bootstrap`,
      status: runtime.status || "prototype",
      truthMode:
        runtime.truthMode || runtime.truth?.truthMode || (cached?.value ? "observed" : "declared"),
      deliveryMode: runtime.deliveryMode || "cluster-gpu-inference-fabric",
      endpoint: runtime.endpoint || controlPlane.endpoint || engine.endpoint || "",
      models: models.map((entry) => ({
        id: entry.id || "",
        provider: entry.provider || entry.family || ""
      })),
      engine: {
        provider: engine.provider || "sglang",
        status: normalizedEngineStatus,
        endpoint: engine.endpoint || "",
        target: engine.target || "gpu-runtime"
      },
      controlPlane: {
        provider: controlPlane.provider || "dynamo",
        status: controlPlane.status || "planned",
        endpoint: controlPlane.endpoint || "",
        target: controlPlane.target || "openai-compatible-routing-frontend"
      }
    };
  } catch (error) {
    return {
      projectSlug,
      route: `/api/projects/${projectSlug}/inference/runtime`,
      workloadRoute: `/api/projects/${projectSlug}/inference/workload`,
      modelsRoute: `/api/projects/${projectSlug}/inference/models`,
      bootstrapRoute: `/api/projects/${projectSlug}/inference/bootstrap`,
      status: "unavailable",
      truthMode: "declared",
      deliveryMode: "cluster-gpu-inference-fabric",
      endpoint: "",
      models: [],
      engine: {
        provider: "sglang",
        status: "unavailable",
        endpoint: "",
        target: "gpu-runtime"
      },
      controlPlane: {
        provider: "dynamo",
        status: "unavailable",
        endpoint: "",
        target: "openai-compatible-routing-frontend"
      },
      lastError: cleanValue(error?.message) || "vision inference snapshot unavailable"
    };
  }
}

async function buildPublicVisionControlRoomResponse() {
  const runtimeVision = buildPublicVisionRuntimeResponse();
  const inferenceFabric = await buildPublicVisionInferenceSnapshot("sounio");
  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision control room",
    subtitle:
      "Spatial mission control for the sovereign supercomputing playground, pairing Beagle routing, graph lineage, and a pinned scientific viewer lane.",
    route: "/public/vision",
    runtimeVision,
    inferenceFabric,
    runtimeTargets: [
      {
        id: "web",
        name: "Web",
        focus: "browser control room",
        route: "/public",
        status: "public-ready"
      },
      {
        id: "desktop",
        name: "Desktop",
        focus: "native mission control shell",
        route: "/projects/sounio",
        status: "planned"
      },
      {
        id: "ios",
        name: "iOS",
        focus: "touch-first sovereign handoff",
        route: "/projects/sounio",
        status: "planned"
      },
      {
        id: "vision",
        name: "Vision",
        focus: "spatial control room",
        route: "/public/vision",
        status: "showcase-ready"
      }
    ],
    panels: [
      {
        name: "Mission control",
        purpose: "Keep publication, review, and sovereign continuity visible without flattening truth modes."
      },
      {
        name: "Scientific viewport",
        purpose: "Pin one WebGPU-first dataset scene while provenance and runtime diagnostics stay adjacent."
      },
      {
        name: "Graph lineage",
        purpose: "Walk project, branch, PR, dataset, artifact, and lane edges in one spatial shell."
      },
      {
        name: "Execution packets",
        purpose: "Launch Beagle-native Claude, Codex, SGLang, Dynamo, and Sounio flows from the same room."
      }
    ],
    spatialLayout: [
      {
        zone: "center",
        panel: "Scientific viewport",
        reason: "Keep one dataset scene dominant while the rest of the room explains it."
      },
      {
        zone: "left",
        panel: "Mission control",
        reason: "Pin branch, PR, and sovereign continuity where they stay readable."
      },
      {
        zone: "right",
        panel: "Graph lineage",
        reason: "Keep provenance and edges adjacent to the scene instead of buried in text."
      },
      {
        zone: "lower",
        panel: "Execution packets",
        reason: "Let the operator hand off directly into Claude, Codex, SGLang, Dynamo, or Sounio flows."
      }
    ],
    curatedScene: {
      datasetId: "idr0062A-6001240-image",
      artifactRef: "idr0062A/6001240",
      rendering: "webgpu-first",
      provenanceMode: "showcase-linked"
    },
    publicPrivateCrossing: [
      {
        step: "Public portal",
        route: "/public",
        role: "research narrative and showcase entry"
      },
      {
        step: "Vision control room",
        route: "/public/vision",
        role: "spatial orchestration and packet handoff"
      },
      {
        step: "Private cockpit",
        route: "/projects/sounio",
        role: "Beagle substrate, truth surfaces, and execution control"
      },
      {
        step: "Private viewer",
        route: "/projects/sounio/viewer",
        role: "dataset-bound scientific viewport and provenance detail"
      }
    ],
    packets: [
      "researchPacket",
      "scientificViewer",
      "scientificWorkflow",
      "inferenceFabric",
      "sglangServing",
      "dynamoControlPlane",
      "sounioScientificContract",
      "sounioContractPack"
    ],
    handoffPackets: [
      {
        id: "researchPacket",
        name: "researchPacket",
        lane: "research",
        route: "/api/projects/sounio/execution/packets/researchPacket"
      },
      {
        id: "scientificViewer",
        name: "scientificViewer",
        lane: "viewer",
        route: "/api/projects/sounio/execution/packets/scientificViewer"
      },
      {
        id: "inferenceFabric",
        name: "inferenceFabric",
        lane: "inference",
        route: "/api/projects/sounio/execution/packets/inferenceFabric"
      },
      {
        id: "sglangServing",
        name: "sglangServing",
        lane: "inference",
        route: "/api/projects/sounio/execution/packets/sglangServing"
      },
      {
        id: "dynamoControlPlane",
        name: "dynamoControlPlane",
        lane: "inference",
        route: "/api/projects/sounio/inference/bootstrap"
      },
      {
        id: "sounioScientificContract",
        name: "sounioScientificContract",
        lane: "sounio",
        route: "/api/projects/sounio/execution/packets/sounioScientificContract"
      },
      {
        id: "sounioContractPack",
        name: "sounioContractPack",
        lane: "sounio",
        route: "/api/projects/sounio/sounio/contracts"
      }
    ],
    apiSurfaces: [
      "/api/public/portal",
      "/api/public/runtime/vision",
      "/api/public/vision/control-room",
      "/api/public/vision/apple-brief",
      "/api/public/vision/apple-launchpad",
      "/api/public/vision/operator-board",
      "/api/public/vision/packet-graph",
      "/api/public/vision/handoff",
      "/api/public/projects/sounio/showcase",
      "/api/projects/sounio/runtime/manifest",
      "/api/projects/sounio/resume/playground",
      "/api/projects/sounio/inference/runtime",
      "/api/projects/sounio/inference/models",
      "/api/projects/sounio/inference/workload",
      "/api/projects/sounio/inference/bootstrap",
      "/api/projects/sounio/sounio/contracts"
    ],
    recommendedSequence: [
      "Open the public research portal",
      "Enter the Vision control room",
      "Verify the inference fabric handoff",
      "Pin the scientific viewer showcase",
      "Walk graph lineage and execution packets",
      "Hand off into the private cockpit when sovereign truth is required"
    ]
  };
}

async function buildPublicVisionHandoffResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoffPackets = Array.isArray(controlRoom.handoffPackets) ? controlRoom.handoffPackets : [];
  const crossing = Array.isArray(controlRoom.publicPrivateCrossing) ? controlRoom.publicPrivateCrossing : [];
  const runtimeTargets = Array.isArray(controlRoom.runtimeTargets) ? controlRoom.runtimeTargets : [];

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision handoff",
    subtitle:
      "A dedicated public handoff surface for explaining how the Vision room crosses into sovereign cockpit truth without flattening the packets or routes.",
    route: "/public/vision/handoff",
    runtimeVision: controlRoom.runtimeVision,
    inferenceFabric: controlRoom.inferenceFabric,
    handoffPackets,
    publicPrivateCrossing: crossing,
    runtimeTargets,
    handoffChecklist: [
      "Confirm the public Vision room is reading observed inference fabric state.",
      "Choose the shell target that matches the next operator move.",
      "Pick the packet lane before crossing into the private cockpit.",
      "Enter the private cockpit only when sovereign truth or execution control is required.",
      "Keep the private viewer as the final dataset-bound endpoint for provenance-heavy work."
    ],
    handoffSurfaces: [
      "/public/vision",
      "/public/vision/apple-brief",
      "/public/vision/apple-launchpad",
      "/public/vision/operator-board",
      "/public/vision/runtime-matrix",
      "/public/vision/packet-graph",
      "/public/vision/handoff",
      "/api/public/vision/control-room",
      "/api/public/vision/apple-brief",
      "/api/public/vision/apple-launchpad",
      "/api/public/vision/operator-board",
      "/api/public/vision/runtime-matrix",
      "/api/public/vision/packet-graph",
      "/api/public/vision/handoff",
      "/projects/sounio",
      "/projects/sounio/viewer"
    ],
    appleVisionTarget: {
      runtime: "visionos",
      shell: "spatial-control-room",
      route: "/public/vision",
      focus: "public-to-private sovereign handoff"
    }
  };
}

async function buildPublicVisionAppleBriefResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoff = await buildPublicVisionHandoffResponse();
  const packetGraph = await buildPublicVisionPacketGraphResponse();
  const inferenceFabric = controlRoom.inferenceFabric || {};
  const handoffChecklist = Array.isArray(handoff.handoffChecklist) ? handoff.handoffChecklist : [];
  const handoffPackets = Array.isArray(handoff.handoffPackets) ? handoff.handoffPackets : [];
  const runtimeTargets = Array.isArray(controlRoom.runtimeTargets) ? controlRoom.runtimeTargets : [];
  const graphSummary = packetGraph.graphSummary || {};
  const fabricModels = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision brief",
    subtitle:
      "A compact public briefing surface that synthesizes the control room, packet graph, and handoff path into one Apple Vision operator-facing view.",
    route: "/public/vision/apple-brief",
    runtimeVision: controlRoom.runtimeVision,
    inferenceFabric,
    runtimeTargets,
    handoffChecklist,
    handoffPackets,
    packetGraph: {
      route: packetGraph.route || "/public/vision/packet-graph",
      nodeCount: graphSummary.nodeCount || 0,
      edgeCount: graphSummary.edgeCount || 0,
      packetCount: graphSummary.packetCount || 0,
      runtimeTargetCount: graphSummary.runtimeTargetCount || 0
    },
    briefingCards: [
      {
        id: "fabric",
        label: "fabric",
        title: "Published inference path",
        status: inferenceFabric.status || "prototype",
        detail:
          inferenceFabric.controlPlane?.endpoint ||
          inferenceFabric.endpoint ||
          "control plane endpoint unavailable"
      },
      {
        id: "vision-shell",
        label: "shell",
        title: "Vision room semantics",
        status: controlRoom.runtimeVision?.runtime?.focus || "control-room-first",
        detail:
          controlRoom.runtimeVision?.runtime?.interactionMode || "spatial-control-room"
      },
      {
        id: "graph",
        label: "graph",
        title: "Packet graph summary",
        status: `${graphSummary.nodeCount || 0} nodes / ${graphSummary.edgeCount || 0} edges`,
        detail: packetGraph.route || "/public/vision/packet-graph"
      },
      {
        id: "crossing",
        label: "crossing",
        title: "Private landing",
        status: "sovereign cockpit",
        detail: "/projects/sounio -> /projects/sounio/viewer"
      }
    ],
    briefingRoutes: [
      "/public/vision",
      "/public/vision/apple-brief",
      "/public/vision/apple-launchpad",
      "/public/vision/operator-board",
      "/public/vision/runtime-matrix",
      "/public/vision/packet-graph",
      "/public/vision/handoff",
      "/api/public/vision/control-room",
      "/api/public/vision/apple-brief",
      "/api/public/vision/apple-launchpad",
      "/api/public/vision/operator-board",
      "/api/public/vision/runtime-matrix",
      "/api/public/vision/packet-graph",
      "/api/public/vision/handoff",
      "/projects/sounio",
      "/projects/sounio/viewer"
    ],
    briefingSequence: [
      "Read the observed fabric status before discussing shells or packets.",
      "Use the packet graph to explain how Vision reaches the published control-plane path.",
      "Use the handoff checklist to choose when the operator should cross into sovereign truth.",
      "Treat the private cockpit and dataset-bound viewer as the final destinations, not the public shell."
    ],
    appleVisionTarget: {
      runtime: "visionos",
      shell: "spatial-control-room",
      route: "/public/vision/apple-brief",
      focus: "operator briefing before sovereign handoff"
    },
    models: fabricModels
  };
}

async function buildPublicVisionAppleLaunchpadResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoff = await buildPublicVisionHandoffResponse();
  const packetGraph = await buildPublicVisionPacketGraphResponse();
  const brief = await buildPublicVisionAppleBriefResponse();
  const inferenceFabric = controlRoom.inferenceFabric || {};
  const runtimeTargets = Array.isArray(controlRoom.runtimeTargets) ? controlRoom.runtimeTargets : [];
  const visionTarget = runtimeTargets.find((target) => target.id === "vision") || {};
  const handoffChecklist = Array.isArray(handoff.handoffChecklist) ? handoff.handoffChecklist : [];
  const handoffPackets = Array.isArray(handoff.handoffPackets) ? handoff.handoffPackets : [];
  const graphSummary = packetGraph.graphSummary || {};
  const models = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];
  const developerAccount = {
    status: "active",
    label: "Apple Developer account",
    detail: "Active account available for concrete visionOS runtime planning.",
    source:
      "/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_SUPERCOMPUTING_PLAYGROUND_BLUEPRINT.md"
  };

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision launchpad",
    subtitle:
      "A public Apple Vision launch surface that turns the observed fabric, packet graph, and active developer account into concrete launch gates for the spatial shell.",
    route: "/public/vision/apple-launchpad",
    runtimeVision: controlRoom.runtimeVision,
    inferenceFabric,
    runtimeTargets,
    handoffChecklist,
    handoffPackets,
    developerAccount,
    packetGraph: {
      route: packetGraph.route || "/public/vision/packet-graph",
      nodeCount: graphSummary.nodeCount || 0,
      edgeCount: graphSummary.edgeCount || 0,
      packetCount: graphSummary.packetCount || 0
    },
    launchGates: [
      {
        id: "developer-account",
        label: "developer account",
        status: developerAccount.status,
        title: developerAccount.label,
        detail: developerAccount.detail
      },
      {
        id: "fabric",
        label: "fabric",
        status: inferenceFabric.status || "prototype",
        title: "Published inference path",
        detail:
          inferenceFabric.controlPlane?.endpoint ||
          inferenceFabric.endpoint ||
          "control plane endpoint unavailable"
      },
      {
        id: "vision-shell",
        label: "vision shell",
        status: visionTarget.status || controlRoom.runtimeVision?.runtime?.status || "planned",
        title: visionTarget.focus || "spatial control-room shell",
        detail: visionTarget.route || "/public/vision"
      },
      {
        id: "packet-graph",
        label: "packet graph",
        status: `${graphSummary.nodeCount || 0} nodes`,
        title: "Graph-ready briefing",
        detail: packetGraph.route || "/public/vision/packet-graph"
      }
    ],
    launchSequence: [
      "Validate the active Apple developer account before promising shell delivery.",
      "Confirm the observed inference fabric is published via the Dynamo control plane.",
      "Use the Apple Vision brief to align the operator on packets, shells, and crossings.",
      "Open the packet graph and handoff routes before crossing into the sovereign cockpit."
    ],
    launchRoutes: [
      "/public/vision",
      "/public/vision/apple-brief",
      "/public/vision/apple-launchpad",
      "/public/vision/operator-board",
      "/public/vision/runtime-matrix",
      "/public/vision/packet-graph",
      "/public/vision/handoff",
      "/api/public/vision/control-room",
      "/api/public/vision/apple-brief",
      "/api/public/vision/apple-launchpad",
      "/api/public/vision/operator-board",
      "/api/public/vision/runtime-matrix",
      "/api/public/vision/packet-graph",
      "/api/public/vision/handoff",
      "/projects/sounio",
      "/projects/sounio/viewer"
    ],
    launchCards: [
      {
        id: "brief",
        label: "brief",
        status: brief.inferenceFabric?.status || "prototype",
        title: "Operator briefing",
        detail: brief.route || "/public/vision/apple-brief"
      },
      {
        id: "graph",
        label: "graph",
        status: `${graphSummary.edgeCount || 0} edges`,
        title: "Packet graph",
        detail: packetGraph.route || "/public/vision/packet-graph"
      },
      {
        id: "handoff",
        label: "handoff",
        status: `${handoffChecklist.length} steps`,
        title: "Sovereign crossing",
        detail: handoff.route || "/public/vision/handoff"
      },
      {
        id: "landing",
        label: "landing",
        status: "private-ready",
        title: "Private destinations",
        detail: "/projects/sounio -> /projects/sounio/viewer"
      }
    ],
    appleVisionTarget: {
      runtime: "visionos",
      shell: "spatial-control-room",
      route: "/public/vision/apple-launchpad",
      focus: "operator launch sequencing for the Apple Vision shell"
    },
    models
  };
}

async function buildPublicVisionOperatorBoardResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoff = await buildPublicVisionHandoffResponse();
  const packetGraph = await buildPublicVisionPacketGraphResponse();
  const launchpad = await buildPublicVisionAppleLaunchpadResponse();
  const inferenceFabric = controlRoom.inferenceFabric || {};
  const runtimeTargets = Array.isArray(controlRoom.runtimeTargets) ? controlRoom.runtimeTargets : [];
  const handoffChecklist = Array.isArray(handoff.handoffChecklist) ? handoff.handoffChecklist : [];
  const handoffPackets = Array.isArray(handoff.handoffPackets) ? handoff.handoffPackets : [];
  const publicPrivateCrossing = Array.isArray(controlRoom.publicPrivateCrossing)
    ? controlRoom.publicPrivateCrossing
    : [];
  const graphSummary = packetGraph.graphSummary || {};
  const models = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];
  const launchGates = Array.isArray(launchpad.launchGates) ? launchpad.launchGates : [];

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision operator board",
    subtitle:
      "A route-transition board for the Apple Vision shell, showing how briefing, launch, graph, and sovereign crossing fit together for the live fabric.",
    route: "/public/vision/operator-board",
    runtimeVision: controlRoom.runtimeVision,
    inferenceFabric,
    runtimeTargets,
    handoffChecklist,
    handoffPackets,
    publicPrivateCrossing,
    developerAccount: launchpad.developerAccount,
    packetGraph: {
      route: packetGraph.route || "/public/vision/packet-graph",
      nodeCount: graphSummary.nodeCount || 0,
      edgeCount: graphSummary.edgeCount || 0,
      packetCount: graphSummary.packetCount || 0
    },
    operatorTransitions: [
      {
        id: "room-to-brief",
        label: "public room",
        from: "/public/vision",
        to: "/public/vision/apple-brief",
        status: inferenceFabric.status || "prototype",
        reason: "Move from observed room state into a compact operator briefing."
      },
      {
        id: "brief-to-launchpad",
        label: "briefing",
        from: "/public/vision/apple-brief",
        to: "/public/vision/apple-launchpad",
        status: launchpad.developerAccount?.status || "planned",
        reason: "Turn room context into concrete launch gates for visionOS."
      },
      {
        id: "launchpad-to-graph",
        label: "graph",
        from: "/public/vision/apple-launchpad",
        to: "/public/vision/packet-graph",
        status: `${graphSummary.nodeCount || 0} nodes`,
        reason: "Open the packet graph before crossing into sovereign truth."
      },
      {
        id: "graph-to-handoff",
        label: "handoff",
        from: "/public/vision/packet-graph",
        to: "/public/vision/handoff",
        status: `${handoffChecklist.length} steps`,
        reason: "Use the handoff checklist to pace the crossing."
      },
      {
        id: "handoff-to-private",
        label: "sovereign landing",
        from: "/public/vision/handoff",
        to: "/projects/sounio",
        status: "private-ready",
        reason: "Cross into the sovereign cockpit only when execution control is required."
      }
    ],
    operatorLanes: [
      {
        id: "developer",
        label: "developer account",
        status: launchpad.developerAccount?.status || "planned",
        title: launchpad.developerAccount?.label || "Apple Developer account",
        detail: launchpad.developerAccount?.detail || "Account status unavailable"
      },
      {
        id: "fabric",
        label: "fabric",
        status: inferenceFabric.engine?.status || inferenceFabric.status || "prototype",
        title: "Published via control plane",
        detail:
          inferenceFabric.controlPlane?.endpoint ||
          inferenceFabric.endpoint ||
          "control plane endpoint unavailable"
      },
      {
        id: "graph",
        label: "graph",
        status: `${graphSummary.edgeCount || 0} edges`,
        title: "Packet graph active",
        detail: packetGraph.route || "/public/vision/packet-graph"
      },
      {
        id: "crossing",
        label: "crossing",
        status: `${publicPrivateCrossing.length} routes`,
        title: "Public to private crossing",
        detail: "/projects/sounio -> /projects/sounio/viewer"
      }
    ],
    operatorRoutes: [
      "/public/vision",
      "/public/vision/apple-brief",
      "/public/vision/apple-launchpad",
      "/public/vision/operator-board",
      "/public/vision/packet-graph",
      "/public/vision/handoff",
      "/api/public/vision/control-room",
      "/api/public/vision/apple-brief",
      "/api/public/vision/apple-launchpad",
      "/api/public/vision/operator-board",
      "/api/public/vision/packet-graph",
      "/api/public/vision/handoff",
      "/projects/sounio",
      "/projects/sounio/viewer"
    ],
    operatorChecks: [
      "Observed fabric is ready and published via the Dynamo control plane.",
      "Apple Developer account remains active for concrete visionOS planning.",
      "Packet graph is open before the sovereign crossing is invoked.",
      "Handoff checklist is complete before opening the private cockpit."
    ],
    launchGates,
    models
  };
}

async function buildPublicVisionRuntimeMatrixResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoff = await buildPublicVisionHandoffResponse();
  const launchpad = await buildPublicVisionAppleLaunchpadResponse();
  const operatorBoard = await buildPublicVisionOperatorBoardResponse();
  const inferenceFabric = controlRoom.inferenceFabric || {};
  const runtimeVision = controlRoom.runtimeVision || {};
  const runtimeTargets = Array.isArray(controlRoom.runtimeTargets) ? controlRoom.runtimeTargets : [];
  const publicPrivateCrossing = Array.isArray(controlRoom.publicPrivateCrossing)
    ? controlRoom.publicPrivateCrossing
    : [];
  const handoffChecklist = Array.isArray(handoff.handoffChecklist) ? handoff.handoffChecklist : [];
  const launchGates = Array.isArray(launchpad.launchGates) ? launchpad.launchGates : [];
  const operatorTransitions = Array.isArray(operatorBoard.operatorTransitions)
    ? operatorBoard.operatorTransitions
    : [];
  const models = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];
  const developerAccount = launchpad.developerAccount || {};

  const runtimeMatrix = runtimeTargets.map((target, index) => {
    const crossing = publicPrivateCrossing[index % Math.max(publicPrivateCrossing.length, 1)] || null;
    const gate = launchGates[index % Math.max(launchGates.length, 1)] || null;
    const transition = operatorTransitions[index % Math.max(operatorTransitions.length, 1)] || null;
    return {
      id: target.id || `target-${index + 1}`,
      name: target.name || `target ${index + 1}`,
      shell: target.focus || "runtime shell",
      route: target.route || "/public/vision",
      status: target.status || inferenceFabric.engine?.status || inferenceFabric.status || "planned",
      accessMode: inferenceFabric.engine?.status || inferenceFabric.status || "planned",
      crossing: crossing
        ? {
            summary: crossing.summary || crossing.label || "public-private crossing",
            route: crossing.route || "/projects/sounio"
          }
        : null,
      launchGate: gate
        ? {
            title: gate.title || "launch gate",
            status: gate.status || "planned"
          }
        : null,
      transition: transition
        ? {
            from: transition.from || "/public/vision",
            to: transition.to || "/projects/sounio",
            reason: transition.reason || "route transition"
          }
        : null
    };
  });

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision runtime matrix",
    subtitle:
      "A shell-by-shell matrix for the Apple Vision route, keeping runtime targets, control-plane publication, launch gates, and sovereign crossings visible in one observed board.",
    route: "/public/vision/runtime-matrix",
    runtimeVision,
    inferenceFabric,
    runtimeTargets,
    publicPrivateCrossing,
    developerAccount,
    handoffChecklist,
    launchGates,
    operatorTransitions,
    runtimeMatrix,
    matrixChecks: [
      "Observed fabric remains ready before any shell is treated as publishable.",
      "Control-plane publication is the boring path for every public runtime shell.",
      "Each runtime target keeps an explicit crossing into sovereign cockpit or viewer routes.",
      "Launch gates and operator transitions stay adjacent so shell changes remain legible."
    ],
    matrixRoutes: [
      "/public/vision",
      "/public/vision/apple-brief",
      "/public/vision/apple-launchpad",
      "/public/vision/operator-board",
      "/public/vision/runtime-matrix",
      "/public/vision/route-atlas",
      "/public/vision/packet-graph",
      "/public/vision/handoff",
      "/projects/sounio",
      "/projects/sounio/viewer"
    ],
    models
  };
}

async function buildPublicVisionRouteAtlasResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoff = await buildPublicVisionHandoffResponse();
  const launchpad = await buildPublicVisionAppleLaunchpadResponse();
  const operatorBoard = await buildPublicVisionOperatorBoardResponse();
  const runtimeMatrix = await buildPublicVisionRuntimeMatrixResponse();
  const packetGraph = await buildPublicVisionPacketGraphResponse();
  const inferenceFabric = controlRoom.inferenceFabric || {};
  const developerAccount = launchpad.developerAccount || {};
  const operatorTransitions = Array.isArray(operatorBoard.operatorTransitions)
    ? operatorBoard.operatorTransitions
    : [];
  const runtimeMatrixRows = Array.isArray(runtimeMatrix.runtimeMatrix) ? runtimeMatrix.runtimeMatrix : [];
  const handoffChecklist = Array.isArray(handoff.handoffChecklist) ? handoff.handoffChecklist : [];
  const models = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];

  const atlasRoutes = [
    {
      id: "vision-room",
      stage: "room",
      label: "control room",
      route: "/public/vision",
      status: inferenceFabric.status || "prototype",
      summary: "Observed public room for the spatial shell."
    },
    {
      id: "vision-brief",
      stage: "brief",
      label: "apple brief",
      route: "/public/vision/apple-brief",
      status: inferenceFabric.engine?.status || inferenceFabric.status || "prototype",
      summary: "Compact operator briefing before launch sequencing."
    },
    {
      id: "vision-launchpad",
      stage: "launch",
      label: "apple launchpad",
      route: "/public/vision/apple-launchpad",
      status: developerAccount.status || "planned",
      summary: "Launch gates for the Vision shell."
    },
    {
      id: "vision-operator-board",
      stage: "operator",
      label: "operator board",
      route: "/public/vision/operator-board",
      status: `${operatorTransitions.length} transitions`,
      summary: "Route transitions and public/private crossing board."
    },
    {
      id: "vision-runtime-matrix",
      stage: "matrix",
      label: "runtime matrix",
      route: "/public/vision/runtime-matrix",
      status: `${runtimeMatrixRows.length} shells`,
      summary: "Shell-by-shell matrix for launch gates and crossings."
    },
    {
      id: "vision-packet-graph",
      stage: "graph",
      label: "packet graph",
      route: "/public/vision/packet-graph",
      status: `${packetGraph.graphSummary?.edgeCount || 0} edges`,
      summary: "Graph-first view of packets, shells, and crossings."
    },
    {
      id: "vision-handoff",
      stage: "handoff",
      label: "handoff",
      route: "/public/vision/handoff",
      status: `${handoffChecklist.length} steps`,
      summary: "Explicit sovereign crossing into the private cockpit."
    }
  ];

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision route atlas",
    subtitle:
      "A public atlas for the Apple Vision shell, showing how room, briefing, launch, graph, matrix, and handoff routes fit together on top of the observed fabric.",
    route: "/public/vision/route-atlas",
    runtimeVision: controlRoom.runtimeVision,
    inferenceFabric,
    developerAccount,
    atlasRoutes,
    atlasLanes: [
      {
        id: "fabric",
        label: "fabric",
        status: inferenceFabric.status || "prototype",
        title: "Observed inference fabric",
        detail: inferenceFabric.controlPlane?.endpoint || inferenceFabric.endpoint || "fabric endpoint unavailable"
      },
      {
        id: "publication",
        label: "publication",
        status: inferenceFabric.engine?.status || "prototype",
        title: "Published via control plane",
        detail: "Public shells use the Dynamo control plane as the boring path."
      },
      {
        id: "developer",
        label: "developer",
        status: developerAccount.status || "planned",
        title: developerAccount.label || "Apple Developer account",
        detail: developerAccount.detail || "Developer account status unavailable"
      },
      {
        id: "crossing",
        label: "crossing",
        status: `${handoffChecklist.length} steps`,
        title: "Sovereign crossing",
        detail: "/projects/sounio -> /projects/sounio/viewer"
      }
    ],
    atlasChecks: [
      "The room route stays boring and observed before operator routes fan out.",
      "Launchpad, operator board, and runtime matrix all agree on published-via-control-plane semantics.",
      "Packet graph remains available before the handoff route is used for sovereign crossing.",
      "Private cockpit and viewer routes stay explicit at the end of the public Vision chain."
    ],
    atlasDestinations: [
      "/public/vision",
      "/public/vision/apple-brief",
      "/public/vision/apple-launchpad",
      "/public/vision/operator-board",
      "/public/vision/runtime-matrix",
      "/public/vision/route-atlas",
      "/public/vision/mission-timeline",
      "/public/vision/packet-graph",
      "/public/vision/handoff",
      "/projects/sounio",
      "/projects/sounio/viewer"
    ],
    models
  };
}

async function buildPublicVisionMissionTimelineResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoff = await buildPublicVisionHandoffResponse();
  const launchpad = await buildPublicVisionAppleLaunchpadResponse();
  const operatorBoard = await buildPublicVisionOperatorBoardResponse();
  const runtimeMatrix = await buildPublicVisionRuntimeMatrixResponse();
  const routeAtlas = await buildPublicVisionRouteAtlasResponse();
  const inferenceFabric = controlRoom.inferenceFabric || {};
  const developerAccount = launchpad.developerAccount || {};
  const handoffChecklist = Array.isArray(handoff.handoffChecklist) ? handoff.handoffChecklist : [];
  const launchGates = Array.isArray(launchpad.launchGates) ? launchpad.launchGates : [];
  const operatorTransitions = Array.isArray(operatorBoard.operatorTransitions)
    ? operatorBoard.operatorTransitions
    : [];
  const runtimeMatrixRows = Array.isArray(runtimeMatrix.runtimeMatrix) ? runtimeMatrix.runtimeMatrix : [];
  const atlasRoutes = Array.isArray(routeAtlas.atlasRoutes) ? routeAtlas.atlasRoutes : [];
  const models = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];

  const missionTimeline = [
    {
      id: "timeline-room",
      phase: "phase 1",
      label: "room",
      title: "Observe the room",
      route: "/public/vision",
      status: inferenceFabric.status || "prototype",
      detail: "Start in the public control room with the observed SGLang + Dynamo fabric."
    },
    {
      id: "timeline-brief",
      phase: "phase 2",
      label: "brief",
      title: "Brief the operator",
      route: "/public/vision/apple-brief",
      status: inferenceFabric.engine?.status || inferenceFabric.status || "prototype",
      detail: "Compress the room into a briefing before any shell transition begins."
    },
    {
      id: "timeline-launchpad",
      phase: "phase 3",
      label: "launch",
      title: "Open launch gates",
      route: "/public/vision/apple-launchpad",
      status: developerAccount.status || "planned",
      detail: "Turn the public Vision route into concrete launch gates and account state."
    },
    {
      id: "timeline-operator",
      phase: "phase 4",
      label: "operator",
      title: "Align transitions",
      route: "/public/vision/operator-board",
      status: `${operatorTransitions.length} transitions`,
      detail: "Keep route transitions explicit before the sovereign crossing."
    },
    {
      id: "timeline-matrix",
      phase: "phase 5",
      label: "matrix",
      title: "Compare runtime shells",
      route: "/public/vision/runtime-matrix",
      status: `${runtimeMatrixRows.length} shells`,
      detail: "Check shell-by-shell publication, launch gates, and crossings in one board."
    },
    {
      id: "timeline-atlas",
      phase: "phase 6",
      label: "atlas",
      title: "Read the route atlas",
      route: "/public/vision/route-atlas",
      status: `${atlasRoutes.length} routes`,
      detail: "See the whole public Vision route stack as one navigable atlas."
    },
    {
      id: "timeline-handoff",
      phase: "phase 7",
      label: "handoff",
      title: "Cross into sovereign truth",
      route: "/public/vision/handoff",
      status: `${handoffChecklist.length} steps`,
      detail: "Use the checklist to move from public shell to private cockpit and viewer."
    }
  ];

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision mission timeline",
    subtitle:
      "A public mission timeline for the Apple Vision shell, showing the exact order in which the room, briefing, launch, matrix, atlas, and sovereign handoff should be read.",
    route: "/public/vision/mission-timeline",
    runtimeVision: controlRoom.runtimeVision,
    inferenceFabric,
    developerAccount,
    missionTimeline,
    timelineChecks: [
      "The room starts observed and boring before any timeline phase fans out.",
      "Launch gates remain active before the runtime matrix and route atlas are treated as canonical.",
      "The route atlas and runtime matrix remain consistent with published-via-control-plane semantics.",
      "The handoff remains the final public phase before private cockpit and viewer routes."
    ],
    timelineRoutes: [
      "/public/vision",
      "/public/vision/apple-brief",
      "/public/vision/apple-launchpad",
      "/public/vision/operator-board",
      "/public/vision/runtime-matrix",
      "/public/vision/route-atlas",
      "/public/vision/mission-timeline",
      "/public/vision/sovereign-bridge",
      "/public/vision/packet-graph",
      "/public/vision/handoff",
      "/projects/sounio",
      "/projects/sounio/viewer"
    ],
    launchGates,
    models
  };
}

async function buildPublicVisionSovereignBridgeResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoff = await buildPublicVisionHandoffResponse();
  const operatorBoard = await buildPublicVisionOperatorBoardResponse();
  const missionTimeline = await buildPublicVisionMissionTimelineResponse();
  const routeAtlas = await buildPublicVisionRouteAtlasResponse();
  const inferenceFabric = controlRoom.inferenceFabric || {};
  const developerAccount = operatorBoard.developerAccount || {};
  const operatorTransitions = Array.isArray(operatorBoard.operatorTransitions)
    ? operatorBoard.operatorTransitions
    : [];
  const handoffChecklist = Array.isArray(handoff.handoffChecklist) ? handoff.handoffChecklist : [];
  const crossingPackets = Array.isArray(controlRoom.publicPrivateCrossing)
    ? controlRoom.publicPrivateCrossing
    : [];
  const atlasRoutes = Array.isArray(routeAtlas.atlasRoutes) ? routeAtlas.atlasRoutes : [];
  const timelinePhases = Array.isArray(missionTimeline.missionTimeline) ? missionTimeline.missionTimeline : [];
  const models = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];

  const bridgeStages = [
    {
      id: "bridge-room",
      label: "room",
      title: "Public room stays boring",
      route: "/public/vision",
      status: inferenceFabric.status || "prototype",
      detail: "Start from the observed public room before any sovereign crossing begins."
    },
    {
      id: "bridge-operator",
      label: "operator",
      title: "Operator transitions stay visible",
      route: "/public/vision/operator-board",
      status: `${operatorTransitions.length} transitions`,
      detail: "Keep route transitions explicit so the shell handoff never becomes magical."
    },
    {
      id: "bridge-timeline",
      label: "timeline",
      title: "Mission order remains canonical",
      route: "/public/vision/mission-timeline",
      status: `${timelinePhases.length} phases`,
      detail: "Use the mission timeline to keep the Vision shell sequence ordered and legible."
    },
    {
      id: "bridge-handoff",
      label: "handoff",
      title: "Public handoff closes cleanly",
      route: "/public/vision/handoff",
      status: `${handoffChecklist.length} steps`,
      detail: "The handoff checklist remains the explicit end of the public Vision path."
    },
    {
      id: "bridge-cockpit",
      label: "cockpit",
      title: "Sovereign cockpit opens",
      route: "/projects/sounio",
      status: "private-ready",
      detail: "The private cockpit becomes the first sovereign control surface after the public shell."
    },
    {
      id: "bridge-viewer",
      label: "viewer",
      title: "Viewer receives the packet",
      route: "/projects/sounio/viewer",
      status: "viewer-ready",
      detail: "The viewer remains the terminal sovereign route for scientific rendering and packet continuity."
    }
  ];

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision sovereign bridge",
    subtitle:
      "A public bridge surface that makes the crossing from Apple Vision routes into the sovereign Sounio cockpit and viewer explicit.",
    route: "/public/vision/sovereign-bridge",
    runtimeVision: controlRoom.runtimeVision,
    inferenceFabric,
    developerAccount,
    bridgeStages,
    bridgeChecks: [
      "The public room stays observed and boring before the bridge is taken seriously.",
      "Operator transitions and mission order stay visible before sovereign crossing begins.",
      "The handoff remains explicit before the cockpit and viewer routes are treated as destinations.",
      "The sovereign cockpit and viewer remain the terminal bridge routes for private execution."
    ],
    bridgeRoutes: [
      "/public/vision",
      "/public/vision/operator-board",
      "/public/vision/route-atlas",
      "/public/vision/mission-timeline",
      "/public/vision/sovereign-bridge",
      "/public/vision/handoff",
      "/projects/sounio",
      "/projects/sounio/viewer"
    ],
    crossingPackets,
    atlasRoutes: atlasRoutes.map((entry) => entry.route).filter(Boolean),
    models
  };
}

async function buildPublicVisionSovereignCockpitPreviewResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoff = await buildPublicVisionHandoffResponse();
  const sovereignBridge = await buildPublicVisionSovereignBridgeResponse();
  const inferenceFabric = controlRoom.inferenceFabric || {};
  const developerAccount = sovereignBridge.developerAccount || {};
  const crossingPackets = Array.isArray(sovereignBridge.crossingPackets) ? sovereignBridge.crossingPackets : [];
  const bridgeStages = Array.isArray(sovereignBridge.bridgeStages) ? sovereignBridge.bridgeStages : [];
  const handoffChecklist = Array.isArray(handoff.handoffChecklist) ? handoff.handoffChecklist : [];
  const models = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];

  const previewPanels = [
    {
      id: "preview-cockpit",
      label: "cockpit",
      title: "Sovereign cockpit",
      route: "/projects/sounio",
      status: "private-ready",
      detail: "Project control, branch truth, inference fabric status, and execution packets stay visible here."
    },
    {
      id: "preview-viewer",
      label: "viewer",
      title: "Scientific viewer",
      route: "/projects/sounio/viewer",
      status: "viewer-ready",
      detail: "The sovereign viewer remains the rendering endpoint for scientific datasets and provenance-heavy work."
    },
    {
      id: "preview-runtime",
      label: "runtime",
      title: "Inference runtime truth",
      route: "/api/projects/sounio/inference/runtime",
      status: inferenceFabric.engine?.status || inferenceFabric.status || "prototype",
      detail: "Private runtime truth stays explicit even when the public shell is already boring."
    },
    {
      id: "preview-contracts",
      label: "contracts",
      title: "Sounio contract pack",
      route: "/api/projects/sounio/sounio/contracts",
      status: "contract-ready",
      detail: "Scientific contracts remain attached to the sovereign destination instead of being hand-waved in the public shell."
    }
  ];

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Apple Vision sovereign cockpit preview",
    subtitle:
      "A public preview of the sovereign cockpit destination, showing what becomes visible once the Vision shell crosses into private Sounio truth.",
    route: "/public/vision/sovereign-cockpit-preview",
    runtimeVision: controlRoom.runtimeVision,
    inferenceFabric,
    developerAccount,
    previewPanels,
    previewChecks: [
      "The public shell stays boring before the sovereign cockpit preview is trusted.",
      "The bridge and handoff remain explicit before private destinations are treated as openable endpoints.",
      "The sovereign cockpit, viewer, runtime truth, and contract pack stay visible in the same frame.",
      "The private preview never replaces the handoff; it only makes the destination legible."
    ],
    previewRoutes: [
      "/public/vision/sovereign-bridge",
      "/public/vision/sovereign-cockpit-preview",
      "/public/vision/handoff",
      "/projects/sounio",
      "/projects/sounio/viewer",
      "/api/projects/sounio/inference/runtime",
      "/api/projects/sounio/sounio/contracts"
    ],
    handoffChecklist,
    bridgeStages,
    crossingPackets,
    models
  };
}

async function buildPublicVisionPacketGraphResponse() {
  const controlRoom = await buildPublicVisionControlRoomResponse();
  const handoff = await buildPublicVisionHandoffResponse();
  const inferenceFabric = controlRoom.inferenceFabric || {};
  const runtimeTargets = Array.isArray(controlRoom.runtimeTargets) ? controlRoom.runtimeTargets : [];
  const handoffPackets = Array.isArray(controlRoom.handoffPackets) ? controlRoom.handoffPackets : [];
  const crossing = Array.isArray(controlRoom.publicPrivateCrossing) ? controlRoom.publicPrivateCrossing : [];
  const fabricModels = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];

  const graphNodes = [
    {
      id: "public-portal",
      type: "surface",
      lane: "public",
      label: "public portal",
      title: "Sovereign research portal",
      status: "public-ready",
      route: "/public",
      detail: "Entry surface for the research narrative."
    },
    {
      id: "vision-control-room",
      type: "surface",
      lane: "vision",
      label: "vision room",
      title: "Apple Vision control room",
      status: inferenceFabric.status || "prototype",
      route: "/public/vision",
      detail: "Observed public room for the control-room shell."
    },
    {
      id: "inference-fabric",
      type: "fabric",
      lane: "inference",
      label: "fabric",
      title: "Inference fabric",
      status: inferenceFabric.status || "prototype",
      route: inferenceFabric.route || "/api/projects/sounio/inference/runtime",
      detail: inferenceFabric.deliveryMode || "cluster-gpu-inference-fabric"
    },
    {
      id: "sglang-engine",
      type: "engine",
      lane: "inference",
      label: "engine",
      title: "SGLang engine",
      status: inferenceFabric.engine?.status || "planned",
      route: inferenceFabric.modelsUrl || "/api/projects/sounio/inference/models",
      detail: inferenceFabric.engine?.endpoint || "engine endpoint unavailable"
    },
    {
      id: "dynamo-control-plane",
      type: "control-plane",
      lane: "inference",
      label: "control plane",
      title: "Dynamo control plane",
      status: inferenceFabric.controlPlane?.status || "planned",
      route: inferenceFabric.bootstrapRoute || "/api/projects/sounio/inference/bootstrap",
      detail: inferenceFabric.controlPlane?.endpoint || "control plane endpoint unavailable"
    },
    {
      id: "private-cockpit",
      type: "surface",
      lane: "private",
      label: "private cockpit",
      title: "Sovereign cockpit",
      status: "showcase-ready",
      route: "/projects/sounio",
      detail: "Private route for sovereign truth and execution control."
    },
    {
      id: "private-viewer",
      type: "surface",
      lane: "private",
      label: "private viewer",
      title: "Dataset-bound viewer",
      status: "showcase-ready",
      route: "/projects/sounio/viewer",
      detail: "Private viewer for provenance-heavy work."
    },
    ...runtimeTargets.map((target) => ({
      id: `target-${target.id || target.name}`,
      type: "runtime-target",
      lane: "shell",
      label: target.name,
      title: target.focus || target.name,
      status: target.status || "planned",
      route: target.route,
      detail: target.name
    })),
    ...handoffPackets.map((packet) => ({
      id: `packet-${packet.id || packet.name}`,
      type: "packet",
      lane: packet.lane || "general",
      label: packet.lane || "general",
      title: packet.name,
      status: packet.lane === "inference" ? inferenceFabric.engine?.status || inferenceFabric.status || "prototype" : "showcase-ready",
      route: packet.route,
      detail: packet.route
    })),
    ...crossing.map((entry, index) => ({
      id: `crossing-${index + 1}`,
      type: "crossing",
      lane: "crossing",
      label: `step ${index + 1}`,
      title: entry.step,
      status: index < 2 ? "public-ready" : "showcase-ready",
      route: entry.route,
      detail: entry.role
    }))
  ];

  const graphEdges = [
    {
      id: "edge-portal-to-vision",
      from: "public-portal",
      to: "vision-control-room",
      relation: "enter room",
      lane: "public"
    },
    {
      id: "edge-vision-to-fabric",
      from: "vision-control-room",
      to: "inference-fabric",
      relation: "reads observed fabric",
      lane: "inference"
    },
    {
      id: "edge-fabric-to-engine",
      from: "inference-fabric",
      to: "sglang-engine",
      relation: "publishes backend",
      lane: "inference"
    },
    {
      id: "edge-fabric-to-control",
      from: "inference-fabric",
      to: "dynamo-control-plane",
      relation: "routes published access",
      lane: "inference"
    },
    ...runtimeTargets.map((target) => ({
      id: `edge-${target.id || target.name}-to-room`,
      from: `target-${target.id || target.name}`,
      to: "vision-control-room",
      relation: "shares shell semantics",
      lane: "shell"
    })),
    ...handoffPackets.map((packet) => ({
      id: `edge-fabric-to-${packet.id || packet.name}`,
      from: packet.lane === "inference" ? "inference-fabric" : "vision-control-room",
      to: `packet-${packet.id || packet.name}`,
      relation: packet.lane === "inference" ? "materializes packet lane" : "carries route intent",
      lane: packet.lane || "general"
    })),
    {
      id: "edge-packet-viewer-to-private-viewer",
      from: "packet-scientificViewer",
      to: "private-viewer",
      relation: "lands in dataset viewer",
      lane: "viewer"
    },
    {
      id: "edge-packet-research-to-private-cockpit",
      from: "packet-researchPacket",
      to: "private-cockpit",
      relation: "hands off to sovereign cockpit",
      lane: "research"
    },
    ...crossing.map((entry, index) => ({
      id: `edge-crossing-${index + 1}`,
      from: index === 0 ? "public-portal" : `crossing-${index}`,
      to: `crossing-${index + 1}`,
      relation: "crossing step",
      lane: "crossing"
    }))
  ].filter((entry) => entry.from && entry.to);

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Vision packet graph",
    subtitle:
      "A graph-first public view of shells, packets, and crossings that shape the Vision control-room handoff.",
    route: "/public/vision/packet-graph",
    runtimeVision: controlRoom.runtimeVision,
    inferenceFabric,
    runtimeTargets,
    handoffPackets,
    publicPrivateCrossing: crossing,
    graphNodes,
    graphEdges,
    graphLegend: [
      "surface = public or private route",
      "runtime-target = shell that preserves the same sovereign core",
      "packet = lane-specific handoff artifact",
      "fabric = observed SGLang + Dynamo control path",
      "crossing = explicit public-to-private transition step"
    ],
    graphSummary: {
      nodeCount: graphNodes.length,
      edgeCount: graphEdges.length,
      packetCount: handoffPackets.length,
      runtimeTargetCount: runtimeTargets.length,
      modelCount: fabricModels.length
    }
  };
}

function buildPublicBeagleShowcase(project, datasetCatalog) {
  const selectedDataset = Array.isArray(datasetCatalog) ? datasetCatalog[0] || null : null;
  const selectedDatasetId = selectedDataset?.id || "";
  const sounioScientificContract = buildSounioScientificContractPacket(project, selectedDatasetId);
  const sounioContractPack = buildSounioScientificContractPack(project, selectedDatasetId);
  const primaryAnchors = [
    `project:${project.projectSlug}`,
    selectedDatasetId ? `dataset:${selectedDatasetId}` : "",
    selectedDataset?.provenance?.artifactRef ? `artifact:${selectedDataset.provenance.artifactRef}` : "",
    "lane:viewer",
    "lane:research"
  ].filter(Boolean);
  const graphEdges = [
    selectedDatasetId
      ? {
          from: `project:${project.projectSlug}`,
          relation: "showcases-dataset",
          to: `dataset:${selectedDatasetId}`
        }
      : null,
    selectedDatasetId && selectedDataset?.provenance?.artifactRef
      ? {
          from: `dataset:${selectedDatasetId}`,
          relation: "materializes-artifact",
          to: `artifact:${selectedDataset.provenance.artifactRef}`
        }
      : null,
    {
      from: "lane:viewer",
      relation: "explained-by",
      to: "lane:research"
    }
  ].filter(Boolean);

  return {
    routing: {
      status: "curated",
      recommendedAgent: "claude-code",
      lane: "research",
      mode: "explanatory",
      rationale:
        "Public surface uses explanatory Beagle packets and lineage walkthroughs instead of sovereign workspace truth.",
      truth: { source: "declared", truthMode: "declared" }
    },
    knowledgeGraph: {
      status: "curated",
      anchorCount: primaryAnchors.length,
      primaryAnchors,
      graphEdges,
      suggestedQueries: [
        `project:${project.projectSlug} -> dataset:${selectedDatasetId || "showcase"}`,
        selectedDataset?.provenance?.artifactRef
          ? `dataset:${selectedDatasetId} -> artifact:${selectedDataset.provenance.artifactRef}`
          : "dataset -> artifact",
        `vision -> route:/public/projects/${project.projectSlug}`
      ],
      provenanceMode: "showcase-linked",
      truth: { source: "declared", truthMode: "declared" }
    },
    packets: {
      researchPacket: {
        headline: "Public research packet",
        lane: "research",
        objective:
          "Explain the platform as a Beagle-native sovereign supercomputing playground with a scientific viewer and multi-runtime shells."
      },
      scientificViewer: {
        headline: "Scientific viewer showcase",
        lane: "viewer",
        objective:
          `Show ${selectedDataset?.label || "the selected dataset"} with explicit provenance, runtime diagnostics, and multiscale context.`
      },
      inferenceFabric: {
        headline: "Public inference fabric packet",
        lane: "inference",
        objective:
          "Expose the intended private inference fabric honestly, including whether the Dynamo control plane and SGLang engine are configured or still being brought online."
      },
      sglangServing: {
        headline: "Public SGLang runtime packet",
        lane: "inference",
        objective:
          "Show the GPU engine path that will back the private inference fabric once the SGLang runtime is ready."
      },
      dynamoControlPlane: {
        headline: "Public Dynamo control-plane packet",
        lane: "inference",
        objective:
          "Show the control-plane bootstrap/start/test path needed to move the private Dynamo + SGLang substrate from prototype to ready."
      },
      sounioScientificContract,
      sounioContractPack
    }
  };
}

async function buildPublicProjectShowcaseResponse(project) {
  const research = buildSupercomputingResearchResponse();
  const datasetCatalog = await resolveDatasetCatalog(project);
  const runtimeCapabilities = buildRuntimeCapabilitySummary(project);
  const viewerDefaults = project?.viewerDefaults || buildDefaultViewerDefaults({ ...project, datasetCatalog });
  const viewerShowcase = buildViewerStateSummary(project, null, datasetCatalog);
  const inferenceFabric = await buildPublicVisionInferenceSnapshot(project.projectSlug);
  const playgroundExecutive = buildPlaygroundExecutiveSummary({
    project,
    datasetCatalog,
    viewerState: viewerShowcase,
    runtimeCapabilities
  });

  return {
    surface: "public",
    projectSlug: project.projectSlug,
    project: {
      projectSlug: project.projectSlug,
      title: `${project.projectSlug} research showcase`,
      showcaseRoute: `/public/projects/${project.projectSlug}`,
      privateCockpitRoute: `/projects/${project.projectSlug}`,
      privateViewerRoute: `/projects/${project.projectSlug}/viewer`
    },
    generatedAt: new Date().toISOString(),
    title: `${project.projectSlug} research showcase`,
    subtitle:
      "Curated public surface for the sovereign supercomputing playground: research, viewer showcase, lineage, and runtime vision.",
    routes: {
      portal: "/public",
      visionControlRoom: "/public/vision",
      showcase: `/public/projects/${project.projectSlug}`,
      privateCockpit: `/projects/${project.projectSlug}`,
      privateViewer: `/projects/${project.projectSlug}/viewer`
    },
    runtimeCapabilities,
    viewerDefaults,
    datasetCatalog,
    datasetSummary: {
      totalDatasets: datasetCatalog.length,
      realDatasets: datasetCatalog.filter((entry) => entry?.sourceKind === "real").length,
      observedDatasets: datasetCatalog.filter((entry) => entry?.truth?.truthMode === "observed").length,
      selectedDatasetId: viewerShowcase?.currentDatasetId || ""
    },
    inferenceFabric,
    viewerShowcase,
    playgroundExecutive,
    beagleShowcase: buildPublicBeagleShowcase(project, datasetCatalog),
    runtimeVision: buildPublicVisionRuntimeResponse(),
    research: {
      title: research.title,
      horizon: research.horizon,
      pillars: research.pillars || [],
      sources: research.sources || []
    }
  };
}

async function buildPublicProjectSovereignBridgeResponse(project) {
  const showcase = await buildPublicProjectShowcaseResponse(project);
  const packetGraph = await buildPublicProjectPacketGraphResponse(project);
  const visionBridge = await buildPublicVisionSovereignBridgeResponse();
  const inferenceFabric = showcase.inferenceFabric || {};
  const beagle = showcase.beagleShowcase || {};
  const models = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];
  const packetEntries = Object.entries(beagle.packets || {}).map(([id, packet]) => ({
    id,
    lane: packet?.lane || "general",
    title: packet?.headline || id,
    status:
      packet?.lane === "inference"
        ? inferenceFabric.engine?.status || inferenceFabric.status || "prototype"
        : packet?.lane === "viewer"
          ? showcase.viewerShowcase?.renderer?.status || "viewer-ready"
          : "showcase-ready",
    route:
      id === "dynamoControlPlane"
        ? inferenceFabric.bootstrapRoute || `/api/projects/${project.projectSlug}/inference/bootstrap`
        : id === "sounioScientificContract" || id === "sounioContractPack"
          ? `/api/projects/${project.projectSlug}/sounio/contracts`
          : `/api/projects/${project.projectSlug}/execution/packets/${id}`,
    detail: packet?.objective || ""
  }));

  return {
    surface: "public",
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    title: `${project.projectSlug} sovereign bridge`,
    subtitle:
      "A public bridge surface for the showcase side, making the crossing from public Sounio narrative into sovereign cockpit truth explicit instead of implied.",
    route: `/public/projects/${project.projectSlug}/sovereign-bridge`,
    project: showcase.project,
    inferenceFabric,
    runtimeVision: showcase.runtimeVision,
    beagleShowcase: beagle,
    bridgeStages: [
      {
        id: "showcase-portal",
        label: "portal",
        title: "Public research portal",
        route: "/public",
        status: "public-ready",
        detail: "Start from the sovereign supercomputing narrative before narrowing into one project surface."
      },
      {
        id: "showcase-room",
        label: "showcase",
        title: showcase.title,
        route: `/public/projects/${project.projectSlug}`,
        status: "public-ready",
        detail: "The project showcase keeps research, viewer context, and fabric truth in one frame."
      },
      {
        id: "showcase-graph",
        label: "graph",
        title: packetGraph.title,
        route: `/public/projects/${project.projectSlug}/packet-graph`,
        status: inferenceFabric.status || "prototype",
        detail: "Open the packet graph before crossing so the packet lanes stay readable."
      },
      {
        id: "vision-bridge",
        label: "vision",
        title: "Apple Vision sovereign bridge",
        route: "/public/vision/sovereign-bridge",
        status: visionBridge.inferenceFabric?.status || "prototype",
        detail: "The Vision shell stays aligned with the showcase crossing grammar instead of inventing a second story."
      },
      {
        id: "private-cockpit",
        label: "cockpit",
        title: "Sovereign cockpit",
        route: `/projects/${project.projectSlug}`,
        status: "private-ready",
        detail: "Private project control, graph truth, inference runtime, and execution packets live here."
      },
      {
        id: "private-viewer",
        label: "viewer",
        title: "Scientific viewer",
        route: `/projects/${project.projectSlug}/viewer`,
        status: showcase.viewerShowcase?.renderer?.status || "viewer-ready",
        detail: "The dataset-bound viewer remains the final sovereign landing for rendering and provenance-heavy work."
      }
    ],
    bridgeChecks: [
      "Keep the public showcase and packet graph readable before treating the sovereign cockpit as the next hop.",
      "Use the observed inference fabric and packet lanes as the crossing contract, not a declarative guess.",
      "Keep the Apple Vision sovereign bridge adjacent so the showcase and Vision shells tell the same crossing story.",
      "Land inside the private cockpit and viewer only after the public shell has made the destination legible."
    ],
    bridgeRoutes: [
      "/public",
      `/public/projects/${project.projectSlug}`,
      `/public/projects/${project.projectSlug}/packet-graph`,
      "/public/vision/sovereign-bridge",
      `/projects/${project.projectSlug}`,
      `/projects/${project.projectSlug}/viewer`,
      `/api/projects/${project.projectSlug}/inference/runtime`,
      `/api/projects/${project.projectSlug}/sounio/contracts`
    ],
    crossingPackets: packetEntries,
    models
  };
}

async function buildPublicProjectSovereignCockpitPreviewResponse(project) {
  const showcase = await buildPublicProjectShowcaseResponse(project);
  const sovereignBridge = await buildPublicProjectSovereignBridgeResponse(project);
  const inferenceFabric = showcase.inferenceFabric || {};
  const models = Array.isArray(inferenceFabric.models) ? inferenceFabric.models : [];
  const bridgeStages = Array.isArray(sovereignBridge.bridgeStages) ? sovereignBridge.bridgeStages : [];
  const bridgeChecks = Array.isArray(sovereignBridge.bridgeChecks) ? sovereignBridge.bridgeChecks : [];
  const crossingPackets = Array.isArray(sovereignBridge.crossingPackets)
    ? sovereignBridge.crossingPackets
    : [];

  const previewPanels = [
    {
      id: "showcase-preview-cockpit",
      label: "cockpit",
      title: "Sovereign cockpit",
      route: `/projects/${project.projectSlug}`,
      status: "private-ready",
      detail: "Project control, branch truth, graph lineage, and inference runtime truth stay visible here."
    },
    {
      id: "showcase-preview-viewer",
      label: "viewer",
      title: "Scientific viewer",
      route: `/projects/${project.projectSlug}/viewer`,
      status: showcase.viewerShowcase?.renderer?.status || "viewer-ready",
      detail: "The sovereign viewer remains the landing for datasets, rendering state, and provenance-heavy work."
    },
    {
      id: "showcase-preview-runtime",
      label: "runtime",
      title: "Inference runtime truth",
      route: `/api/projects/${project.projectSlug}/inference/runtime`,
      status: inferenceFabric.engine?.status || inferenceFabric.status || "prototype",
      detail: "The private runtime stays explicit even when the public showcase is already boring."
    },
    {
      id: "showcase-preview-contracts",
      label: "contracts",
      title: "Sounio contract pack",
      route: `/api/projects/${project.projectSlug}/sounio/contracts`,
      status: "contract-ready",
      detail: "Scientific contracts stay attached to the sovereign landing instead of being hand-waved in the public shell."
    }
  ];

  return {
    surface: "public",
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    title: `${project.projectSlug} sovereign cockpit preview`,
    subtitle:
      "A public preview of the sovereign cockpit destination for the showcase side, making the private landing legible before the crossing is taken.",
    route: `/public/projects/${project.projectSlug}/sovereign-cockpit-preview`,
    project: showcase.project,
    inferenceFabric,
    runtimeVision: showcase.runtimeVision,
    beagleShowcase: showcase.beagleShowcase,
    previewPanels,
    previewChecks: [
      "Keep the public showcase and sovereign bridge readable before trusting the private preview.",
      "The sovereign cockpit, viewer, runtime truth, and contract pack should stay visible in one frame.",
      "The private preview should explain the landing without replacing the bridge or packet graph.",
      "Cross only after the public shell has made the sovereign destination explicit."
    ],
    previewRoutes: [
      `/public/projects/${project.projectSlug}`,
      `/public/projects/${project.projectSlug}/packet-graph`,
      `/public/projects/${project.projectSlug}/sovereign-bridge`,
      `/public/projects/${project.projectSlug}/sovereign-cockpit-preview`,
      `/projects/${project.projectSlug}`,
      `/projects/${project.projectSlug}/viewer`,
      `/api/projects/${project.projectSlug}/inference/runtime`,
      `/api/projects/${project.projectSlug}/sounio/contracts`
    ],
    bridgeStages,
    bridgeChecks,
    crossingPackets,
    models
  };
}

async function buildPublicProjectPacketGraphResponse(project) {
  const showcase = await buildPublicProjectShowcaseResponse(project);
  const inferenceFabric = showcase.inferenceFabric || {};
  const beagle = showcase.beagleShowcase || {};
  const runtimeCapabilities = showcase.runtimeCapabilities || {};
  const packetEntries = Object.entries(beagle.packets || {}).map(([id, packet]) => ({
    id: `packet-${id}`,
    type: "packet",
    lane: packet?.lane || "general",
    label: packet?.lane || "general",
    title: packet?.headline || id,
    status: packet?.lane === "inference"
      ? inferenceFabric.engine?.status || inferenceFabric.status || "prototype"
      : "showcase-ready",
    route: id === "dynamoControlPlane"
      ? inferenceFabric.bootstrapRoute || `/api/projects/${project.projectSlug}/inference/bootstrap`
      : id === "sounioScientificContract" || id === "sounioContractPack"
        ? `/api/projects/${project.projectSlug}/sounio/contracts`
        : `/api/projects/${project.projectSlug}/execution/packets/${id}`,
    detail: packet?.objective || ""
  }));

  const graphNodes = [
    {
      id: "public-showcase",
      type: "surface",
      lane: "public",
      label: "showcase",
      title: showcase.title,
      status: "public-ready",
      route: `/public/projects/${project.projectSlug}`,
      detail: "Public narrative and viewer-facing route."
    },
    {
      id: "viewer-dataset",
      type: "dataset",
      lane: "viewer",
      label: "dataset",
      title: showcase.viewerShowcase?.selectedDataset?.label || showcase.datasetSummary?.selectedDatasetId || "dataset not selected",
      status: showcase.viewerShowcase?.renderer?.status || "planned",
      route: `/projects/${project.projectSlug}/viewer`,
      detail: `${showcase.datasetSummary?.totalDatasets || 0} datasets · ${showcase.datasetSummary?.realDatasets || 0} real`
    },
    {
      id: "inference-fabric",
      type: "fabric",
      lane: "inference",
      label: "fabric",
      title: "Inference fabric",
      status: inferenceFabric.status || "prototype",
      route: inferenceFabric.route || `/api/projects/${project.projectSlug}/inference/runtime`,
      detail: inferenceFabric.deliveryMode || "cluster-gpu-inference-fabric"
    },
    {
      id: "sglang-engine",
      type: "engine",
      lane: "inference",
      label: "engine",
      title: "SGLang engine",
      status: inferenceFabric.engine?.status || "planned",
      route: inferenceFabric.modelsRoute || `/api/projects/${project.projectSlug}/inference/models`,
      detail: inferenceFabric.engine?.endpoint || "engine endpoint unavailable"
    },
    {
      id: "dynamo-control-plane",
      type: "control-plane",
      lane: "inference",
      label: "control plane",
      title: "Dynamo control plane",
      status: inferenceFabric.controlPlane?.status || "planned",
      route: inferenceFabric.bootstrapRoute || `/api/projects/${project.projectSlug}/inference/bootstrap`,
      detail: inferenceFabric.controlPlane?.endpoint || "control plane endpoint unavailable"
    },
    {
      id: "beagle-substrate",
      type: "substrate",
      lane: "beagle",
      label: "beagle",
      title: beagle.routing?.recommendedAgent || "claude-code",
      status: beagle.packets?.sounioScientificContract ? "showcase-ready" : "planned",
      route: `/api/projects/${project.projectSlug}/beagle/substrate`,
      detail: `${beagle.routing?.lane || "research"} · ${beagle.routing?.mode || "explanatory"}`
    },
    {
      id: "vision-shell",
      type: "shell",
      lane: "vision",
      label: "vision",
      title: runtimeCapabilities.vision?.interaction || "spatial-control-room",
      status: runtimeCapabilities.vision?.status || "planned",
      route: showcase.runtimeVision?.humanRoute || "/public/vision",
      detail: showcase.runtimeVision?.runtime?.focus || "control-room-first"
    },
    ...packetEntries
  ];

  const graphEdges = [
    {
      id: "edge-showcase-dataset",
      from: "public-showcase",
      to: "viewer-dataset",
      relation: "curates viewer state",
      lane: "viewer"
    },
    {
      id: "edge-showcase-fabric",
      from: "public-showcase",
      to: "inference-fabric",
      relation: "publishes observed fabric",
      lane: "inference"
    },
    {
      id: "edge-fabric-engine",
      from: "inference-fabric",
      to: "sglang-engine",
      relation: "backs model execution",
      lane: "inference"
    },
    {
      id: "edge-fabric-control",
      from: "inference-fabric",
      to: "dynamo-control-plane",
      relation: "publishes boring access",
      lane: "inference"
    },
    {
      id: "edge-showcase-beagle",
      from: "public-showcase",
      to: "beagle-substrate",
      relation: "explains substrate",
      lane: "beagle"
    },
    {
      id: "edge-showcase-vision",
      from: "public-showcase",
      to: "vision-shell",
      relation: "hands off to vision shell",
      lane: "vision"
    },
    ...packetEntries.map((packet) => ({
      id: `edge-beagle-${packet.id}`,
      from: packet.lane === "inference" ? "inference-fabric" : "beagle-substrate",
      to: packet.id,
      relation: packet.lane === "inference" ? "materializes inference lane" : "materializes public explanation",
      lane: packet.lane
    }))
  ];

  return {
    surface: "public",
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    title: `${project.projectSlug} packet graph`,
    subtitle:
      "A graph-first public view of the showcase: dataset, fabric, Beagle substrate, Vision shell, and packet lanes.",
    route: `/public/projects/${project.projectSlug}/packet-graph`,
    inferenceFabric,
    runtimeVision: showcase.runtimeVision,
    beagleShowcase: beagle,
    graphNodes,
    graphEdges,
    graphLegend: [
      "surface = public route that frames the narrative",
      "dataset = selected viewer anchor for the showcase",
      "fabric = observed SGLang + Dynamo serving path",
      "substrate = Beagle explanatory lane",
      "packet = route-specific handoff or explanatory artifact"
    ],
    graphSummary: {
      nodeCount: graphNodes.length,
      edgeCount: graphEdges.length,
      packetCount: packetEntries.length,
      modelCount: Array.isArray(inferenceFabric.models) ? inferenceFabric.models.length : 0
    }
  };
}

async function buildPublicPortalResponse() {
  const catalog = await loadCatalog();
  const projects = Array.isArray(catalog.projects) ? catalog.projects : [];
  const publicProjects = projects.filter(
    (project) =>
      project.projectSlug === "sounio" ||
      Boolean(project.playgroundClass) ||
      (Array.isArray(project.datasetCatalog) && project.datasetCatalog.length > 0)
  );

  return {
    surface: "public",
    generatedAt: new Date().toISOString(),
    title: "Sovereign supercomputing research portal",
    subtitle:
      "Curated public window into the Beagle-native control room, scientific viewer, and Sounio-driven workflow semantics.",
    research: buildSupercomputingResearchResponse(),
    runtimeVision: buildPublicVisionRuntimeResponse(),
    visionControlRoomRoute: "/public/vision",
    projects: publicProjects.map((project) => ({
      projectSlug: project.projectSlug,
      slug: project.projectSlug,
      title: `${project.projectSlug} showcase`,
      route: `/public/projects/${project.projectSlug}`,
      showcaseRoute: `/public/projects/${project.projectSlug}`,
      playgroundClass: project.playgroundClass || "mission-control",
      runtimeCapabilities: buildRuntimeCapabilitySummary(project),
      datasetCount: Array.isArray(project.datasetCatalog) ? project.datasetCatalog.length : 0,
      realDatasetCount: Array.isArray(project.datasetCatalog)
        ? project.datasetCatalog.filter((entry) => entry?.sourceKind === "real").length
        : 0
    }))
  };
}

async function buildInferenceRuntimeResponse(project) {
  const runtime = await readResolvedInferenceRuntime(project, { preferStale: true });
  const platform = runtime.controlPlane?.platform || null;
  return {
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    surface: "private",
    runtime: {
      provider: runtime.provider,
      primaryFabric: runtime.primaryFabric,
      compatibility: runtime.compatibility,
      target: runtime.target,
      configured: Boolean(runtime.configured),
      reachable: Boolean(runtime.reachable),
      status: runtime.status,
      truthMode: runtime.truthMode,
      healthStatus: runtime.healthStatus || "",
      lastError: runtime.lastError || "",
      endpoint: runtime.endpoint || "",
      healthUrl: runtime.healthUrl || "",
      modelsUrl: runtime.modelsUrl || "",
      completionsUrl: runtime.completionsUrl || "",
      chatCompletionsUrl: runtime.chatCompletionsUrl || "",
      models: Array.isArray(runtime.models)
        ? runtime.models.map((entry) => ({
            ...entry,
            provider: entry?.provider || entry?.family || ""
          }))
        : [],
      controlPlaneMissing: Boolean(runtime.controlPlaneMissing),
      docsPath: runtime.docsPath || "",
      engine: {
        provider: runtime.engine?.provider || "",
        role: runtime.engine?.role || "",
        status: runtime.engine?.status || "",
        accessMode: runtime.engine?.accessMode || "",
        target: runtime.engine?.target || "",
        endpoint: runtime.engine?.endpoint || "",
        reachable: Boolean(runtime.engine?.reachable),
        lastError: runtime.engine?.lastError || "",
        healthUrl: runtime.engine?.healthUrl || "",
        modelsUrl: runtime.engine?.modelsUrl || "",
        completionsUrl:
          runtime.engine?.endpoint && runtime.engine?.completionsPath
            ? `${runtime.engine.endpoint}${runtime.engine.completionsPath}`
            : "",
        chatCompletionsUrl:
          runtime.engine?.endpoint && runtime.engine?.chatCompletionsPath
            ? `${runtime.engine.endpoint}${runtime.engine.chatCompletionsPath}`
            : "",
        backendTransports: runtime.engine?.backendTransports || [],
        discoveryNamespaces: runtime.engine?.discoveryNamespaces || [],
        bootstrapCommand: runtime.engine?.bootstrapCommand || "",
        rolloutCommand: runtime.engine?.rolloutCommand || "",
        logsCommand: runtime.engine?.logsCommand || "",
        testCommand: runtime.engine?.testCommand || ""
      },
      controlPlane: {
        provider: runtime.controlPlane?.provider || "",
        role: runtime.controlPlane?.role || "",
        status: runtime.controlPlane?.status || "",
        target: runtime.controlPlane?.target || "",
        endpoint: runtime.controlPlane?.endpoint || "",
        reachable: Boolean(runtime.controlPlane?.reachable),
        lastError: runtime.controlPlane?.lastError || "",
        healthUrl: runtime.controlPlane?.healthUrl || "",
        modelsUrl: runtime.controlPlane?.modelsUrl || "",
        completionsUrl:
          runtime.controlPlane?.endpoint && runtime.controlPlane?.completionsPath
            ? `${runtime.controlPlane.endpoint}${runtime.controlPlane.completionsPath}`
            : "",
        chatCompletionsUrl:
          runtime.controlPlane?.endpoint && runtime.controlPlane?.chatCompletionsPath
            ? `${runtime.controlPlane.endpoint}${runtime.controlPlane.chatCompletionsPath}`
            : "",
        models: Array.isArray(runtime.controlPlane?.models) ? runtime.controlPlane.models : [],
        bootstrapCommand: runtime.controlPlane?.bootstrapCommand || "",
        rolloutCommand: runtime.controlPlane?.rolloutCommand || "",
        logsCommand: runtime.controlPlane?.logsCommand || "",
        testCommand: runtime.controlPlane?.testCommand || "",
        platform: platform
          ? {
              platformNamespace: platform.platformNamespace || "",
              pullSecretName: platform.pullSecretName || "",
              pullSecretPresent: Boolean(platform.pullSecretPresent),
              platformNamespacePresent: Boolean(platform.platformNamespacePresent),
              crdsPresent: Boolean(platform.crdsPresent),
              operatorPresent: Boolean(platform.operatorPresent),
              status: platform.status || "",
              lastError: platform.lastError || ""
            }
          : null
      }
    }
  };
}

async function buildInferenceModelsResponse(project) {
  const runtime = await readResolvedInferenceRuntime(project, { preferStale: true });
  return {
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    provider: runtime.provider,
    compatibility: runtime.compatibility,
    status: runtime.status,
    sourceEndpoint: runtime.endpoint,
    modelCount: Array.isArray(runtime.models) ? runtime.models.length : 0,
    models: runtime.models || []
  };
}

async function buildInferenceBootstrapApiResponse(project) {
  const declared = buildInferenceBootstrapResponse(project);
  const runtime = await readResolvedInferenceRuntime(project, { preferStale: true });
  return {
    ...declared,
    runtimeStatus: runtime.status,
    reachable: runtime.reachable,
    lastError: runtime.lastError || "",
    activeEndpoint: runtime.endpoint,
    models: runtime.models || [],
    workload: runtime.workload || null
  };
}

async function buildInferenceWorkloadResponse(project) {
  const runtime = await readResolvedInferenceRuntime(project, { preferStale: true });
  return {
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    provider: runtime.provider,
    endpoint: runtime.endpoint,
    workload: runtime.workload || null
  };
}

async function buildSounioContractsResponse(project) {
  const selectedDatasetId =
    project?.viewerDefaults?.entryDatasetId ||
    (Array.isArray(project?.datasetCatalog) ? project.datasetCatalog[0]?.id || "" : "");
  const pack = buildSounioScientificContractPack(project, selectedDatasetId);
  return {
    projectSlug: project.projectSlug,
    generatedAt: new Date().toISOString(),
    lane: "sounio",
    pack,
    latestRun: await readScientificWorkflowRun(project.projectSlug)
  };
}

function buildSupercomputingResearchResponse() {
  return {
    ...SUPERCOMPUTING_RESEARCH_BRIEF,
    generatedAt: new Date().toISOString()
  };
}

function buildProjectPosturePolicyResponse(projects = []) {
  const entries = Array.isArray(projects) ? projects : [];
  const assignments = entries.map((project) => ({
    projectSlug: cleanValue(project?.projectSlug || "unknown"),
    posture: cleanValue(project?.mode || "undeclared"),
    workspaceId: cleanValue(project?.workspaceId || ""),
    workstreamId: cleanValue(project?.workstreamId || "")
  }));

  return {
    generatedAt: new Date().toISOString(),
    lane: "sovereign-project-posture",
    title: "Sovereign project posture policy",
    coreRule:
      "one large project = one sovereign surface, but not every sovereign surface = always-on",
    separationRules: [
      "workspace habitat != research job",
      "research operations stay run-shaped and ephemeral",
      "cluster truth stays infrastructure-shaped"
    ],
    postureDefinitions: [
      {
        name: "always-on",
        summary: "continuous sovereign habitat",
        operationalMeaning: "replicas can stay at 1 when daily continuity matters"
      },
      {
        name: "warm",
        summary: "persistent sovereign habitat kept on standby",
        operationalMeaning:
          "PVC and identity remain live while the habitat normally rests at replicas 0"
      },
      {
        name: "cold",
        summary: "cataloged sovereign habitat activated intentionally",
        operationalMeaning:
          "the surface stays reproducible without pretending it is an active daily lane"
      }
    ],
    counts: {
      totalProjects: assignments.length,
      alwaysOn: assignments.filter((entry) => entry.posture === "always-on").length,
      warm: assignments.filter((entry) => entry.posture === "warm").length,
      cold: assignments.filter((entry) => entry.posture === "cold").length
    },
    assignments
  };
}

async function readCatalogExecutiveState() {
  const catalog = await loadCatalog();
  const projects = Array.isArray(catalog.projects) ? catalog.projects : [];
  const entries = await Promise.all(
    projects.map(async (project) => {
      const [operationalTruth, fastCluster] = await Promise.all([
        resolveOperationalTruth(project).catch(() => null),
        readCachedFastClusterState(project, { preferStale: true }).catch(() => null)
      ]);
      const clusterState = fastCluster?.value || null;
      const cachedFast = getCachedFastWorkspaceMemory(project.projectSlug, { allowStale: true });
      if (cachedFast?.value) {
        return buildCatalogExecutiveEntry(
          project,
          cachedFast.value,
          "ready",
          operationalTruth,
          clusterState
        );
      }
      if (project.projectSlug !== "sounio") {
        return buildCatalogExecutiveEntry(project, null, "policy", operationalTruth, clusterState);
      }
      try {
        const memory = await withTimeout(
          readFastWorkspaceMemory(project, { preferStale: true }),
          `catalog executive ${project.projectSlug}`,
          2500
        );
        return buildCatalogExecutiveEntry(
          project,
          memory,
          "ready",
          operationalTruth,
          clusterState
        );
      } catch {
        return buildCatalogExecutiveEntry(project, null, "policy", operationalTruth, clusterState);
      }
    })
  );

  return {
    generatedAt: new Date().toISOString(),
    startupWarm: startupWarmState,
    projectPosturePolicy: buildProjectPosturePolicyResponse(projects),
    projects: entries
  };
}

async function readCachedCatalogExecutiveState({ preferStale = false } = {}) {
  const cached = getCachedCatalogExecutiveState({ allowStale: preferStale });
  if (cached?.value) {
    if (preferStale && cached.isStale && !cached.promise) {
      const refresh = readCatalogExecutiveState()
        .then((value) => {
          setCachedCatalogExecutiveState(value, null);
          return value;
        })
        .catch(() => {
          const current = getCachedCatalogExecutiveState({ allowStale: true });
          if (current?.value) {
            setCachedCatalogExecutiveState(current.value, null);
            return current.value;
          }
          invalidateCatalogExecutiveState();
          return null;
        });
      setCachedCatalogExecutiveState(cached.value, refresh);
    }
    return cached.value;
  }
  if (cached?.promise) {
    return cached.promise;
  }

  const pending = readCatalogExecutiveState()
    .then((value) => {
      setCachedCatalogExecutiveState(value, null);
      return value;
    })
    .catch((error) => {
      invalidateCatalogExecutiveState();
      throw error;
    });

  setCachedCatalogExecutiveState(null, pending);
  return pending;
}

function jsonResponse(fn) {
  return async (req, res) => {
    try {
      const payload = await fn(req, res);
      if (!res.headersSent) {
        res.json(payload);
      }
    } catch (error) {
      res.status(error.statusCode || 500).json({
        error: error.message,
        stderr: error.stderr || "",
        stdout: error.stdout || ""
      });
    }
  };
}

function ensureConfirmed(req, actionLabel) {
  if (req.body?.confirm === true) {
    return;
  }
  const error = new Error(`${actionLabel} requires explicit confirmation`);
  error.statusCode = 400;
  throw error;
}

async function readGitStatus(project) {
  const statusCommand =
    'cd "$WORKSPACE_ROOT" && ' +
    'printf "BRANCH:%s\\n" "$(git branch --show-current)" && ' +
    'printf "DIRTY:%s\\n" "$(git status --short | wc -l | tr -d \' \')" && ' +
    'printf "PUBLISHABLE_DIRTY:%s\\n" "$(git status --short | grep -vE \'^\\?\\? \\.beagle(/|$)\' | wc -l | tr -d \' \')" && ' +
    'printf "MEMORY_LOCAL_DIRTY:%s\\n" "$(git status --short | grep -E \'^\\?\\? \\.beagle(/|$)\' | wc -l | tr -d \' \')" && ' +
    'echo "__STATUS__" && git status --short && ' +
    'echo "__DIFFSTAT__" && git diff --stat && ' +
    'echo "__RECENT__" && git log --oneline -5';

  const { stdout } = await runWorkspaceShell(
    project,
    { WORKSPACE_ROOT: project.workspaceRoot },
    statusCommand
  );

  const branchMatch = stdout.match(/^BRANCH:(.*)$/m);
  const dirtyMatch = stdout.match(/^DIRTY:(.*)$/m);
  const publishableDirtyMatch = stdout.match(/^PUBLISHABLE_DIRTY:(.*)$/m);
  const memoryLocalDirtyMatch = stdout.match(/^MEMORY_LOCAL_DIRTY:(.*)$/m);

  return {
    branch: branchMatch?.[1]?.trim() || "",
    dirtyCount: Number(dirtyMatch?.[1]?.trim() || "0"),
    publishableDirtyCount: Number(publishableDirtyMatch?.[1]?.trim() || "0"),
    memoryLocalDirtyCount: Number(memoryLocalDirtyMatch?.[1]?.trim() || "0"),
    statusShort: parseSection(stdout, "STATUS", "DIFFSTAT"),
    diffStat: parseSection(stdout, "DIFFSTAT", "RECENT"),
    recentCommits: parseSection(stdout, "RECENT")
  };
}

async function readToolchainStatus(project) {
  const script =
    'cd "$WORKSPACE_ROOT" && ' +
    'for tool in claude codex kimi "$BROWSER_TOOL"; do ' +
    'if command -v "$tool" >/dev/null 2>&1; then ' +
    'printf "__TOOL__%s\\n" "$tool"; ' +
    '"$tool" --version 2>&1 | sed -n "1p"; ' +
    "else " +
    'printf "__TOOL__%s\\nmissing\\n" "$tool"; ' +
    "fi; " +
    "done";

  const { stdout } = await runWorkspaceShell(
    project,
    {
      WORKSPACE_ROOT: project.workspaceRoot,
      BROWSER_TOOL: project.browserAutomationCommand || "agent-browser"
    },
    script
  );

  const tools = {};
  let currentName = "";
  for (const line of stdout.split("\n")) {
    const toolMatch = line.match(/^__TOOL__(.+)$/);
    if (toolMatch) {
      currentName = toolMatch[1].trim();
      continue;
    }
    if (!currentName) {
      continue;
    }
    const version = line.trim();
    tools[currentName] = {
      installed: version !== "missing" && version.length > 0,
      version: version === "missing" ? "" : version
    };
    currentName = "";
  }

  return tools;
}

async function readDiffPreview(project) {
  const script =
    'cd "$WORKSPACE_ROOT" && ' +
    'echo "__WORKING_STAT__" && git diff --stat && ' +
    'echo "__WORKING_PATCH__" && git diff --no-ext-diff --unified=3 | sed -n "1,220p" && ' +
    'echo "__STAGED_STAT__" && git diff --cached --stat && ' +
    'echo "__STAGED_PATCH__" && git diff --cached --no-ext-diff --unified=3 | sed -n "1,220p"';

  const { stdout } = await runWorkspaceShell(
    project,
    { WORKSPACE_ROOT: project.workspaceRoot },
    script
  );

  return {
    workingStat: parseSection(stdout, "WORKING_STAT", "WORKING_PATCH"),
    workingPatchPreview: parseSection(stdout, "WORKING_PATCH", "STAGED_STAT"),
    stagedStat: parseSection(stdout, "STAGED_STAT", "STAGED_PATCH"),
    stagedPatchPreview: parseSection(stdout, "STAGED_PATCH")
  };
}

async function readPrPreview(project, base) {
  const script =
    'cd "$WORKSPACE_ROOT" && ' +
    'printf "BRANCH:%s\\n" "$(git branch --show-current)" && ' +
    'printf "BASE:%s\\n" "$PR_BASE" && ' +
    'git fetch origin "$PR_BASE" >/dev/null 2>&1 || true && ' +
    'printf "COUNTS:%s\\n" "$(git rev-list --left-right --count "origin/$PR_BASE...HEAD" 2>/dev/null || echo \'0 0\')" && ' +
    'echo "__COMMITS__" && (git log --oneline "origin/$PR_BASE..HEAD" -10 2>/dev/null || git log --oneline -10) && ' +
    'echo "__EXISTING_PR__" && (gh pr view --json number,url,title,state,isDraft,headRefName,baseRefName,reviewDecision,mergeStateStatus 2>/dev/null || echo "{}")';

  const { stdout } = await runWorkspaceShell(
    project,
    {
      WORKSPACE_ROOT: project.workspaceRoot,
      PR_BASE: base
    },
    script
  );

  const branch = stdout.match(/^BRANCH:(.*)$/m)?.[1]?.trim() || "";
  const resolvedBase = stdout.match(/^BASE:(.*)$/m)?.[1]?.trim() || base;
  const counts = stdout.match(/^COUNTS:(.*)$/m)?.[1]?.trim() || "0 0";
  const [behind = "0", ahead = "0"] = counts.split(/\s+/);
  const existingPrRaw = parseSection(stdout, "EXISTING_PR");

  let existingPr = null;
  try {
    if (existingPrRaw && existingPrRaw !== "{}") {
      existingPr = JSON.parse(existingPrRaw);
    }
  } catch {
    existingPr = null;
  }

  return {
    branch,
    base: resolvedBase,
    ahead: Number(ahead || "0"),
    behind: Number(behind || "0"),
    branchCommits: parseSection(stdout, "COMMITS", "EXISTING_PR"),
    existingPr
  };
}

async function readGitGuardrails(project, base) {
  const script =
    'cd "$WORKSPACE_ROOT" && ' +
    'printf "BRANCH:%s\\n" "$(git branch --show-current)" && ' +
    'printf "DIRTY:%s\\n" "$(git status --short | wc -l | tr -d \' \')" && ' +
    'printf "REMOTE:%s\\n" "$(git remote get-url origin 2>/dev/null || echo \'\')" && ' +
    'printf "BASE:%s\\n" "$PR_BASE" && ' +
    'printf "HAS_REMOTE_TRACKING:%s\\n" "$(git show-ref --verify --quiet "refs/remotes/origin/$CURRENT_BRANCH" && echo yes || echo no)" && ' +
    'printf "PUSH_COUNTS:%s\\n" "$(if git show-ref --verify --quiet "refs/remotes/origin/$CURRENT_BRANCH"; then git rev-list --left-right --count "origin/$CURRENT_BRANCH...HEAD"; else echo \'0 0\'; fi)" && ' +
    'echo "__GH_AUTH__" && (gh auth status 2>&1 || true)';

  const status = await readGitStatus(project);
  const preview = await readPrPreview(project, base);
  const { stdout } = await runWorkspaceShell(
    project,
    {
      WORKSPACE_ROOT: project.workspaceRoot,
      PR_BASE: base,
      CURRENT_BRANCH: status.branch
    },
    script
  );

  const branch = stdout.match(/^BRANCH:(.*)$/m)?.[1]?.trim() || status.branch || "";
  const dirtyCount = Number(stdout.match(/^DIRTY:(.*)$/m)?.[1]?.trim() || status.dirtyCount || 0);
  const publishableDirtyCount = Number(status.publishableDirtyCount || 0);
  const memoryLocalDirtyCount = Number(status.memoryLocalDirtyCount || 0);
  const remoteUrl = stdout.match(/^REMOTE:(.*)$/m)?.[1]?.trim() || "";
  const remoteTracking = stdout.match(/^HAS_REMOTE_TRACKING:(.*)$/m)?.[1]?.trim() === "yes";
  const counts = stdout.match(/^PUSH_COUNTS:(.*)$/m)?.[1]?.trim() || "0 0";
  const [behindOrigin = "0", aheadOrigin = "0"] = counts.split(/\s+/);
  const ghAuthSummary = parseSection(stdout, "GH_AUTH");
  const ghAuthOk =
    ghAuthSummary.includes("Logged in to") ||
    ghAuthSummary.includes("Active account");

  const cautions = [];
  if (!publishableDirtyCount) {
    cautions.push("Working tree is clean. There is nothing new to commit from the cockpit.");
  }
  if (memoryLocalDirtyCount > 0) {
    cautions.push(`Memory-local artifacts are present (${memoryLocalDirtyCount} entries under .beagle/) but are intentionally excluded from publication.`);
  }
  if (!ghAuthOk) {
    cautions.push("GitHub auth is not healthy in the habitat. Push and PR creation will fail until gh auth is repaired.");
  }
  if (Number(behindOrigin) > 0) {
    cautions.push(`Local branch is behind origin/${branch} by ${behindOrigin}. Pull or reconcile before pushing more changes.`);
  }
  if (branch && base && branch === base) {
    cautions.push("Current branch matches the PR base. Opening a PR from the base branch is intentionally blocked.");
  }
  if (preview.behind > 0) {
    cautions.push(`Branch is behind ${base} by ${preview.behind}. Reconcile before opening a draft PR.`);
  }
  if (preview.existingPr?.url) {
    cautions.push(`An existing PR already exists for this branch: ${preview.existingPr.url}`);
  }
  if (!remoteTracking) {
    cautions.push("No remote tracking branch exists yet. The first push will create origin/<branch>.");
  }

  return {
    branch,
    base,
    branchMatchesBase: Boolean(branch && base && branch === base),
    dirtyCount,
    publishableDirtyCount,
    memoryLocalDirtyCount,
    remoteUrl,
    remoteTracking,
    aheadOrigin: Number(aheadOrigin || 0),
    behindOrigin: Number(behindOrigin || 0),
    ghAuthOk,
    ghAuthSummary,
    canCommit: publishableDirtyCount > 0,
    canPush: Boolean(branch) && ghAuthOk && Number(behindOrigin || 0) === 0,
    canPr:
      Boolean(branch) &&
      ghAuthOk &&
      preview.ahead > 0 &&
      branch !== base &&
      preview.behind === 0 &&
      !preview.existingPr,
    cautions
  };
}

function safeJsonParse(raw, fallback = null) {
  try {
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function computeMergeReadiness(preview, guardrails) {
  const existingPr = preview?.existingPr;
  if (!existingPr?.url) {
    return "no-pr";
  }
  if (existingPr.state && existingPr.state !== "OPEN") {
    return "closed";
  }
  if (existingPr.isDraft) {
    return "draft";
  }
  if (existingPr.reviewDecision === "CHANGES_REQUESTED") {
    return "changes-requested";
  }
  if (existingPr.reviewDecision === "REVIEW_REQUIRED") {
    return "review-required";
  }
  if (existingPr.mergeStateStatus && !["CLEAN", "HAS_HOOKS", "UNSTABLE"].includes(existingPr.mergeStateStatus)) {
    return `merge-${String(existingPr.mergeStateStatus).toLowerCase()}`;
  }
  if (guardrails?.publishableDirtyCount > 0) {
    return "dirty-habitat";
  }
  return "merge-ready-ish";
}

function derivePublicationStage(preview, guardrails, mergeReadiness, session = null) {
  const existingPr = preview?.existingPr;
  const mergeDecision = session?.lastMergeDecision || "";
  if (mergeDecision === "merged") {
    return "merged-later";
  }
  if (mergeDecision === "merge-ready") {
    return "merge-ready";
  }
  if (!existingPr?.url) {
    if (guardrails?.publishableDirtyCount > 0 || guardrails?.canCommit) {
      return "working";
    }
    if ((guardrails?.aheadOrigin ?? 0) > 0 || guardrails?.remoteTracking) {
      return "published";
    }
    return "working";
  }
  if (existingPr.state && existingPr.state !== "OPEN") {
    return existingPr.state === "MERGED" ? "merged-later" : "published";
  }
  if (mergeReadiness === "merge-ready-ish") {
    return "merge-ready";
  }
  return "under-review";
}

function parseEnvBlock(raw) {
  const env = {};
  for (const line of String(raw || "").split("\n")) {
    const match = line.match(/^export\s+([A-Z0-9_]+)=(.*)$/);
    if (!match) {
      continue;
    }
    const [, key, value] = match;
    env[key] = cleanValue(value).replace(/^'/, "").replace(/'$/, "");
  }
  return env;
}

function splitCsv(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function workspaceRootToClaudeProjectDir(workspaceRoot) {
  return String(workspaceRoot || "")
    .replace(/\//g, "-");
}

async function readAiMemory(project) {
  const claudeProjectDir = workspaceRootToClaudeProjectDir(project.workspaceRoot);
  const script = `
python3 - <<'PY'
import json, os, glob
from pathlib import Path

home = Path(os.environ.get("HOME", ""))
claude_dir = home / ".claude" / "projects" / os.environ["CLAUDE_PROJECT_DIR"]
codex_dir = home / ".codex"

def truncate(text, limit=220):
    text = " ".join(str(text or "").split())
    return text[:limit] + ("..." if len(text) > limit else "")

def read_tail_jsonl(path, max_lines=24, block_size=65536):
    try:
        with path.open("rb") as fh:
            fh.seek(0, 2)
            size = fh.tell()
            read_size = min(size, block_size)
            fh.seek(max(0, size - read_size))
            raw = fh.read().decode("utf-8", errors="replace")
    except Exception:
        return []
    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    rows = []
    for line in lines[-max_lines:]:
        try:
            rows.append(json.loads(line))
        except Exception:
            continue
    return rows

def latest_text_from_claude_record(record):
    message = record.get("message") or {}
    content = message.get("content") or []
    if isinstance(content, str):
        return content
    if isinstance(content, dict):
        if content.get("text"):
            return content.get("text")
        if content.get("content"):
            return truncate(content.get("content"))
    if isinstance(content, list):
        for item in reversed(content):
            if isinstance(item, str) and item:
                return item
            if isinstance(item, dict) and item.get("text"):
                return item.get("text")
    tool_result = record.get("toolUseResult") or {}
    if isinstance(tool_result, str):
        return tool_result
    if tool_result.get("stdout"):
        return tool_result.get("stdout")
    return ""

def score_claude_record(record):
    score = 0
    text = latest_text_from_claude_record(record)
    if text:
        score += 5
    if record.get("timestamp"):
        score += 2
    if record.get("gitBranch"):
        score += 2
    if record.get("cwd"):
        score += 2
    if record.get("slug"):
        score += 1
    if record.get("type") == "assistant":
        score += 2
    if record.get("type") == "user":
        score += 1
    return score

def read_claude():
    payload = {
        "available": False,
        "projectDir": str(claude_dir),
        "sessionCount": 0,
        "latestSessionId": "",
        "latestTimestamp": "",
        "latestSlug": "",
        "latestBranch": "",
        "latestCwd": "",
        "latestRole": "",
        "latestSnippet": "",
        "recentSessions": []
    }
    if not claude_dir.exists():
        return payload
    files = sorted(claude_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    payload["available"] = True
    payload["sessionCount"] = len(files)
    for path in files[:5]:
        records = read_tail_jsonl(path)
        if not records:
            continue
        ranked = []
        for idx, record in enumerate(records):
            ranked.append((score_claude_record(record), idx, record, truncate(latest_text_from_claude_record(record))))
        ranked.sort(key=lambda item: (item[0], item[1]), reverse=True)
        _, _, last, snippet = ranked[0]
        item = {
            "sessionId": last.get("sessionId") or path.stem,
            "timestamp": last.get("timestamp", ""),
            "slug": last.get("slug", ""),
            "branch": last.get("gitBranch", ""),
            "cwd": last.get("cwd", ""),
            "role": last.get("type", ""),
            "snippet": snippet
        }
        payload["recentSessions"].append(item)
        if not payload["latestSessionId"]:
            payload["latestSessionId"] = item["sessionId"]
            payload["latestTimestamp"] = item["timestamp"]
            payload["latestSlug"] = item["slug"]
            payload["latestBranch"] = item["branch"]
            payload["latestCwd"] = item["cwd"]
            payload["latestRole"] = item["role"]
            payload["latestSnippet"] = item["snippet"]
    return payload

def read_jsonl_tail(path, count=5):
    if not path.exists():
        return []
    return read_tail_jsonl(path, max_lines=max(10, count * 3))[-count:]

def read_codex():
    history_path = codex_dir / "history.jsonl"
    session_index_path = codex_dir / "session_index.jsonl"
    history_tail = read_jsonl_tail(history_path, 5)
    session_tail = read_jsonl_tail(session_index_path, 5)
    latest = history_tail[-1] if history_tail else {}
    payload = {
        "available": history_path.exists() or session_index_path.exists(),
        "historyPath": str(history_path),
        "sessionIndexPath": str(session_index_path),
        "latestSessionId": latest.get("session_id", ""),
        "latestTimestamp": latest.get("ts", ""),
        "latestSnippet": truncate(latest.get("text", "")),
        "recentPrompts": [
            {
                "sessionId": row.get("session_id", ""),
                "timestamp": row.get("ts", ""),
                "snippet": truncate(row.get("text", ""), 160)
            }
            for row in history_tail
        ],
        "recentThreads": [
            {
                "id": row.get("id", ""),
                "name": row.get("thread_name", ""),
                "updatedAt": row.get("updated_at", "")
            }
            for row in reversed(session_tail)
        ]
    }
    return payload

print(json.dumps({"claude": read_claude(), "codex": read_codex()}))
PY
`;

  const { stdout } = await runWorkspaceShell(
    project,
    { CLAUDE_PROJECT_DIR: claudeProjectDir },
    script
  );

  return safeJsonParse(stdout, {
    claude: { available: false, recentSessions: [] },
    codex: { available: false, recentPrompts: [], recentThreads: [] }
  });
}

async function readFastVsixStatus(project) {
  const script =
    'cd "$WORKSPACE_ROOT" && ' +
    '(sed -n "1,260p" .beagle/context/vsix-pack-status.json 2>/dev/null || true)';
  try {
    const { stdout } = await runWorkspaceShell(project, { WORKSPACE_ROOT: project.workspaceRoot }, script);
    return safeJsonParse(stdout, {});
  } catch {
    return {};
  }
}

async function readCachedFastVsixStatus(project, { preferStale = false } = {}) {
  const cached = getCachedFastVsixStatus(project.projectSlug, { allowStale: preferStale });
  if (cached?.value) {
    if (preferStale && cached.isStale && !cached.promise) {
      const refresh = readFastVsixStatus(project)
        .then((value) => {
          setCachedFastVsixStatus(project.projectSlug, value, null);
          return { value, source: "live" };
        })
        .catch(() => {
          const current = getCachedFastVsixStatus(project.projectSlug, { allowStale: true });
          if (current?.value) {
            setCachedFastVsixStatus(project.projectSlug, current.value, null);
            return { value: current.value, source: "cached" };
          }
          invalidateFastVsixStatus(project.projectSlug);
          return { value: {}, source: "policy-fallback" };
        });
      setCachedFastVsixStatus(project.projectSlug, cached.value, refresh);
    }
    return { value: cached.value, source: cached.isStale ? "cached" : "live" };
  }
  if (cached?.promise) {
    return cached.promise;
  }

  const pending = readFastVsixStatus(project)
    .then((value) => {
      setCachedFastVsixStatus(project.projectSlug, value, null);
      return { value, source: "live" };
    })
    .catch((error) => {
      invalidateFastVsixStatus(project.projectSlug);
      throw error;
    });

  setCachedFastVsixStatus(project.projectSlug, null, pending);
  return pending;
}

async function readFastPublicationState(project) {
  const preferredBase = project.preferredPrBase || project.branch || "main";
  const [gitResult, prPreviewResult] = await Promise.allSettled([
    withTimeout(readGitStatus(project), "fast git status", fastGitStatusTimeoutMs),
    withTimeout(readPrPreview(project, preferredBase), "fast pr preview", fastPrPreviewTimeoutMs)
  ]);

  if (gitResult.status !== "fulfilled") {
    const publicFallback = await withTimeout(
      readPublicGitHubOpenPrByBase(project, preferredBase),
      "public github open pr",
      fastPrPreviewTimeoutMs
    ).catch(() => null);
    if (publicFallback?.branch) {
      return {
        preferredBase,
        git: {
          branch: publicFallback.branch,
          dirtyCount: null,
          publishableDirtyCount: null,
          memoryLocalDirtyCount: null,
          statusShort: "",
          diffStat: "",
          recentCommits: ""
        },
        prPreview: publicFallback,
        partial: true
      };
    }
    throw gitResult.reason;
  }

  const git = gitResult.value;
  let prPreview =
    prPreviewResult.status === "fulfilled"
      ? prPreviewResult.value
      : null;
  let partial = prPreviewResult.status !== "fulfilled";

  if (!prPreview && git.branch) {
    try {
      prPreview = await withTimeout(
        readPublicGitHubPrPreview(project, preferredBase, git.branch),
        "public github pr preview",
        fastPrPreviewTimeoutMs
      );
      partial = false;
    } catch {
      prPreview = null;
    }
  }

  if (!prPreview) {
    prPreview = {
      branch: git.branch || "",
      base: preferredBase,
      ahead: 0,
      behind: 0,
      branchCommits: [],
      existingPr: null
    };
  }
  return {
    preferredBase,
    git,
    prPreview,
    partial
  };
}

async function readCachedFastPublicationState(project, { preferStale = false } = {}) {
  const cached = getCachedFastPublicationState(project.projectSlug, { allowStale: preferStale });
  if (cached?.value) {
    if (preferStale && cached.isStale && !cached.promise) {
      const refresh = readFastPublicationState(project)
        .then((value) => {
          setCachedFastPublicationState(project.projectSlug, value, null);
          return { value, source: "live" };
        })
        .catch(() => {
          const current = getCachedFastPublicationState(project.projectSlug, { allowStale: true });
          if (current?.value) {
            setCachedFastPublicationState(project.projectSlug, current.value, null);
            return { value: current.value, source: "cached" };
          }
          invalidateFastPublicationState(project.projectSlug);
          return { value: null, source: "session-fallback" };
        });
      setCachedFastPublicationState(project.projectSlug, cached.value, refresh);
    }
    return { value: cached.value, source: cached.isStale ? "cached" : "live" };
  }
  if (cached?.promise) {
    return cached.promise;
  }

  const pending = readFastPublicationState(project)
    .then((value) => {
      setCachedFastPublicationState(project.projectSlug, value, null);
      return { value, source: "live" };
    })
    .catch((error) => {
      invalidateFastPublicationState(project.projectSlug);
      throw error;
    });

  setCachedFastPublicationState(project.projectSlug, null, pending);
  return pending;
}

async function readFastClusterState(project) {
  const cluster = await withTimeout(readClusterSummary(project), "fast cluster state", 3000);
  return {
    workspacePod: cluster.workspacePod || null,
    workspaceWorkload: cluster.workspaceWorkload || null,
    cockpitPod: cluster.cockpitPod || null,
    surfaces: Array.isArray(cluster.surfaces) ? cluster.surfaces : [],
    doctorBundle: Array.isArray(cluster.doctorBundle) ? cluster.doctorBundle : clusterDoctorBundle
  };
}

async function readCachedFastClusterState(project, { preferStale = false } = {}) {
  const cached = getCachedFastClusterState(project.projectSlug, { allowStale: preferStale });
  if (cached?.value) {
    if (preferStale && cached.isStale && !cached.promise) {
      const refresh = readFastClusterState(project)
        .then((value) => {
          setCachedFastClusterState(project.projectSlug, value, null);
          return { value, source: "live" };
        })
        .catch(() => {
          const current = getCachedFastClusterState(project.projectSlug, { allowStale: true });
          if (current?.value) {
            setCachedFastClusterState(project.projectSlug, current.value, null);
            return { value: current.value, source: "cached" };
          }
          invalidateFastClusterState(project.projectSlug);
          return { value: null, source: "policy-fallback" };
        });
      setCachedFastClusterState(project.projectSlug, cached.value, refresh);
    }
    return { value: cached.value, source: cached.isStale ? "cached" : "live" };
  }
  if (cached?.promise) {
    return cached.promise;
  }

  const pending = readFastClusterState(project)
    .then((value) => {
      setCachedFastClusterState(project.projectSlug, value, null);
      return { value, source: "live" };
    })
    .catch((error) => {
      invalidateFastClusterState(project.projectSlug);
      throw error;
    });

  setCachedFastClusterState(project.projectSlug, null, pending);
  return pending;
}

async function computeFastWorkspaceMemory(project) {
  const deepCacheEntry = getCachedWorkspaceMemory(project.projectSlug, { allowStale: true });
  const [sessions, liveVsixResult, publicationResult, bootstrapProbe, rememberedState] = await Promise.all([
    withTimeout(listProjectSessions(project.projectSlug), "project sessions", 3000).catch(() => ({
      active: [],
      recent: []
    })),
    withTimeout(readCachedFastVsixStatus(project, { preferStale: true }), "fast vsix status", 2500).catch(
      () => ({ value: {}, source: "policy-fallback" })
    ),
    withTimeout(
      readCachedFastPublicationState(project, { preferStale: true }),
      "fast publication state",
      fastPublicationResponseTimeoutMs
    ).catch(() => ({ value: null, source: "session-fallback" })),
    withTimeout(
      readFastWorkspaceBootstrap(project, { timeoutMs: 9000 }),
      "fast workspace bootstrap",
      9500
    ).catch(() => null),
    withTimeout(
      readRememberedWorkspaceMemory(project.projectSlug),
      "remembered workspace memory",
      8000
    ).catch(() => null)
  ]);
  const liveVsix = liveVsixResult?.value || {};
  const bootstrapVsix = bootstrapProbe?.vsix || {};
  const fastPublication = publicationResult?.value || null;
  const deepCached = deepCacheEntry?.value;
  const deepCachedAt = cacheTimestamp(deepCacheEntry);
  const vsixCache = getCachedFastVsixStatus(project.projectSlug, { allowStale: true });
  const publicationCache = getCachedFastPublicationState(project.projectSlug, { allowStale: true });
  const clusterCache = getCachedFastClusterState(project.projectSlug, { allowStale: true });
  const fastCluster = clusterCache?.value || null;
  const rememberedCluster =
    !fastCluster && deepCached?.cluster &&
    (deepCached.cluster.workspacePod ||
      deepCached.cluster.cockpitPod ||
      (Array.isArray(deepCached.cluster.surfaces) && deepCached.cluster.surfaces.length > 0))
      ? {
          workspacePod: deepCached.cluster.workspacePod || null,
          cockpitPod: deepCached.cluster.cockpitPod || null,
          surfaces: Array.isArray(deepCached.cluster.surfaces) ? deepCached.cluster.surfaces : [],
          doctorBundle: Array.isArray(deepCached.cluster.doctorBundle)
            ? deepCached.cluster.doctorBundle
            : clusterDoctorBundle
        }
      : null;
  const effectiveCluster = fastCluster || rememberedCluster;
  const clusterSource = fastCluster
    ? clusterCache?.isStale
      ? "cached"
      : "live"
    : rememberedCluster
      ? "cached"
      : "policy-fallback";
  if (!clusterCache?.promise && (!fastCluster || clusterCache?.isStale)) {
    readCachedFastClusterState(project, { preferStale: true }).catch(() => null);
  }

  const recentSessions = sessions.recent || [];
  const latestSession = recentSessions[0] || null;
  const fastDatasetCatalog =
    Array.isArray(project?.datasetCatalog) && project.datasetCatalog.length
      ? project.datasetCatalog
      : buildDefaultDatasetCatalog(project);
  const preferredBase = project.preferredPrBase || project.branch || "main";
  const bootstrapBranch = cleanValue(bootstrapProbe?.branch);
  const rememberedBranch = cleanValue(rememberedState?.workspace?.liveBranch);
  const fastGit = fastPublication?.git || null;
  const fastPrUrl = cleanValue(fastPublication?.prPreview?.existingPr?.url);
  const baseBranch = cleanValue(project.branch);
  const bootstrapGit = bootstrapBranch ? {
    branch: bootstrapBranch,
    dirtyCount: null,
    publishableDirtyCount: null,
    memoryLocalDirtyCount: null,
    recentCommits: []
  } : null;
  const rememberedGit = rememberedBranch ? {
    branch: rememberedBranch,
    dirtyCount: rememberedState?.publication?.dirtyCount ?? null,
    publishableDirtyCount: rememberedState?.publication?.publishableDirtyCount ?? null,
    memoryLocalDirtyCount: rememberedState?.publication?.memoryLocalDirtyCount ?? null,
    recentCommits: []
  } : null;
  const weakFastGit =
    fastGit &&
    (!cleanValue(fastGit.branch) ||
      (cleanValue(fastGit.branch) === baseBranch &&
        !fastPrUrl &&
        ((bootstrapBranch && bootstrapBranch !== baseBranch) ||
          (rememberedBranch && rememberedBranch !== baseBranch))));
  const git = (weakFastGit ? (bootstrapGit || rememberedGit || null) : null) ||
    fastGit ||
    bootstrapGit ||
    rememberedGit ||
    deepCached?.publication || {
    branch:
      latestSession?.lastPushBranch ||
      rememberedBranch ||
      bootstrapProbe?.packet?.branch ||
      project.branch ||
      "",
    dirtyCount: null,
    publishableDirtyCount: null,
    memoryLocalDirtyCount: null,
    recentCommits: []
  };
  const branchMatchesBase = git.branch && git.branch === preferredBase;
  const fastCheckpoint = fastPublication?.prPreview?.existingPr
    ? {
        prUrl: fastPublication.prPreview.existingPr.url || "",
        prTitle: fastPublication.prPreview.existingPr.title || "",
        prBase: fastPublication.prPreview.existingPr.baseRefName || "",
        prHead: fastPublication.prPreview.existingPr.headRefName || "",
        mergeReadiness:
          fastPublication.prPreview.existingPr.isDraft
            ? "draft"
            : fastPublication.prPreview.existingPr.reviewDecision === "CHANGES_REQUESTED"
              ? "changes-requested"
              : fastPublication.prPreview.existingPr.reviewDecision === "REVIEW_REQUIRED"
                ? "review-required"
                : "merge-ready-ish",
        publicationStage: fastPublication.prPreview.existingPr.isDraft ? "under-review" : "merge-ready"
      }
    : null;
  const cachedCheckpoint = fastCheckpoint || deepCached?.resumePacket?.publicationCheckpoint || null;
  const cachedPrUrl =
    cachedCheckpoint?.prUrl ||
    rememberedState?.publicationCheckpoint?.prUrl ||
    deepCached?.resumePacket?.lastPrUrl ||
    latestSession?.lastPrUrl ||
    "";
  const cachedPrTitle =
    cachedCheckpoint?.prTitle ||
    rememberedState?.publicationCheckpoint?.prTitle ||
    deepCached?.resumePacket?.lastPrTitle ||
    latestSession?.lastPrTitle ||
    "";
  const cachedPrBase =
    cachedCheckpoint?.prBase ||
    rememberedState?.publicationCheckpoint?.prBase ||
    deepCached?.resumePacket?.lastPrBase ||
    latestSession?.lastPrBase ||
    "";
  const cachedPrHead =
    cachedCheckpoint?.prHead ||
    rememberedState?.publicationCheckpoint?.prHead ||
    deepCached?.resumePacket?.lastPrHead ||
    latestSession?.lastPrHead ||
    "";
  const cachedReviewStep =
    cachedCheckpoint?.reviewStep ||
    rememberedState?.publicationCheckpoint?.reviewStep ||
    deepCached?.resumePacket?.lastReviewStep ||
    latestSession?.lastReviewStep ||
    "";
  const cachedReviewUrl =
    cachedCheckpoint?.reviewUrl ||
    rememberedState?.publicationCheckpoint?.reviewUrl ||
    deepCached?.resumePacket?.lastReviewUrl ||
    latestSession?.lastReviewUrl ||
    "";
  const cachedMergeReadiness =
    cachedCheckpoint?.mergeReadiness ||
    rememberedState?.publicationCheckpoint?.mergeReadiness ||
    deepCached?.resumePacket?.lastMergeReadiness ||
    latestSession?.lastMergeReadiness ||
    (cachedPrUrl ? "draft" : "no-pr");
  const cachedChecksPass =
    cachedCheckpoint?.checksPass ||
    deepCached?.resumePacket?.lastChecksPass ||
    latestSession?.lastChecksPass ||
    "";
  const cachedChecksPassAt =
    cachedCheckpoint?.checksPassAt ||
    deepCached?.resumePacket?.lastChecksPassAt ||
    latestSession?.lastChecksPassAt ||
    "";
  const cachedChecksUrl =
    cachedCheckpoint?.checksUrl ||
    deepCached?.resumePacket?.lastChecksUrl ||
    latestSession?.lastChecksUrl ||
    "";
  const cachedCommentsReview =
    cachedCheckpoint?.commentsReview ||
    deepCached?.resumePacket?.lastCommentsReview ||
    latestSession?.lastCommentsReview ||
    "";
  const cachedCommentsReviewAt =
    cachedCheckpoint?.commentsReviewAt ||
    deepCached?.resumePacket?.lastCommentsReviewAt ||
    latestSession?.lastCommentsReviewAt ||
    "";
  const cachedMergeDecision =
    cachedCheckpoint?.mergeDecision ||
    deepCached?.resumePacket?.lastMergeDecision ||
    latestSession?.lastMergeDecision ||
    "";
  const cachedMergeDecisionAt =
    cachedCheckpoint?.mergeDecisionAt ||
    deepCached?.resumePacket?.lastMergeDecisionAt ||
    latestSession?.lastMergeDecisionAt ||
    "";
  const cachedMergeAction =
    cachedCheckpoint?.mergeAction ||
    deepCached?.resumePacket?.lastMergeAction ||
    latestSession?.lastMergeAction ||
    "";
  const cachedMergeActionAt =
    cachedCheckpoint?.mergeActionAt ||
    deepCached?.resumePacket?.lastMergeActionAt ||
    latestSession?.lastMergeActionAt ||
    "";
  const cachedPublicationStage =
    cachedCheckpoint?.publicationStage ||
    rememberedState?.publicationCheckpoint?.publicationStage ||
    deepCached?.resumePacket?.publicationStage ||
    latestSession?.publicationStage ||
    "";
  const idePolicy = inferIdePolicy(project);
  const cachedIde = deepCached?.ide || null;
  const ideSource = liveVsix.pack
    ? liveVsixResult?.source || "live"
    : bootstrapVsix.pack
      ? "live"
    : rememberedState?.ide?.pack
      ? "cached"
    : cachedIde?.pack
      ? "cached"
      : "policy-fallback";
  const ide = {
    ...idePolicy,
    ...(cachedIde || {}),
    ...((liveVsix.pack || bootstrapVsix.pack) ? {
      pack: liveVsix.pack || bootstrapVsix.pack,
      packVersion: liveVsix.packVersion || bootstrapVsix.packVersion || idePolicy.packVersion,
      requiredExtensions: splitCsv(liveVsix.required || bootstrapVsix.required || ""),
      recommendedExtensions: splitCsv(liveVsix.recommended || bootstrapVsix.recommended || ""),
      experimentalExtensions: splitCsv(liveVsix.experimental || bootstrapVsix.experimental || ""),
      aiIdeAgents: mergeAiIdeAgents(
        (Array.isArray(liveVsix.aiIdeAgents) && liveVsix.aiIdeAgents.length > 0)
          ? liveVsix.aiIdeAgents
          : (Array.isArray(bootstrapVsix.aiIdeAgents) && bootstrapVsix.aiIdeAgents.length > 0)
            ? bootstrapVsix.aiIdeAgents
          : (cachedIde?.aiIdeAgents || []),
        idePolicy.aiIdeAgents || []
      ),
      installedExtensions: Array.isArray(liveVsix.installedExtensions)
        ? liveVsix.installedExtensions
        : Array.isArray(bootstrapVsix.installedExtensions)
          ? bootstrapVsix.installedExtensions
          : (cachedIde?.installedExtensions || []),
      missingRequired: Array.isArray(liveVsix.missingRequired)
        ? liveVsix.missingRequired
        : Array.isArray(bootstrapVsix.missingRequired)
          ? bootstrapVsix.missingRequired
          : (cachedIde?.missingRequired || []),
      requiredReady:
        typeof liveVsix.requiredReady === "boolean"
          ? liveVsix.requiredReady
          : typeof bootstrapVsix.requiredReady === "boolean"
            ? bootstrapVsix.requiredReady
            : (cachedIde?.requiredReady ?? false),
      recommendedEnabled:
        typeof liveVsix.recommendedEnabled === "boolean"
          ? liveVsix.recommendedEnabled
          : typeof bootstrapVsix.recommendedEnabled === "boolean"
            ? bootstrapVsix.recommendedEnabled
          : (cachedIde?.recommendedEnabled ?? idePolicy.recommendedEnabled),
      experimentalEnabled:
        typeof liveVsix.experimentalEnabled === "boolean"
          ? liveVsix.experimentalEnabled
          : typeof bootstrapVsix.experimentalEnabled === "boolean"
            ? bootstrapVsix.experimentalEnabled
          : (cachedIde?.experimentalEnabled ?? idePolicy.experimentalEnabled),
      status: liveVsix.status || bootstrapVsix.status || cachedIde?.status || "unknown"
    } : {})
  };
  if (!liveVsix.pack && !bootstrapVsix.pack && rememberedState?.ide?.pack) {
    ide.pack = rememberedState.ide.pack;
    ide.status = rememberedState.ide.status || ide.status || "unknown";
    ide.installedExtensions = Array.isArray(rememberedState.ide.installedExtensions)
      ? rememberedState.ide.installedExtensions
      : (ide.installedExtensions || []);
    ide.missingRequired = Array.isArray(rememberedState.ide.missingRequired)
      ? rememberedState.ide.missingRequired
      : (ide.missingRequired || []);
    ide.requiredReady =
      typeof rememberedState.ide.requiredReady === "boolean"
        ? rememberedState.ide.requiredReady
        : (ide.requiredReady ?? false);
  }
  ide.aiIdeAgents = mergeAiIdeAgents(ide.aiIdeAgents || [], idePolicy.aiIdeAgents || []);
  Object.assign(ide, buildIdeTruth(ideSource));
  ide.truthAt =
    ideSource === "live" || ideSource === "cached"
      ? cacheTimestamp(vsixCache) || deepCachedAt
      : "";

  const nextSafeMove =
    Number(git.publishableDirtyCount ?? 0) > 0
      ? `review dirty habitat state on ${git.branch || "current branch"} before publishing`
      : Number(git.memoryLocalDirtyCount ?? 0) > 0
        ? `memory-local context is present; branch off or publish without staging .beagle/`
        : branchMatchesBase
          ? `branch off safely from ${preferredBase} before opening a draft PR`
          : `resume on ${git.branch || "current branch"} and publish when ready`;
  const publicationHint =
    Number(git.publishableDirtyCount ?? 0) > 0
      ? "working tree still has unpublished changes"
      : Number(git.memoryLocalDirtyCount ?? 0) > 0
        ? "only memory-local habitat artifacts are dirty; publication can stay clean"
        : branchMatchesBase
          ? "publication from the base branch is intentionally blocked"
          : "branch is publication-ready if previews stay clean";
  const publicationCheckpoint = {
    commitSha: latestSession?.lastCommitSha || "",
    commitMessage: latestSession?.lastCommitMessage || "",
    commitAt: latestSession?.lastCommitAt || "",
    pushBranch: latestSession?.lastPushBranch || "",
    pushAt: latestSession?.lastPushAt || "",
    prUrl: latestSession?.lastPrUrl || cachedPrUrl,
    prTitle: latestSession?.lastPrTitle || cachedPrTitle,
    prBase: latestSession?.lastPrBase || cachedPrBase,
    prHead: latestSession?.lastPrHead || cachedPrHead,
    reviewStep: latestSession?.lastReviewStep || cachedReviewStep,
    reviewStepAt: latestSession?.lastReviewStepAt || "",
    reviewUrl: latestSession?.lastReviewUrl || cachedReviewUrl,
    mergeReadiness: latestSession?.lastMergeReadiness || cachedMergeReadiness,
    checksPass: latestSession?.lastChecksPass || cachedChecksPass,
    checksPassAt: latestSession?.lastChecksPassAt || cachedChecksPassAt,
    checksUrl: latestSession?.lastChecksUrl || cachedChecksUrl,
    commentsReview: latestSession?.lastCommentsReview || cachedCommentsReview,
    commentsReviewAt: latestSession?.lastCommentsReviewAt || cachedCommentsReviewAt,
    mergeDecision: latestSession?.lastMergeDecision || cachedMergeDecision,
    mergeDecisionAt: latestSession?.lastMergeDecisionAt || cachedMergeDecisionAt,
    mergeAction: latestSession?.lastMergeAction || cachedMergeAction,
    mergeActionAt: latestSession?.lastMergeActionAt || cachedMergeActionAt,
    publicationStage: latestSession?.publicationStage || cachedPublicationStage
  };
  const publicationTruth =
    publicationCheckpoint.prUrl ||
    publicationCheckpoint.commitSha ||
    publicationCheckpoint.pushBranch ||
    Number(git.publishableDirtyCount ?? 0) > 0 ||
    publicationCheckpoint.publicationStage
      ? {
          source: "cached",
          truthMode: "remembered",
          at: cacheTimestamp(publicationCache) || deepCachedAt
        }
      : { source: "policy-fallback", truthMode: "declared", at: "" };
  const reviewTruth =
    publicationCheckpoint.reviewStep ||
    publicationCheckpoint.reviewUrl ||
    publicationCheckpoint.prUrl ||
    publicationCheckpoint.checksPass ||
    publicationCheckpoint.commentsReview ||
    publicationCheckpoint.mergeDecision ||
    (publicationCheckpoint.mergeReadiness && publicationCheckpoint.mergeReadiness !== "no-pr") ||
    (publicationCheckpoint.publicationStage &&
      ["under-review", "merge-ready", "merged-later"].includes(publicationCheckpoint.publicationStage))
      ? {
          source: "cached",
          truthMode: "remembered",
          at: cacheTimestamp(publicationCache) || deepCachedAt
        }
      : { source: "policy-fallback", truthMode: "declared", at: "" };
  const clusterTruth =
    effectiveCluster &&
    (effectiveCluster.workspacePod || effectiveCluster.cockpitPod || effectiveCluster.surfaces?.length)
      ? {
          source: clusterSource,
          truthMode:
            clusterSource === "live"
              ? "observed"
              : clusterSource === "cached"
                ? "remembered"
                : "declared",
          at:
            clusterSource === "live" || clusterSource === "cached"
              ? cacheTimestamp(clusterCache) || deepCachedAt
              : ""
        }
      : { source: "policy-fallback", truthMode: "declared", at: "" };
  const continuityTimeline = buildContinuityTimeline(latestSession, {
    publicationCheckpoint
  });
  const cachedWorkspace = deepCached?.workspace || {};
  const contextDrift = buildContextDriftSummary({
    contractBranch: cachedWorkspace.branchContract || project.branch,
    contextBranch:
      cachedWorkspace.branchContract ||
      bootstrapProbe?.packet?.branch ||
      rememberedState?.workspace?.contextDrift?.contextBranch ||
      project.branch,
    liveBranch:
      git.branch ||
      bootstrapBranch ||
      rememberedState?.workspace?.contextDrift?.liveBranch ||
      "",
    bootstrapStatus:
      cachedWorkspace.bootstrapStatus ||
      bootstrapProbe?.packet?.status ||
      rememberedState?.workspace?.contextDrift?.bootstrapStatus ||
      "",
    bootstrapReason: cachedWorkspace.bootstrapReason || "",
    contextMode:
      cachedWorkspace.contextMode ||
      bootstrapProbe?.packet?.context_mode ||
      rememberedState?.workspace?.contextDrift?.contextMode ||
      "fast-resume"
  });
  const truthSummary = {
    ide: {
      source: ide.source || "policy-fallback",
      truthMode: ide.truthMode || "declared",
      at: ide.truthAt || ""
    },
    publication: publicationTruth,
    review: reviewTruth,
    cluster: clusterTruth
  };

  const missionControl = buildMissionControlSummary({
    nextSafeMove,
    existingPrUrl: cachedPrUrl,
    publicationStage: latestSession?.publicationStage || cachedPublicationStage,
    lastMergeReadiness: latestSession?.lastMergeReadiness || cachedMergeReadiness,
    truthSummary,
    publicationCheckpoint
  });
  const beagleSubstrate = buildBeagleSubstrateSummary({
    project,
    truthSummary,
    missionControl,
    ide,
    runtimeCapabilities: buildRuntimeCapabilitySummary(project),
    datasetCatalog: fastDatasetCatalog,
    viewerState: buildViewerStateSummary(project, latestSession, fastDatasetCatalog),
    workspace: {
      liveBranch: git.branch || "",
      branchContract: project.branch
    }
  });

  return {
    workspace: {
      workstreamId: project.workstreamId || "",
      workspaceId: project.workspaceId || "",
      sessionId: project.sessionId || "",
      workspaceRoot: project.workspaceRoot,
      repoUrl: project.repoUrl,
      branchContract: project.branch,
      liveBranch: git.branch || bootstrapBranch || "",
      contextMode: "fast-resume",
      startupMode: "",
      hydrationPath: "",
      warmStartUsed: null,
      bootstrapStatus: "",
      bootstrapReason: "",
      subagentRoles: [],
      contextDrift
    },
    publication: {
      branch: git.branch,
      dirtyCount: git.dirtyCount,
      publishableDirtyCount: git.publishableDirtyCount,
      memoryLocalDirtyCount: git.memoryLocalDirtyCount,
      recentCommits: git.recentCommits
    },
    sessions,
    ai: {
      claude: { available: false, recentSessions: [] },
      codex: { available: false, recentPrompts: [], recentThreads: [] }
    },
    viewer: buildViewerStateSummary(project, latestSession, fastDatasetCatalog),
    cluster: fastCluster
      ? {
          ...fastCluster,
          source: clusterTruth.source,
          truthMode: clusterTruth.truthMode
        }
      : rememberedCluster
        ? {
            ...rememberedCluster,
          source: clusterTruth.source,
          truthMode: clusterTruth.truthMode
        }
      : {
          workspacePod: null,
          cockpitPod: null,
          surfaces: [],
          doctorBundle: clusterDoctorBundle,
          source: clusterTruth.source,
          truthMode: clusterTruth.truthMode
        },
    ide,
    resumePacket: {
      preferredBase,
      branchMatchesBase,
      lastObjective: latestSession?.currentAction || "",
      nextSafeMove,
      publicationHint,
      existingPrUrl: cachedPrUrl,
      existingPrTitle: cachedPrTitle,
      existingPrBase: cachedPrBase,
      existingPrHead: cachedPrHead,
      lastHumanAlias: latestSession?.viewer?.displayName || latestSession?.viewer?.alias || "",
      lastAiLane: latestSession?.lastAiLane || "",
      lastAiLaneAt: latestSession?.lastAiLaneAt || "",
      lastCommand: latestSession?.lastCommand || "",
      lastCommandAt: latestSession?.lastCommandAt || "",
      lastUsefulCommand: latestSession?.lastUsefulCommand || "",
      lastUsefulCommandAt: latestSession?.lastUsefulCommandAt || "",
      lastUsefulOutputHint: latestSession?.lastUsefulOutputHint || "",
      lastMutationLabel: latestSession?.lastMutationLabel || "",
      lastMutationAt: latestSession?.lastMutationAt || "",
      lastCommitSha: latestSession?.lastCommitSha || "",
      lastCommitMessage: latestSession?.lastCommitMessage || "",
      lastCommitAt: latestSession?.lastCommitAt || "",
      lastPushBranch: latestSession?.lastPushBranch || "",
      lastPushAt: latestSession?.lastPushAt || "",
      lastPrUrl: latestSession?.lastPrUrl || "",
      lastPrAt: latestSession?.lastPrAt || "",
      lastPrTitle: latestSession?.lastPrTitle || "",
      lastPrBase: latestSession?.lastPrBase || "",
      lastPrHead: latestSession?.lastPrHead || "",
      lastReviewStep: latestSession?.lastReviewStep || cachedReviewStep,
      lastReviewStepAt: latestSession?.lastReviewStepAt || "",
      lastReviewUrl: latestSession?.lastReviewUrl || cachedReviewUrl,
      lastMergeReadiness: latestSession?.lastMergeReadiness || cachedMergeReadiness,
      lastChecksPass: latestSession?.lastChecksPass || cachedChecksPass,
      lastChecksPassAt: latestSession?.lastChecksPassAt || cachedChecksPassAt,
      lastChecksUrl: latestSession?.lastChecksUrl || cachedChecksUrl,
      lastCommentsReview: latestSession?.lastCommentsReview || cachedCommentsReview,
      lastCommentsReviewAt: latestSession?.lastCommentsReviewAt || cachedCommentsReviewAt,
      lastMergeDecision: latestSession?.lastMergeDecision || cachedMergeDecision,
      lastMergeDecisionAt: latestSession?.lastMergeDecisionAt || cachedMergeDecisionAt,
      lastMergeAction: latestSession?.lastMergeAction || cachedMergeAction,
      lastMergeActionAt: latestSession?.lastMergeActionAt || cachedMergeActionAt,
      publicationStage: latestSession?.publicationStage || cachedPublicationStage,
      truthSummary,
      missionControl,
      beagleSubstrate,
      publicationCheckpoint,
      continuityTimeline,
      commands: {
        terminal: `ssh ${project.sshHost}\nexport TMUX_SOCKET_DIR=${project.workspaceRoot}/.tmux\nexport TMUX_SOCKET=$TMUX_SOCKET_DIR/${project.tmuxSession}.sock\nmkdir -p "$TMUX_SOCKET_DIR" && chmod 700 "$TMUX_SOCKET_DIR"\ntmux -S "$TMUX_SOCKET" new-session -A -s ${project.tmuxSession}`,
        workspace: `ssh ${project.sshHost}\ncd ${project.workspaceRoot}`,
        inspectDirty: `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\ngit status --short --branch\ngit diff --stat`,
        context: `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\nsed -n '1,160p' .beagle/context/current-context-packet.json\nsed -n '1,160p' .beagle/context/workspace-hydration.json`,
        publish:
          git.publishableDirtyCount > 0
            ? `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\ngit status --short --branch`
            : branchMatchesBase
              ? `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\ngit switch -c feat/next-step ${preferredBase}`
              : `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\ngit push -u origin ${git.branch || preferredBase}`
      }
    }
  };
}

async function primeStartupWarmCaches() {
  if (startupWarmPromise) {
    return startupWarmPromise;
  }
  startupWarmPromise = (async () => {
  startupWarmState = {
    ...startupWarmState,
    status: "warming",
    lastAttemptAt: new Date().toISOString(),
    lastError: ""
  };
  try {
    const catalog = await withTimeout(loadCatalog(), "startup catalog", 4000);
    const priorityProjects = catalog.projects.filter(
      (project) => project.projectSlug === "sounio" || project.mode === "always-on"
    );
    for (const project of priorityProjects) {
      if (project.projectSlug === "sounio") {
        await withTimeout(
          readWorkspaceMemory(project, { preferStale: false }),
          "startup deep memory",
          25000
        ).catch(() => null);
      }
      await withTimeout(readCachedFastVsixStatus(project, { preferStale: true }), "startup fast vsix", 4000).catch(
        () => ({ value: {}, source: "policy-fallback" })
      );
      await withTimeout(
        readCachedFastPublicationState(project, { preferStale: true }),
        "startup fast publication",
        startupFastPublicationTimeoutMs
      ).catch(() => ({ value: null, source: "session-fallback" }));
      await withTimeout(
        readCachedFastClusterState(project, { preferStale: true }),
        "startup fast cluster",
        4000
      ).catch(() => ({ value: null, source: "policy-fallback" }));
      let fastMemory = await withTimeout(
        computeFastWorkspaceMemory(project),
        "startup fast memory",
        startupFastMemoryTimeoutMs
      ).catch(() => null);
      if (project.projectSlug === "sounio" && isWeakFastWorkspaceMemory(project, fastMemory)) {
        for (let attempt = 0; attempt < 2; attempt += 1) {
          invalidateFastWorkspaceMemory(project.projectSlug);
          invalidateFastVsixStatus(project.projectSlug);
          invalidateFastPublicationState(project.projectSlug);
          await withTimeout(
            readCachedFastVsixStatus(project, { preferStale: false }),
            "startup retry fast vsix",
            4000
          ).catch(() => ({ value: {}, source: "policy-fallback" }));
          await withTimeout(
            readCachedFastPublicationState(project, { preferStale: false }),
            "startup retry fast publication",
            startupFastPublicationTimeoutMs
          ).catch(() => ({ value: null, source: "session-fallback" }));
          fastMemory = await withTimeout(
            computeFastWorkspaceMemory(project),
            "startup retry fast memory",
            startupFastMemoryTimeoutMs
          ).catch(() => null);
          if (fastMemory && !isWeakFastWorkspaceMemory(project, fastMemory)) {
            break;
          }
        }
      }
      if (fastMemory) {
        setCachedFastWorkspaceMemory(project.projectSlug, fastMemory, null);
      }
      if (
        project.projectSlug === "sounio" &&
        (!fastMemory || !isStartupAcceptableFastWorkspaceMemory(project, fastMemory))
      ) {
        throw new Error("startup fast truth remained weak for sounio");
      }
    }
    startupWarmState = {
      ...startupWarmState,
      status: "ready",
      lastReadyAt: new Date().toISOString(),
      lastError: ""
    };
  } catch (error) {
    startupWarmState = {
      ...startupWarmState,
      status: "degraded",
      lastError: error?.message || "startup warm failed"
    };
  } finally {
    startupWarmPromise = null;
  }
  })();
  return startupWarmPromise;
}

async function selfHealWeakFastWorkspaceMemory(project) {
  if (startupWarmState.status === "booting" || startupWarmState.status === "warming") {
    await withTimeout(
      readCachedFastVsixStatus(project, { preferStale: false }),
      "self-heal fast vsix",
      4000
    ).catch(() => ({ value: {}, source: "policy-fallback" }));
    await withTimeout(
      readCachedFastPublicationState(project, { preferStale: false }),
      "self-heal fast publication",
      startupFastPublicationTimeoutMs
    ).catch(() => ({ value: null, source: "session-fallback" }));
    return withTimeout(
      computeFastWorkspaceMemory(project),
      "self-heal fast memory",
      5000
    ).catch(() => null);
  }
  invalidateFastWorkspaceMemory(project.projectSlug);
  invalidateFastVsixStatus(project.projectSlug);
  invalidateFastPublicationState(project.projectSlug);
  invalidateWorkspaceMemory(project.projectSlug);
  await withTimeout(
    readWorkspaceMemory(project, { preferStale: false }),
    "self-heal deep memory",
    12000
  ).catch(() => null);
  await withTimeout(
    readCachedFastVsixStatus(project, { preferStale: false }),
    "self-heal fast vsix",
    4000
  ).catch(() => ({ value: {}, source: "policy-fallback" }));
  await withTimeout(
    readCachedFastPublicationState(project, { preferStale: false }),
    "self-heal fast publication",
    startupFastPublicationTimeoutMs
  ).catch(() => ({ value: null, source: "session-fallback" }));
  return withTimeout(
    computeFastWorkspaceMemory(project),
    "self-heal fast memory",
    7000
  ).catch(() => null);
}

async function readFastWorkspaceMemory(project, { preferStale = false } = {}) {
  const allowWeakDuringWarm =
    project?.projectSlug === "sounio" &&
    (startupWarmState.status === "booting" || startupWarmState.status === "warming");
  const cached = getCachedFastWorkspaceMemory(project.projectSlug, { allowStale: preferStale });
  if (cached?.value) {
    if (preferStale && cached.isStale && !cached.promise) {
      const refresh = computeFastWorkspaceMemory(project)
        .then(async (value) => {
          let effective = value;
          if (isWeakFastWorkspaceMemory(project, value) && !allowWeakDuringWarm) {
            effective = (await selfHealWeakFastWorkspaceMemory(project)) || value;
          }
          if (!isWeakFastWorkspaceMemory(project, effective) || allowWeakDuringWarm) {
            setCachedFastWorkspaceMemory(project.projectSlug, effective, null);
            if (!isWeakFastWorkspaceMemory(project, effective)) {
              queueRememberedWorkspaceMemory(project.projectSlug, effective);
            }
          } else {
            invalidateFastWorkspaceMemory(project.projectSlug);
          }
          return effective;
        })
        .catch(() => {
          const current = getCachedFastWorkspaceMemory(project.projectSlug, { allowStale: true });
          if (current?.value) {
            setCachedFastWorkspaceMemory(project.projectSlug, current.value, null);
            return current.value;
          }
          invalidateFastWorkspaceMemory(project.projectSlug);
          return null;
        });
      setCachedFastWorkspaceMemory(project.projectSlug, cached.value, refresh);
    }
    return cached.value;
  }
  if (cached?.promise) {
    return cached.promise;
  }

  const pending = computeFastWorkspaceMemory(project)
    .then(async (value) => {
      let effective = value;
      if (isWeakFastWorkspaceMemory(project, value) && !allowWeakDuringWarm) {
        effective = (await selfHealWeakFastWorkspaceMemory(project)) || value;
      }
      if (!isWeakFastWorkspaceMemory(project, effective) || allowWeakDuringWarm) {
        setCachedFastWorkspaceMemory(project.projectSlug, effective, null);
        if (!isWeakFastWorkspaceMemory(project, effective)) {
          queueRememberedWorkspaceMemory(project.projectSlug, effective);
        }
      } else {
        invalidateFastWorkspaceMemory(project.projectSlug);
      }
      return effective;
    })
    .catch((error) => {
      invalidateFastWorkspaceMemory(project.projectSlug);
      throw error;
    });

  setCachedFastWorkspaceMemory(project.projectSlug, null, pending);
  return pending;
}

async function buildFastMemoryResponse(project) {
  const startedAt = Date.now();
  const before = getCachedFastWorkspaceMemory(project.projectSlug, { allowStale: true });
  try {
    const memory = await withTimeout(
      readFastWorkspaceMemory(project, { preferStale: true }),
      "fast workspace memory",
      fastMemoryResponseTimeoutMs
    );
    const enrichedMemory = await attachOperationalTruth(project, memory);
    const after = getCachedFastWorkspaceMemory(project.projectSlug, { allowStale: true });
    const cache = describeCacheState(after || before, fastMemoryCacheTtlMs);
    return {
      depth: "fast",
      memory: enrichedMemory,
      meta: {
        ...cache,
        elapsedMs: Date.now() - startedAt,
        servedAt: new Date().toISOString()
      }
    };
  } catch (error) {
    const staleFast = before?.value;
    if (staleFast) {
      const cache = describeCacheState(before, fastMemoryCacheTtlMs);
      const enrichedMemory = await attachOperationalTruth(project, staleFast);
      return {
        depth: "fast-stale",
        memory: enrichedMemory,
        meta: {
          ...cache,
          fallback: "stale-fast-cache",
          elapsedMs: Date.now() - startedAt,
          servedAt: new Date().toISOString(),
          warning: error.message
        }
      };
    }

    const deepCached = getCachedWorkspaceMemory(project.projectSlug, { allowStale: true })?.value;
    if (deepCached) {
      const enrichedMemory = await attachOperationalTruth(project, deepCached);
      return {
        depth: "fast-deep-fallback",
        memory: enrichedMemory,
        meta: {
          cacheState: "fallback",
          stale: true,
          ageMs: null,
          fallback: "deep-memory",
          elapsedMs: Date.now() - startedAt,
          servedAt: new Date().toISOString(),
          warning: error.message
        }
      };
    }

    throw error;
  }
}

function queueRememberedWorkspaceMemory(projectSlug, memory) {
  if (!memory) {
    return;
  }
  Promise.resolve()
    .then(() => writeRememberedWorkspaceMemory(projectSlug, memory))
    .catch(() => null);
}

async function buildDeepMemoryResponse(project) {
  const startedAt = Date.now();
  const before = getCachedWorkspaceMemory(project.projectSlug, { allowStale: true });
  try {
    const memory = await withTimeout(
      readWorkspaceMemory(project, { preferStale: true }),
      "deep workspace memory",
      45000
    );
    const enrichedMemory = await attachOperationalTruth(project, memory);
    const after = getCachedWorkspaceMemory(project.projectSlug, { allowStale: true });
    const cache = describeCacheState(after || before, memoryCacheTtlMs);
    return {
      depth: "deep",
      memory: enrichedMemory,
      meta: {
        ...cache,
        elapsedMs: Date.now() - startedAt,
        servedAt: new Date().toISOString()
      }
    };
  } catch (error) {
    const stale = before?.value;
    if (stale) {
      const cache = describeCacheState(before, memoryCacheTtlMs);
      const enrichedMemory = await attachOperationalTruth(project, stale);
      return {
        depth: "deep-stale",
        memory: enrichedMemory,
        meta: {
          ...cache,
          fallback: "stale-cache",
          elapsedMs: Date.now() - startedAt,
          servedAt: new Date().toISOString(),
          warning: error.message
        }
      };
    }

    const fast = await readFastWorkspaceMemory(project, { preferStale: true });
    const enrichedMemory = await attachOperationalTruth(project, fast);
    return {
      depth: "deep-fast-fallback",
      memory: enrichedMemory,
      meta: {
        cacheState: "fallback",
        stale: true,
        ageMs: null,
        fallback: "fast-memory",
        elapsedMs: Date.now() - startedAt,
        servedAt: new Date().toISOString(),
        warning: error.message
      }
    };
  }
}

async function readViewerState(project) {
  const sessions = await listProjectSessions(project.projectSlug);
  const latestSession = sessions.recent?.[0] || null;
  const datasetCatalog = await resolveDatasetCatalog(project);
  const viewerState = buildViewerStateSummary(project, latestSession, datasetCatalog);
  const runtimeCapabilities = buildRuntimeCapabilitySummary(project);
  const beagleSubstrate = buildBeagleSubstrateSummary({
    project,
    truthSummary: {
      ide: { source: "policy-fallback", truthMode: "declared" },
      publication: { source: "policy-fallback", truthMode: "declared" },
      review: { source: "policy-fallback", truthMode: "declared" },
      cluster: { source: "policy-fallback", truthMode: "declared" }
    },
    missionControl: buildMissionControlSummary({}),
    ide: inferIdePolicy(project),
    runtimeCapabilities,
    datasetCatalog,
    viewerState,
    workspace: null
  });
  return {
    projectSlug: project.projectSlug,
    playgroundClass: project.playgroundClass || "mission-control",
    runtimeCapabilities,
    viewerDefaults: project.viewerDefaults || buildDefaultViewerDefaults(project),
    datasetCatalog,
    viewerState,
    beagleSubstrate
  };
}

async function warmMemoryCaches() {
  const catalog = await loadCatalog();
  const projects = Array.isArray(catalog.projects) ? catalog.projects : [];
  await Promise.allSettled(
    projects.map(async (project) => {
      if (project.projectSlug !== "sounio") {
        return;
      }
      try {
        await readWorkspaceMemory(project, { preferStale: true });
      } catch {
        // best-effort warming only
      }
      try {
        await readCachedFastVsixStatus(project, { preferStale: true });
      } catch {
        // best-effort warming only
      }
      try {
        await readCachedFastPublicationState(project, { preferStale: true });
      } catch {
        // best-effort warming only
      }
      try {
        await readCachedFastClusterState(project, { preferStale: true });
      } catch {
        // best-effort warming only
      }
      try {
        await readFastWorkspaceMemory(project, { preferStale: true });
      } catch {
        // best-effort warming only
      }
    })
  );
}

async function computeWorkspaceMemory(project) {
  const script =
    'cd "$WORKSPACE_ROOT" && ' +
    'echo "__ENV__" && (sed -n "1,160p" .beagle/context/beagle-context.env 2>/dev/null || true) && ' +
    'echo "__BOOTSTRAP__" && (sed -n "1,220p" .beagle/context/bootstrap.json 2>/dev/null || true) && ' +
    'echo "__PACKET__" && (sed -n "1,220p" .beagle/context/current-context-packet.json 2>/dev/null || true) && ' +
    'echo "__HYDRATION__" && (sed -n "1,220p" .beagle/context/workspace-hydration.json 2>/dev/null || true) && ' +
    'echo "__SUBAGENTS__" && (sed -n "1,260p" .beagle/context/workspace-subagents.json 2>/dev/null || true) && ' +
    'echo "__VSIX__" && (sed -n "1,220p" .beagle/context/vsix-pack-status.json 2>/dev/null || true)';

  const [workspaceShell, git, sessions, ai] = await Promise.all([
    runWorkspaceShell(project, { WORKSPACE_ROOT: project.workspaceRoot }, script, { timeoutMs: 25000 }),
    readGitStatus(project),
    listProjectSessions(project.projectSlug),
    readAiMemory(project)
  ]);

  const env = parseEnvBlock(parseSection(workspaceShell.stdout, "ENV", "BOOTSTRAP"));
  const bootstrap = safeJsonParse(parseSection(workspaceShell.stdout, "BOOTSTRAP", "PACKET"), {});
  const packet = safeJsonParse(parseSection(workspaceShell.stdout, "PACKET", "HYDRATION"), {});
  const hydration = safeJsonParse(parseSection(workspaceShell.stdout, "HYDRATION", "SUBAGENTS"), {});
  const subagents = safeJsonParse(parseSection(workspaceShell.stdout, "SUBAGENTS", "VSIX"), {});
  const vsix = safeJsonParse(parseSection(workspaceShell.stdout, "VSIX"), {});
  const recentSessions = sessions.recent || [];
  const latestSession = recentSessions[0] || null;
  const resolvedDatasetCatalog = await resolveDatasetCatalog(project);
  const preferredBase = project.preferredPrBase || project.branch || "main";
  const branchMatchesBase = git.branch && git.branch === preferredBase;
  const prPreview = await readPrPreview(project, preferredBase);
  const mergeReadiness = computeMergeReadiness(prPreview, git);
  const publicationStage = derivePublicationStage(prPreview, git, mergeReadiness, latestSession);
  const lastObjective =
    ai?.claude?.latestSnippet ||
    ai?.codex?.latestSnippet ||
    latestSession?.currentAction ||
    "";
  const nextSafeMove =
    git.publishableDirtyCount > 0
      ? `review dirty habitat state on ${git.branch || "current branch"} before publishing`
      : git.memoryLocalDirtyCount > 0
        ? `memory-local context is present; branch off or publish without staging .beagle/`
      : branchMatchesBase
        ? `branch off safely from ${preferredBase} before opening a draft PR`
        : `resume on ${git.branch || "current branch"} and publish when ready`;
  const publicationHint =
    git.publishableDirtyCount > 0
      ? "working tree still has unpublished changes"
      : git.memoryLocalDirtyCount > 0
        ? "only memory-local habitat artifacts are dirty; publication can stay clean"
      : branchMatchesBase
        ? "publication from the base branch is intentionally blocked"
        : "branch is publication-ready if previews stay clean";
  const publicationCheckpoint = {
    commitSha: latestSession?.lastCommitSha || "",
    commitMessage: latestSession?.lastCommitMessage || "",
    commitAt: latestSession?.lastCommitAt || "",
    pushBranch: latestSession?.lastPushBranch || "",
    pushAt: latestSession?.lastPushAt || "",
    prUrl: latestSession?.lastPrUrl || prPreview?.existingPr?.url || "",
    prTitle: latestSession?.lastPrTitle || prPreview?.existingPr?.title || "",
    prBase: latestSession?.lastPrBase || prPreview?.existingPr?.baseRefName || "",
    prHead: latestSession?.lastPrHead || prPreview?.existingPr?.headRefName || "",
    reviewStep: latestSession?.lastReviewStep || "",
    reviewStepAt: latestSession?.lastReviewStepAt || "",
    reviewUrl: latestSession?.lastReviewUrl || "",
    mergeReadiness: latestSession?.lastMergeReadiness || mergeReadiness,
    checksPass: latestSession?.lastChecksPass || "",
    checksPassAt: latestSession?.lastChecksPassAt || "",
    checksUrl: latestSession?.lastChecksUrl || "",
    commentsReview: latestSession?.lastCommentsReview || "",
    commentsReviewAt: latestSession?.lastCommentsReviewAt || "",
    mergeDecision: latestSession?.lastMergeDecision || "",
    mergeDecisionAt: latestSession?.lastMergeDecisionAt || "",
    mergeAction: latestSession?.lastMergeAction || "",
    mergeActionAt: latestSession?.lastMergeActionAt || "",
    publicationStage
  };
  const continuityTimeline = buildContinuityTimeline(latestSession, {
    publicationCheckpoint
  });
  const contextDrift = buildContextDriftSummary({
    contractBranch: env.BEAGLE_WORKSPACE_BRANCH || packet.branch || project.branch,
    contextBranch: packet.branch || env.BEAGLE_WORKSPACE_BRANCH || project.branch,
    liveBranch: git.branch || "",
    bootstrapStatus: bootstrap.status || "",
    bootstrapReason: bootstrap.reason || "",
    contextMode: env.BEAGLE_WORKSPACE_CONTEXT_MODE || packet.context_mode || bootstrap.bootstrap_mode || ""
  });
  const ideSource = vsix.pack ? "live" : env.BEAGLE_VSIX_PACK ? "policy-fallback" : "policy-fallback";
  const truthSummary = {
    ide: {
      source: ideSource || "policy-fallback",
      truthMode: ideSource === "live" ? "observed" : "declared"
    },
    publication:
      publicationCheckpoint.prUrl || publicationCheckpoint.commitSha || publicationCheckpoint.pushBranch
        ? { source: "live", truthMode: "observed" }
        : { source: "policy-fallback", truthMode: "declared" },
    review:
      publicationCheckpoint.reviewStep ||
      publicationCheckpoint.reviewUrl ||
      publicationCheckpoint.prUrl ||
      publicationCheckpoint.checksPass ||
      publicationCheckpoint.commentsReview ||
      publicationCheckpoint.mergeDecision ||
      (publicationCheckpoint.mergeReadiness && publicationCheckpoint.mergeReadiness !== "no-pr") ||
      (publicationCheckpoint.publicationStage &&
        ["under-review", "merge-ready", "merged-later"].includes(publicationCheckpoint.publicationStage))
        ? { source: "live", truthMode: "observed" }
        : { source: "policy-fallback", truthMode: "declared" },
    cluster: { source: "live", truthMode: "observed" }
  };
  const missionControl = buildMissionControlSummary({
    nextSafeMove,
    existingPrUrl: prPreview?.existingPr?.url || latestSession?.lastPrUrl || "",
    publicationStage,
    lastMergeReadiness: latestSession?.lastMergeReadiness || mergeReadiness,
    truthSummary,
    publicationCheckpoint
  });
  const viewerState = buildViewerStateSummary(project, latestSession, resolvedDatasetCatalog);
  const beagleSubstrate = buildBeagleSubstrateSummary({
    project,
    truthSummary,
    missionControl,
    ide: {
      substrate: "openvscode-server",
      pack: vsix.pack || env.BEAGLE_VSIX_PACK || "",
      aiIdeAgents:
        (Array.isArray(vsix.aiIdeAgents) && vsix.aiIdeAgents.length > 0)
          ? vsix.aiIdeAgents
          : safeJsonParse(env.BEAGLE_AI_IDE_AGENTS || "[]", []),
      source: ideSource || "policy-fallback",
      truthMode: ideSource === "live" ? "observed" : "declared"
    },
    runtimeCapabilities: buildRuntimeCapabilitySummary(project),
    datasetCatalog: resolvedDatasetCatalog,
    viewerState,
    workspace: {
      liveBranch: git.branch || "",
      branchContract: env.BEAGLE_WORKSPACE_BRANCH || packet.branch || project.branch
    }
  });
  const resumeCommands = {
    terminal: `ssh ${project.sshHost}\nexport TMUX_SOCKET_DIR=${project.workspaceRoot}/.tmux\nexport TMUX_SOCKET=$TMUX_SOCKET_DIR/${project.tmuxSession}.sock\nmkdir -p "$TMUX_SOCKET_DIR" && chmod 700 "$TMUX_SOCKET_DIR"\ntmux -S "$TMUX_SOCKET" new-session -A -s ${project.tmuxSession}`,
    workspace: `ssh ${project.sshHost}\ncd ${project.workspaceRoot}`,
    inspectDirty: `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\ngit status --short --branch\ngit diff --stat`,
    context: `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\nsed -n '1,160p' .beagle/context/current-context-packet.json\nsed -n '1,160p' .beagle/context/workspace-hydration.json`,
    publish:
      git.dirtyCount > 0
        ? `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\ngit status --short --branch`
        : branchMatchesBase
          ? `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\ngit switch -c feat/next-step ${preferredBase}`
          : `ssh ${project.sshHost}\ncd ${project.workspaceRoot}\ngit push -u origin ${git.branch || preferredBase}`
  };

  return {
    workspace: {
      workstreamId: env.BEAGLE_WORKSTREAM_ID || packet.workstream_id || project.workstreamId || "",
      workspaceId: env.BEAGLE_WORKSPACE_ID || packet.workspace_id || "",
      sessionId: env.BEAGLE_SESSION_ID || packet.session_id || "",
      workspaceRoot: env.BEAGLE_WORKSPACE_ROOT || packet.workspace_root || project.workspaceRoot,
      repoUrl: env.BEAGLE_WORKSPACE_REPO_URL || packet.repo_url || project.repoUrl,
      branchContract: env.BEAGLE_WORKSPACE_BRANCH || packet.branch || project.branch,
      liveBranch: git.branch || "",
      contextMode: env.BEAGLE_WORKSPACE_CONTEXT_MODE || packet.context_mode || bootstrap.bootstrap_mode || "",
      startupMode: hydration.startup_mode || "",
      hydrationPath: hydration.hydrated_startup_path || "",
      warmStartUsed: hydration.warm_start_used ?? null,
      bootstrapStatus: bootstrap.status || "",
      bootstrapReason: bootstrap.reason || "",
      subagentRoles: Array.isArray(subagents.roles)
        ? subagents.roles.map((role) => ({
            subagentId: role.subagent_id,
            label: role.label,
            role: role.role,
            defaultTools: role.default_tools || []
          }))
        : [],
      contextDrift
    },
    publication: {
      branch: git.branch,
      dirtyCount: git.dirtyCount,
      publishableDirtyCount: git.publishableDirtyCount,
      memoryLocalDirtyCount: git.memoryLocalDirtyCount,
      recentCommits: git.recentCommits
    },
    sessions,
    ai,
    viewer: viewerState,
    ide: {
      substrate: "openvscode-server",
      pack: vsix.pack || env.BEAGLE_VSIX_PACK || "",
      packVersion: vsix.packVersion || env.BEAGLE_VSIX_PACK_VERSION || "",
      requiredExtensions: splitCsv(vsix.required || env.BEAGLE_VSIX_REQUIRED_EXTENSIONS || ""),
      recommendedExtensions: splitCsv(vsix.recommended || env.BEAGLE_VSIX_RECOMMENDED_EXTENSIONS || ""),
      experimentalExtensions: splitCsv(vsix.experimental || env.BEAGLE_VSIX_EXPERIMENTAL_EXTENSIONS || ""),
      aiIdeAgents:
        (Array.isArray(vsix.aiIdeAgents) && vsix.aiIdeAgents.length > 0)
          ? vsix.aiIdeAgents
          : safeJsonParse(env.BEAGLE_AI_IDE_AGENTS || "[]", []),
      installedExtensions: Array.isArray(vsix.installedExtensions) ? vsix.installedExtensions : [],
      missingRequired: Array.isArray(vsix.missingRequired) ? vsix.missingRequired : [],
      requiredReady: typeof vsix.requiredReady === "boolean" ? vsix.requiredReady : Boolean(vsix.pack),
      recommendedEnabled: String(vsix.recommendedEnabled || env.BEAGLE_VSIX_ENABLE_RECOMMENDED || "").toLowerCase() === "true",
      experimentalEnabled: String(vsix.experimentalEnabled || env.BEAGLE_VSIX_ENABLE_EXPERIMENTAL || "").toLowerCase() === "true",
      status: vsix.status || (vsix.pack ? "ready" : "unknown"),
      ...buildIdeTruth(ideSource)
    },
    resumePacket: {
      preferredBase,
      branchMatchesBase,
      lastObjective,
      nextSafeMove,
      publicationHint,
      existingPrUrl: prPreview?.existingPr?.url || latestSession?.lastPrUrl || "",
      existingPrTitle: prPreview?.existingPr?.title || "",
      existingPrBase: prPreview?.existingPr?.baseRefName || "",
      existingPrHead: prPreview?.existingPr?.headRefName || "",
      lastHumanAlias: latestSession?.viewer?.displayName || latestSession?.viewer?.alias || "",
      lastAiLane: latestSession?.lastAiLane || "",
      lastAiLaneAt: latestSession?.lastAiLaneAt || "",
      lastCommand: latestSession?.lastCommand || "",
      lastCommandAt: latestSession?.lastCommandAt || "",
      lastUsefulCommand: latestSession?.lastUsefulCommand || "",
      lastUsefulCommandAt: latestSession?.lastUsefulCommandAt || "",
      lastUsefulOutputHint: latestSession?.lastUsefulOutputHint || "",
      lastMutationLabel: latestSession?.lastMutationLabel || "",
      lastMutationAt: latestSession?.lastMutationAt || "",
      lastCommitSha: latestSession?.lastCommitSha || "",
      lastCommitMessage: latestSession?.lastCommitMessage || "",
      lastCommitAt: latestSession?.lastCommitAt || "",
      lastPushBranch: latestSession?.lastPushBranch || "",
      lastPushAt: latestSession?.lastPushAt || "",
      lastPrUrl: latestSession?.lastPrUrl || "",
      lastPrAt: latestSession?.lastPrAt || "",
      lastPrTitle: latestSession?.lastPrTitle || "",
      lastPrBase: latestSession?.lastPrBase || "",
      lastPrHead: latestSession?.lastPrHead || "",
      lastReviewStep: latestSession?.lastReviewStep || "",
      lastReviewStepAt: latestSession?.lastReviewStepAt || "",
      lastReviewUrl: latestSession?.lastReviewUrl || "",
      lastMergeReadiness: latestSession?.lastMergeReadiness || mergeReadiness,
      lastChecksPass: latestSession?.lastChecksPass || "",
      lastChecksPassAt: latestSession?.lastChecksPassAt || "",
      lastChecksUrl: latestSession?.lastChecksUrl || "",
      lastCommentsReview: latestSession?.lastCommentsReview || "",
      lastCommentsReviewAt: latestSession?.lastCommentsReviewAt || "",
      lastMergeDecision: latestSession?.lastMergeDecision || "",
      lastMergeDecisionAt: latestSession?.lastMergeDecisionAt || "",
      lastMergeAction: latestSession?.lastMergeAction || "",
      lastMergeActionAt: latestSession?.lastMergeActionAt || "",
      publicationStage,
      truthSummary,
      missionControl,
      beagleSubstrate,
      publicationCheckpoint,
      continuityTimeline,
      commands: resumeCommands
    }
  };
}

async function readWorkspaceMemory(project, { preferStale = false } = {}) {
  const cached = getCachedWorkspaceMemory(project.projectSlug, { allowStale: preferStale });
  if (cached?.value) {
    if (preferStale && cached.isStale && !cached.promise) {
      const refresh = computeWorkspaceMemory(project)
        .then((value) => {
          setCachedWorkspaceMemory(project.projectSlug, value, null);
          queueRememberedWorkspaceMemory(project.projectSlug, value);
          return value;
        })
        .catch(() => {
          const current = getCachedWorkspaceMemory(project.projectSlug, { allowStale: true });
          if (current?.value) {
            setCachedWorkspaceMemory(project.projectSlug, current.value, null);
            return current.value;
          }
          invalidateWorkspaceMemory(project.projectSlug);
          return null;
        });
      setCachedWorkspaceMemory(project.projectSlug, cached.value, refresh);
    }
    return cached.value;
  }
  if (cached?.promise) {
    return cached.promise;
  }

  const pending = computeWorkspaceMemory(project)
    .then((value) => {
      setCachedWorkspaceMemory(project.projectSlug, value, null);
      queueRememberedWorkspaceMemory(project.projectSlug, value);
      return value;
    })
    .catch((error) => {
      invalidateWorkspaceMemory(project.projectSlug);
      throw error;
    });

  setCachedWorkspaceMemory(project.projectSlug, null, pending);
  return pending;
}

function summarizePod(pod) {
  if (!pod) {
    return null;
  }
  const statuses = pod.status?.containerStatuses || [];
  return {
    name: pod.metadata?.name || "",
    phase: pod.status?.phase || "Unknown",
    nodeName: pod.spec?.nodeName || "",
    podIP: pod.status?.podIP || "",
    ready: statuses.length > 0 ? statuses.every((status) => status.ready) : false,
    restarts: statuses.reduce((sum, status) => sum + Number(status.restartCount || 0), 0),
    containers: statuses.map((status) => ({
      name: status.name,
      ready: status.ready,
      restartCount: status.restartCount
    }))
  };
}

function summarizeService(service) {
  if (!service) {
    return null;
  }
  const condition = (service.status?.conditions || []).find(
    (item) => item.type === "TailscaleIngressSvcConfigured"
  );
  const ingress = service.status?.loadBalancer?.ingress?.[0] || {};
  return {
    name: service.metadata?.name || "",
    clusterIP: service.spec?.clusterIP || "",
    type: service.spec?.type || "ClusterIP",
    hostname: ingress.hostname || "",
    vip: ingress.ip || "",
    conditionStatus: condition?.status || "",
    conditionReason: condition?.reason || "",
    conditionMessage: condition?.message || "",
    selector: service.spec?.selector || {},
    ports: (service.spec?.ports || []).map((item) => ({
      name: item.name,
      port: item.port,
      targetPort: item.targetPort
    }))
  };
}

function summarizeWorkload(kind, workload) {
  if (!workload) {
    return null;
  }

  const status = workload.status || {};
  const spec = workload.spec || {};
  const metadata = workload.metadata || {};

  return {
    kind,
    name: metadata.name || "",
    namespace: metadata.namespace || "",
    generation: metadata.generation || 0,
    observedGeneration: status.observedGeneration || 0,
    desiredReplicas: spec.replicas ?? 1,
    readyReplicas: status.readyReplicas || 0,
    availableReplicas: status.availableReplicas || 0,
    updatedReplicas: status.updatedReplicas || 0,
    currentRevision: status.currentRevision || "",
    updateRevision: status.updateRevision || ""
  };
}

function inferWorkspaceStatefulSetName(project) {
  return (
    cleanValue(project.workspaceWorkloadName) ||
    cleanValue(project.workspaceId) ||
    cleanValue(project.workspacePod).replace(/-\d+$/, "")
  );
}

async function safeReadService(namespace, name) {
  try {
    const service = await runKubectlJson(["-n", namespace, "get", "service", name]);
    return summarizeService(service);
  } catch (error) {
    return {
      name,
      error: error.message
    };
  }
}

async function safeReadPod(namespace, name) {
  try {
    const pod = await runKubectlJson(["-n", namespace, "get", "pod", name]);
    return summarizePod(pod);
  } catch (error) {
    return {
      name,
      phase: "NotFound",
      nodeName: "",
      podIP: "",
      ready: false,
      restarts: 0,
      containers: [],
      error: error.message
    };
  }
}

async function safeReadWorkload(kind, namespace, name) {
  try {
    const resource =
      kind === "StatefulSet"
        ? await runKubectlJson(["-n", namespace, "get", "statefulset", name])
        : await runKubectlJson(["-n", namespace, "get", "deployment", name]);
    return summarizeWorkload(kind, resource);
  } catch (error) {
    return {
      kind,
      name,
      error: error.message
    };
  }
}

async function readClusterActionPreview(project) {
  const workspaceStatefulSetName = inferWorkspaceStatefulSetName(project);
  const [workspaceWorkload, cockpitWorkload, workspaceHttp, workspaceSsh] = await Promise.all([
    safeReadWorkload("StatefulSet", project.namespace, workspaceStatefulSetName),
    safeReadWorkload("Deployment", project.namespace, "project-cockpit"),
    safeReadService(project.namespace, `${project.workspaceId}-tailnet-http`),
    safeReadService(project.namespace, `${project.workspaceId}-tailnet-ssh`)
  ]);

  return [
    {
      actionId: "restart-workspace",
      title: "Restart workspace habitat",
      target: workspaceWorkload,
      summary:
        "Rollout restart the canonical workspace StatefulSet so the habitat comes back cleanly without changing the tmux contract.",
      command: `kubectl -n ${project.namespace} rollout restart statefulset/${workspaceStatefulSetName}`
    },
    {
      actionId: "restart-cockpit",
      title: "Restart cockpit deployment",
      target: cockpitWorkload,
      summary:
        "Rollout restart the cockpit deployment itself when the web surface gets stale but the project habitat is healthy.",
      command: `kubectl -n ${project.namespace} rollout restart deployment/project-cockpit`
    },
    {
      actionId: "repair-workspace-tailnet-services",
      title: "Repair workspace tailnet services",
      target: {
        kind: "TailnetSurface",
        name: `${project.workspaceId}-tailnet-http + ${project.workspaceId}-tailnet-ssh`,
        readyReplicas:
          workspaceHttp.conditionStatus === "True" && workspaceSsh.conditionStatus === "True" ? 2 : 0,
        desiredReplicas: 2,
        http: workspaceHttp,
        ssh: workspaceSsh
      },
      summary:
        "Recreate only the workspace tailnet HTTP/SSH Services when the workspace VIPs are stale after ingress churn but the habitat itself is healthy.",
      command:
        `kubectl -n ${project.namespace} delete svc ${project.workspaceId}-tailnet-http ${project.workspaceId}-tailnet-ssh --wait=true\n` +
        `kubectl apply -f /home/devsounio/beagle/k8s/tailscale-operator/${project.workspaceId}-tailnet-http.yaml \\\n` +
        `              -f /home/devsounio/beagle/k8s/tailscale-operator/${project.workspaceId}-tailnet-ssh.yaml`
    }
  ];
}

async function readClusterSummary(project) {
  const workspaceHttpServiceName = `${project.workspaceId}-tailnet-http`;
  const workspaceSshServiceName = `${project.workspaceId}-tailnet-ssh`;
  const cockpitServiceName = "project-cockpit-tailnet-http";
  const workspaceStatefulSetName = inferWorkspaceStatefulSetName(project);

  const [
    workspacePod,
    namespacePodsRaw,
    cockpitPodsRaw,
    workspaceHttp,
    workspaceSsh,
    cockpitSurface,
    workspaceWorkload,
    cockpitWorkload
  ] =
    await Promise.all([
      safeReadPod(project.namespace, project.workspacePod),
      runKubectlJson(["-n", project.namespace, "get", "pods"]),
      runKubectlJson([
        "-n",
        project.namespace,
        "get",
        "pods",
        "-l",
        "app.kubernetes.io/name=project-cockpit"
      ]),
      safeReadService(project.namespace, workspaceHttpServiceName),
      safeReadService(project.namespace, workspaceSshServiceName),
      safeReadService(project.namespace, cockpitServiceName),
      safeReadWorkload("StatefulSet", project.namespace, workspaceStatefulSetName),
      safeReadWorkload("Deployment", project.namespace, "project-cockpit")
    ]);

  const namespacePods = (namespacePodsRaw.items || [])
    .map(summarizePod)
    .sort((left, right) => left.name.localeCompare(right.name))
    .slice(0, 12);

  const cockpitPod = summarizePod(cockpitPodsRaw.items?.[0]);

  return {
    workspacePod,
    cockpitPod,
    workspaceWorkload,
    cockpitWorkload,
    namespacePods,
    surfaces: [workspaceHttp, workspaceSsh, cockpitSurface],
    doctorBundle: clusterDoctorBundle
  };
}

const app = express();
app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (origin && allowedCorsOrigins.has(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  }
  if (req.method === "OPTIONS") {
    res.status(204).end();
    return;
  }
  next();
});
// Physiome HealthKit/WeatherKit uploads arrive in multi-MB 5000-sample chunks;
// give that path a large body limit BEFORE the default 100kb json parser (which
// would 413 the upload). express.json() skips bodies already parsed (req._body).
app.use("/api/physiome", express.json({ limit: "25mb" }));
app.use(express.json());

// ─── Security middleware ────────────────────────────────────────────

const COCKPIT_AUTH_TOKEN = cleanValue(process.env.PROJECT_COCKPIT_AUTH_TOKEN);
// Separate service-to-service credential for trusted cluster clients such as
// beagle-mcp-server. Keep it distinct from the mobile/operator-facing token so
// neither caller has to impersonate the other auth surface.
const COCKPIT_INTERNAL_AUTH_TOKEN = cleanValue(process.env.PROJECT_COCKPIT_INTERNAL_AUTH_TOKEN);
const COCKPIT_AUTH_TOKENS = new Set(
  [COCKPIT_AUTH_TOKEN, COCKPIT_INTERNAL_AUTH_TOKEN].filter(Boolean)
);

// Slug validation: reject any :slug param that isn't a safe k8s label value.
const VALID_SLUG = /^[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$/;
app.param("slug", (req, res, next, slug) => {
  if (!VALID_SLUG.test(slug)) {
    return res.status(400).json({ error: "invalid project slug", truthMode: "stale" });
  }
  next();
});

// Auth gate. Two holes were found and closed here on 2026-08-08 (both PROVEN live from another
// pod in the cluster, which is exactly the position the worm had):
//
//   1. FAIL-OPEN on a missing secret. `tokens.size === 0 → next()` meant that an empty or
//      unmounted PROJECT_COCKPIT_AUTH_TOKEN silently opened the ENTIRE control plane. Now it
//      fails CLOSED unless the operator opts in explicitly with PROJECT_COCKPIT_ALLOW_OPEN=1.
//
//   2. FORGEABLE IDENTITY HEADER. `tailscale-user-login` is injected by the tailnet proxy, but
//      nothing stopped any in-cluster caller from simply sending it. Measured: a curl from the
//      workspace pod with a made-up header got 200 on reads AND successfully POSTed a write.
//      The header cannot be authenticated here (the tailnet arrives via a LoadBalancer, not a
//      loopback sidecar), so it is now treated as what it is: a CONVENIENCE FOR READS ONLY.
//      Anything that changes state requires a real token. Read access over the tailnet keeps
//      working exactly as before — the operator is not locked out of his own cockpit.
const ALLOW_OPEN = /^(1|true|yes)$/i.test(process.env.PROJECT_COCKPIT_ALLOW_OPEN || "");

app.use((req, res, next) => {
  const verdict = classifyAuth({
    method: req.method,
    path: req.path,
    bearer: (req.headers.authorization || "").replace(/^Bearer\s+/i, ""),
    headerToken: req.headers["x-cockpit-token"] || "",
    tsUser: req.headers["tailscale-user-login"],
    tokens: COCKPIT_AUTH_TOKENS,
    allowOpen: ALLOW_OPEN,
  });
  if (verdict.allow) return next();
  return res.status(401).json({ error: "unauthorized", detail: verdict.reason, truthMode: "stale" });
});

app.get("/livez", (_req, res) => {
  res.json({ ok: true });
});

app.get("/healthz", (_req, res) => {
  if (startupWarmState.status === "booting" || startupWarmState.status === "warming") {
    res.status(503).json({
      ok: false,
      startupWarm: startupWarmState
    });
    return;
  }
  res.json({
    ok: true,
    startupWarm: startupWarmState
  });
});

app.get("/api/viewer", jsonResponse(async (req) => {
  return {
    viewer: deriveViewer(req)
  };
}));

app.get("/api/catalog", jsonResponse(async () => loadCatalog()));

app.get(
  "/api/catalog/project-posture-policy",
  jsonResponse(async () => {
    const catalog = await loadCatalog();
    return buildProjectPosturePolicyResponse(catalog?.projects || []);
  })
);

app.get(
  "/api/catalog/executive",
  jsonResponse(async () => readCachedCatalogExecutiveState({ preferStale: true }))
);

app.get(
  "/api/research/supercomputing",
  jsonResponse(async () => buildSupercomputingResearchResponse())
);

app.get(
  "/api/public/portal",
  jsonResponse(async () => buildPublicPortalResponse())
);

app.get(
  "/api/public/runtime/vision",
  jsonResponse(async () => buildPublicVisionRuntimeResponse())
);

app.get(
  "/api/public/vision/control-room",
  jsonResponse(async () => buildPublicVisionControlRoomResponse())
);

app.get(
  "/api/public/vision/apple-brief",
  jsonResponse(async () => buildPublicVisionAppleBriefResponse())
);

app.get(
  "/api/public/vision/apple-launchpad",
  jsonResponse(async () => buildPublicVisionAppleLaunchpadResponse())
);

app.get(
  "/api/public/vision/operator-board",
  jsonResponse(async () => buildPublicVisionOperatorBoardResponse())
);

app.get(
  "/api/public/vision/runtime-matrix",
  jsonResponse(async () => buildPublicVisionRuntimeMatrixResponse())
);

app.get(
  "/api/public/vision/route-atlas",
  jsonResponse(async () => buildPublicVisionRouteAtlasResponse())
);

app.get(
  "/api/public/vision/mission-timeline",
  jsonResponse(async () => buildPublicVisionMissionTimelineResponse())
);

app.get(
  "/api/public/vision/sovereign-bridge",
  jsonResponse(async () => buildPublicVisionSovereignBridgeResponse())
);

app.get(
  "/api/public/vision/sovereign-cockpit-preview",
  jsonResponse(async () => buildPublicVisionSovereignCockpitPreviewResponse())
);

app.get(
  "/api/public/vision/packet-graph",
  jsonResponse(async () => buildPublicVisionPacketGraphResponse())
);

app.get(
  "/api/public/vision/handoff",
  jsonResponse(async () => buildPublicVisionHandoffResponse())
);

app.get(
  "/api/public/projects/:slug/showcase",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return await buildPublicProjectShowcaseResponse(project);
  })
);

app.get(
  "/api/public/projects/:slug/sovereign-bridge",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return await buildPublicProjectSovereignBridgeResponse(project);
  })
);

app.get(
  "/api/public/projects/:slug/sovereign-cockpit-preview",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return await buildPublicProjectSovereignCockpitPreviewResponse(project);
  })
);

app.get(
  "/api/public/projects/:slug/packet-graph",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return await buildPublicProjectPacketGraphResponse(project);
  })
);

app.get(
  "/api/projects/:slug",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return { project };
  })
);

app.post(
  "/api/projects/:slug/session/heartbeat",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (!clientSessionId) {
      const error = new Error("clientSessionId is required");
      error.statusCode = 400;
      throw error;
    }

    const viewer = deriveViewer(req, req.body?.alias);
    const session = await touchSession(project.projectSlug, clientSessionId, viewer, {
      route: cleanValue(req.body?.route) || `/projects/${project.projectSlug}`,
      currentAction: cleanValue(req.body?.currentAction) || "viewing-cockpit"
    });

    return {
      viewer,
      session,
      sessions: await listProjectSessions(project.projectSlug)
    };
  })
);

app.post(
  "/api/projects/:slug/session/ai-lane",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (!clientSessionId) {
      const error = new Error("clientSessionId is required");
      error.statusCode = 400;
      throw error;
    }
    const aiLane = cleanValue(req.body?.aiLane);
    if (!aiLane) {
      const error = new Error("aiLane is required");
      error.statusCode = 400;
      throw error;
    }
    const session = await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
      currentAction: `using-${aiLane}-lane`,
      lastAiLane: aiLane,
      lastAiLaneAt: new Date().toISOString()
    });
    return { ok: true, session };
  })
);

app.post(
  "/api/projects/:slug/session/command",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (!clientSessionId) {
      const error = new Error("clientSessionId is required");
      error.statusCode = 400;
      throw error;
    }
    const command = cleanValue(req.body?.command);
    if (!command) {
      const error = new Error("command is required");
      error.statusCode = 400;
      throw error;
    }
    const inferredAiLane = detectAiLaneFromCommand(command);
    const usefulCommand = isLauncherOnlyCommand(command) ? "" : command;
    const git = await readGitStatus(project);
    const usefulOutputHint = summarizeUsefulOutputHint(command, project, git);
    const session = await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
      currentAction: `ran: ${command}`,
      lastCommand: command,
      lastCommandAt: new Date().toISOString(),
      lastAiLane: inferredAiLane,
      lastAiLaneAt: inferredAiLane ? new Date().toISOString() : "",
      lastUsefulCommand: usefulCommand,
      lastUsefulCommandAt: usefulCommand ? new Date().toISOString() : "",
      lastUsefulOutputHint: usefulOutputHint
    });
    return { ok: true, session };
  })
);

app.post(
  "/api/projects/:slug/session/review-step",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (!clientSessionId) {
      const error = new Error("clientSessionId is required");
      error.statusCode = 400;
      throw error;
    }
    const reviewStep = cleanValue(req.body?.reviewStep);
    if (!reviewStep) {
      const error = new Error("reviewStep is required");
      error.statusCode = 400;
      throw error;
    }
    const reviewUrl = cleanValue(req.body?.reviewUrl);
    const mergeReadiness = cleanValue(req.body?.mergeReadiness);
    const checksPass = cleanValue(req.body?.checksPass);
    const commentsReview = cleanValue(req.body?.commentsReview);
    const mergeDecision = cleanValue(req.body?.mergeDecision);
    const mergeAction = cleanValue(req.body?.mergeAction);
    const publicationStage = cleanValue(req.body?.publicationStage);
    const now = new Date().toISOString();
    const checksUrl = reviewStep.includes("checks") || checksPass ? reviewUrl : "";
    const session = await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
      currentAction: `reviewing: ${reviewStep}`,
      lastReviewStep: reviewStep,
      lastReviewStepAt: now,
      lastReviewUrl: reviewUrl,
      lastMergeReadiness: mergeReadiness,
      lastChecksPass: checksPass,
      lastChecksPassAt: checksPass ? now : "",
      lastChecksUrl: checksUrl,
      lastCommentsReview: commentsReview,
      lastCommentsReviewAt: commentsReview ? now : "",
      lastMergeDecision: mergeDecision,
      lastMergeDecisionAt: mergeDecision ? now : "",
      lastMergeAction: mergeAction,
      lastMergeActionAt: mergeAction ? now : "",
      publicationStage
    });
    return { ok: true, session };
  })
);

app.get(
  "/api/projects/:slug/memory/fast",
  jsonResponse(async (req, res) => {
    const project = await getProjectOrThrow(req.params.slug);
    res.setHeader("Cache-Control", "public, max-age=5, stale-while-revalidate=25");
    const payload = await buildFastMemoryResponse(project);
    return {
      project,
      viewer: deriveViewer(req),
      ...payload
    };
  })
);

app.get(
  "/api/projects/:slug/memory/deep",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const payload = await buildDeepMemoryResponse(project);
    return {
      project,
      viewer: deriveViewer(req),
      ...payload
    };
  })
);

app.get(
  "/api/projects/:slug/memory",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const payload = await buildDeepMemoryResponse(project);
    return {
      project,
      viewer: deriveViewer(req),
      ...payload
    };
  })
);

app.get(
  "/api/projects/:slug/beagle/substrate",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildBeagleSubstrateResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/playground/executive",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildPlaygroundExecutiveResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/truth/summary",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildTruthSummaryResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/mission-control",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildMissionControlResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/sovereign-surface",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildSovereignSurfaceResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/cluster/lane-truth",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildClusterLaneTruthResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/research/operations",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildResearchOperationsResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/go-work-now",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildGoWorkNowResponse(project, depth))
    };
  })
);

app.post(
  "/api/projects/:slug/go-work-now/actions/:actionId",
  jsonResponse(async (req) => {
    ensureConfirmed(req, "go work action");
    const project = await getProjectOrThrow(req.params.slug);
    const actionId = cleanValue(req.params.actionId);
    const { label, output } = await runGoWorkNowAction(project, actionId);

    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (clientSessionId) {
      await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
        currentAction: "go-work-now-mutation-from-cockpit",
        lastMutationAt: new Date().toISOString(),
        lastMutationLabel: label
      });
    }

    return {
      ok: true,
      actionId,
      output,
      project,
      viewer: deriveViewer(req),
      cluster: await readClusterSummary(project),
      ...(await buildGoWorkNowResponse(project))
    };
  })
);

app.get(
  "/api/projects/:slug/graph/lineage",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildGraphLineageResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/workflows/scientific",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildScientificWorkflowResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/workflows/scientific/checks",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildScientificWorkflowChecksResponse(project))
    };
  })
);

app.post(
  "/api/projects/:slug/workflows/scientific/checks/run",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      latestRun: await runScientificWorkflowChecks(project)
    };
  })
);

app.get(
  "/api/projects/:slug/execution/packets",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildExecutionPacketsResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/execution/packets/:packet",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildExecutionPacketDetailResponse(project, req.params.packet, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/datasets/catalog",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildDatasetCatalogResponse(project))
    };
  })
);

app.get(
  "/api/projects/:slug/viewer/runtime",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildViewerRuntimeResponse(project))
    };
  })
);

app.get(
  "/api/projects/:slug/viewer/state",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      ...(await readViewerState(project))
    };
  })
);

app.get(
  "/api/projects/:slug/inference/runtime",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildInferenceRuntimeResponse(project))
    };
  })
);

app.get(
  "/api/projects/:slug/inference/models",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildInferenceModelsResponse(project))
    };
  })
);

app.get(
  "/api/projects/:slug/inference/workload",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildInferenceWorkloadResponse(project))
    };
  })
);

app.get(
  "/api/projects/:slug/inference/bootstrap",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildInferenceBootstrapApiResponse(project))
    };
  })
);

app.get(
  "/api/projects/:slug/sounio/contracts",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildSounioContractsResponse(project))
    };
  })
);

app.get(
  "/api/projects/:slug/resume/playground",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildPlaygroundResumeResponse(project, depth))
    };
  })
);

app.get(
  "/api/projects/:slug/runtime/manifest",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const depth = req.query.depth === "deep" ? "deep" : "fast";
    return {
      project,
      viewer: deriveViewer(req),
      ...(await buildRuntimeManifestResponse(project, depth))
    };
  })
);

app.post(
  "/api/projects/:slug/viewer/state",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (!clientSessionId) {
      const error = new Error("clientSessionId is required");
      error.statusCode = 400;
      throw error;
    }
    const now = new Date().toISOString();
    const session = await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
      currentAction: "viewing-viewer",
      lastViewerDatasetId: cleanValue(req.body?.datasetId),
      lastViewerChannel: cleanValue(req.body?.channel),
      lastViewerScale: cleanValue(req.body?.scale),
      lastViewerCamera: cleanValue(req.body?.camera),
      lastViewerRendererStatus: cleanValue(req.body?.rendererStatus),
      lastViewerRendererMessage: cleanValue(req.body?.rendererMessage),
      lastViewerRendererSource: cleanValue(req.body?.rendererSource),
      lastViewerRendererTruthMode: cleanValue(req.body?.rendererTruthMode),
      lastViewerRendererRuntime: cleanValue(req.body?.rendererRuntime),
      lastViewerRendererBackend: cleanValue(req.body?.rendererBackend),
      lastViewerRendererAdapter: cleanValue(req.body?.rendererAdapter),
      lastViewerRendererFormat: cleanValue(req.body?.rendererFormat),
      lastViewerRendererFeatures: cleanDelimitedList(req.body?.rendererFeatures).join(","),
      lastViewerRendererLimits: cleanDelimitedList(req.body?.rendererLimits).join(","),
      lastViewerRendererObservedAt: cleanValue(req.body?.rendererObservedAt) || now,
      lastViewerSceneAt: now
    });
    return {
      ok: true,
      session,
      viewerState: buildViewerStateSummary(
        project,
        session,
        await resolveDatasetCatalog(project)
      )
    };
  })
);

app.get(
  "/api/projects/:slug/cluster/summary",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      cluster: await withTimeout(readClusterSummary(project), "cluster summary", 12000)
    };
  })
);

app.get(
  "/api/projects/:slug/cluster/actions/preview",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return {
      project,
      actions: await withTimeout(readClusterActionPreview(project), "cluster action preview", 12000)
    };
  })
);

app.post(
  "/api/projects/:slug/cluster/actions/:actionId",
  jsonResponse(async (req) => {
    ensureConfirmed(req, "cluster action");
    const project = await getProjectOrThrow(req.params.slug);
    const actionId = cleanValue(req.params.actionId);
    const workspaceStatefulSetName = inferWorkspaceStatefulSetName(project);

    let args;
    let label;
    let output;

    if (actionId === "restart-workspace") {
      label = `restart-workspace:${workspaceStatefulSetName}`;
      const { stdout } = await runKubectlPty([
        "-n",
        project.namespace,
        "rollout",
        "restart",
        `statefulset/${workspaceStatefulSetName}`
      ]);
      output = stdout;
    } else if (actionId === "restart-cockpit") {
      label = "restart-cockpit:project-cockpit";
      const { stdout } = await runKubectlPty([
        "-n",
        project.namespace,
        "rollout",
        "restart",
        "deployment/project-cockpit"
      ]);
      output = stdout;
    } else if (actionId === "repair-workspace-tailnet-services") {
      label = "repair-workspace-tailnet-services";
      const httpService = {
        apiVersion: "v1",
        kind: "Service",
        metadata: {
          name: `${project.workspaceId}-tailnet-http`,
          namespace: project.namespace,
          annotations: {
            "tailscale.com/proxy-group": "sounio-workspace-ingress",
            "tailscale.com/hostname": project.workspaceId,
            "tailscale.com/tags": "tag:k8s,tag:sounio-workspace"
          }
        },
        spec: {
          type: "LoadBalancer",
          loadBalancerClass: "tailscale",
          selector: {
            "app.kubernetes.io/name": "sounio-workspace-habitat"
          },
          ports: [{ name: "http", port: 8080, targetPort: "http", protocol: "TCP" }]
        }
      };
      const sshService = {
        apiVersion: "v1",
        kind: "Service",
        metadata: {
          name: `${project.workspaceId}-tailnet-ssh`,
          namespace: project.namespace,
          annotations: {
            "tailscale.com/proxy-group": "sounio-workspace-ingress",
            "tailscale.com/hostname": `${project.workspaceId}-ssh`,
            "tailscale.com/tags": "tag:k8s,tag:sounio-workspace"
          }
        },
        spec: {
          type: "LoadBalancer",
          loadBalancerClass: "tailscale",
          selector: {
            "app.kubernetes.io/name": "sounio-workspace-habitat"
          },
          ports: [{ name: "ssh", port: 2222, targetPort: "ssh", protocol: "TCP" }]
        }
      };
      await runKubectlJson(["-n", project.namespace, "get", "statefulset", workspaceStatefulSetName]);
      await runKubectlJson(["get", "proxygroup", "sounio-workspace-ingress"]);
      await runKubectlPty([
        "-n",
        project.namespace,
        "delete",
        "service",
        `${project.workspaceId}-tailnet-http`,
        `${project.workspaceId}-tailnet-ssh`,
        "--ignore-not-found=true",
        "--wait=true"
      ], { timeoutMs: 30000 });
      for (const name of [`${project.workspaceId}-tailnet-http`, `${project.workspaceId}-tailnet-ssh`]) {
        for (let attempt = 0; attempt < 20; attempt += 1) {
          try {
            await runKubectlJson(["-n", project.namespace, "get", "service", name]);
            await new Promise((resolve) => setTimeout(resolve, 500));
          } catch (error) {
            if (
              error.code === 1 &&
              String(error.stdout || error.message || "").includes(`services \"${name}\" not found`)
            ) {
              break;
            }
            throw error;
          }
        }
      }
      const manifestJson = shellQuote(JSON.stringify({ apiVersion: "v1", kind: "List", items: [httpService, sshService] }));
      const applyResult = await runPtyCommand(
        "/bin/sh",
        ["-lc", `printf '%s\n' ${manifestJson} | ${[kubectlBin, ...buildKubectlCliArgs(["apply", "-f", "-"])].map(shellQuote).join(" ")}`],
        { timeoutMs: 30000 }
      );
      output = JSON.stringify(
        {
          recreated: [`${project.workspaceId}-tailnet-http`, `${project.workspaceId}-tailnet-ssh`],
          applyOutput: sanitizePtyOutput(applyResult.stdout)
        },
        null,
        2
      );
    } else {
      const error = new Error(`unknown cluster action: ${actionId}`);
      error.statusCode = 404;
      throw error;
    }

    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (clientSessionId) {
      await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
        currentAction: "cluster-mutation-from-cockpit",
        lastMutationAt: new Date().toISOString(),
        lastMutationLabel: label
      });
    }

    return {
      ok: true,
      actionId,
      output,
      actions: await readClusterActionPreview(project),
      cluster: await readClusterSummary(project)
    };
  })
);

app.get(
  "/api/projects/:slug/git/status",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return { project, git: await withTimeout(readGitStatus(project), "git status", 20000) };
  })
);

app.get(
  "/api/projects/:slug/toolchain",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return { project, tools: await withTimeout(readToolchainStatus(project), "toolchain status", 20000) };
  })
);

app.get(
  "/api/projects/:slug/git/diff",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    return { project, diff: await withTimeout(readDiffPreview(project), "git diff preview", 20000) };
  })
);

app.get(
  "/api/projects/:slug/git/pr/preview",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const base = String(req.query.base || project.preferredPrBase || "main").trim();
    return { project, preview: await withTimeout(readPrPreview(project, base), "git PR preview", 20000) };
  })
);

app.get(
  "/api/projects/:slug/git/guardrails",
  jsonResponse(async (req) => {
    const project = await getProjectOrThrow(req.params.slug);
    const base = String(req.query.base || project.preferredPrBase || "main").trim();
    return {
      project,
      guardrails: await withTimeout(readGitGuardrails(project, base), "git guardrails", 25000)
    };
  })
);

app.post(
  "/api/projects/:slug/git/topic-branch",
  jsonResponse(async (req) => {
    ensureConfirmed(req, "start topic branch");
    const project = await getProjectOrThrow(req.params.slug);
    const base = String(req.body?.base || project.preferredPrBase || "main").trim();
    const branch = normalizeBranchName(req.body?.branch);

    if (!branch) {
      const error = new Error("topic branch name is required");
      error.statusCode = 400;
      throw error;
    }

    if (!/^[A-Za-z0-9._/-]+$/.test(branch)) {
      const error = new Error("topic branch name may only use letters, numbers, ., _, /, and -");
      error.statusCode = 400;
      throw error;
    }

    const guardrails = await readGitGuardrails(project, base);
    if (guardrails.publishableDirtyCount > 0) {
      const error = new Error(
        "cannot start a topic branch while the habitat working tree is dirty; review or commit the pending changes first"
      );
      error.statusCode = 409;
      throw error;
    }

    const { stdout } = await withTimeout(
      runWorkspaceShell(
        project,
        {
          WORKSPACE_ROOT: project.workspaceRoot,
          PR_BASE: base,
          TOPIC_BRANCH: branch
        },
        'cd "$WORKSPACE_ROOT" && git fetch origin "$PR_BASE" >/dev/null 2>&1 || true && if git show-ref --verify --quiet "refs/heads/$TOPIC_BRANCH"; then git switch "$TOPIC_BRANCH"; else git switch -c "$TOPIC_BRANCH" "$PR_BASE"; fi'
      ),
      "git topic branch mutation",
      30000
    );

    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (clientSessionId) {
      await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
        currentAction: "started-topic-branch-from-cockpit",
        lastMutationAt: new Date().toISOString(),
        lastMutationLabel: `topic-branch: ${branch} <- ${base}`,
        publicationStage: "working"
      });
    }

    return {
      ok: true,
      branch,
      base,
      output: stdout,
      git: await readGitStatus(project),
      diff: await readDiffPreview(project),
      preview: await readPrPreview(project, base),
      guardrails: await readGitGuardrails(project, base)
    };
  })
);

app.post(
  "/api/projects/:slug/git/commit",
  jsonResponse(async (req) => {
    ensureConfirmed(req, "commit");
    const project = await getProjectOrThrow(req.params.slug);
    const message = String(req.body?.message || "").trim();
    if (!message) {
      const error = new Error("commit message is required");
      error.statusCode = 400;
      throw error;
    }
    const guardrails = await readGitGuardrails(project, project.preferredPrBase || "main");
    if (!guardrails.canCommit) {
      const error = new Error("git guardrails block commit because there is nothing new to commit");
      error.statusCode = 409;
      throw error;
    }

    const { stdout } = await withTimeout(
      runWorkspaceShell(
        project,
        {
          WORKSPACE_ROOT: project.workspaceRoot,
          COMMIT_MESSAGE: message
        },
        'cd "$WORKSPACE_ROOT" && git add -A && (git reset -q HEAD -- .beagle >/dev/null 2>&1 || true) && git commit -m "$COMMIT_MESSAGE"'
      ),
      "git commit mutation",
      30000
    );
    const commitSha = extractCommitSha(stdout);

    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (clientSessionId) {
      await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
        currentAction: "committed-from-cockpit",
        lastMutationAt: new Date().toISOString(),
        lastMutationLabel: `commit: ${message}`,
        lastCommitSha: commitSha,
        lastCommitMessage: message,
        lastCommitAt: new Date().toISOString(),
        publicationStage: "working"
      });
    }

    return {
      ok: true,
      output: stdout,
      git: await readGitStatus(project),
      diff: await readDiffPreview(project),
      guardrails: await readGitGuardrails(project, project.preferredPrBase || "main")
    };
  })
);

app.post(
  "/api/projects/:slug/git/push",
  jsonResponse(async (req) => {
    ensureConfirmed(req, "push");
    const project = await getProjectOrThrow(req.params.slug);
    const guardrails = await readGitGuardrails(project, project.preferredPrBase || "main");
    const branch = guardrails.branch;
    if (!branch) {
      const error = new Error("could not determine current branch");
      error.statusCode = 400;
      throw error;
    }
    if (!guardrails.canPush) {
      const error = new Error("git guardrails block push; inspect cautions before retrying");
      error.statusCode = 409;
      throw error;
    }

    const { stdout } = await withTimeout(
      runWorkspaceShell(
        project,
        {
          WORKSPACE_ROOT: project.workspaceRoot,
          CURRENT_BRANCH: branch
        },
        'cd "$WORKSPACE_ROOT" && git push -u origin "$CURRENT_BRANCH"'
      ),
      "git push mutation",
      30000
    );

    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (clientSessionId) {
      await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
        currentAction: "pushed-from-cockpit",
        lastMutationAt: new Date().toISOString(),
        lastMutationLabel: `push: ${branch}`,
        lastPushBranch: branch,
        lastPushAt: new Date().toISOString(),
        lastMergeReadiness: "pushed-awaiting-pr",
        publicationStage: "published"
      });
    }

    return {
      ok: true,
      branch,
      output: stdout,
      git: await readGitStatus(project),
      guardrails: await readGitGuardrails(project, project.preferredPrBase || "main")
    };
  })
);

app.post(
  "/api/projects/:slug/git/pr",
  jsonResponse(async (req) => {
    ensureConfirmed(req, "draft PR");
    const project = await getProjectOrThrow(req.params.slug);
    const base = String(req.body?.base || project.preferredPrBase || "main").trim();
    const title = String(req.body?.title || "").trim();
    const body = String(req.body?.body || "").trim();
    const guardrails = await readGitGuardrails(project, base);
    const branch = guardrails.branch;

    if (!branch) {
      const error = new Error("could not determine current branch");
      error.statusCode = 400;
      throw error;
    }
    if (!guardrails.canPr) {
      const error = new Error("git guardrails block draft PR creation; inspect cautions and PR preview before retrying");
      error.statusCode = 409;
      throw error;
    }

    const command =
      title || body
        ? 'cd "$WORKSPACE_ROOT" && gh pr create --draft --base "$PR_BASE" --head "$CURRENT_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"'
        : 'cd "$WORKSPACE_ROOT" && gh pr create --draft --fill --base "$PR_BASE" --head "$CURRENT_BRANCH"';

    const { stdout } = await withTimeout(
      runWorkspaceShell(
        project,
        {
          WORKSPACE_ROOT: project.workspaceRoot,
          PR_BASE: base,
          CURRENT_BRANCH: branch,
          PR_TITLE: title,
          PR_BODY: body
        },
        command
      ),
      "git draft PR mutation",
      30000
    );

    const url = stdout
      .trim()
      .split("\n")
      .find((line) => line.startsWith("http")) || "";

    const clientSessionId = cleanValue(req.body?.clientSessionId);
    if (clientSessionId) {
      const normalizedTitle = title || firstNonEmptyLine(stdout);
      await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, req.body?.alias), {
        currentAction: "opened-draft-pr-from-cockpit",
        lastMutationAt: new Date().toISOString(),
        lastMutationLabel: `draft-pr: ${branch} -> ${base}`,
        lastPrUrl: url,
        lastPrAt: new Date().toISOString(),
        lastPrTitle: normalizedTitle,
        lastPrBase: base,
        lastPrHead: branch,
        lastReviewStep: "draft-pr-opened",
        lastReviewStepAt: new Date().toISOString(),
        lastReviewUrl: url,
        lastMergeReadiness: "draft",
        publicationStage: "under-review"
      });
    }

    return {
      ok: true,
      branch,
      base,
      url,
      output: stdout,
      preview: await readPrPreview(project, base),
      guardrails: await readGitGuardrails(project, base)
    };
  })
);

function renderProjectLaunchPage(project) {
  const slug = cleanValue(project.projectSlug || "sounio");
  const title = `${slug} Workday`;
  const workspaceRoot = cleanValue(project.workspaceRoot || "");
  const authority = cleanValue(project.workbenchAuthority || process.env.PROJECT_COCKPIT_WORKBENCH_AUTHORITY || "workspace-agent");
  const namespace = cleanValue(project.namespace || "beagle");
  const wsBase = `/ws/workspaces/${encodeURIComponent(slug)}`;
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Beagle ${escapeHtml(title)}</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #080a0f;
      --panel: rgba(255, 255, 255, 0.075);
      --panel-strong: rgba(255, 255, 255, 0.12);
      --text: #f6f7fb;
      --muted: #a9b0c2;
      --line: rgba(255, 255, 255, 0.16);
      --accent: #79f2c0;
      --warn: #f6c76f;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background: radial-gradient(circle at top left, rgba(70, 135, 255, 0.14), transparent 32rem), var(--bg);
      color: var(--text);
    }
    main {
      width: min(1120px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 32px 0 48px;
    }
    header {
      display: grid;
      gap: 12px;
      padding-bottom: 24px;
      border-bottom: 1px solid var(--line);
    }
    .eyebrow {
      margin: 0;
      color: var(--accent);
      text-transform: uppercase;
      letter-spacing: 0.08em;
      font-size: 12px;
      font-weight: 700;
    }
    h1 {
      margin: 0;
      font-size: clamp(32px, 7vw, 62px);
      line-height: 0.95;
      letter-spacing: 0;
    }
    .subtitle {
      max-width: 720px;
      color: var(--muted);
      font-size: 17px;
      line-height: 1.5;
      margin: 0;
    }
    .grid {
      display: grid;
      grid-template-columns: minmax(0, 1.25fr) minmax(280px, 0.75fr);
      gap: 18px;
      margin-top: 22px;
    }
    section, .panel {
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 8px;
      padding: 18px;
      backdrop-filter: blur(18px);
    }
    h2 {
      margin: 0 0 12px;
      font-size: 16px;
      letter-spacing: 0;
    }
    .meta {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 6px;
    }
    .pill {
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 6px 9px;
      color: var(--muted);
      background: rgba(0, 0, 0, 0.18);
      font-size: 12px;
      max-width: 100%;
      overflow-wrap: anywhere;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 16px;
    }
    button, a.button {
      appearance: none;
      border: 1px solid var(--line);
      background: var(--panel-strong);
      color: var(--text);
      border-radius: 8px;
      padding: 10px 12px;
      font: inherit;
      font-weight: 650;
      text-decoration: none;
      cursor: pointer;
    }
    button.primary {
      color: #05120d;
      background: var(--accent);
      border-color: transparent;
    }
    button:disabled {
      opacity: 0.55;
      cursor: wait;
    }
    .status {
      display: grid;
      gap: 10px;
    }
    .row {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      border-top: 1px solid var(--line);
      padding-top: 10px;
      color: var(--muted);
      font-size: 14px;
    }
    .row strong {
      color: var(--text);
      overflow-wrap: anywhere;
      text-align: right;
    }
    pre {
      min-height: 170px;
      max-height: 360px;
      overflow: auto;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      margin: 0;
      color: #d7deeb;
      font-size: 12px;
      line-height: 1.45;
    }
    input.command-input {
      width: 100%;
      min-width: 0;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 11px 12px;
      background: rgba(0, 0, 0, 0.28);
      color: var(--text);
      font: inherit;
    }
    .terminal-output {
      min-height: 320px;
      max-height: 46vh;
      background: rgba(0, 0, 0, 0.34);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 12px;
    }
    .command-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 10px;
      margin-top: 12px;
    }
    .lane-list {
      display: grid;
      gap: 8px;
    }
    .lane {
      display: grid;
      gap: 4px;
      padding: 10px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgba(0, 0, 0, 0.16);
    }
    .lane strong, .lane span { overflow-wrap: anywhere; }
    .lane span { color: var(--muted); font-size: 13px; }
    .warn { color: var(--warn); }
    @media (max-width: 760px) {
      main { width: min(100vw - 22px, 1120px); padding-top: 22px; }
      .grid { grid-template-columns: 1fr; }
      h1 { font-size: clamp(30px, 12vw, 46px); }
      button, a.button { width: 100%; text-align: center; }
      .command-row { grid-template-columns: 1fr; }
      .row { display: grid; }
      .row strong { text-align: left; }
    }
    /* ── Fleet Terminal (xterm.js) ───────────────────────────────────────── */
    .fleet-terminal-wrap {
      height: 420px;
      border-radius: 8px;
      overflow: hidden;
      background: #0d1117;
      border: 1px solid var(--line);
    }
    #fleet-terminal {
      height: 100%;
      width: 100%;
    }
    .fleet-header {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 12px;
    }
    .fleet-pill {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 4px 10px;
      font-size: 12px;
      color: var(--muted);
      background: rgba(0, 0, 0, 0.18);
    }
    .fleet-pill .dot {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: var(--muted);
      flex-shrink: 0;
      transition: background 0.2s;
    }
    .fleet-pill.connected .dot  { background: var(--accent); }
    .fleet-pill.connected       { color: var(--accent); }
    .fleet-pill.disconnected .dot { background: #ff5f5f; }
    .fleet-pill.disconnected    { color: #ff8a8a; }
    #fleet-reconnect { margin-left: auto; }
    @media (max-width: 760px) {
      .fleet-header { flex-wrap: wrap; }
      #fleet-reconnect { margin-left: 0; width: 100%; }
      .fleet-terminal-wrap { height: 300px; }
    }
  </style>
  <!-- xterm.js Fleet Terminal — loaded from CDN (unpkg).                     -->
  <!-- SRI hashes pinned to @xterm/xterm@5.x and @xterm/addon-fit@0.10.x.    -->
  <!-- TODO air-gap hardening: vendor these files under                        -->
  <!--      apps/project-cockpit/public/ and serve them as static assets.      -->
  <link rel="stylesheet"
        href="https://unpkg.com/@xterm/xterm@5/css/xterm.css"
        integrity="sha384-8Xk9wy/gzEDUKrXtrmCFa2bBuK3BpjpDuL/p0SeKQX19Khl/M+lHOgD/CyYf7efP"
        crossorigin="anonymous" />
  <script src="https://unpkg.com/@xterm/xterm@5/lib/xterm.js"
          integrity="sha384-M169f14mRZOXm3hD/v2Ti0ThIT/RnAQagXA9nlE15yHAtrW19gdePJh/HaTzUOe/"
          crossorigin="anonymous"></script>
  <script src="https://unpkg.com/@xterm/addon-fit@0.10/lib/addon-fit.js"
          integrity="sha384-iF+jqbuti4XlB64clWgFWYEscb+UnSRv3VgVikGYZu+otNFnSHr7y7NcKfBnGizn"
          crossorigin="anonymous"></script>
</head>
<body>
  <main>
    <header>
      <p class="eyebrow">Beagle Sounio Workday MVP</p>
      <h1>${escapeHtml(title)}</h1>
      <p class="subtitle">Fallback launch pad for the live Workbench. It talks to the cluster Project Cockpit and workspace-agent; canonical memory remains in Beagle Core on the cluster.</p>
      <div class="meta">
        <span class="pill">authority: ${escapeHtml(authority)}</span>
        <span class="pill">namespace: ${escapeHtml(namespace)}</span>
        <span class="pill">workspace: ${escapeHtml(workspaceRoot || "declared")}</span>
      </div>
    </header>

    <div class="grid">
      <section>
        <h2>Agent Fabric</h2>
        <div id="lanes" class="lane-list"><span class="pill">Loading lanes...</span></div>
        <div class="actions">
          <button class="primary" id="start-session">Start Shell Session</button>
          <button id="refresh">Refresh</button>
          <a class="button" href="/projects/${encodeURIComponent(slug)}/workbench-v2">Visual Workbench v2</a>
          <a class="button" href="/projects/${encodeURIComponent(slug)}/warp">Warp Bridge Lab</a>
          <a class="button" href="/api/workspaces/${encodeURIComponent(slug)}/agents/registry">Registry JSON</a>
          <a class="button" href="/api/workspaces/${encodeURIComponent(slug)}/sessions">Sessions JSON</a>
        </div>
      </section>

      <section class="status">
        <h2>Live State</h2>
        <div class="row"><span>Project</span><strong>${escapeHtml(slug)}</strong></div>
        <div class="row"><span>WebSocket base</span><strong>${escapeHtml(wsBase)}/...</strong></div>
        <div class="row"><span>Latest session</span><strong id="latest-session">Loading...</strong></div>
        <div class="row"><span>Warp bridge</span><strong id="warp-bridge">Loading...</strong></div>
        <div class="row"><span>Truth mode</span><strong id="truth-mode">Loading...</strong></div>
      </section>
    </div>

    <section style="margin-top: 18px;">
      <h2>Shell Lane</h2>
      <pre id="terminal-output" class="terminal-output">No shell attached yet. Start or refresh a session, then connect.</pre>
      <form id="terminal-form" class="command-row">
        <input id="terminal-input" class="command-input" autocomplete="off" spellcheck="false" placeholder="Type a command for /workspace/sounio" />
        <button class="primary" type="submit">Send</button>
      </form>
      <div class="actions">
        <button id="connect-terminal" type="button">Connect Latest Shell</button>
        <button id="interrupt-terminal" type="button">Interrupt</button>
        <button id="remember-block" type="button">Remember Last Block</button>
      </div>
    </section>

    <section style="margin-top: 18px;">
      <div class="fleet-header">
        <h2 style="margin:0;">Fleet Terminal</h2>
        <span id="fleet-pill" class="fleet-pill"><span class="dot"></span><span id="fleet-pill-text">connecting…</span></span>
        <button id="fleet-reconnect" type="button">Reconnect</button>
      </div>
      <div class="fleet-terminal-wrap">
        <div id="fleet-terminal"></div>
      </div>
    </section>

    <section style="margin-top: 18px;">
      <h2>Response</h2>
      <pre id="output">Opening Beagle Workbench...</pre>
    </section>
  </main>

  <script>
    const slug = ${JSON.stringify(slug)};
    const output = document.getElementById("output");
    const lanes = document.getElementById("lanes");
    const latestSession = document.getElementById("latest-session");
    const warpBridge = document.getElementById("warp-bridge");
    const truthMode = document.getElementById("truth-mode");
    const startButton = document.getElementById("start-session");
    const refreshButton = document.getElementById("refresh");
    const terminalOutput = document.getElementById("terminal-output");
    const terminalForm = document.getElementById("terminal-form");
    const terminalInput = document.getElementById("terminal-input");
    const connectTerminalButton = document.getElementById("connect-terminal");
    const interruptTerminalButton = document.getElementById("interrupt-terminal");
    const rememberBlockButton = document.getElementById("remember-block");
    let currentSessions = [];
    let currentSessionId = "";
    let currentPaneId = "";
    let terminalWs = null;
    let terminalConnectedKey = "";
    let lastBlockId = "";
    let currentRegistry = null;

    function show(payload) {
      output.textContent = typeof payload === "string" ? payload : JSON.stringify(payload, null, 2);
    }

    function stripOscSequences(value) {
      const ESC = String.fromCharCode(27);
      const BEL = String.fromCharCode(7);
      let result = String(value || "");
      let start = result.indexOf(ESC + "]");
      while (start !== -1) {
        const belEnd = result.indexOf(BEL, start + 2);
        const stEnd = result.indexOf(ESC + "\\\\", start + 2);
        let end = -1;
        let endLength = 1;
        if (belEnd !== -1 && (stEnd === -1 || belEnd < stEnd)) {
          end = belEnd;
          endLength = 1;
        } else if (stEnd !== -1) {
          end = stEnd;
          endLength = 2;
        }
        if (end === -1) {
          result = result.slice(0, start);
          break;
        }
        result = result.slice(0, start) + result.slice(end + endLength);
        start = result.indexOf(ESC + "]");
      }
      return result;
    }

    function stripBareOscFragments(value) {
      return String(value || "")
        .split("\\n")
        .map((line) => {
          for (const marker of ["]0;", "]2;"]) {
            let start = line.indexOf(marker);
            while (start !== -1) {
              const promptStart = line.indexOf("node@", start + marker.length);
              if (promptStart === -1) {
                line = line.slice(0, start);
                break;
              }
              line = line.slice(0, start) + line.slice(promptStart);
              start = line.indexOf(marker);
            }
          }
          return line;
        })
        .join("\\n");
    }

    function appendTerminal(text) {
      const ESC = String.fromCharCode(27);
      const cleaned = stripBareOscFragments(stripOscSequences(text))
        .replace(new RegExp(ESC + "\\\\[[0-?]*[ -/]*[@-~]", "g"), "")
        .replace(new RegExp(ESC + "[>=]", "g"), "")
        .split("\\r\\n").join("\\n")
        .split("\\r").join("\\n");
      terminalOutput.textContent = (terminalOutput.textContent + cleaned).slice(-50000);
      terminalOutput.scrollTop = terminalOutput.scrollHeight;
    }

    async function apiJson(path, options = {}) {
      const response = await fetch(path, {
        ...options,
        headers: {
          "content-type": "application/json",
          ...(options.headers || {})
        }
      });
      const text = await response.text();
      let payload;
      try {
        payload = text ? JSON.parse(text) : {};
      } catch (_error) {
        payload = { raw: text };
      }
      if (!response.ok) {
        throw new Error(payload.error || payload.raw || response.statusText);
      }
      return payload;
    }

    function roleName(role) {
      if (typeof role === "string") return role;
      return role.title || role.label || role.displayName || role.display_name || role.role || role.id || role.kind || "agent";
    }

    function roleDetail(role) {
      if (typeof role === "string") return "provider slot pending";
      const slots = role.providerSlots || role.provider_slots || role.slots || [];
      const enabled = Array.isArray(slots) ? slots.find((slot) => slot.enabled !== false) || slots[0] : null;
      const readiness = role.readiness && typeof role.readiness === "object" ? role.readiness : {};
      const provider = enabled ? enabled.title || enabled.model_id || enabled.modelId || enabled.command || enabled.provider || "" : "";
      const status = readiness.status || role.status || enabled?.status || "";
      let reason = readiness.reason || role.subtitle || "";
      const command = role.launchCommand || enabled?.command || "";
      if (status === "ready" && !command && enabled?.runtime) {
        reason = "provider slot ready; interactive adapter pending";
      }
      return [provider, status, reason].filter(Boolean).join(" - ") || "provider slot pending";
    }

    function renderLanes(registry) {
      const allRoles = Array.isArray(registry.roles) ? registry.roles : [];
      const byRole = new Map(allRoles.map((role) => [role.role || role.id || role.kind, role]));
      const visibleRefs = registry.visibleRoles || registry.visible_roles || [];
      const selected = (Array.isArray(visibleRefs) && visibleRefs.length > 0
        ? visibleRefs.map((entry) => typeof entry === "string" ? byRole.get(entry) || entry : entry)
        : allRoles.filter((role) => role.visible !== false)
      ).filter(Boolean).slice(0, 8);
      if (selected.length === 0) {
        lanes.innerHTML = '<span class="pill warn">No role lanes reported by workspace-agent yet.</span>';
        return;
      }
      lanes.innerHTML = selected.map((role) =>
        '<div class="lane"><strong>' + roleName(role) + '</strong><span>' + roleDetail(role) + '</span></div>'
      ).join("");
    }

    function agentSetupGuard(command) {
      const value = String(command || "").trim();
      if (!value) return null;
      const token = value.split(" ").filter(Boolean)[0] || "";
      const lookup = token === "cursor" ? "cursor-agent" : token;
      const roles = Array.isArray(currentRegistry?.roles) ? currentRegistry.roles : [];
      for (const role of roles) {
        const slots = Array.isArray(role.providerSlots || role.provider_slots) ? role.providerSlots || role.provider_slots : [];
        const commands = [role.launchCommand, role.readiness?.command, ...slots.map((slot) => slot.command)].filter(Boolean);
        if (!commands.includes(token) && !commands.includes(lookup)) continue;
        const readiness = role.readiness || {};
        if (readiness.status === "needs_setup") {
          const reason = readiness.command === token || readiness.command === lookup
            ? readiness.reason
            : lookup + " is not on PATH in the workspace";
          return {
            token,
            role: roleName(role),
            reason: reason || "agent lane needs setup",
          };
        }
      }
      return null;
    }

    function summarizeRefresh(registry, sessions) {
      const list = sessions.sessions || [];
      const selected = selectDefaultSession(list);
      return {
        registryVersion: registry.registryVersion || registry.registry_version || "unknown",
        authority: registry.authority?.authority || sessions.authority?.authority || "unknown",
        supervisor: registry.authority?.supervisor?.status || sessions.authority?.supervisor?.status || "unknown",
        visibleRoles: registry.visibleRoles || registry.visible_roles || [],
        selectedSession: selected ? {
          id: selected.id || selected.session_id,
          title: selected.title,
          reason: isOperatorSession(selected) ? "operator" : "fallback"
        } : null,
        warpBridge: registry.authority?.bridgeVersion || sessions.authority?.bridgeVersion || selected?.bridgeVersion || "not_reported",
        warpBoundary: "apps/warp-workbench -> vendor/warp@805b3e2",
        latestSessions: list.slice(0, 5).map((session) => ({
          id: session.id || session.session_id,
          title: session.title,
          panes: Array.isArray(session.panes) ? session.panes.length : 0,
          memory: session.lastMemoryStatus?.status || "none"
        }))
      };
    }

    function isOperatorSession(session) {
      const title = String(session?.title || "").toLowerCase();
      return !(
        title.includes("smoke") ||
        title.includes("probe") ||
        title.includes("isolation")
      );
    }

    function selectDefaultSession(list) {
      return list.find(isOperatorSession) || list[0] || null;
    }

    function selectShellPane(session) {
      const panes = Array.isArray(session?.panes) ? session.panes : [];
      return panes.find((pane) => pane.kind === "human" || pane.kind === "shell") || panes[0] || null;
    }

    function closeTerminal() {
      if (terminalWs) {
        terminalWs.close();
        terminalWs = null;
      }
      terminalConnectedKey = "";
    }

    function connectTerminal(session = null) {
      const targetSession = session || selectDefaultSession(currentSessions);
      const pane = selectShellPane(targetSession);
      if (!targetSession?.id || !pane?.id) {
        appendTerminal("\\n[beagle] no shell pane available yet\\n");
        return;
      }
      const key = targetSession.id + ":" + pane.id;
      if (terminalWs && terminalConnectedKey === key && terminalWs.readyState === WebSocket.OPEN) {
        return;
      }
      closeTerminal();
      currentSessionId = targetSession.id;
      currentPaneId = pane.id;
      terminalConnectedKey = key;
      terminalOutput.textContent = "[beagle] connecting " + key + "...\\n";
      const scheme = location.protocol === "https:" ? "wss:" : "ws:";
      const url = scheme + "//" + location.host + "/ws/workspaces/" + encodeURIComponent(slug) + "/sessions/" + encodeURIComponent(currentSessionId) + "/panes/" + encodeURIComponent(currentPaneId);
      terminalWs = new WebSocket(url);
      terminalWs.addEventListener("open", () => {
        appendTerminal("[beagle] connected to Shell lane\\n");
        terminalWs.send(JSON.stringify({ type: "resize", cols: 120, rows: 34 }));
      });
      terminalWs.addEventListener("message", (event) => {
        let message = {};
        try {
          message = JSON.parse(String(event.data));
        } catch (_error) {
          appendTerminal(String(event.data));
          return;
        }
        if (message.type === "data") {
          appendTerminal(String(message.data || ""));
          return;
        }
        if (message.type === "raw_output") return;
        if (message.type === "ready") {
          appendTerminal("\\n[beagle] ready: " + JSON.stringify(message.data || {}) + "\\n");
          return;
        }
        if (message.type === "block_started") {
          lastBlockId = message.blockId || message.block_id || "";
          appendTerminal("\\n[block started] " + (message.title || lastBlockId || "command") + "\\n");
          return;
        }
        if (message.type === "block_finished") {
          lastBlockId = message.blockId || message.block_id || lastBlockId;
          appendTerminal("\\n[block finished] " + (message.status || "finished") + " " + (lastBlockId || "") + "\\n");
          refresh().catch(() => {});
          return;
        }
        if (message.type === "memory_imported") {
          appendTerminal("\\n[memory] " + (message.status || "updated") + " " + (message.blockId || "") + "\\n");
          refresh().catch(() => {});
          return;
        }
        if (message.type === "secret_redacted") {
          appendTerminal("\\n[restricted] secret redacted; block will not be canonical memory\\n");
          return;
        }
        if (message.type === "agent_state") {
          appendTerminal("\\n[agent] " + (message.state || "updated") + "\\n");
          return;
        }
        if (message.type === "exit" || message.type === "error") {
          appendTerminal("\\n[" + message.type + "] " + (message.data || message.error || "") + "\\n");
          return;
        }
      });
      terminalWs.addEventListener("close", () => {
        appendTerminal("\\n[beagle] shell disconnected\\n");
      });
      terminalWs.addEventListener("error", () => {
        appendTerminal("\\n[beagle] shell websocket error\\n");
      });
    }

    async function refresh() {
      refreshButton.disabled = true;
      try {
        const registry = await apiJson("/api/workspaces/" + encodeURIComponent(slug) + "/agents/registry");
        const sessions = await apiJson("/api/workspaces/" + encodeURIComponent(slug) + "/sessions");
        currentRegistry = registry;
        renderLanes(registry);
        const list = sessions.sessions || [];
        currentSessions = list;
        const selected = selectDefaultSession(list);
        latestSession.textContent = selected ? selected.id || selected.session_id || "active" : "none";
        warpBridge.textContent = registry.authority?.bridgeVersion || sessions.authority?.bridgeVersion || selected?.bridgeVersion || "not reported";
        truthMode.textContent = registry.truthMode || registry.truth_mode || sessions.truthMode || sessions.truth_mode || "observed";
        show(summarizeRefresh(registry, sessions));
        if (!terminalWs && selected) connectTerminal(selected);
      } catch (error) {
        lanes.innerHTML = '<span class="pill warn">Workbench unavailable: ' + error.message + '</span>';
        truthMode.textContent = "stale";
        show(String(error.stack || error.message || error));
      } finally {
        refreshButton.disabled = false;
      }
    }

    async function startSession() {
      startButton.disabled = true;
      try {
        const created = await apiJson("/api/workspaces/" + encodeURIComponent(slug) + "/sessions", {
          method: "POST",
          body: JSON.stringify({
            title: "Sounio Workday MVP",
            layout: "notebook",
            sourceModel: "beagle"
          })
        });
        const session = created.session || created;
        const sessionId = session.id || session.sessionId || session.session_id;
        const panes = Array.isArray(session.panes) ? session.panes : [];
        if (sessionId && panes.length === 0) {
          await apiJson("/api/workspaces/" + encodeURIComponent(slug) + "/sessions/" + encodeURIComponent(sessionId) + "/panes", {
            method: "POST",
            body: JSON.stringify({ kind: "human", title: "Shell" })
          });
        }
        await refresh();
        const refreshed = currentSessions.find((entry) => entry.id === sessionId || entry.session_id === sessionId);
        if (refreshed) connectTerminal(refreshed);
      } catch (error) {
        show(String(error.stack || error.message || error));
      } finally {
        startButton.disabled = false;
      }
    }

    refreshButton.addEventListener("click", refresh);
    startButton.addEventListener("click", startSession);
    connectTerminalButton.addEventListener("click", () => connectTerminal());
    interruptTerminalButton.addEventListener("click", () => {
      if (terminalWs && terminalWs.readyState === WebSocket.OPEN) {
        terminalWs.send(JSON.stringify({ type: "signal", signal: "SIGINT" }));
      }
    });
    rememberBlockButton.addEventListener("click", async () => {
      if (!currentSessionId || !lastBlockId) {
        appendTerminal("\\n[beagle] no finished block to remember yet\\n");
        return;
      }
      try {
        const remembered = await apiJson("/api/workspaces/" + encodeURIComponent(slug) + "/sessions/" + encodeURIComponent(currentSessionId) + "/blocks/" + encodeURIComponent(lastBlockId) + "/remember", {
          method: "POST",
          body: JSON.stringify({ confirmed: true, summary: "Manual Workbench remember from Project Cockpit launch pad." })
        });
        appendTerminal("\\n[memory] " + JSON.stringify(remembered.memory || remembered) + "\\n");
        await refresh();
      } catch (error) {
        appendTerminal("\\n[memory error] " + (error.message || error) + "\\n");
      }
    });
    terminalForm.addEventListener("submit", (event) => {
      event.preventDefault();
      const command = terminalInput.value;
      if (!command.trim()) return;
      const setupGap = agentSetupGuard(command);
      if (setupGap) {
        appendTerminal("\\n[setup] " + setupGap.role + " is not ready: " + setupGap.reason + ". Command not sent to the PTY. Configure the CLI/provider in the workspace image or use an available lane.\\n");
        terminalInput.value = "";
        terminalInput.focus();
        return;
      }
      if (!terminalWs || terminalWs.readyState !== WebSocket.OPEN) {
        connectTerminal();
        setTimeout(() => {
          if (terminalWs && terminalWs.readyState === WebSocket.OPEN) {
            terminalWs.send(JSON.stringify({ type: "input", data: command + "\\n" }));
          }
        }, 450);
      } else {
        terminalWs.send(JSON.stringify({ type: "input", data: command + "\\n" }));
      }
      terminalInput.value = "";
      terminalInput.focus();
    });
    refresh();

    // ── Fleet Terminal (xterm.js → /ws/terminal PTY) ─────────────────────────
    // Connects to the shared interactive PTY for pod sounio-workspace-control-0.
    // Auth uses the tailscale-user-login header the browser already sends on the
    // upgrade request (same gate as the page) — NOT a token in the URL, which
    // would leak into cloudflared/proxy access logs. The old Shell Lane <pre>
    // above is intentionally kept; both coexist.
    (function () {
      const fleetPillEl      = document.getElementById("fleet-pill");
      const fleetPillText    = document.getElementById("fleet-pill-text");
      const fleetReconnectBtn = document.getElementById("fleet-reconnect");

      let fleetWs        = null;
      let fleetTerm      = null;
      let fleetFit       = null;
      let fleetResizeObs = null;

      function fleetSetPill(state, label) {
        fleetPillEl.className = "fleet-pill" + (state ? " " + state : "");
        fleetPillText.textContent = label;
      }

      function fleetConnect() {
        if (fleetWs) {
          try { fleetWs.close(); } catch (_) {}
          fleetWs = null;
        }
        fleetSetPill("", "connecting\\u2026");
        const scheme = location.protocol === "https:" ? "wss:" : "ws:";
        const params = new URLSearchParams({ project: slug });
        const url = scheme + "//" + location.host + "/ws/terminal?" + params.toString();
        fleetWs = new WebSocket(url);

        fleetWs.addEventListener("open", () => {
          if (fleetTerm && fleetFit) {
            try { fleetFit.fit(); } catch (_) {}
            fleetWs.send(JSON.stringify({ type: "resize", cols: fleetTerm.cols, rows: fleetTerm.rows }));
          }
        });

        fleetWs.addEventListener("message", (event) => {
          let msg = {};
          try { msg = JSON.parse(String(event.data)); } catch (_) {
            fleetTerm && fleetTerm.write(String(event.data));
            return;
          }
          if (msg.type === "data")  { fleetTerm && fleetTerm.write(msg.data); return; }
          if (msg.type === "ready") {
            fleetSetPill("connected", "connected \\u00b7 " + (msg.data && msg.data.projectSlug ? msg.data.projectSlug : slug));
            return;
          }
          if (msg.type === "exit")  {
            fleetSetPill("disconnected", "exited \\u00b7 " + (msg.data || ""));
            return;
          }
          if (msg.type === "error") {
            fleetSetPill("disconnected", "error \\u00b7 " + (msg.data || msg.error || ""));
            return;
          }
        });

        fleetWs.addEventListener("close", () => fleetSetPill("disconnected", "disconnected"));
        fleetWs.addEventListener("error", () => fleetSetPill("disconnected", "ws error"));
      }

      function fleetInit() {
        const container = document.getElementById("fleet-terminal");
        if (!container) return;

        // Dispose previous instance if reconnecting
        if (fleetResizeObs) { try { fleetResizeObs.disconnect(); } catch (_) {} fleetResizeObs = null; }
        if (fleetTerm)      { try { fleetTerm.dispose(); }          catch (_) {} fleetTerm = null; }

        fleetTerm = new Terminal({
          cursorBlink: true,
          theme: {
            background:          "#0d1117",
            foreground:          "#f6f7fb",
            cursor:              "#79f2c0",
            selectionBackground: "rgba(121, 242, 192, 0.25)"
          },
          fontFamily: '"SF Mono", "Cascadia Code", "Fira Code", ui-monospace, monospace',
          fontSize: 13,
          lineHeight: 1.35,
          scrollback: 5000,
          allowTransparency: false
        });

        fleetFit = new FitAddon.FitAddon();
        fleetTerm.loadAddon(fleetFit);
        fleetTerm.open(container);
        try { fleetFit.fit(); } catch (_) {}

        // Relay user keystrokes / paste to the PTY
        fleetTerm.onData((d) => {
          if (fleetWs && fleetWs.readyState === WebSocket.OPEN) {
            fleetWs.send(JSON.stringify({ type: "input", data: d }));
          }
        });

        // Track container resizes and notify the server PTY
        fleetResizeObs = new ResizeObserver(() => {
          try { fleetFit && fleetFit.fit(); } catch (_) {}
          if (fleetWs && fleetWs.readyState === WebSocket.OPEN && fleetTerm) {
            fleetWs.send(JSON.stringify({ type: "resize", cols: fleetTerm.cols, rows: fleetTerm.rows }));
          }
        });
        fleetResizeObs.observe(container);

        fleetConnect();
      }

      fleetReconnectBtn.addEventListener("click", () => {
        // Full re-init so the terminal canvas is fresh after a reconnect
        fleetInit();
      });

      // xterm.js scripts are synchronous in <head>; Terminal is defined by now.
      // Fallback to window load if a browser extension somehow defers them.
      if (typeof Terminal !== "undefined" && typeof FitAddon !== "undefined") {
        fleetInit();
      } else {
        window.addEventListener("load", fleetInit);
      }
    })();
  </script>
</body>
</html>`;
}

function renderVisualWorkbenchPrototypePage(project) {
  const slug = cleanValue(project.projectSlug || "sounio");
  const title = `${slug} Agent Deck`;
  const workspaceRoot = cleanValue(project.workspaceRoot || "");
  const authority = cleanValue(project.workbenchAuthority || process.env.PROJECT_COCKPIT_WORKBENCH_AUTHORITY || "workspace-agent");
  const namespace = cleanValue(project.namespace || "beagle");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Beagle ${escapeHtml(title)}</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #080b0f;
      --surface: rgba(15, 19, 24, 0.92);
      --surface-2: rgba(255, 255, 255, 0.072);
      --surface-3: rgba(255, 255, 255, 0.12);
      --line: rgba(255, 255, 255, 0.15);
      --line-strong: rgba(255, 255, 255, 0.25);
      --text: #f5f7fb;
      --muted: #a8b1be;
      --dim: #737f90;
      --green: #7df0bd;
      --blue: #7fb6ff;
      --amber: #f2c36b;
      --red: #ff8a8a;
      --violet: #c5a8ff;
      --shadow: 0 18px 56px rgba(0, 0, 0, 0.38);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background:
        linear-gradient(145deg, rgba(9, 12, 17, 0.92), rgba(9, 13, 15, 0.98)),
        radial-gradient(circle at 12% 12%, rgba(125, 240, 189, 0.12), transparent 34rem),
        radial-gradient(circle at 88% 20%, rgba(127, 182, 255, 0.10), transparent 30rem),
        var(--bg);
      color: var(--text);
    }
    main {
      width: min(1440px, calc(100vw - 28px));
      margin: 0 auto;
      padding: 24px 0 32px;
    }
    header {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      align-items: end;
      gap: 20px;
      padding: 18px 0 20px;
      border-bottom: 1px solid var(--line);
    }
    .eyebrow {
      margin: 0 0 7px;
      color: var(--green);
      text-transform: uppercase;
      letter-spacing: 0.08em;
      font-size: 12px;
      font-weight: 750;
    }
    h1 {
      margin: 0;
      font-size: clamp(34px, 6vw, 76px);
      line-height: 0.92;
      letter-spacing: 0;
    }
    .subtitle {
      max-width: 840px;
      margin: 12px 0 0;
      color: var(--muted);
      font-size: 17px;
      line-height: 1.45;
    }
    .pills {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 14px;
    }
    .pill, .badge {
      display: inline-flex;
      align-items: center;
      min-height: 26px;
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 5px 9px;
      color: var(--muted);
      background: rgba(0, 0, 0, 0.22);
      font-size: 12px;
      max-width: 100%;
      overflow-wrap: anywhere;
    }
    .badge.ready { color: var(--green); border-color: rgba(125, 240, 189, 0.38); }
    .badge.warn { color: var(--amber); border-color: rgba(242, 195, 107, 0.36); }
    .badge.blocked { color: var(--red); border-color: rgba(255, 138, 138, 0.36); }
    .header-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;
    }
    button, a.button {
      appearance: none;
      border: 1px solid var(--line);
      background: rgba(255, 255, 255, 0.08);
      color: var(--text);
      border-radius: 8px;
      padding: 10px 12px;
      min-height: 40px;
      font: inherit;
      font-weight: 680;
      text-decoration: none;
      cursor: pointer;
    }
    button.primary, a.button.primary {
      color: #06120d;
      background: var(--green);
      border-color: transparent;
    }
    button.ghost { color: var(--muted); }
    button:disabled { opacity: 0.55; cursor: wait; }
    .mission-strip {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: 10px;
      margin-top: 14px;
      padding: 10px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgba(255, 255, 255, 0.055);
    }
    .mission-cell {
      min-height: 62px;
      border: 1px solid rgba(255, 255, 255, 0.11);
      border-radius: 8px;
      background: rgba(0, 0, 0, 0.14);
      padding: 9px;
      display: grid;
      gap: 4px;
      align-content: start;
    }
    .mission-cell span {
      color: var(--dim);
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-weight: 760;
    }
    .mission-cell strong {
      color: var(--text);
      font-size: 13px;
      line-height: 1.25;
      overflow-wrap: anywhere;
    }
    .quick-intents {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      align-content: start;
    }
    .quick-intents button {
      min-height: 28px;
      padding: 5px 8px;
      border-radius: 999px;
      color: var(--muted);
      font-size: 12px;
      font-weight: 650;
    }
    .stage {
      display: grid;
      grid-template-columns: minmax(260px, 0.78fr) minmax(420px, 1.32fr) minmax(300px, 0.86fr);
      gap: 14px;
      margin-top: 18px;
      min-height: calc(100vh - 178px);
    }
    .panel {
      border: 1px solid var(--line);
      background: var(--surface-2);
      border-radius: 8px;
      box-shadow: var(--shadow);
      backdrop-filter: blur(22px);
      min-width: 0;
      overflow: hidden;
    }
    .panel-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      padding: 14px 15px;
      border-bottom: 1px solid var(--line);
    }
    .panel-title {
      display: grid;
      gap: 3px;
      min-width: 0;
    }
    h2, h3, p { letter-spacing: 0; }
    h2 {
      margin: 0;
      font-size: 15px;
      line-height: 1.2;
    }
    .caption {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.3;
    }
    .lane-board {
      display: grid;
      gap: 10px;
      padding: 12px;
      max-height: calc(100vh - 260px);
      overflow: auto;
    }
    .lane-card {
      border: 1px solid var(--line);
      background: rgba(0, 0, 0, 0.18);
      border-radius: 8px;
      padding: 12px;
      display: grid;
      gap: 10px;
      cursor: pointer;
    }
    .lane-card.selected {
      border-color: rgba(125, 240, 189, 0.55);
      background: rgba(125, 240, 189, 0.085);
    }
    .lane-top {
      display: grid;
      grid-template-columns: 36px minmax(0, 1fr) auto;
      gap: 10px;
      align-items: center;
    }
    .lane-icon {
      width: 36px;
      height: 36px;
      display: grid;
      place-items: center;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgba(255, 255, 255, 0.08);
      color: var(--green);
      font-weight: 800;
    }
    .lane-name, .artifact-title, .memory-title {
      font-weight: 760;
      overflow-wrap: anywhere;
    }
    .lane-meta {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
    }
    .lane-task {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.35;
      overflow-wrap: anywhere;
    }
    .canvas {
      display: grid;
      grid-template-rows: auto minmax(0, 1fr) auto;
      min-height: 0;
    }
    .active-work {
      padding: 18px;
      display: grid;
      gap: 14px;
      border-bottom: 1px solid var(--line);
    }
    .work-hero {
      display: grid;
      grid-template-columns: minmax(0, 1fr);
      gap: 16px;
      align-items: start;
    }
    .work-hero h2 {
      font-size: clamp(26px, 3.6vw, 42px);
      line-height: 1.02;
      max-width: 760px;
    }
    .next-move {
      border: 1px solid rgba(125, 240, 189, 0.32);
      background: rgba(125, 240, 189, 0.09);
      border-radius: 8px;
      padding: 12px;
      width: min(100%, 560px);
    }
    .next-move strong { display: block; margin-bottom: 5px; }
    .mission-composer {
      border: 1px solid rgba(127, 182, 255, 0.28);
      background: rgba(127, 182, 255, 0.07);
      border-radius: 8px;
      padding: 12px;
      display: grid;
      gap: 10px;
    }
    .mission-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 10px;
      align-items: stretch;
    }
    .intent-input {
      width: 100%;
      min-height: 76px;
      resize: vertical;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 11px 12px;
      background: rgba(0, 0, 0, 0.24);
      color: var(--text);
      font: inherit;
      line-height: 1.35;
    }
    .composer-actions {
      display: grid;
      gap: 8px;
      align-content: start;
    }
    .route-decision {
      display: none;
      border: 1px solid rgba(125, 240, 189, 0.26);
      background: rgba(125, 240, 189, 0.07);
      border-radius: 8px;
      padding: 12px;
      gap: 10px;
    }
    .route-decision.visible { display: grid; }
    .workflow-steps {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
    }
    .workflow-step {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgba(0, 0, 0, 0.16);
      padding: 9px;
      min-height: 64px;
    }
    .workflow-step strong {
      display: block;
      font-size: 12px;
      margin-bottom: 4px;
    }
    .workflow-step span {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.28;
    }
    .artifact-strip {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 10px;
    }
    .artifact {
      border: 1px solid var(--line);
      background: rgba(0, 0, 0, 0.18);
      border-radius: 8px;
      padding: 12px;
      display: grid;
      gap: 8px;
      min-height: 108px;
    }
    .artifact-body, .memory-body {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.38;
      overflow-wrap: anywhere;
    }
    .evidence-frontier {
      padding: 14px;
      display: grid;
      gap: 10px;
      overflow: auto;
      min-height: 0;
    }
    .evidence-item, .memory-item {
      border: 1px solid var(--line);
      background: rgba(0, 0, 0, 0.18);
      border-radius: 8px;
      padding: 12px;
      display: grid;
      gap: 8px;
      cursor: pointer;
    }
    .evidence-item.selected {
      border-color: rgba(127, 182, 255, 0.48);
      background: rgba(127, 182, 255, 0.08);
    }
    .inspector-body {
      display: grid;
      gap: 12px;
      padding: 12px;
      max-height: calc(100vh - 252px);
      overflow: auto;
    }
    .memory-item { cursor: default; }
    .spatial-preview {
      display: grid;
      gap: 10px;
      padding: 12px;
      border-top: 1px solid var(--line);
    }
    .spatial-zones {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
    }
    .spatial-zone {
      min-height: 68px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgba(0, 0, 0, 0.16);
      padding: 10px;
      display: grid;
      gap: 4px;
    }
    .spatial-zone strong {
      font-size: 13px;
      overflow-wrap: anywhere;
    }
    .spatial-zone span {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.3;
    }
    .portal-preview {
      display: grid;
      gap: 10px;
      padding: 12px;
      border-top: 1px solid var(--line);
    }
    .portal-grid {
      display: grid;
      gap: 8px;
    }
    .portal-card {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgba(0, 0, 0, 0.16);
      padding: 10px;
      display: grid;
      gap: 5px;
    }
    .portal-card strong {
      overflow-wrap: anywhere;
    }
    .portal-card span {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.3;
    }
    .fixture-ribbon {
      display: none;
      margin-top: 12px;
      border: 1px solid rgba(242, 195, 107, 0.36);
      border-radius: 8px;
      padding: 10px 12px;
      color: var(--amber);
      background: rgba(242, 195, 107, 0.08);
      font-size: 13px;
      line-height: 1.35;
    }
    .fixture-ribbon.visible { display: block; }
    .kv {
      display: grid;
      grid-template-columns: 108px minmax(0, 1fr);
      gap: 8px;
      padding-top: 8px;
      border-top: 1px solid var(--line);
      color: var(--muted);
      font-size: 12px;
    }
    .kv strong {
      color: var(--text);
      font-weight: 650;
      overflow-wrap: anywhere;
    }
    .dock {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      padding: 12px;
      border-top: 1px solid var(--line);
      background: rgba(0, 0, 0, 0.16);
    }
    .runtime {
      position: fixed;
      inset: auto 18px 18px auto;
      width: min(780px, calc(100vw - 36px));
      max-height: min(620px, calc(100vh - 36px));
      display: none;
      grid-template-rows: auto minmax(0, 1fr);
      border: 1px solid var(--line-strong);
      border-radius: 8px;
      background: rgba(8, 11, 15, 0.98);
      box-shadow: 0 24px 90px rgba(0, 0, 0, 0.56);
      z-index: 10;
      overflow: hidden;
    }
    .runtime.open { display: grid; }
    pre {
      margin: 0;
      padding: 14px;
      min-height: 240px;
      overflow: auto;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      color: #d7deeb;
      font-size: 12px;
      line-height: 1.45;
      background: rgba(0, 0, 0, 0.28);
    }
    .empty {
      color: var(--muted);
      border: 1px dashed var(--line);
      border-radius: 8px;
      padding: 16px;
      line-height: 1.45;
    }
    @media (max-width: 1080px) {
      header { grid-template-columns: 1fr; align-items: start; }
      .header-actions { justify-content: flex-start; }
      .stage { grid-template-columns: 1fr; min-height: auto; }
      .mission-strip { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .lane-board, .inspector-body { max-height: none; }
      .artifact-strip { grid-template-columns: 1fr; }
      .work-hero { grid-template-columns: 1fr; }
    }
    @media (max-width: 680px) {
      main { width: min(100vw - 18px, 1440px); padding-top: 12px; }
      h1 { font-size: clamp(34px, 14vw, 54px); }
      button, a.button { width: 100%; justify-content: center; text-align: center; }
      .lane-top { grid-template-columns: 32px minmax(0, 1fr); }
      .lane-top .badge { grid-column: 1 / -1; width: fit-content; }
      .kv { grid-template-columns: 1fr; }
      .mission-strip { grid-template-columns: 1fr; }
      .mission-row, .spatial-zones, .workflow-steps { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <p class="eyebrow">Beagle v4 visual-first prototype</p>
        <h1>${escapeHtml(title)}</h1>
        <p class="subtitle">A web-first workbench for validating the actual experience: visual agent lanes, active work canvas, memory/proof inspector, and runtime logs only on demand.</p>
        <div class="pills">
          <span class="pill">project: ${escapeHtml(slug)}</span>
          <span class="pill">authority: ${escapeHtml(authority)}</span>
          <span class="pill">namespace: ${escapeHtml(namespace)}</span>
          <span class="pill">workspace: ${escapeHtml(workspaceRoot || "declared")}</span>
          <span class="pill">runtime=hidden</span>
          <span class="pill">canonical_memory=cluster-only</span>
        </div>
        <div id="fixture-ribbon" class="fixture-ribbon">Design fixture active: visual-only sample data. No canonical memory, private artifact, or workspace command is being written from this page.</div>
      </div>
      <div class="header-actions">
        <a class="button primary" href="/projects/${encodeURIComponent(slug)}/workbench-v2">Agent Deck</a>
        <a class="button" href="/projects/${encodeURIComponent(slug)}">Runtime Launchpad</a>
        <a class="button" href="/projects/${encodeURIComponent(slug)}/warp">Warp Lab</a>
        <button id="refresh" type="button">Refresh</button>
      </div>
    </header>

    <section class="mission-strip" aria-label="Mission status">
      <div class="mission-cell"><span>Mission</span><strong id="mission-now">Sounio Workday</strong></div>
      <div class="mission-cell"><span>Route</span><strong id="mission-route">Primary builder lane</strong></div>
      <div class="mission-cell"><span>Evidence</span><strong id="mission-evidence">Waiting for block</strong></div>
      <div class="mission-cell"><span>Safety</span><strong id="mission-safety">Cluster-only memory</strong></div>
      <div class="mission-cell">
        <span>Quick intents</span>
        <div class="quick-intents">
          <button type="button" data-quick-intent="Analyze Sounio Claim<T> semantics and list proof needs.">Semantics</button>
          <button type="button" data-quick-intent="Refactor the Sounio compiler tests and summarize expected diff.">Refactor tests</button>
          <button type="button" data-quick-intent="Inspect a Kubernetes deploy incident and prepare an approval-gated runbook.">Incident</button>
          <button type="button" data-quick-intent="Promote a selected Claude or ChatGPT clip after redaction and provenance review.">Promote clip</button>
        </div>
      </div>
    </section>

    <section class="stage" aria-label="Visual Workbench">
      <aside class="panel">
        <div class="panel-header">
          <div class="panel-title">
            <h2>Agent Lanes</h2>
            <span class="caption">Role-first, provider second. Missing tools become setup gaps.</span>
          </div>
          <span id="lane-count" class="badge">loading</span>
        </div>
        <div id="lane-board" class="lane-board">
          <div class="empty">Loading agent ecology from the workspace registry...</div>
        </div>
      </aside>

      <section class="panel canvas">
        <div class="active-work">
          <div class="work-hero">
            <div>
              <span id="selected-kind" class="badge ready">visual-first</span>
              <h2 id="work-title">Sounio work, without staring at a terminal.</h2>
              <p id="work-summary" class="subtitle">The terminal still runs underneath Beagle Terminal Protocol v1, but the default surface is a lab bench: lanes, artifacts, memory, proof, and approvals.</p>
            </div>
            <div class="next-move">
              <strong>Next gesture</strong>
              <span id="next-gesture" class="caption">Pick a lane or evidence object.</span>
            </div>
          </div>
          <div class="mission-composer" aria-label="Visual intent composer">
            <div class="panel-title">
              <h2>Visual Intent Composer</h2>
              <span class="caption">Draft an intention. This prototype routes it visually without executing commands or writing canonical memory.</span>
            </div>
            <div class="mission-row">
              <textarea id="intent-input" class="intent-input" spellcheck="true" placeholder="Example: ask Kimi to analyze Sounio Claim<T> semantics, then have MiniMax sketch compiler tests."></textarea>
              <div class="composer-actions">
                <button id="draft-intent-action" class="primary" type="button">Draft Intent</button>
                <button id="route-intent-action" type="button">Route Only</button>
              </div>
            </div>
          </div>
          <div id="route-decision" class="route-decision" aria-label="Route decision"></div>
          <div id="artifact-strip" class="artifact-strip"></div>
        </div>

        <div id="evidence-frontier" class="evidence-frontier">
          <div class="empty">Evidence objects will appear from real Workbench blocks, with restricted output redacted.</div>
        </div>

        <div class="dock">
          <button id="focus-action" class="primary" type="button">Focus</button>
          <button id="scout-action" type="button">Scout</button>
          <button id="compare-action" type="button">Compare</button>
          <button id="remember-action" type="button">Remember</button>
          <button id="approve-action" type="button">Approve</button>
          <button id="interrupt-action" type="button">Interrupt</button>
          <button id="runtime-action" class="ghost" type="button">Show Runtime Log</button>
        </div>
      </section>

      <aside class="panel">
        <div class="panel-header">
          <div class="panel-title">
            <h2>Memory & Proof</h2>
            <span class="caption">What this block became, why it matters, and whether it is safe to remember.</span>
          </div>
          <span id="memory-badge" class="badge">not_saved</span>
        </div>
        <div id="inspector" class="inspector-body"></div>
        <div id="spatial-deck" class="spatial-preview"></div>
        <div id="portal-deck" class="portal-preview"></div>
      </aside>
    </section>
  </main>

  <section id="runtime-panel" class="runtime" aria-label="Runtime Log">
    <div class="panel-header">
      <div class="panel-title">
        <h2>Runtime Log</h2>
        <span id="runtime-subtitle" class="caption">Hidden by default. Opened only when you ask.</span>
      </div>
      <button id="close-runtime" type="button">Close</button>
    </div>
    <pre id="runtime-output">No runtime block selected.</pre>
  </section>

  <script>
    const slug = ${JSON.stringify(slug)};
    const seededRoles = [
      { role: "primary_builder", kind: "codex", title: "Claude / Codex", subtitle: "High-stakes implementation", readiness: { status: "needs_setup", reason: "codex/claude CLI not confirmed in this workspace" } },
      { role: "code_worker", kind: "minimax", title: "MiniMax Worker", subtitle: "Refactors, tests, compiler bugs", readiness: { status: "ready", reason: "provider slot can be configured independently" } },
      { role: "long_thought_architect", kind: "kimi", title: "Kimi Architect", subtitle: "Deep Sounio semantics", readiness: { status: "needs_setup", reason: "kimi CLI/provider not confirmed in this workspace" } },
      { role: "maintenance_agent", kind: "qwen-coder", title: "Qwen Maintainer", subtitle: "Cheap lint and repair loops", readiness: { status: "needs_setup", reason: "Qwen provider not confirmed in this workspace" } },
      { role: "platform_operator", kind: "glm-air", title: "GLM Operator", subtitle: "Kubernetes and incidents", readiness: { status: "needs_setup", reason: "GLM provider not confirmed in this workspace" } },
      { role: "shell", kind: "human", title: "Shell Runtime", subtitle: "Human fallback lane", readiness: { status: "ready", reason: "builtin workspace lane" } }
    ];
    const state = {
      registry: null,
      sessions: [],
      blocks: [],
      roles: seededRoles,
      selectedRole: "primary_builder",
      selectedBlockId: "",
      routeDecision: null,
      loading: true,
      loadError: ""
    };

    const laneBoard = document.getElementById("lane-board");
    const laneCount = document.getElementById("lane-count");
    const artifactStrip = document.getElementById("artifact-strip");
    const evidenceFrontier = document.getElementById("evidence-frontier");
    const inspector = document.getElementById("inspector");
    const selectedKind = document.getElementById("selected-kind");
    const workTitle = document.getElementById("work-title");
    const workSummary = document.getElementById("work-summary");
    const nextGesture = document.getElementById("next-gesture");
    const memoryBadge = document.getElementById("memory-badge");
    const runtimePanel = document.getElementById("runtime-panel");
    const runtimeOutput = document.getElementById("runtime-output");
    const runtimeSubtitle = document.getElementById("runtime-subtitle");
    const fixtureRibbon = document.getElementById("fixture-ribbon");
    const intentInput = document.getElementById("intent-input");
    const spatialDeck = document.getElementById("spatial-deck");
    const routeDecisionPanel = document.getElementById("route-decision");
    const portalDeck = document.getElementById("portal-deck");
    const missionNow = document.getElementById("mission-now");
    const missionRoute = document.getElementById("mission-route");
    const missionEvidence = document.getElementById("mission-evidence");
    const missionSafety = document.getElementById("mission-safety");
    const fixtureSession = {
      id: "fixture-sounio-workday",
      status: "design_fixture",
      panes: [{ id: "pane-agent-deck", kind: "fixture" }]
    };
    const fixtureBlocks = [
      {
        id: "fixture-codex-decision",
        sessionId: "fixture-sounio-workday",
        paneId: "codex-lane",
        title: "Decision: visual-first Workbench",
        command: "codex summary",
        outputPreview: "Decision: Beagle Workbench should open as visual agent lanes, active work canvas, and proof inspector. Runtime logs stay behind an explicit action.",
        privacyClass: "sensitive",
        memoryStatus: "remembered",
        blockHash: "sha256:fixture-visual-workbench-decision",
        bridgeVersion: "beagle-terminal-v1",
        tags: ["design-fixture", "workbench", "agent:codex"]
      },
      {
        id: "fixture-minimax-worker",
        sessionId: "fixture-sounio-workday",
        paneId: "minimax-lane",
        title: "MiniMax worker patch queue",
        command: "minimax refactor",
        outputPreview: "Planned bounded patch: extract VisualAgentLaneSnapshot, classify block signals, and keep restricted output redacted before any memory import.",
        privacyClass: "sensitive",
        memoryStatus: "queued",
        blockHash: "sha256:fixture-minimax-worker",
        bridgeVersion: "beagle-terminal-v1",
        tags: ["design-fixture", "workbench", "agent:minimax"]
      },
      {
        id: "fixture-kimi-semantics",
        sessionId: "fixture-sounio-workday",
        paneId: "kimi-lane",
        title: "Kimi semantic note",
        command: "kimi sounio semantics",
        outputPreview: "Sounio types the work product: intentions, claims, evidence, decisions, and next actions. Beagle observes and preserves provenance.",
        privacyClass: "sensitive",
        memoryStatus: "manual",
        blockHash: "sha256:fixture-kimi-semantics",
        bridgeVersion: "beagle-terminal-v1",
        tags: ["design-fixture", "sounio", "agent:kimi"]
      },
      {
        id: "fixture-test-pass",
        sessionId: "fixture-sounio-workday",
        paneId: "shell-lane",
        title: "Project Cockpit check",
        command: "npm --prefix apps/project-cockpit run check",
        outputPreview: "All Project Cockpit server modules passed node --check. Visual prototype route is syntactically valid.",
        privacyClass: "sensitive",
        memoryStatus: "remembered",
        blockHash: "sha256:fixture-project-cockpit-check",
        bridgeVersion: "beagle-terminal-v1",
        tags: ["design-fixture", "test", "project:sounio"]
      },
      {
        id: "fixture-restricted-redacted",
        sessionId: "fixture-sounio-workday",
        paneId: "shell-lane",
        title: "Restricted block example",
        command: "[redacted]",
        outputPreview: "This should never be visible.",
        privacyClass: "restricted_local_only",
        memoryStatus: "blocked",
        restricted: true,
        blockHash: "sha256:fixture-restricted",
        bridgeVersion: "beagle-terminal-v1",
        tags: ["design-fixture", "restricted"]
      }
    ];

    function activateFixture(reason) {
      state.loadError = reason || "";
      state.sessions = [fixtureSession];
      state.blocks = fixtureBlocks;
      state.selectedBlockId = state.selectedBlockId || fixtureBlocks[0].id;
      fixtureRibbon.classList.add("visible");
    }

    function escapeHtmlClient(value) {
      return String(value == null ? "" : value).replace(/[&<>"']/g, function(char) {
        if (char === "&") return "&amp;";
        if (char === "<") return "&lt;";
        if (char === ">") return "&gt;";
        if (char === '"') return "&quot;";
        if (char === "'") return "&#39;";
        return char;
      });
    }

    function asArray(value) {
      return Array.isArray(value) ? value : [];
    }

    function normalizeStatus(value) {
      const status = String(value || "unknown");
      if (status === "ready" || status === "remembered") return "ready";
      if (status === "blocked" || status === "restricted_local_only") return "blocked";
      if (status === "needs_setup" || status === "failed" || status === "queued") return "warn";
      return "";
    }

    function roleInitial(role) {
      const source = String(role.title || role.role || "?").trim();
      return source ? source.slice(0, 1).toUpperCase() : "?";
    }

    function roleTask(role) {
      const readiness = role.readiness || {};
      const reason = readiness.reason || role.roleSummary || role.subtitle || "Ready for focused work.";
      if (readiness.status === "needs_setup") return "Setup gap: " + reason;
      if (role.role === "shell") return "Runtime available, but kept behind the visual bench.";
      if (role.role === "code_worker") return "Best for compiler bugs, tests, refactors, and bounded edits.";
      if (role.role === "long_thought_architect") return "Best for Sounio semantics, Claim<T>, and language architecture.";
      if (role.role === "platform_operator") return "Best for cluster health, runbooks, incidents, and deploy recovery.";
      if (role.role === "maintenance_agent") return "Best for low-risk patches, lint, and repair loops.";
      return reason;
    }

    function roleHeadline(role) {
      const headlines = {
        primary_builder: "Primary builder lane",
        code_worker: "Code worker lane",
        long_thought_architect: "Semantic architecture lane",
        maintenance_agent: "Maintenance lane",
        platform_operator: "Platform operator lane",
        shell: "Runtime lane"
      };
      return headlines[role.role] || ((role.title || "Agent") + " lane");
    }

    function routeIntentToRole(intent) {
      return routeIntentDetails(intent).role;
    }

    function routeIntentDetails(intent) {
      const text = String(intent || "").toLowerCase();
      if (text.includes("claim") || text.includes("type") || text.includes("semantic") || text.includes("sounio")) {
        return {
          role: "long_thought_architect",
          reason: "Semantic or Sounio-language work needs long thought before edits.",
          arousal: "tonic_explore",
          expected: ["semantic note", "claim seeds", "open questions", "proof needs"]
        };
      }
      if (text.includes("test") || text.includes("refactor") || text.includes("compiler") || text.includes("bug")) {
        return {
          role: "code_worker",
          reason: "Bounded code/test work should go to a worker lane with visible artifacts.",
          arousal: "phasic_focus",
          expected: ["patch sketch", "test command", "diff summary", "memory candidate"]
        };
      }
      if (text.includes("k8s") || text.includes("kubectl") || text.includes("deploy") || text.includes("pod") || text.includes("incident")) {
        return {
          role: "platform_operator",
          reason: "Infrastructure intent needs operator context, approvals, and incident provenance.",
          arousal: "recovering",
          expected: ["runbook step", "cluster check", "approval gate", "incident note"]
        };
      }
      if (text.includes("lint") || text.includes("small patch") || text.includes("maintenance")) {
        return {
          role: "maintenance_agent",
          reason: "Low-risk repair loop can be routed to a maintenance lane.",
          arousal: "phasic_focus",
          expected: ["lint result", "small diff", "test loop", "memory summary"]
        };
      }
      if (text.includes("shell") || text.includes("runtime") || text.includes("log")) {
        return {
          role: "shell",
          reason: "Runtime inspection stays available, but it is no longer the primary surface.",
          arousal: "phasic_focus",
          expected: ["runtime log", "redaction check", "proof link", "manual decision"]
        };
      }
      if (text.includes("promote") || text.includes("portal") || text.includes("chatgpt") || text.includes("claude") || text.includes("grok")) {
        return {
          role: "primary_builder",
          reason: "Conversation clips need a human-selected Portal + Promote path before memory.",
          arousal: "recovering",
          expected: ["selected clip", "redaction", "provenance", "assisted import draft"]
        };
      }
      return {
        role: "primary_builder",
        reason: "High-level or ambiguous work starts with the primary builder lane.",
        arousal: "phasic_focus",
        expected: ["plan", "decision", "diff/test summary", "next action"]
      };
    }

    function laneLabel(roleName) {
      const role = state.roles.find(function(item) { return item.role === roleName; }) || seededRoles.find(function(item) { return item.role === roleName; }) || {};
      return role.title || roleName || "Agent lane";
    }

    function isRestricted(block) {
      const privacy = String(block && block.privacyClass || "").toLowerCase();
      return privacy === "restricted" || privacy === "restricted_local_only" || block && block.restricted === true;
    }

    function blockPreview(block) {
      if (!block) return "";
      if (isRestricted(block)) return "Restricted output redacted. Provenance remains visible.";
      const text = String(block.outputPreview || block.command || block.title || "");
      return text.replace(/\\u001b\\[[0-9;?]*[A-Za-z]/g, "").replace(/[\\r\\n]+/g, " ").trim().slice(0, 360);
    }

    function blockKind(block) {
      const command = String(block && block.command || block && block.title || "").toLowerCase();
      if (command.includes("test") || command.includes("pytest") || command.includes("swift test") || command.includes("cargo test")) return "test";
      if (command.includes("git diff") || command.includes("diff")) return "diff";
      if (command.includes("codex") || command.includes("claude") || command.includes("kimi")) return "agent";
      if (command.includes("kubectl")) return "ops";
      return "command";
    }

    function memoryStatus(block) {
      if (!block) return "not_saved";
      if (block.lastMemoryStatus && block.lastMemoryStatus.status) return block.lastMemoryStatus.status;
      return block.memoryStatus || "not_saved";
    }

    function runtimeContinuity(block) {
      if (block && block.runtimeContinuity && typeof block.runtimeContinuity === "object") {
        return block.runtimeContinuity;
      }
      return {
        status: "unattributed",
        verified: false,
        hasRuntimeEvidence: false,
        transitionLabel: "Unknown transition",
        runtimeAuthority: null,
        supervisorRuntime: null,
        loomInstanceId: null,
        generationFingerprint: null,
        journalVerified: false,
        semanticJournalHead: null,
        guardianJournalHead: null,
        kernelRecoveryCount: 0,
        lineageVerified: false,
        generationLineageHead: null,
        generationTransitionCount: 0,
        podResurrectionCount: 0,
        predecessorInstanceId: null,
        predecessorSemanticJournalHead: null,
        predecessorGuardianJournalHead: null
      };
    }

    function runtimeStatusLabel(continuity) {
      const labels = {
        "verified-initial-generation": "verified initial generation",
        "verified-clean-respawn": "verified clean respawn",
        "verified-pod-resurrection": "verified Pod resurrection",
        "proof-incomplete": "proof incomplete",
        "foreign-runtime": "foreign runtime",
        "unattributed": "unattributed runtime"
      };
      return labels[continuity.status] || "unverified runtime";
    }

    function runtimeBadgeClass(continuity) {
      if (continuity.verified) return "ready";
      return continuity.hasRuntimeEvidence ? "warn" : "blocked";
    }

    function compactRuntimeValue(value) {
      const text = String(value || "");
      if (!text) return "none";
      if (text.length <= 22) return text;
      return text.slice(0, 10) + "..." + text.slice(-8);
    }

    function runtimeContinuitySummary(block) {
      const continuity = runtimeContinuity(block);
      if (continuity.verified) {
        return continuity.transitionLabel + "; generation " + compactRuntimeValue(continuity.loomInstanceId) +
          "; Pod resurrections " + Number(continuity.podResurrectionCount || 0) +
          "; kernel recoveries " + Number(continuity.kernelRecoveryCount || 0) + ".";
      }
      if (continuity.hasRuntimeEvidence) {
        return "Continuity proof incomplete for " + (continuity.runtimeAuthority || "unknown authority") +
          "; transition " + (continuity.transitionLabel || "unknown") + ".";
      }
      return "No runtime continuity receipt is attached to this block.";
    }

    function latestSession() {
      return state.sessions[0] || null;
    }

    function selectedRole() {
      return state.roles.find(function(role) { return role.role === state.selectedRole; }) || state.roles[0] || seededRoles[0];
    }

    function selectedBlock() {
      return state.blocks.find(function(block) { return block.id === state.selectedBlockId; }) || state.blocks[0] || null;
    }

    function renderLaneBoard() {
      const visible = state.roles.filter(function(role) { return role.visible !== false; });
      laneCount.textContent = String(visible.length) + " lanes";
      laneBoard.innerHTML = visible.map(function(role) {
        const readiness = role.readiness || {};
        const readinessStatus = readiness.status || "unknown";
        const selected = role.role === state.selectedRole ? " selected" : "";
        const badgeClass = normalizeStatus(readinessStatus);
        const provider = asArray(role.providerSlots)[0] || {};
        const providerLabel = provider.title || role.kind || role.role;
        return '<button class="lane-card' + selected + '" type="button" data-role="' + escapeHtmlClient(role.role) + '">' +
          '<div class="lane-top">' +
            '<div class="lane-icon">' + escapeHtmlClient(roleInitial(role)) + '</div>' +
            '<div><div class="lane-name">' + escapeHtmlClient(role.title || role.role) + '</div><div class="caption">' + escapeHtmlClient(providerLabel) + '</div></div>' +
            '<span class="badge ' + badgeClass + '">' + escapeHtmlClient(readinessStatus) + '</span>' +
          '</div>' +
          '<div class="lane-task">' + escapeHtmlClient(roleTask(role)) + '</div>' +
          '<div class="lane-meta">' +
            '<span class="pill">' + escapeHtmlClient(role.arousalRole || "phasic_focus") + '</span>' +
            '<span class="pill">' + escapeHtmlClient(role.memoryPolicy || "curated") + '</span>' +
          '</div>' +
        '</button>';
      }).join("");
      laneBoard.querySelectorAll("[data-role]").forEach(function(button) {
        button.addEventListener("click", function() {
          state.selectedRole = button.getAttribute("data-role") || state.selectedRole;
          renderAll();
        });
      });
    }

    function renderArtifacts() {
      const block = selectedBlock();
      const role = selectedRole();
      const continuity = runtimeContinuity(block);
      const artifacts = [
        {
          title: "Active task",
          badge: role.readiness && role.readiness.status || "observed",
          badgeClass: normalizeStatus(role.readiness && role.readiness.status || "observed"),
          body: roleTask(role)
        },
        {
          title: "Latest evidence",
          badge: block ? blockKind(block) : "waiting",
          badgeClass: block ? normalizeStatus(memoryStatus(block)) : "warn",
          body: block ? blockPreview(block) : "No Workbench block selected yet."
        },
        {
          title: "Runtime continuity",
          badge: runtimeStatusLabel(continuity),
          badgeClass: runtimeBadgeClass(continuity),
          body: runtimeContinuitySummary(block)
        }
      ];
      artifactStrip.innerHTML = artifacts.map(function(item) {
        return '<article class="artifact">' +
          '<span class="badge ' + escapeHtmlClient(item.badgeClass || "") + '">' + escapeHtmlClient(item.badge) + '</span>' +
          '<div class="artifact-title">' + escapeHtmlClient(item.title) + '</div>' +
          '<div class="artifact-body">' + escapeHtmlClient(item.body) + '</div>' +
        '</article>';
      }).join("");
    }

    function renderEvidence() {
      if (!state.blocks.length) {
        evidenceFrontier.innerHTML = '<div class="empty">No blocks found yet. Start work in the existing runtime launchpad, then return here for the visual bench.</div>';
        return;
      }
      evidenceFrontier.innerHTML = state.blocks.slice(0, 12).map(function(block) {
        const selected = block.id === state.selectedBlockId ? " selected" : "";
        const restricted = isRestricted(block);
        const badgeClass = restricted ? "blocked" : normalizeStatus(memoryStatus(block));
        return '<button class="evidence-item' + selected + '" type="button" data-block="' + escapeHtmlClient(block.id || "") + '">' +
          '<div class="lane-meta">' +
            '<span class="badge ' + badgeClass + '">' + escapeHtmlClient(memoryStatus(block)) + '</span>' +
            '<span class="pill">' + escapeHtmlClient(blockKind(block)) + '</span>' +
            '<span class="pill">' + escapeHtmlClient(block.privacyClass || "sensitive") + '</span>' +
          '</div>' +
          '<div class="artifact-title">' + escapeHtmlClient(block.title || block.command || block.id || "Workbench block") + '</div>' +
          '<div class="artifact-body">' + escapeHtmlClient(blockPreview(block)) + '</div>' +
        '</button>';
      }).join("");
      evidenceFrontier.querySelectorAll("[data-block]").forEach(function(button) {
        button.addEventListener("click", function() {
          state.selectedBlockId = button.getAttribute("data-block") || state.selectedBlockId;
          renderAll();
        });
      });
    }

    function renderCanvas() {
      const role = selectedRole();
      const block = selectedBlock();
      selectedKind.textContent = role.title || role.role || "Agent lane";
      const status = role.readiness && role.readiness.status || "unknown";
      selectedKind.className = "badge " + normalizeStatus(status);
      workTitle.textContent = roleHeadline(role);
      workSummary.textContent = roleTask(role);
      if (block) {
        nextGesture.textContent = memoryStatus(block) === "remembered" ? "Open proof or compare provenance." : "Review evidence, then remember only if useful.";
      } else if (state.loadError) {
        nextGesture.textContent = "Live fetch degraded; use this as the visual contract, then reconnect to cluster.";
      } else {
        nextGesture.textContent = status === "needs_setup" ? "Keep lane visible as a setup gap; do not auto-install." : "Choose evidence or start a focused work block.";
      }
    }

    function renderInspector() {
      const block = selectedBlock();
      const role = selectedRole();
      const status = memoryStatus(block);
      memoryBadge.textContent = status;
      memoryBadge.className = "badge " + normalizeStatus(status);
      if (!block) {
        inspector.innerHTML = '<div class="empty">' + escapeHtmlClient(state.loadError || "Select a block to inspect memory status, provenance, privacy, and runtime linkage.") + '</div>';
        return;
      }
      const restricted = isRestricted(block);
      const continuity = runtimeContinuity(block);
      inspector.innerHTML =
        '<article class="memory-item">' +
          '<span class="badge ' + (restricted ? "blocked" : normalizeStatus(status)) + '">' + escapeHtmlClient(restricted ? "restricted redacted" : status) + '</span>' +
          '<div class="memory-title">' + escapeHtmlClient(block.title || block.command || block.id || "Workbench block") + '</div>' +
          '<div class="memory-body">' + escapeHtmlClient(blockPreview(block)) + '</div>' +
        '</article>' +
        '<article class="memory-item">' +
          '<div class="memory-title">Sounio typing candidate</div>' +
          '<div class="memory-body">' + escapeHtmlClient(restricted ? "Blocked from automatic typing. Requires explicit review." : "Candidate SounioMoment only. Claims remain belief/contest until evidence and provenance support promotion.") + '</div>' +
        '</article>' +
        '<article class="memory-item" data-runtime-continuity="' + escapeHtmlClient(continuity.status || "unattributed") + '">' +
          '<div class="lane-meta">' +
            '<span class="badge ' + runtimeBadgeClass(continuity) + '">' + escapeHtmlClient(runtimeStatusLabel(continuity)) + '</span>' +
            '<span class="pill">' + escapeHtmlClient(continuity.runtimeAuthority || "no authority") + '</span>' +
          '</div>' +
          '<div class="memory-title">Runtime continuity</div>' +
          '<div class="memory-body">' + escapeHtmlClient(runtimeContinuitySummary(block)) + '</div>' +
          '<div class="kv"><span>transition</span><strong>' + escapeHtmlClient(continuity.transitionLabel || "Unknown transition") + '</strong></div>' +
          '<div class="kv"><span>runtime</span><strong>' + escapeHtmlClient(continuity.supervisorRuntime || "unattributed") + '</strong></div>' +
          '<div class="kv"><span>generation</span><strong>' + escapeHtmlClient(continuity.loomInstanceId || "none") + '</strong></div>' +
          '<div class="kv"><span>fingerprint</span><strong>' + escapeHtmlClient(continuity.generationFingerprint || "none") + '</strong></div>' +
          '<div class="kv"><span>predecessor</span><strong>' + escapeHtmlClient(continuity.predecessorInstanceId || "not applicable") + '</strong></div>' +
          '<div class="kv"><span>lineage head</span><strong>' + escapeHtmlClient(continuity.generationLineageHead || "not applicable") + '</strong></div>' +
          '<div class="kv"><span>journal proof</span><strong>' + escapeHtmlClient(continuity.journalVerified ? "verified" : "unverified") + '</strong></div>' +
          '<div class="kv"><span>semantic head</span><strong>' + escapeHtmlClient(continuity.semanticJournalHead || "none") + '</strong></div>' +
          '<div class="kv"><span>guardian head</span><strong>' + escapeHtmlClient(continuity.guardianJournalHead || "none") + '</strong></div>' +
          '<div class="kv"><span>lineage proof</span><strong>' + escapeHtmlClient(continuity.lineageVerified ? "verified" : "unverified") + '</strong></div>' +
          '<div class="kv"><span>prior semantic</span><strong>' + escapeHtmlClient(continuity.predecessorSemanticJournalHead || "not applicable") + '</strong></div>' +
          '<div class="kv"><span>prior guardian</span><strong>' + escapeHtmlClient(continuity.predecessorGuardianJournalHead || "not applicable") + '</strong></div>' +
          '<div class="kv"><span>transitions</span><strong>' + escapeHtmlClient(String(continuity.generationTransitionCount || 0)) + '</strong></div>' +
          '<div class="kv"><span>Pod recoveries</span><strong>' + escapeHtmlClient(String(continuity.podResurrectionCount || 0)) + '</strong></div>' +
          '<div class="kv"><span>kernel recoveries</span><strong>' + escapeHtmlClient(String(continuity.kernelRecoveryCount || 0)) + '</strong></div>' +
        '</article>' +
        '<article class="memory-item">' +
          '<div class="memory-title">Provenance</div>' +
          '<div class="kv"><span>role</span><strong>' + escapeHtmlClient(role.role || "") + '</strong></div>' +
          '<div class="kv"><span>session</span><strong>' + escapeHtmlClient(block.sessionId || "") + '</strong></div>' +
          '<div class="kv"><span>pane</span><strong>' + escapeHtmlClient(block.paneId || "") + '</strong></div>' +
          '<div class="kv"><span>block</span><strong>' + escapeHtmlClient(block.id || "") + '</strong></div>' +
          '<div class="kv"><span>hash</span><strong>' + escapeHtmlClient(block.blockHash || "pending") + '</strong></div>' +
          '<div class="kv"><span>bridge</span><strong>' + escapeHtmlClient(block.bridgeVersion || "beagle-terminal-v1") + '</strong></div>' +
          '<div class="kv"><span>source</span><strong>' + escapeHtmlClient(block.id && block.id.startsWith("fixture-") ? "visual fixture, not canonical" : "live workspace") + '</strong></div>' +
        '</article>';
    }

    function renderSpatialDeck() {
      const role = selectedRole();
      const block = selectedBlock();
      const blockLabel = block ? block.title || block.command || block.id : "No selected evidence";
      spatialDeck.innerHTML =
        '<div class="panel-title">' +
          '<h2>visionOS Agent Deck preview</h2>' +
          '<span class="caption">Same state, mapped to spatial instruments later. No Marble dependency for this acceptance slice.</span>' +
        '</div>' +
        '<div class="spatial-zones">' +
          '<div class="spatial-zone"><strong>Central desk</strong><span>' + escapeHtmlClient(roleHeadline(role)) + '</span></div>' +
          '<div class="spatial-zone"><strong>Agent rail</strong><span>' + escapeHtmlClient(laneLabel(role.role)) + '</span></div>' +
          '<div class="spatial-zone"><strong>Evidence wall</strong><span>' + escapeHtmlClient(blockLabel) + '</span></div>' +
          '<div class="spatial-zone"><strong>Runtime corridor</strong><span>Collapsed until explicitly opened.</span></div>' +
        '</div>';
    }

    function renderRouteDecision() {
      const decision = state.routeDecision;
      if (!decision) {
        routeDecisionPanel.classList.remove("visible");
        routeDecisionPanel.innerHTML = "";
        return;
      }
      const expected = decision.expected || [];
      routeDecisionPanel.classList.add("visible");
      routeDecisionPanel.innerHTML =
        '<div class="panel-title">' +
          '<h2>Route decision</h2>' +
          '<span class="caption">' + escapeHtmlClient(decision.reason || "") + '</span>' +
        '</div>' +
        '<div class="lane-meta">' +
          '<span class="badge ready">' + escapeHtmlClient(laneLabel(decision.role)) + '</span>' +
          '<span class="pill">' + escapeHtmlClient(decision.arousal || "phasic_focus") + '</span>' +
          '<span class="pill">privacy: sensitive review</span>' +
          '<span class="pill">no command execution</span>' +
        '</div>' +
        '<div class="workflow-steps">' +
          expected.map(function(item, index) {
            return '<div class="workflow-step"><strong>' + escapeHtmlClient("artifact " + (index + 1)) + '</strong><span>' + escapeHtmlClient(item) + '</span></div>';
          }).join("") +
        '</div>';
    }

    function renderPortals() {
      const portals = [
        { title: "Claude / Claude Code", mode: "Portal + Promote", detail: "Reference conversation or coding run; promote selected clip only after redaction." },
        { title: "ChatGPT", mode: "Portal + Promote", detail: "No invisible scraping. Import selected exchange/export with provenance." },
        { title: "Grok / other chats", mode: "Manual import", detail: "Conversation stays outside Beagle until explicitly promoted." }
      ];
      portalDeck.innerHTML =
        '<div class="panel-title">' +
          '<h2>Conversation portals</h2>' +
          '<span class="caption">Separate from terminal. External chats become memory only by Promote.</span>' +
        '</div>' +
        '<div class="portal-grid">' +
          portals.map(function(portal) {
            return '<div class="portal-card">' +
              '<div class="lane-meta"><span class="badge">' + escapeHtmlClient(portal.mode) + '</span></div>' +
              '<strong>' + escapeHtmlClient(portal.title) + '</strong>' +
              '<span>' + escapeHtmlClient(portal.detail) + '</span>' +
            '</div>';
          }).join("") +
        '</div>';
    }

    function renderMissionStrip() {
      const role = selectedRole();
      const block = selectedBlock();
      const decision = state.routeDecision;
      missionNow.textContent = decision ? "Intent drafted" : "Sounio Workday";
      missionRoute.textContent = decision ? laneLabel(decision.role) + " / " + (decision.arousal || "phasic_focus") : roleHeadline(role);
      missionEvidence.textContent = block ? (block.title || block.command || block.id || "Selected block") : "Waiting for block";
      if (block && isRestricted(block)) {
        missionSafety.textContent = "Restricted redacted";
      } else if (block && block.id && block.id.startsWith("fixture-")) {
        missionSafety.textContent = "Visual fixture, not canonical";
      } else {
        missionSafety.textContent = "Cluster-only memory";
      }
    }

    function renderRuntime() {
      const block = selectedBlock();
      if (!block) {
        runtimeSubtitle.textContent = "No runtime block selected.";
        runtimeOutput.textContent = "No runtime block selected.";
        return;
      }
      runtimeSubtitle.textContent = (block.sessionId || "session") + " / " + (block.paneId || "pane") + " / " + (block.id || "block");
      runtimeOutput.textContent = isRestricted(block) ? "Restricted output redacted. Runtime content is intentionally hidden." : String(block.outputPreview || block.command || "No runtime output preview available.");
    }

    function renderAll() {
      renderLaneBoard();
      renderArtifacts();
      renderEvidence();
      renderCanvas();
      renderInspector();
      renderRuntime();
      renderSpatialDeck();
      renderRouteDecision();
      renderPortals();
      renderMissionStrip();
    }

    function draftIntent(shouldCreateBlock) {
      const intent = String(intentInput.value || "").trim() || "Plan the next Sounio workday step visually, then preserve proof and memory only after review.";
      const decision = routeIntentDetails(intent);
      const targetRole = decision.role;
      state.routeDecision = decision;
      state.selectedRole = targetRole;
      nextGesture.textContent = "Routed to " + laneLabel(targetRole) + ".";
      if (shouldCreateBlock) {
        const id = "fixture-intent-" + Date.now();
        state.blocks.unshift({
          id,
          sessionId: "fixture-sounio-workday",
          paneId: targetRole + "-lane",
          title: "Operator visual intent",
          command: "visual intent",
          outputPreview: intent,
          privacyClass: "sensitive",
          memoryStatus: "manual",
          blockHash: "sha256:" + id,
          bridgeVersion: "beagle-visual-workbench-v2",
          tags: ["design-fixture", "operator-intent", "role:" + targetRole]
        });
        state.sessions = state.sessions.length ? state.sessions : [fixtureSession];
        state.selectedBlockId = id;
        fixtureRibbon.classList.add("visible");
      }
      renderAll();
    }

    async function getJson(url) {
      const response = await fetch(url, { headers: { accept: "application/json" } });
      if (!response.ok) throw new Error(url + " returned " + response.status);
      return response.json();
    }

    async function refresh() {
      document.getElementById("refresh").disabled = true;
      try {
        state.loadError = "";
        fixtureRibbon.classList.remove("visible");
        const registry = await getJson("/api/workspaces/" + encodeURIComponent(slug) + "/agents/registry");
        state.registry = registry;
        const visibleRoles = asArray(registry.roles).filter(function(role) {
          return role.visible !== false || asArray(registry.visibleRoles).includes(role.role);
        });
        state.roles = visibleRoles.length ? visibleRoles : seededRoles;

        const sessionsPayload = await getJson("/api/workspaces/" + encodeURIComponent(slug) + "/sessions");
        state.sessions = asArray(sessionsPayload.sessions);
        const session = latestSession();
        if (session) {
          const blocksPayload = await getJson("/api/workspaces/" + encodeURIComponent(slug) + "/sessions/" + encodeURIComponent(session.id) + "/blocks");
          state.blocks = asArray(blocksPayload.blocks);
          state.selectedBlockId = state.selectedBlockId || (state.blocks[0] && state.blocks[0].id) || "";
        }
        renderAll();
      } catch (error) {
        state.roles = seededRoles;
        activateFixture("Could not load live workspace data: " + String(error.message || error));
        renderAll();
      } finally {
        document.getElementById("refresh").disabled = false;
      }
    }

    document.getElementById("runtime-action").addEventListener("click", function() {
      runtimePanel.classList.add("open");
      renderRuntime();
    });
    document.getElementById("close-runtime").addEventListener("click", function() {
      runtimePanel.classList.remove("open");
    });
    document.getElementById("focus-action").addEventListener("click", function() {
      nextGesture.textContent = "Focused on " + (selectedRole().title || selectedRole().role || "lane") + ". Runtime stays hidden until requested.";
    });
    document.getElementById("scout-action").addEventListener("click", function() {
      nextGesture.textContent = "Scout mode: compare a thought lane before touching runtime.";
    });
    document.getElementById("compare-action").addEventListener("click", function() {
      window.location.href = "/projects/" + encodeURIComponent(slug) + "/warp";
    });
    document.getElementById("remember-action").addEventListener("click", function() {
      nextGesture.textContent = "Use existing remember endpoint from the runtime launchpad for this prototype; this view stays read-only.";
    });
    document.getElementById("approve-action").addEventListener("click", function() {
      nextGesture.textContent = "Approval is represented visually here; destructive/runtime approval remains gated by workspace-agent.";
    });
    document.getElementById("interrupt-action").addEventListener("click", function() {
      nextGesture.textContent = "Interrupt is intentionally not sent from this read-only visual prototype.";
    });
    document.getElementById("draft-intent-action").addEventListener("click", function() {
      draftIntent(true);
    });
    document.getElementById("route-intent-action").addEventListener("click", function() {
      draftIntent(false);
    });
    document.querySelectorAll("[data-quick-intent]").forEach(function(button) {
      button.addEventListener("click", function() {
        intentInput.value = button.getAttribute("data-quick-intent") || "";
        draftIntent(false);
      });
    });
    document.getElementById("refresh").addEventListener("click", refresh);
    renderAll();
    refresh();
  </script>
</body>
</html>`;
}

function readRendererProbeResults(projectSlug) {
  const candidateDirs = [
    cleanValue(process.env.PROJECT_COCKPIT_RENDERER_PROBE_DIR),
    path.join("/workspace/.beagle/workbench/renderer-probes", projectSlug),
    path.join("/workspace/.beagle/workbench/renderer-probes"),
    path.resolve(rootDir, "..", "warp-workbench", "renderer", "results", projectSlug),
    path.resolve(rootDir, "..", "warp-workbench", "renderer", "results"),
  ].filter(Boolean);
  const seen = new Set();
  const files = [];
  for (const dir of candidateDirs) {
    if (!existsSync(dir) || seen.has(dir)) continue;
    seen.add(dir);
    try {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (!entry.isFile() || !entry.name.endsWith(".json")) continue;
        const file = path.join(dir, entry.name);
        const stat = statSync(file);
        files.push({ file, mtimeMs: stat.mtimeMs });
      }
    } catch (_error) {
      // Probe results are optional and derived; unreadable paths degrade to not_measured.
    }
  }
  files.sort((a, b) => b.mtimeMs - a.mtimeMs);
  const results = [];
  for (const item of files.slice(0, 8)) {
    try {
      const payload = JSON.parse(readFileSync(item.file, "utf8"));
      const notes = Array.isArray(payload.fidelity_notes)
        ? payload.fidelity_notes.slice(0, 4).map((note) => String(note).slice(0, 260))
        : [];
      results.push({
        file: path.basename(item.file),
        updatedAt: new Date(item.mtimeMs).toISOString(),
        schemaVersion: payload.schema_version || "unknown",
        status: payload.status || "unknown",
        platform: payload.platform || "unknown",
        arch: payload.arch || "unknown",
        renderer: payload.renderer?.name || "warp-metal-probe",
        promoted: Boolean(payload.renderer?.promoted),
        hotPath: payload.renderer?.hot_path || "beagle-terminal-v1",
        bridgeVersion: payload.bridge?.version || "beagle-warp-bridge-v0.2",
        vendorCommit: payload.bridge?.vendor_commit || "805b3e2a576e689a1e414f01ed3fc51e9e704d69",
        fixture: payload.fixture
          ? {
              blockId: payload.fixture.block_id || "",
              privacyClass: payload.fixture.privacy_class || "",
              restrictedRedacted: Boolean(payload.fixture.restricted_redacted),
              outputPreviewBytes: payload.fixture.output_preview_bytes ?? null,
            }
          : null,
        timingMs: payload.timing_ms?.total ?? null,
        vtFidelity: payload.vt_fidelity
          ? {
              status: payload.vt_fidelity.status || "unknown",
              mode: payload.vt_fidelity.mode || "unknown",
              ratios: payload.vt_fidelity.ratios || {},
              expected: payload.vt_fidelity.expected || {},
              observed: payload.vt_fidelity.observed || {},
              notes: Array.isArray(payload.vt_fidelity.notes)
                ? payload.vt_fidelity.notes.slice(0, 4).map((note) => String(note).slice(0, 260))
                : [],
            }
          : null,
        latencyBudget: payload.latency_budget
          ? {
              status: payload.latency_budget.status || "unknown",
              totalMs: payload.latency_budget.total_ms ?? null,
              thresholdMs: payload.latency_budget.threshold_ms ?? null,
              scope: payload.latency_budget.scope || "unknown",
              note: payload.latency_budget.note || "",
            }
          : null,
        fidelityNotes: notes,
        artifact: payload.artifact_path ? path.basename(String(payload.artifact_path)) : null,
      });
    } catch (_error) {
      results.push({
        file: path.basename(item.file),
        updatedAt: new Date(item.mtimeMs).toISOString(),
        schemaVersion: "unknown",
        status: "unreadable",
        platform: "unknown",
        arch: "unknown",
        renderer: "unknown",
        promoted: false,
        hotPath: "beagle-terminal-v1",
        bridgeVersion: "beagle-warp-bridge-v0.2",
        vendorCommit: "805b3e2a576e689a1e414f01ed3fc51e9e704d69",
        fixture: null,
        timingMs: null,
        fidelityNotes: ["Probe result JSON could not be parsed."],
        artifact: null,
      });
    }
  }
  return {
    state: results.length ? "measured" : "not_measured",
    searchedDirs: Array.from(seen).map((dir) => path.basename(dir)),
    latest: results[0] || null,
    results,
  };
}

function safeArtifactPart(value) {
  return String(value || "sample")
    .replace(/[^a-zA-Z0-9_.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 96) || "sample";
}

function restrictedLookingText(value) {
  const text = String(value || "").toLowerCase();
  return (
    text.includes("client_secret") ||
    text.includes("refresh_token") ||
    text.includes("private key") ||
    text.includes("-----begin") ||
    text.includes("bearer ") ||
    text.includes("api_key") ||
    text.includes("password:") ||
    text.includes("passwd") ||
    /\bsk-[a-z0-9]{20,}/i.test(text) ||
    /\bghp_[a-z0-9_]{20,}/i.test(text)
  );
}

function appleDevicePassDirs(projectSlug) {
  const base = cleanValue(process.env.PROJECT_COCKPIT_APPLE_DEVICE_PASS_DIR)
    || (cleanValue(process.env.PROJECT_COCKPIT_RENDERER_PROBE_DIR)
      ? path.join(cleanValue(process.env.PROJECT_COCKPIT_RENDERER_PROBE_DIR), "apple-device-pass")
      : path.join("/tmp", "project-cockpit", "apple-device-pass"));
  return [
    path.join(base, projectSlug),
    base,
    path.join("/workspace/.beagle/workbench/apple-device-pass", projectSlug),
    path.join("/workspace/.beagle/workbench/apple-device-pass"),
    path.resolve(rootDir, "apple-device-pass", projectSlug),
    path.resolve(rootDir, "apple-device-pass"),
  ].filter(Boolean);
}

function normalizeAppleDevicePass(projectSlug, body = {}) {
  const notes = cleanValue(body.notes).slice(0, 600);
  if (restrictedLookingText(notes)) {
    const error = new Error("device pass notes look restricted; redact before upload");
    error.statusCode = 400;
    throw error;
  }
  const humanScoreRaw = Number(body.human_score ?? body.humanScore ?? 0);
  const humanScore = Number.isFinite(humanScoreRaw)
    ? Math.max(1, Math.min(5, Math.round(humanScoreRaw)))
    : null;
  const viewportWidth = Number(body.viewport_width ?? body.viewportWidth ?? 0);
  const inputToPaintMs = Number(body.input_to_paint_ms ?? body.inputToPaintMs ?? 0);
  const dynamicTypeReady = body.dynamic_type_ready ?? body.dynamicTypeReady ?? true;
  const touchTargetReady = body.touch_target_ready ?? body.touchTargetReady ?? true;
  const restrictedLeakCheck = cleanValue(body.restricted_leak_check || body.restrictedLeakCheck || "passed:no_restricted_output");
  const vtFidelityStatus = cleanValue(body.vt_fidelity_status || body.vtFidelityStatus || "not_measured");
  const latencyStatus = cleanValue(body.latency_status || body.latencyStatus || "not_measured");
  const blockers = Array.isArray(body.blockers)
    ? body.blockers.map((item) => cleanValue(item).slice(0, 160)).filter(Boolean).slice(0, 12)
    : [];
  const computedBlockers = [...blockers];
  if (!humanScore || humanScore < 4) computedBlockers.push("human device score below 4");
  if (restrictedLeakCheck !== "passed:no_restricted_output") computedBlockers.push("restricted leak check failed");
  if (vtFidelityStatus !== "pass") computedBlockers.push("VT fidelity not passed");
  if (latencyStatus !== "pass") computedBlockers.push("latency budget not passed");
  if (!dynamicTypeReady) computedBlockers.push("large Dynamic Type not verified");
  if (!touchTargetReady) computedBlockers.push("touch targets below 44pt");

  const gateStatus = computedBlockers.length ? "needs_human_device_pass" : "device_pass";
  return {
    schema_version: "beagle-apple-device-pass-v0.1",
    project_slug: projectSlug,
    sample_id: cleanValue(body.sample_id || body.sampleId || ""),
    session_id: cleanValue(body.session_id || body.sessionId || ""),
    block_id: cleanValue(body.block_id || body.blockId || ""),
    selected_candidate: cleanValue(body.selected_candidate || body.selectedCandidate || "beagle-terminal-v1"),
    device: {
      platform: cleanValue(body.device?.platform || body.platform || "apple"),
      form_factor: cleanValue(body.device?.form_factor || body.form_factor || body.formFactor || "unknown"),
      os_version: cleanValue(body.device?.os_version || body.os_version || body.osVersion || ""),
      build: cleanValue(body.device?.build || body.build || ""),
    },
    gate_status: gateStatus,
    viewport_width: Number.isFinite(viewportWidth) && viewportWidth > 0 ? viewportWidth : null,
    dynamic_type_ready: Boolean(dynamicTypeReady),
    touch_target_ready: Boolean(touchTargetReady),
    input_to_paint_ms: Number.isFinite(inputToPaintMs) && inputToPaintMs > 0 ? Math.round(inputToPaintMs * 100) / 100 : null,
    human_score: humanScore,
    restricted_leak_check: restrictedLeakCheck,
    vt_fidelity_status: vtFidelityStatus,
    latency_status: latencyStatus,
    blockers: Array.from(new Set(computedBlockers)).slice(0, 12),
    notes,
    promotion_allowed: false,
    canonical_memory_written: false,
    created_at: cleanValue(body.created_at || body.createdAt) || new Date().toISOString(),
  };
}

function readAppleDevicePassResults(projectSlug) {
  const seen = new Set();
  const files = [];
  for (const dir of appleDevicePassDirs(projectSlug)) {
    if (!existsSync(dir) || seen.has(dir)) continue;
    seen.add(dir);
    try {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (!entry.isFile() || !entry.name.endsWith(".json")) continue;
        const file = path.join(dir, entry.name);
        const stat = statSync(file);
        files.push({ file, mtimeMs: stat.mtimeMs });
      }
    } catch (_error) {
      // Device pass evidence is optional and derived.
    }
  }
  files.sort((a, b) => b.mtimeMs - a.mtimeMs);
  const results = [];
  for (const item of files.slice(0, 8)) {
    try {
      const payload = JSON.parse(readFileSync(item.file, "utf8"));
      results.push({
        file: path.basename(item.file),
        updatedAt: new Date(item.mtimeMs).toISOString(),
        schemaVersion: payload.schema_version || "unknown",
        status: payload.gate_status || payload.status || "unknown",
        sampleId: payload.sample_id || "",
        sessionId: payload.session_id || "",
        blockId: payload.block_id || "",
        selectedCandidate: payload.selected_candidate || "",
        device: payload.device || {},
        viewportWidth: payload.viewport_width ?? null,
        inputToPaintMs: payload.input_to_paint_ms ?? null,
        humanScore: payload.human_score ?? null,
        restrictedLeakCheck: payload.restricted_leak_check || "unknown",
        vtFidelityStatus: payload.vt_fidelity_status || "unknown",
        latencyStatus: payload.latency_status || "unknown",
        blockers: Array.isArray(payload.blockers) ? payload.blockers.slice(0, 12) : [],
        promotionAllowed: Boolean(payload.promotion_allowed),
        canonicalMemoryWritten: Boolean(payload.canonical_memory_written),
        notes: cleanValue(payload.notes).slice(0, 600),
      });
    } catch (_error) {
      results.push({
        file: path.basename(item.file),
        updatedAt: new Date(item.mtimeMs).toISOString(),
        schemaVersion: "unknown",
        status: "unreadable",
        sampleId: "",
        sessionId: "",
        blockId: "",
        selectedCandidate: "",
        device: {},
        viewportWidth: null,
        inputToPaintMs: null,
        humanScore: null,
        restrictedLeakCheck: "unknown",
        vtFidelityStatus: "unknown",
        latencyStatus: "unknown",
        blockers: ["device pass result JSON could not be parsed"],
        promotionAllowed: false,
        canonicalMemoryWritten: false,
        notes: "",
      });
    }
  }
  return {
    state: results.length ? "measured" : "not_measured",
    searchedDirs: Array.from(seen).map((dir) => path.basename(dir)),
    latest: results[0] || null,
    results,
  };
}

async function writeAppleDevicePassResult(projectSlug, body) {
  const payload = normalizeAppleDevicePass(projectSlug, body);
  const dir = appleDevicePassDirs(projectSlug)[0];
  await fs.mkdir(dir, { recursive: true, mode: 0o700 });
  const stem = safeArtifactPart(payload.sample_id || payload.block_id || "device-pass");
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const file = path.join(dir, `${timestamp}-${stem}.json`);
  await fs.writeFile(file, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
  return {
    status: "recorded",
    file: path.basename(file),
    result: payload,
    truthMode: "observed",
  };
}

function renderWarpBridgeLabPage(project) {
  const slug = project.projectSlug || project.slug || "sounio";
  const title = `${project.title || slug} Warp Bridge Lab`;
  const authority = project.workbench?.authority || project.workspace?.authority || "workspace-agent";
  const namespace = project.namespace || "beagle";
  const vendorCommit = "805b3e2a576e689a1e414f01ed3fc51e9e704d69";
  const bridgeVersion = "beagle-warp-bridge-v0.2";
  const rendererProbeResults = readRendererProbeResults(slug);
  const appleDevicePassResults = readAppleDevicePassResults(slug);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #07090d;
      --panel: rgba(255,255,255,0.07);
      --panel2: rgba(255,255,255,0.045);
      --line: rgba(255,255,255,0.16);
      --text: #f4f7fb;
      --muted: #a7b1c2;
      --accent: #75d6ff;
      --ok: #8df3b3;
      --warn: #ffd580;
      --danger: #ff9aa8;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background: radial-gradient(circle at top left, rgba(117,214,255,0.16), transparent 34rem), var(--bg);
      color: var(--text);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    main { width: min(100vw - 32px, 1180px); margin: 0 auto; padding: 34px 0 42px; }
    header, section {
      border: 1px solid var(--line);
      border-radius: 10px;
      background: linear-gradient(180deg, var(--panel), var(--panel2));
      padding: 18px;
      backdrop-filter: blur(18px);
    }
    header { margin-bottom: 16px; }
    .eyebrow { color: var(--accent); text-transform: uppercase; letter-spacing: .12em; font-size: 12px; margin: 0 0 8px; }
    h1 { margin: 0; font-size: clamp(34px, 5vw, 64px); letter-spacing: 0; }
    h2 { margin: 0 0 12px; font-size: 18px; }
    p { color: var(--muted); line-height: 1.55; }
    a { color: inherit; }
    .meta, .actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 14px; }
    .pill, a.button, button {
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 8px 11px;
      background: rgba(0,0,0,0.18);
      color: var(--text);
      text-decoration: none;
      font: inherit;
    }
    button, a.button { cursor: pointer; }
    button.primary, a.primary { background: rgba(117,214,255,0.18); border-color: rgba(117,214,255,0.42); }
    .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
    .compare-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
    .full { grid-column: 1 / -1; }
    .select-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto;
      gap: 10px;
      margin: 12px 0;
    }
    select {
      width: 100%;
      min-width: 0;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 10px 11px;
      background: rgba(0,0,0,0.28);
      color: var(--text);
      font: inherit;
    }
    .row {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 14px;
      padding: 9px 0;
      border-bottom: 1px solid rgba(255,255,255,0.08);
    }
    .row:last-child { border-bottom: 0; }
    .row span { color: var(--muted); }
    .row strong { text-align: right; overflow-wrap: anywhere; }
    .ok { color: var(--ok); }
    .warn { color: var(--warn); }
    .danger { color: var(--danger); }
    .column {
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 12px;
      background: rgba(0,0,0,0.18);
      min-width: 0;
    }
    .column h3, .memo h3 { margin: 0 0 10px; font-size: 15px; }
    .memo {
      border: 1px solid rgba(117,214,255,0.25);
      background: rgba(117,214,255,0.08);
      border-radius: 8px;
      padding: 12px;
    }
    .field-list {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
      margin-top: 12px;
    }
    .field {
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 8px;
      background: rgba(0,0,0,0.18);
      overflow-wrap: anywhere;
    }
    .field strong { display: block; font-size: 12px; color: var(--muted); margin-bottom: 4px; }
    .score-grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
      margin-top: 12px;
    }
    .score-card {
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 10px;
      background: rgba(0,0,0,0.18);
      min-height: 118px;
      display: grid;
      align-content: start;
      gap: 6px;
      overflow-wrap: anywhere;
    }
    .score-card strong { font-size: 13px; }
    .score-card span { color: var(--muted); font-size: 12px; line-height: 1.4; }
    .score-pass { color: var(--ok); }
    .score-pending { color: var(--warn); }
    .score-fail { color: var(--danger); }
    .probe-list {
      display: grid;
      gap: 10px;
      margin-top: 12px;
    }
    .probe-item {
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 10px;
      background: rgba(0,0,0,0.18);
    }
    .probe-item h3 { margin: 0 0 8px; font-size: 14px; }
    .probe-item p { margin: 6px 0 0; font-size: 13px; }
    .memo-grid {
      display: grid;
      grid-template-columns: minmax(0, 1.1fr) minmax(0, .9fr);
      gap: 12px;
      align-items: stretch;
    }
    pre {
      margin: 0;
      min-height: 220px;
      max-height: 50vh;
      overflow: auto;
      white-space: pre-wrap;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgba(0,0,0,0.34);
      padding: 12px;
      color: #eaf2ff;
    }
    @media (max-width: 760px) {
      main { width: min(100vw - 22px, 1180px); padding-top: 22px; }
      .grid { grid-template-columns: 1fr; }
      .compare-grid { grid-template-columns: 1fr; }
      .select-row { grid-template-columns: 1fr; }
      .field-list { grid-template-columns: 1fr; }
      .score-grid, .memo-grid { grid-template-columns: 1fr; }
      h1 { font-size: clamp(30px, 12vw, 46px); }
      .row { display: grid; }
      .row strong { text-align: left; }
      button, a.button { width: 100%; text-align: center; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <p class="eyebrow">Beagle Workbench AGPL Showcase</p>
      <h1>${escapeHtml(title)}</h1>
      <p>This is the visible bridge surface for the Warp-derived Workbench spike. The hot path remains Beagle Terminal Protocol v1; Warp-derived concepts are evaluated through a dual bridge before any renderer authority switch.</p>
      <div class="meta">
        <span class="pill">authority: ${escapeHtml(authority)}</span>
        <span class="pill">namespace: ${escapeHtml(namespace)}</span>
        <span class="pill">bridge: ${escapeHtml(bridgeVersion)}</span>
        <span class="pill">vendor: warp@${escapeHtml(vendorCommit.slice(0, 7))}</span>
        <span class="pill">hot_path=beagle-terminal-v1</span>
        <span class="pill">warp_renderer=not_promoted</span>
        <span class="pill">canonical_memory=cluster-only</span>
      </div>
      <div class="actions">
        <a class="button primary" href="/projects/${encodeURIComponent(slug)}">Open Beagle Workbench</a>
        <a class="button" href="/api/workspaces/${encodeURIComponent(slug)}/sessions">Sessions JSON</a>
        <a class="button" href="/api/workspaces/${encodeURIComponent(slug)}/agents/registry">Agent Registry</a>
      </div>
    </header>

    <div class="grid">
      <section>
        <h2>Boundary</h2>
        <div class="row"><span>Warp source</span><strong>apps/warp-workbench/vendor/warp</strong></div>
        <div class="row"><span>Vendor commit</span><strong>${escapeHtml(vendorCommit)}</strong></div>
        <div class="row"><span>License boundary</span><strong>AGPL-3.0-only</strong></div>
        <div class="row"><span>Core dependency</span><strong class="ok">protocol-only</strong></div>
        <div class="row"><span>Private data</span><strong class="ok">cluster-only</strong></div>
      </section>

      <section>
        <h2>Runtime</h2>
        <div class="row"><span>Workspace authority</span><strong id="authority">Loading...</strong></div>
        <div class="row"><span>Supervisor</span><strong id="supervisor">Loading...</strong></div>
        <div class="row"><span>Sessions</span><strong id="sessions-count">Loading...</strong></div>
        <div class="row"><span>Selected session</span><strong id="selected-session">Loading...</strong></div>
        <div class="row"><span>Selected block</span><strong id="selected-block">Loading...</strong></div>
        <div class="row"><span>Bridge mode</span><strong>dual bridge bake-off</strong></div>
      </section>

      <section class="full">
        <h2>Live Block Selection</h2>
        <div class="select-row">
          <select id="session-select" aria-label="Workbench session"></select>
          <select id="block-select" aria-label="Terminal block"></select>
          <button id="refresh" type="button">Refresh</button>
        </div>
        <div id="privacy-note" class="pill">Loading privacy status...</div>
        <div class="actions">
          <button id="download-fixture" type="button">Download Fixture JSON</button>
          <button id="copy-probe-command" type="button">Copy Probe Command</button>
          <span id="probe-action-note" class="pill">fixture=not_ready</span>
        </div>
      </section>

      <section class="full">
        <h2>Beagle vs Warp-Derived</h2>
        <div class="compare-grid">
          <div class="column">
            <h3>Beagle TerminalBlock</h3>
            <pre id="beagle-preview">Loading...</pre>
          </div>
          <div class="column">
            <h3>WarpBlock Preview</h3>
            <pre id="warp-preview">Loading...</pre>
          </div>
        </div>
        <div id="field-diff" class="field-list"></div>
      </section>

      <section class="full">
        <h2>Bake-off Scorecard</h2>
        <div id="promotion-gate" class="pill">Loading promotion gate...</div>
        <div id="scorecard" class="score-grid"></div>
      </section>

      <section class="full">
        <h2>Renderer Probe Results</h2>
        <div id="renderer-probe-state" class="pill">Loading renderer probe...</div>
        <div id="renderer-probe-results" class="probe-list"></div>
      </section>

      <section class="full">
        <h2>Apple Device Pass Results</h2>
        <div id="apple-device-pass-state" class="pill">Loading Apple device pass...</div>
        <div id="apple-device-pass-results" class="probe-list"></div>
      </section>

      <section class="full">
        <h2>Decision Memo</h2>
        <div class="memo-grid">
          <div id="decision-memo" class="memo">Loading decision memo...</div>
          <pre id="decision-json">Loading decision JSON...</pre>
        </div>
      </section>
    </div>
  </main>

  <script>
    const slug = ${JSON.stringify(slug)};
    const bridgeVersion = ${JSON.stringify(bridgeVersion)};
    const vendorCommit = ${JSON.stringify(vendorCommit)};
    const rendererProbe = ${JSON.stringify(rendererProbeResults)};
    const appleDevicePass = ${JSON.stringify(appleDevicePassResults)};
    const authority = document.getElementById("authority");
    const supervisor = document.getElementById("supervisor");
    const sessionsCount = document.getElementById("sessions-count");
    const selectedSession = document.getElementById("selected-session");
    const selectedBlock = document.getElementById("selected-block");
    const sessionSelect = document.getElementById("session-select");
    const blockSelect = document.getElementById("block-select");
    const refreshButton = document.getElementById("refresh");
    const downloadFixtureButton = document.getElementById("download-fixture");
    const copyProbeCommandButton = document.getElementById("copy-probe-command");
    const probeActionNote = document.getElementById("probe-action-note");
    const privacyNote = document.getElementById("privacy-note");
    const beaglePreview = document.getElementById("beagle-preview");
    const warpPreview = document.getElementById("warp-preview");
    const fieldDiff = document.getElementById("field-diff");
    const promotionGate = document.getElementById("promotion-gate");
    const scorecard = document.getElementById("scorecard");
    const rendererProbeState = document.getElementById("renderer-probe-state");
    const rendererProbeResults = document.getElementById("renderer-probe-results");
    const appleDevicePassState = document.getElementById("apple-device-pass-state");
    const appleDevicePassResults = document.getElementById("apple-device-pass-results");
    const decisionMemo = document.getElementById("decision-memo");
    const decisionJson = document.getElementById("decision-json");
    let state = {
      sessions: [],
      blocksBySession: new Map(),
      selectedSessionId: "",
      selectedBlockId: "",
      currentBeagleBlock: null,
      restrictedAudit: null
    };

    async function apiJson(path) {
      const response = await fetch(path, { headers: { "accept": "application/json" } });
      const text = await response.text();
      let payload;
      try {
        payload = text ? JSON.parse(text) : {};
      } catch (_error) {
        payload = { raw: text };
      }
      if (!response.ok) throw new Error(payload.error || payload.raw || response.statusText);
      return payload;
    }

    function isOperatorSession(session) {
      const title = String(session?.title || "").toLowerCase();
      return !(title.includes("smoke") || title.includes("probe") || title.includes("isolation"));
    }

    function selectSession(list) {
      return list.find(isOperatorSession) || list[0] || null;
    }

    function escapeHtmlClient(value) {
      return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
    }

    function normalizeMemoryStatus(value) {
      const status = String(value || "not_saved");
      if (status === "saved") return "remembered";
      return status;
    }

    function blockPrivacy(block) {
      return String(block?.privacyClass || block?.privacy_class || "sensitive");
    }

    function isRestrictedPrivacy(privacyClass) {
      return privacyClass === "restricted_local_only" || privacyClass === "restricted";
    }

    function sanitizeBlock(block) {
      const privacyClass = blockPrivacy(block);
      const restricted = isRestrictedPrivacy(privacyClass);
      return {
        id: block?.id || "no-live-block-yet",
        sessionId: block?.sessionId || block?.session_id || "",
        paneId: block?.paneId || block?.pane_id || "pane-main",
        kind: block?.kind || "command",
        title: block?.title || block?.command || "Terminal block",
        command: restricted ? "[restricted command redacted]" : (block?.command || ""),
        outputPreview: restricted ? "[restricted output redacted]" : (block?.outputPreview || block?.output_preview || ""),
        outputByteCount: restricted ? null : (block?.outputByteCount || block?.output_byte_count || null),
        startedAt: block?.startedAt || block?.started_at || "",
        finishedAt: block?.finishedAt || block?.finished_at || "",
        durationMs: block?.durationMs ?? block?.duration_ms ?? null,
        exitCode: block?.exitCode ?? block?.exit_code ?? null,
        status: block?.status || "pending",
        privacyClass,
        memoryStatus: normalizeMemoryStatus(block?.memoryStatus || block?.memory_status),
        tags: Array.isArray(block?.tags) ? block.tags : [],
        sourceModel: block?.sourceModel || block?.source_model || "beagle",
        bridgeVersion: block?.bridgeVersion || block?.bridge_version || bridgeVersion,
        blockHash: block?.blockHash || block?.block_hash || null,
        sessionHash: block?.sessionHash || block?.session_hash || null,
        rendererHint: block?.rendererHint || block?.renderer_hint || "beagle-terminal-v1",
        restricted
      };
    }

    function terminalBlockToWarpBlock(block) {
      return {
        id: block.id,
        sessionId: block.sessionId,
        paneId: block.paneId,
        type: block.kind || "command",
        title: block.title || block.command || "Terminal block",
        command: block.command || "",
        outputPreview: block.outputPreview || "",
        status: block.status || "finished",
        memoryStatus: block.memoryStatus || "not_saved",
        provenance: {
          source_model: "beagle",
          bridge_version: bridgeVersion,
          renderer_hint: "warp-derived-preview",
          vendor_commit: vendorCommit,
          block_hash: block.blockHash || null,
          privacy_class: block.privacyClass,
          restricted_redacted: Boolean(block.restricted)
        }
      };
    }

    function warpBlockToTerminalBlock(warpBlock) {
      return {
        id: warpBlock.id,
        sessionId: warpBlock.sessionId,
        paneId: warpBlock.paneId,
        kind: warpBlock.type,
        title: warpBlock.title,
        command: warpBlock.command,
        outputPreview: warpBlock.outputPreview,
        status: warpBlock.status,
        memoryStatus: normalizeMemoryStatus(warpBlock.memoryStatus),
        sourceModel: "warp",
        bridgeVersion,
        rendererHint: "warp-block",
        blockHash: warpBlock.provenance?.block_hash || null
      };
    }

    function preservedFields(beagleBlock, warpBlock, roundTripBlock) {
      const checks = [
        ["id", beagleBlock.id, warpBlock.id, roundTripBlock.id],
        ["session", beagleBlock.sessionId, warpBlock.sessionId, roundTripBlock.sessionId],
        ["pane", beagleBlock.paneId, warpBlock.paneId, roundTripBlock.paneId],
        ["command", beagleBlock.command, warpBlock.command, roundTripBlock.command],
        ["status", beagleBlock.status, warpBlock.status, roundTripBlock.status],
        ["memoryStatus", beagleBlock.memoryStatus, warpBlock.memoryStatus, roundTripBlock.memoryStatus],
        ["provenance", beagleBlock.blockHash || "", warpBlock.provenance?.block_hash || "", roundTripBlock.blockHash || ""],
        ["blockHash", beagleBlock.blockHash || "", warpBlock.provenance?.block_hash || "", roundTripBlock.blockHash || ""]
      ];
      return checks.map(([field, beagle, warp, roundTrip]) => ({
        field,
        beagle,
        warp,
        roundTrip,
        preserved: String(beagle || "") === String(warp || "") && String(warp || "") === String(roundTrip || "")
      }));
    }

    function renderFieldDiff(fields) {
      fieldDiff.innerHTML = fields.map((entry) => (
        '<div class="field">' +
          '<strong>' + escapeHtmlClient(entry.field) + '</strong>' +
          '<span class="' + (entry.preserved ? 'ok' : 'warn') + '">' + (entry.preserved ? 'preserved' : 'changed') + '</span>' +
        '</div>'
      )).join("");
    }

    function metricClass(status) {
      if (status === "pass") return "score-pass";
      if (status === "fail") return "score-fail";
      return "score-pending";
    }

    function buildBakeOffMetrics(beagleBlock, fields) {
      const preservedCount = fields.filter((entry) => entry.preserved).length;
      const hasLiveBlock = beagleBlock.id !== "no-live-block-yet";
      const restrictedSafe = !beagleBlock.restricted || beagleBlock.outputPreview === "[restricted output redacted]";
      const hasProvenance = Boolean(beagleBlock.blockHash || beagleBlock.sessionHash || beagleBlock.bridgeVersion);
      const latestProbe = rendererProbe.latest;
      const probeMeasured = Boolean(latestProbe);
      const vtFidelity = latestProbe?.vtFidelity || null;
      const latencyBudget = latestProbe?.latencyBudget || null;
      const latestDevicePass = appleDevicePass.latest;
      const devicePassMeasured = Boolean(latestDevicePass);
      const secretAudit = state.restrictedAudit || { status: "pending", blockId: "" };
      const secretAuditPass = secretAudit.status === "pass" && secretAudit.outputExposed === false && secretAudit.redacted === true;
      return [
        {
          key: "live_block",
          label: "Live block",
          status: hasLiveBlock ? "pass" : "pending",
          evidence: hasLiveBlock ? "Workbench block selected from cluster replay." : "Run a command, refresh, then select a real block."
        },
        {
          key: "bridge_round_trip",
          label: "Bridge round-trip",
          status: preservedCount === fields.length ? "pass" : "pending",
          evidence: preservedCount + "/" + fields.length + " tracked fields preserved."
        },
        {
          key: "provenance",
          label: "Provenance",
          status: hasProvenance ? "pass" : "pending",
          evidence: hasProvenance ? "Bridge version/hash metadata is present." : "No block/session hash available yet."
        },
        {
          key: "restricted_safety",
          label: "Restricted safety",
          status: restrictedSafe ? "pass" : "fail",
          evidence: beagleBlock.restricted ? "Restricted output redacted before preview." : "Selected block is not restricted."
        },
        {
          key: "memory_authority",
          label: "Memory authority",
          status: "pass",
          evidence: "Bake-off route is read-only; canonical memory remains cluster-only."
        },
        {
          key: "license_boundary",
          label: "AGPL boundary",
          status: "pass",
          evidence: "Project Cockpit consumes protocol previews and does not import Warp-derived code."
        },
        {
          key: "vt_fidelity",
          label: "VT fidelity",
          status: vtFidelity?.status === "pass" ? "pass" : "pending",
          evidence: vtFidelity
            ? "Probe VT audit=" + vtFidelity.status + " mode=" + vtFidelity.mode + "."
            : "Renderer escape-sequence fidelity has not been measured yet."
        },
        {
          key: "renderer_probe",
          label: "Renderer probe",
          status: "pending",
          evidence: probeMeasured
            ? "Latest probe returned " + latestProbe.status + " on " + latestProbe.platform + "/" + latestProbe.arch + "."
            : "No renderer probe result JSON found yet."
        },
        {
          key: "renderer_latency",
          label: "Renderer latency",
          status: latencyBudget?.status === "pass" ? "pass" : "pending",
          evidence: latencyBudget
            ? "Probe conversion latency " + latencyBudget.totalMs + "ms under " + latencyBudget.thresholdMs + "ms; input-to-paint still needs device pass."
            : "Input-to-paint latency still needs iPad/iPhone/macOS measurement."
        },
        {
          key: "apple_usability",
          label: "Apple usability",
          status: latestDevicePass?.status === "device_pass" ? "pass" : "pending",
          evidence: devicePassMeasured
            ? "Latest Apple device pass=" + latestDevicePass.status + " score=" + (latestDevicePass.humanScore || "pending") + " form=" + (latestDevicePass.device?.form_factor || "unknown") + "."
            : "Dynamic Type, small iPhone width, keyboard shortcuts, and touch ergonomics need device pass."
        },
        {
          key: "secret_scan_audit",
          label: "Secret-scan audit",
          status: secretAuditPass ? "pass" : "pending",
          evidence: secretAuditPass
            ? "Restricted block " + secretAudit.blockId + " is blocked/redacted in Workbench replay; output is not exposed in bake-off."
            : "No restricted_local_only replay block found yet for this page-level audit."
        }
      ];
    }

    function buildPromotionGate(metrics) {
      const passCount = metrics.filter((metric) => metric.status === "pass").length;
      const pending = metrics.filter((metric) => metric.status === "pending");
      const failed = metrics.filter((metric) => metric.status === "fail");
      const verdict = failed.length
        ? "block Warp renderer promotion"
        : "continue dual bridge; do not promote Warp renderer yet";
      const reason = failed.length
        ? failed.map((metric) => metric.label).join(", ") + " failed."
        : pending.length
          ? pending.map((metric) => metric.label).join(", ") + " still pending."
          : "All tracked metrics pass; a human promotion memo is still required.";
      return {
        eligible: false,
        state: failed.length ? "blocked" : "not_promoted",
        verdict,
        reason,
        passCount,
        pendingCount: pending.length,
        failCount: failed.length,
        requiredBeforePromotion: pending.map((metric) => metric.key)
      };
    }

    function renderScorecard(metrics, promotion) {
      promotionGate.textContent = "promotion_gate=" + promotion.state + ": " + promotion.verdict;
      promotionGate.className = promotion.failCount ? "pill danger" : "pill warn";
      scorecard.innerHTML = metrics.map((metric) => (
        '<div class="score-card">' +
          '<strong>' + escapeHtmlClient(metric.label) + '</strong>' +
          '<b class="' + metricClass(metric.status) + '">' + escapeHtmlClient(metric.status) + '</b>' +
          '<span>' + escapeHtmlClient(metric.evidence) + '</span>' +
        '</div>'
      )).join("");
    }

    function renderRendererProbeResults() {
      rendererProbeState.textContent = "renderer_probe=" + rendererProbe.state;
      rendererProbeState.className = rendererProbe.state === "measured" ? "pill warn" : "pill";
      if (!rendererProbe.results.length) {
        rendererProbeResults.innerHTML = '<div class="probe-item"><h3>not_measured</h3><p>No probe JSON found. Run the isolated AGPL probe and place its JSON in the configured renderer-probe directory.</p></div>';
        return;
      }
      rendererProbeResults.innerHTML = rendererProbe.results.map((result) => {
        const fixture = result.fixture
          ? 'fixture=' + escapeHtmlClient(result.fixture.blockId || "unknown") + ' · privacy=' + escapeHtmlClient(result.fixture.privacyClass || "unknown") + ' · redacted=' + escapeHtmlClient(String(result.fixture.restrictedRedacted))
          : 'fixture=none';
        const notes = (result.fidelityNotes || []).map((note) => '<p>' + escapeHtmlClient(note) + '</p>').join("");
        const vt = result.vtFidelity
          ? '<div class="row"><span>VT fidelity</span><strong>' + escapeHtmlClient(result.vtFidelity.status + ' / ' + result.vtFidelity.mode) + '</strong></div>'
          : "";
        const latency = result.latencyBudget
          ? '<div class="row"><span>Latency budget</span><strong>' + escapeHtmlClient(result.latencyBudget.status + ' · ' + result.latencyBudget.totalMs + 'ms/' + result.latencyBudget.thresholdMs + 'ms') + '</strong></div>'
          : "";
        return (
          '<div class="probe-item">' +
            '<h3>' + escapeHtmlClient(result.status) + ' · ' + escapeHtmlClient(result.platform) + '/' + escapeHtmlClient(result.arch) + '</h3>' +
            '<div class="row"><span>File</span><strong>' + escapeHtmlClient(result.file) + '</strong></div>' +
            '<div class="row"><span>Renderer</span><strong>' + escapeHtmlClient(result.renderer) + '</strong></div>' +
            '<div class="row"><span>Hot path</span><strong>' + escapeHtmlClient(result.hotPath) + '</strong></div>' +
            '<div class="row"><span>Timing</span><strong>' + escapeHtmlClient(result.timingMs == null ? "not_reported" : result.timingMs + "ms") + '</strong></div>' +
            vt +
            latency +
            '<p>' + fixture + '</p>' +
            notes +
          '</div>'
        );
      }).join("");
    }

    function renderAppleDevicePassResults() {
      appleDevicePassState.textContent = "apple_device_pass=" + appleDevicePass.state;
      appleDevicePassState.className = appleDevicePass.latest?.status === "device_pass" ? "pill ok" : "pill warn";
      if (!appleDevicePass.results.length) {
        appleDevicePassResults.innerHTML = '<div class="probe-item"><h3>not_measured</h3><p>No sanitized Apple device pass JSON has been recorded yet. Record one from the Workbench after a real device session.</p></div>';
        return;
      }
      appleDevicePassResults.innerHTML = appleDevicePass.results.map((result) => {
        const device = result.device || {};
        const blockers = (result.blockers || []).map((blocker) => '<p>' + escapeHtmlClient(blocker) + '</p>').join("");
        return (
          '<div class="probe-item">' +
            '<h3>' + escapeHtmlClient(result.status) + ' · ' + escapeHtmlClient(device.form_factor || "unknown") + '</h3>' +
            '<div class="row"><span>File</span><strong>' + escapeHtmlClient(result.file) + '</strong></div>' +
            '<div class="row"><span>Block</span><strong>' + escapeHtmlClient(result.blockId || "unknown") + '</strong></div>' +
            '<div class="row"><span>Candidate</span><strong>' + escapeHtmlClient(result.selectedCandidate || "unknown") + '</strong></div>' +
            '<div class="row"><span>Score</span><strong>' + escapeHtmlClient(result.humanScore == null ? "pending" : result.humanScore + "/5") + '</strong></div>' +
            '<div class="row"><span>Input-to-paint</span><strong>' + escapeHtmlClient(result.inputToPaintMs == null ? "not_reported" : result.inputToPaintMs + "ms") + '</strong></div>' +
            '<div class="row"><span>Leak check</span><strong>' + escapeHtmlClient(result.restrictedLeakCheck) + '</strong></div>' +
            '<div class="row"><span>Canonical memory</span><strong>' + escapeHtmlClient(result.canonicalMemoryWritten ? "unexpected" : "not_written") + '</strong></div>' +
            (result.notes ? '<p>' + escapeHtmlClient(result.notes) + '</p>' : '') +
            blockers +
          '</div>'
        );
      }).join("");
    }

    function selectedFixtureJson() {
      const block = state.currentBeagleBlock || emptyBlock(state.selectedSessionId);
      return JSON.stringify({
        id: block.id,
        sessionId: block.sessionId,
        paneId: block.paneId,
        kind: block.kind,
        title: block.title,
        command: block.command,
        outputPreview: block.outputPreview,
        outputByteCount: block.outputByteCount,
        startedAt: block.startedAt,
        finishedAt: block.finishedAt,
        durationMs: block.durationMs,
        exitCode: block.exitCode,
        status: block.status,
        privacyClass: block.privacyClass,
        memoryStatus: block.memoryStatus,
        tags: block.tags,
        sourceModel: block.sourceModel,
        bridgeVersion: block.bridgeVersion,
        blockHash: block.blockHash,
        sessionHash: block.sessionHash,
        rendererHint: block.rendererHint
      }, null, 2);
    }

    function fixtureFileName() {
      const block = state.currentBeagleBlock || {};
      const safe = String(block.id || "no-live-block-yet").replace(/[^a-zA-Z0-9_.-]+/g, "-").slice(0, 96);
      return slug + "-" + safe + "-warp-fixture.json";
    }

    function probeCommand() {
      const fixture = fixtureFileName();
      return [
        "npm --silent --prefix apps/warp-workbench run renderer:probe:block --",
        "--base-url",
        "http://127.0.0.1:4370",
        "--project",
        slug,
        "--session-id",
        state.currentBeagleBlock?.sessionId || state.selectedSessionId || "",
        "--block-id",
        state.currentBeagleBlock?.id || "no-live-block-yet",
        "--out-dir",
        "/workspace/.beagle/workbench/renderer-probes/" + slug,
        "  # fixture download: " + fixture
      ].join(" ");
    }

    function downloadSelectedFixture() {
      const blob = new Blob([selectedFixtureJson() + "\\n"], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = fixtureFileName();
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      URL.revokeObjectURL(url);
      probeActionNote.textContent = "fixture_downloaded=" + fixtureFileName();
      probeActionNote.className = "pill";
    }

    async function copySelectedProbeCommand() {
      const command = probeCommand();
      try {
        await navigator.clipboard.writeText(command);
        probeActionNote.textContent = "probe_command_copied";
        probeActionNote.className = "pill ok";
      } catch (_error) {
        probeActionNote.textContent = command;
        probeActionNote.className = "pill warn";
      }
    }

    function renderDecisionMemo(beagleBlock, fields, metrics, promotion) {
      const preservedCount = fields.filter((entry) => entry.preserved).length;
      const restricted = beagleBlock.restricted;
      const secretAuditPass = state.restrictedAudit?.status === "pass";
      decisionMemo.innerHTML = [
        '<h3>Verdict</h3>',
        '<p><strong>' + escapeHtmlClient(promotion.verdict) + '</strong></p>',
        '<p>Bridge conversion is inspectable and preserves ' + preservedCount + '/' + fields.length + ' tracked fields for the selected block. The current gate has ' + promotion.passCount + ' passing, ' + promotion.pendingCount + ' pending, and ' + promotion.failCount + ' failing checks.</p>',
        '<p class="' + (restricted ? 'warn' : 'ok') + '">' + (restricted ? 'Selected block is restricted; output is intentionally hidden.' : 'Selected block is safe for outputPreview-level comparison.') + '</p>',
        secretAuditPass
          ? '<p class="ok">Secret-scan audit found restricted block ' + escapeHtmlClient(state.restrictedAudit.blockId) + ' and keeps output hidden in the bake-off.</p>'
          : '<p class="warn">Secret-scan audit still needs a restricted replay block to be measured on this page.</p>',
        '<p>Renderer promotion remains blocked until VT fidelity, latency, iPad/iPhone/macOS usability, and secret-scan behavior are measured against the Beagle Notebook Terminal.</p>',
        '<p>Next: live block selection, isolated renderer spike, Apple-device latency pass' + (secretAuditPass ? '.' : ', and secret-scan audit.') + '</p>'
      ].join("");
      decisionJson.textContent = JSON.stringify({
        vendorCommit,
        bridgeVersion,
        selectedBlock: {
          id: beagleBlock.id,
          sessionId: beagleBlock.sessionId,
          privacyClass: beagleBlock.privacyClass,
          memoryStatus: beagleBlock.memoryStatus,
          blockHash: beagleBlock.blockHash,
          restrictedRedacted: Boolean(beagleBlock.restricted)
        },
        rendererProbe: {
          state: rendererProbe.state,
          latest: rendererProbe.latest
            ? {
                status: rendererProbe.latest.status,
                platform: rendererProbe.latest.platform,
                arch: rendererProbe.latest.arch,
                timingMs: rendererProbe.latest.timingMs,
                promoted: rendererProbe.latest.promoted,
                vtFidelity: rendererProbe.latest.vtFidelity,
                latencyBudget: rendererProbe.latest.latencyBudget
              }
            : null
        },
        appleDevicePass: {
          state: appleDevicePass.state,
          latest: appleDevicePass.latest
        },
        restrictedAudit: state.restrictedAudit,
        fieldPreservation: fields.map((entry) => ({
          field: entry.field,
          preserved: entry.preserved
        })),
        metrics,
        promotionGate: promotion
      }, null, 2);
    }

    function populateSessionSelect(list) {
      sessionSelect.innerHTML = list.map((session) => {
        const id = session.id || session.session_id;
        const label = (session.title || "Workbench session") + " - " + id;
        return '<option value="' + escapeHtmlClient(id) + '">' + escapeHtmlClient(label) + '</option>';
      }).join("");
      sessionSelect.value = state.selectedSessionId;
    }

    function populateBlockSelect(blocks) {
      if (!blocks.length) {
        blockSelect.innerHTML = '<option value="no-live-block-yet">No finished block yet</option>';
        blockSelect.value = "no-live-block-yet";
        return;
      }
      blockSelect.innerHTML = blocks.map((block) => {
        const label = (block.title || block.command || block.id || "block").slice(0, 96);
        return '<option value="' + escapeHtmlClient(block.id) + '">' + escapeHtmlClient(label) + '</option>';
      }).join("");
      blockSelect.value = state.selectedBlockId || blocks[0].id;
    }

    async function loadBlocksForSession(sessionId) {
      if (!sessionId) return [];
      if (state.blocksBySession.has(sessionId)) return state.blocksBySession.get(sessionId);
      const blockResponse = await apiJson("/api/workspaces/" + encodeURIComponent(slug) + "/sessions/" + encodeURIComponent(sessionId) + "/blocks");
      const blocks = blockResponse.blocks || [];
      state.blocksBySession.set(sessionId, blocks);
      return blocks;
    }

    async function findRestrictedAudit(list) {
      const existing = list.find((session) => {
        const privacy = String(session?.lastMemoryStatus?.privacyClass || session?.lastMemoryStatus?.privacy_class || "");
        return isRestrictedPrivacy(privacy);
      });
      if (existing) {
        const memory = existing.lastMemoryStatus || {};
        return {
          status: "pass",
          source: "session_last_memory_status",
          sessionId: existing.id || existing.session_id || "",
          blockId: memory.blockId || memory.block_id || "unknown",
          privacyClass: memory.privacyClass || memory.privacy_class || "restricted_local_only",
          memoryStatus: memory.status || "blocked",
          outputExposed: false,
          redacted: true
        };
      }

      for (const session of list.slice(0, 40)) {
        const sessionId = session.id || session.session_id || "";
        if (!sessionId) continue;
        const blocks = await loadBlocksForSession(sessionId);
        const block = blocks.find((candidate) => isRestrictedPrivacy(blockPrivacy(candidate)));
        if (!block) continue;
        return {
          status: "pass",
          source: "block_replay",
          sessionId,
          blockId: block.id || "unknown",
          privacyClass: blockPrivacy(block),
          memoryStatus: normalizeMemoryStatus(block.memoryStatus || block.memory_status || "blocked"),
          outputExposed: false,
          redacted: true
        };
      }

      return {
        status: "pending",
        source: "not_found",
        sessionId: "",
        blockId: "",
        privacyClass: "",
        memoryStatus: "",
        outputExposed: false,
        redacted: false
      };
    }

    function emptyBlock(sessionId) {
      return {
        id: "no-live-block-yet",
        sessionId,
        paneId: "pane-main",
        kind: "command",
        title: "No finished block yet",
        command: "",
        outputPreview: "Run a command in the Beagle Workbench, then refresh this lab.",
        status: "pending",
        memoryStatus: "not_saved",
        privacyClass: "sensitive",
        blockHash: null,
        tags: []
      };
    }

    async function renderSelectedBlock() {
      const blocks = await loadBlocksForSession(state.selectedSessionId);
      populateBlockSelect(blocks);
      const rawBlock = blocks.find((block) => block.id === (state.selectedBlockId || blockSelect.value)) || blocks[0] || emptyBlock(state.selectedSessionId);
      state.selectedBlockId = rawBlock.id;
      blockSelect.value = rawBlock.id;
      selectedBlock.textContent = rawBlock.id;

      const beagleBlock = sanitizeBlock(rawBlock);
      state.currentBeagleBlock = beagleBlock;
      const warpBlock = terminalBlockToWarpBlock(beagleBlock);
      const roundTripBlock = warpBlockToTerminalBlock(warpBlock);
      const fields = preservedFields(beagleBlock, warpBlock, roundTripBlock);
      const metrics = buildBakeOffMetrics(beagleBlock, fields);
      const promotion = buildPromotionGate(metrics);
      privacyNote.textContent = beagleBlock.restricted
        ? "restricted_local_only: outputPreview hidden; no memory write occurs here"
        : "outputPreview only: derived preview; no memory write occurs here";
      privacyNote.className = beagleBlock.restricted ? "pill warn" : "pill";
      probeActionNote.textContent = "fixture=" + fixtureFileName();
      probeActionNote.className = beagleBlock.restricted ? "pill warn" : "pill";
      beaglePreview.textContent = JSON.stringify(beagleBlock, null, 2);
      warpPreview.textContent = JSON.stringify(warpBlock, null, 2);
      renderFieldDiff(fields);
      renderScorecard(metrics, promotion);
      renderRendererProbeResults();
      renderAppleDevicePassResults();
      renderDecisionMemo(beagleBlock, fields, metrics, promotion);
    }

    async function refresh() {
      try {
        const registry = await apiJson("/api/workspaces/" + encodeURIComponent(slug) + "/agents/registry");
        const sessions = await apiJson("/api/workspaces/" + encodeURIComponent(slug) + "/sessions");
        const list = sessions.sessions || [];
        const selected = selectSession(list);
        state.sessions = list;
        state.blocksBySession = new Map();
        state.selectedSessionId = state.selectedSessionId || selected?.id || selected?.session_id || "";
        state.restrictedAudit = await findRestrictedAudit(list);
        authority.textContent = registry.authority?.authority || sessions.authority?.authority || "unknown";
        supervisor.textContent = registry.authority?.supervisor?.status || sessions.authority?.supervisor?.status || "unknown";
        sessionsCount.textContent = String(list.length);
        selectedSession.textContent = state.selectedSessionId || "none";
        populateSessionSelect(list);
        await renderSelectedBlock();
      } catch (error) {
        authority.textContent = "degraded";
        supervisor.textContent = "unknown";
        promotionGate.textContent = "promotion_gate=degraded";
        promotionGate.className = "pill danger";
        scorecard.innerHTML = "";
        decisionJson.textContent = "{}";
        decisionMemo.textContent = String(error.stack || error.message || error);
      }
    }

    sessionSelect.addEventListener("change", async () => {
      state.selectedSessionId = sessionSelect.value;
      state.selectedBlockId = "";
      selectedSession.textContent = state.selectedSessionId || "none";
      await renderSelectedBlock();
    });
    blockSelect.addEventListener("change", async () => {
      state.selectedBlockId = blockSelect.value;
      await renderSelectedBlock();
    });
    downloadFixtureButton.addEventListener("click", downloadSelectedFixture);
    copyProbeCommandButton.addEventListener("click", copySelectedProbeCommand);
    refreshButton.addEventListener("click", refresh);
    refresh();
  </script>
</body>
</html>`;
}

app.get("/api/workspaces/:slug/warp/device-pass", jsonResponse(async (req) => {
  return readAppleDevicePassResults(req.params.slug);
}));

app.post("/api/workspaces/:slug/warp/device-pass", jsonResponse(async (req) => {
  return writeAppleDevicePassResult(req.params.slug, req.body || {});
}));

if (!existsSync(distDir)) {
  app.get("/projects/:slug/workbench-v2", async (req, res) => {
    try {
      const project = await getProjectOrThrow(req.params.slug);
      res.type("html").send(renderVisualWorkbenchPrototypePage(project));
    } catch (error) {
      res.status(error.statusCode || 500).type("text/plain").send(error.message || "project unavailable");
    }
  });

  app.get("/projects/:slug/warp", async (req, res) => {
    try {
      const project = await getProjectOrThrow(req.params.slug);
      res.type("html").send(renderWarpBridgeLabPage(project));
    } catch (error) {
      res.status(error.statusCode || 500).type("text/plain").send(error.message || "project unavailable");
    }
  });

  app.get(["/projects/:slug", "/projects/:slug/viewer"], async (req, res) => {
    try {
      const project = await getProjectOrThrow(req.params.slug);
      res.type("html").send(renderProjectLaunchPage(project));
    } catch (error) {
      res.status(error.statusCode || 500).type("text/plain").send(error.message || "project unavailable");
    }
  });
}

if (existsSync(distDir)) {
  app.use(express.static(distDir));

  app.get("*", (req, res, next) => {
    if (req.path.startsWith("/api/")) {
      next();
      return;
    }
    res.sendFile(path.join(distDir, "index.html"));
  });
}

// Serve the OpenAPI spec at a stable, well-known path so ChatGPT Custom
// GPT Actions / Swagger UI / any OAI-consuming client can discover it
// without depending on the SolidJS build output. Lives in public/ so
// Vite copies it into dist/ too; this direct route is defensive.
app.get(["/openapi.yaml", "/.well-known/openapi.yaml"], (_req, res) => {
  const specPath = path.join(rootDir, "public", "openapi.yaml");
  if (!existsSync(specPath)) {
    return res.status(404).type("text/plain").send("openapi.yaml missing in build");
  }
  res.type("application/yaml").sendFile(specPath);
});

// ─── MCP Manifest (published contract for external MCP clients) ─────────
registerManifestRoutes(app);

// ─── Mobile v1 routes (stable iOS/macOS-facing contract boundary) ────────
registerMobileRoutes(app, {
  getProjectOrThrow,
  readCatalog: loadCatalog,
  readCachedCatalogExecutiveState,
  buildMissionControlResponse,
  buildClusterLaneTruthResponse,
  buildResearchOperationsResponse,
  buildInferenceRuntimeResponse,
  buildViewerRuntimeResponse,
  buildGoWorkNowResponse,
  deriveViewer,
  touchSession,
  listProjectSessions,
  runGoWorkNowAction
});

// ─── Agent routes (persistent agent pods — Claude Code, Codex, etc.) ────
registerAgentRoutes(app);

// ─── Notebook terminal workspace routes — Sounio Workbench v1 ──────────
registerWorkspaceRoutes(app, {
  getProjectOrThrow,
  readCatalog: loadCatalog,
});

// ─── Agent scratchpad — shared notepad between agent + iOS ──────────────
registerScratchpadRoutes(app);
registerPlatformRoutes(app);

// ─── OFICINA — the dev half: "está verde? o que quebrou? onde estou?" ──────
// Read-only: it reads CI verdicts and git head, never launches a build/test/gate.
const oficinaPoller = new OficinaPoller({
  kubectl: process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl",
  ns: process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle",
});
oficinaPoller.start();
registerOficinaRoutes(app, oficinaPoller);

// ─── COORDENAÇÃO — keep agents out of each other's work (advisory: warns, never blocks) ──
// Measured hazard: all live lanes share one working tree + branch, so an edit by one is
// clobberable by all. This surfaces that, and lets a lane declare what it is touching.
const claimRegistry = new ClaimRegistry();
const hazardPoller = new HazardPoller({
  kubectl: process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl",
  ns: process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle",
  execFn: nodeExecFile,
  workspaceQueryArgv: coordQueryArgv,
});
hazardPoller.start();
registerCoordRoutes(app, { registry: claimRegistry, hazards: hazardPoller });

// ─── Job routes (cluster batch jobs — canonical escalation path) ───────
registerJobRoutes(app);

// ─── Queue routes (unified K8s + Slurm + Kueue view) ────────────────────
registerQueueRoutes(app);

// ─── Auth bridge to beagle-server (iOS gets token via cockpit) ──────────
registerAuthBridgeRoutes(app);

// ─── Physiome ingest proxy — /api/physiome/* → physiome-ingest ──────────
// The iOS Physiome uploader (PhysiomeUploader.swift) posts HealthKit and
// WeatherKit samples to beagle.chiuratto.ai/api/physiome/ingest (this cockpit,
// behind the cloudflared tunnel). The cockpit gate validates the operator Bearer;
// this handler substitutes the physiome-specific ingest token (physiome-secrets)
// before forwarding to the in-cluster ingest service.
//   Service:  physiome-ingest.beagle.svc.cluster.local:8080
//   Endpoint: POST /api/physiome/ingest
(function registerPhysiomeProxyRoutes() {
  const PHYSIOME_INGEST_INTERNAL_URL =
    process.env.PROJECT_COCKPIT_PHYSIOME_INGEST_URL ||
    "http://physiome-ingest.beagle.svc.cluster.local:8080";
  const PHYSIOME_SECRET = "physiome-secrets";
  const PHYSIOME_TOKEN_KEY = "PHYSIOME_INGEST_TOKEN";
  const PHYSIOME_TOKEN_TTL_MS = 5 * 60 * 1000; // 5-minute cache

  let physiomeTokenCache = null;
  let physiomeTokenCachedAt = 0;

  async function fetchPhysiomeToken() {
    const now = Date.now();
    if (physiomeTokenCache && (now - physiomeTokenCachedAt) < PHYSIOME_TOKEN_TTL_MS) {
      return physiomeTokenCache;
    }
    try {
      const { stdout } = await runKubectl(
        ["-n", "beagle", "get", "secret", PHYSIOME_SECRET,
         "-o", `jsonpath={.data.${PHYSIOME_TOKEN_KEY}}`],
        { timeoutMs: 5000 }
      );
      const decoded = Buffer.from(String(stdout || "").trim(), "base64").toString("utf8").trim();
      if (decoded) {
        physiomeTokenCache = decoded;
        physiomeTokenCachedAt = now;
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  // Mobile READ: body×sky×ambient correlations (lag scan) for the iOS data screen. The phone
  // can't reach physiome's ClusterIP and doesn't hold the physiome token, so the cockpit reads
  // through with the substituted token (same pattern as the ingest proxy). Front gate is the
  // cockpit (tailnet/CF Access). Best-effort.
  app.get("/api/mobile/v1/correlations", async (req, res) => {
    try {
      const token = await fetchPhysiomeToken();
      const days = Math.min(Math.max(Number(req.query.days) || 30, 7), 365);
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 8000);
      try {
        const r = await fetch(`${PHYSIOME_INGEST_INTERNAL_URL}/api/physiome/correlations?days=${days}`, {
          headers: { Accept: "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
          signal: ctrl.signal,
        });
        const payload = JSON.parse(await r.text());
        res.status(r.ok ? 200 : 502).json(payload);
      } finally { clearTimeout(timer); }
    } catch (e) {
      res.status(502).json({ ok: false, error: String(e?.message || e) });
    }
  });

  app.post("/api/physiome/*", async (req, res) => {
    // Validate the incoming operator token against the known beagle token so this
    // endpoint cannot be abused by any bearer that merely passed the cockpit gate.
    const incoming = (req.headers["authorization"] || "").replace(/^Bearer\s+/i, "").trim();
    const tokenResult = await fetchOperatorToken();
    if (tokenResult.error || !tokenResult.token || incoming !== tokenResult.token) {
      return res.status(401).json({ ok: false, error: "invalid operator token for physiome ingest" });
    }

    // Fetch the physiome-ingest-specific token (a different secret).
    const physToken = await fetchPhysiomeToken();
    if (!physToken) {
      return res.status(503).json({ ok: false, error: "physiome-ingest token unavailable (check physiome-secrets)" });
    }

    // Strip the /api/physiome prefix and forward to the ingest service.
    const tail = req.originalUrl.replace(/^\/api\/physiome/, "") || "/";
    const target = `${PHYSIOME_INGEST_INTERNAL_URL}/api/physiome${tail}`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 60_000);
    try {
      const upstream = await fetch(target, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${physToken}`,
          "X-Beagle-Consumer": "beagle-operator"
        },
        body: JSON.stringify(req.body ?? {}),
        signal: ctrl.signal
      });
      const text = await upstream.text();
      res
        .status(upstream.status)
        .set("Content-Type", upstream.headers.get("content-type") || "application/json")
        .send(text);
    } catch (err) {
      res.status(503).json({
        ok: false,
        error: err.name === "AbortError" ? "physiome-ingest timeout (60s)" : err.message
      });
    } finally {
      clearTimeout(timer);
    }
  });
})();

const server = http.createServer(app);

// Keep upstream HTTP connections alive long enough for proxy/tunnel reuse.
// Node's default 5s origin keepalive is short enough to cause intermittent
// ECONNRESET/502s behind persistent proxy layers like cloudflared.
const keepAliveTimeoutMs = Number.parseInt(
  process.env.PROJECT_COCKPIT_KEEP_ALIVE_TIMEOUT_MS || "75000",
  10
);
if (Number.isFinite(keepAliveTimeoutMs) && keepAliveTimeoutMs > 0) {
  server.keepAliveTimeout = keepAliveTimeoutMs;
  server.headersTimeout = keepAliveTimeoutMs + 5000;
}

// Both WSS use noServer: true and we route via a single upgrade handler.
const wss = new WebSocketServer({ noServer: true });
const agentWss = new WebSocketServer({ noServer: true });
const workspaceWss = new WebSocketServer({ noServer: true });
const loomWss = new WebSocketServer({ noServer: true });
const loomBroker = mountLoom();
loomWss.on("connection", (ws) => loomBroker.handleConnection(ws));

// ─── AGIR NA LANE — one named key, no attach ──────────────────────────────────────────────
// Registered here (not next to the other mobile routes) because it needs the LanePoller that
// mountLoom() builds. These are POSTs, so the SPA's GET "*" fallback never sees them, and they
// inherit the global auth gate: a write without a real token is 401.
registerLaneActionRoutes(app, {
  poller: loomBroker.lanePoller,
  kubectl: process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl",
  ns: process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle",
  execFn: nodeExecFile,
});
attachAgentWebSocket(agentWss);
attachWorkspaceWebSocket(workspaceWss, { getProjectOrThrow });

server.on("upgrade", (req, socket, head) => {
  // Auth for WebSocket upgrades. Every terminal socket carries keystrokes INTO a live session,
  // so it is classified as a WRITE: the forgeable `tailscale-user-login` header alone never
  // suffices (see auth-gate.mjs — an in-cluster caller can simply send it).
  //
  // This used to be wrapped in `if (COCKPIT_AUTH_TOKEN) { … }`, which meant an empty or unmounted
  // secret left EVERY socket — including /ws/loom, which can type into any lane — wide open. The
  // HTTP gate was fixed to fail closed on 2026-08-08; the WS gate was not, and it also ignored
  // the internal token. It now goes through the same classifier, so the two cannot drift again.
  {
    // Os clientes iOS/macOS mandam o mesmo `x-cockpit-token` de toda chamada REST; `Authorization:
    // Bearer` e `?token=` também valem. A leitura mora em `wsAuthInputs`, pura e testável — ver o
    // comentário dela para a divergência que isso fechou.
    const verdict = classifyAuth({
      ...wsAuthInputs({ url: req.url, headers: req.headers }),
      tokens: COCKPIT_AUTH_TOKENS,
      allowOpen: ALLOW_OPEN,
    });
    if (!verdict.allow) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy();
      console.warn(`[auth] refused WS upgrade for ${req.url}: ${verdict.reason}`);
      return;
    }
  }

  const urlPath = (req.url || "").split("?")[0];
  if (urlPath === "/ws/terminal") {
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit("connection", ws, req));
    return;
  }
  const agentMatch = urlPath.match(/^\/ws\/projects\/([^/]+)\/agent\/([^/]+)$/);
  if (agentMatch) {
    const [, wsSlug, wsKind] = agentMatch;
    // Validate slug and kind before proceeding
    if (!VALID_SLUG.test(wsSlug)) { socket.destroy(); return; }
    const validKinds = ["claude-code", "codex", "local-sglang", "custom"];
    // t560-* kinds are Command Deck tmux sessions (allowlisted in platform-bridge.mjs);
    // let them through the upgrade gate so registerAgentWebSocket's t560 branch handles them.
    if (!validKinds.includes(wsKind) && !isT560Kind(wsKind)) { socket.destroy(); return; }
    agentWss.handleUpgrade(req, socket, head, (ws) => agentWss.emit("connection", ws, req));
    return;
  }
  const workspaceMatch = urlPath.match(/^\/ws\/workspaces\/([^/]+)\/sessions\/([^/]+)\/panes\/([^/]+)$/);
  if (workspaceMatch) {
    const [, wsSlug] = workspaceMatch;
    if (!VALID_SLUG.test(wsSlug)) { socket.destroy(); return; }
    workspaceWss.handleUpgrade(req, socket, head, (ws) => workspaceWss.emit("connection", ws, req));
    return;
  }
  if (urlPath === "/ws/loom") {
    loomWss.handleUpgrade(req, socket, head, (ws) => loomWss.emit("connection", ws, req));
    return;
  }
  socket.destroy();
});

wss.on("connection", async (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const slug = url.searchParams.get("project") || "sounio";
  const clientSessionId = cleanValue(url.searchParams.get("sessionId"));
  const alias = cleanValue(url.searchParams.get("alias"));

  let project;
  try {
    project = await getProjectOrThrow(slug);
  } catch (error) {
    ws.send(JSON.stringify({ type: "error", data: error.message }));
    ws.close();
    return;
  }

  if (clientSessionId) {
    await touchSession(project.projectSlug, clientSessionId, deriveViewer(req, alias), {
      route: `/projects/${project.projectSlug}`,
      currentAction: "terminal-attached",
      lastTerminalAttachAt: new Date().toISOString()
    });
  }

  const shellCommand =
    'cd "$WORKSPACE_ROOT" && TMUX_SOCKET_DIR="$WORKSPACE_ROOT/.tmux" && TMUX_SOCKET="$TMUX_SOCKET_DIR/$TMUX_SESSION.sock" && mkdir -p "$TMUX_SOCKET_DIR" && chmod 700 "$TMUX_SOCKET_DIR" && exec tmux -S "$TMUX_SOCKET" new-session -A -s "$TMUX_SESSION"';

  const proc = pty.spawn(
    "kubectl",
    kubectlArgs(
      project,
      [
        "env",
        `WORKSPACE_ROOT=${project.workspaceRoot}`,
        `TMUX_SESSION=${project.tmuxSession}`,
        "sh",
        "-lc",
        shellCommand
      ],
      { tty: true }
    ),
    {
      name: "xterm-256color",
      cols: 120,
      rows: 34,
      cwd: process.cwd(),
      env: process.env
    }
  );

  proc.onData((data) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify({ type: "data", data }));
    }
  });

  proc.onExit(({ exitCode, signal }) => {
    if (ws.readyState === ws.OPEN) {
      const detail = signal ? `terminal exited (${exitCode}, signal ${signal})` : `terminal exited (${exitCode})`;
      ws.send(JSON.stringify({ type: "exit", data: detail }));
      ws.close();
    }
  });

  ws.send(JSON.stringify({ type: "ready", data: { projectSlug: project.projectSlug } }));

  ws.on("message", (payload) => {
    try {
      const message = JSON.parse(String(payload));
      if (message.type === "input") {
        proc.write(message.data);
      }
      if (message.type === "resize") {
        proc.resize(Number(message.cols || 120), Number(message.rows || 34));
      }
    } catch {
      proc.write(String(payload));
    }
  });

  ws.on("close", () => {
    proc.kill();
  });
});

server.listen(port, host, () => {
  console.log(`Project cockpit server listening on http://${host}:${port}`);
  startJobReconciler();
  // Companion-digest warmer: NOT gated by DISABLE_MEMORY_WARMERS — this is the cheap, targeted
  // one that keeps personal chat's grounding (biography/sounio/physiome) hot so the first
  // message after idle doesn't stall on cold beagle-core fetches.
  if (companionWarmEnabled) {
    warmCompanionDigests().catch(() => {});
    setInterval(() => { warmCompanionDigests().catch(() => {}); }, companionWarmIntervalMs).unref();
  }
  if (disableMemoryWarmers) {
    startupWarmState = {
      ...startupWarmState,
      status: "ready",
      lastReadyAt: new Date().toISOString(),
      lastError: "memory warmers disabled"
    };
    console.warn("[cockpit] memory warmers disabled; serving memory lanes on demand");
    return;
  }
  primeStartupWarmCaches().catch(() => {});
  setInterval(() => {
    warmMemoryCaches().catch(() => {});
    if (startupWarmState.status !== "ready") {
      primeStartupWarmCaches().catch(() => {});
    }
  }, memoryWarmIntervalMs).unref();
});
