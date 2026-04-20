// job-routes.mjs
//
// Cluster job submission — canonical escalation path from agent workspaces
// to GPU/HPC nodes. Agents call cockpit_submit_job via MCP instead of
// handcrafting Kubernetes Job YAML.
//
// Endpoints:
//   POST /api/projects/:slug/jobs/submit    — submit new job
//   GET  /api/projects/:slug/jobs/:jobId    — status of one job
//   GET  /api/projects/:slug/jobs           — list recent jobs
//   POST /api/projects/:slug/jobs/:jobId/cancel — delete job (kill)
//
// Supported `kind`:
//   "k8s"   — native K8s Job (default)
//   "slurm" — Slurm via Slinky (sbatch wrapper) — stub, pending ops wiring

import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { ErrorCode, contractFailure, idempotent, withEnvelope } from "./contract.mjs";
import { applyPreset, listPresets } from "./job-presets.mjs";
import { fetchDarwinHpcAdapterConfig, fetchOperatorToken } from "./auth-bridge.mjs";

const NAMESPACE = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl";
const DEFAULT_IMAGE = process.env.PROJECT_COCKPIT_JOB_DEFAULT_IMAGE || "ttl.sh/beagle-sounio:latest";
const BEAGLE_INTERNAL_URL =
  process.env.PROJECT_COCKPIT_BEAGLE_INTERNAL_URL ||
  "http://beagle-core.beagle.svc.cluster.local:8080";
const DARWIN_HPC_GATEWAY_URL =
  process.env.PROJECT_COCKPIT_DARWIN_HPC_GATEWAY_URL ||
  "http://darwin-hpc-gateway.darwin-platform.svc.cluster.local";
const HPC_SUBMIT_TIMEOUT_MS = Number(process.env.PROJECT_COCKPIT_HPC_SUBMIT_TIMEOUT_MS || 120000);
const HPC_READ_TIMEOUT_MS = Number(process.env.PROJECT_COCKPIT_HPC_READ_TIMEOUT_MS || 15000);
const HPC_OBJECT_TIMEOUT_MS = Number(process.env.PROJECT_COCKPIT_HPC_OBJECT_TIMEOUT_MS || 60000);
const HPC_ALLOWED_PROFILES = new Set(["cpu-short-v1", "cpu-batch-v1", "gpu-single-v1"]);
const HPC_LEGACY_KIND_MAP = Object.freeze({
  cpu: "cpu-short-v1",
  "cpu-short": "cpu-short-v1",
  "cpu-batch": "cpu-batch-v1",
  gpu: "gpu-single-v1",
  "gpu-single": "gpu-single-v1"
});
const HPC_PROJECT_WORKSTREAM_MAP = Object.freeze({
  sounio: "sounio-lang-main"
});

// Known data mount profiles — maps short name → k8s volume + mountPath
const MOUNT_PROFILES = {
  "orangefs-training": {
    volume: { name: "orangefs", persistentVolumeClaim: { claimName: "orangefs-training" } },
    mount:  { name: "orangefs", mountPath: "/orangefs" }
  },
  "hf-cache": {
    volume: { name: "hf-cache", emptyDir: { sizeLimit: "20Gi" } },
    mount:  { name: "hf-cache", mountPath: "/home/runner/.cache" }
  },
  "workspace": {
    volume: { name: "workspace", persistentVolumeClaim: { claimName: "sounio-workspace" } },
    mount:  { name: "workspace", mountPath: "/workspace" }
  },
  // Ephemeral scratch for presets that git-clone at runtime. Cannot share
  // an RWO PVC with an already-attached workspace pod, so we use emptyDir.
  "work-tmp": {
    volume: { name: "work-tmp", emptyDir: { sizeLimit: "10Gi" } },
    mount:  { name: "work-tmp", mountPath: "/work" }
  }
};

function runKubectl(args, { input, timeoutMs = 15000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(KUBECTL, args, { stdio: ["pipe", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error(`kubectl timeout: ${args.join(" ")}`));
    }, timeoutMs);
    child.stdout.on("data", (d) => { stdout += d.toString(); });
    child.stderr.on("data", (d) => { stderr += d.toString(); });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code !== 0) reject(new Error(`kubectl exit ${code}: ${stderr || stdout}`));
      else resolve(stdout);
    });
    child.on("error", (e) => { clearTimeout(timer); reject(e); });
    if (input !== undefined) { child.stdin.write(input); child.stdin.end(); }
  });
}

function shortId() {
  return randomBytes(4).toString("hex");
}

function cleanString(value) {
  if (typeof value === "string") {
    return value.trim();
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).trim();
  }
  return "";
}

function buildDefaultRunLabel(slug, profileId) {
  const base = `${slug}-${profileId.replace(/-v\d+$/, "")}-${shortId()}`
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/--+/g, "-");
  return base.slice(0, 40);
}

function asNumericJobId(value) {
  const parsed = Number(cleanString(value));
  return Number.isFinite(parsed) ? parsed : null;
}

function resolveHpcWorkstreamId(slug) {
  const normalized = cleanString(slug).toLowerCase();
  return HPC_PROJECT_WORKSTREAM_MAP[normalized] || `${normalized}-main`;
}

function hasMappedHpcWorkstream(slug) {
  const normalized = cleanString(slug).toLowerCase();
  return Boolean(HPC_PROJECT_WORKSTREAM_MAP[normalized]);
}

function workbenchRecipeKindForProfile(profileId) {
  if (profileId === "gpu-single-v1") {
    return "operator_gpu_loop";
  }
  return "operator_cpu_loop";
}

function buildWorkbenchRunRequest(slug, request) {
  const profileId = request.profile_id;
  const runLabel = request.parameters.run_label;
  const recipeKind = workbenchRecipeKindForProfile(profileId);
  const workflowDescriptor = profileId === "gpu-single-v1" ? "GPU operator workflow" : "CPU operator workflow";
  const reservationLane = profileId === "gpu-single-v1" ? "gpu-single" : profileId;
  const experimentSuffix = recipeKind.replace(/[^a-z0-9]+/gi, "-").toLowerCase();

  return {
    requested_by: "partner-dev",
    requester_role_id: "partner-dev",
    selected_subagent_id: "experiments",
    task_family: "analysis",
    intent_text: `Run a bounded ${workflowDescriptor} for ${slug} through the shared Beagle workbench and bind the published result back into the same session.`,
    compute_profile_id: profileId,
    run_label: runLabel,
    recipe_kind: recipeKind,
    experiment_id: `${slug}-${experimentSuffix}`,
    reservation_note: `Reserve the bounded partner-dev ${reservationLane} lane for the canonical ${slug} ${workflowDescriptor.toLowerCase()}.`,
    dispatch_note: `Dispatch the bounded partner-dev analysis run for ${slug} through the workbench orchestration surface and persist the published result binding.`,
    poll_interval_seconds: 5,
    timeout_seconds: profileId === "gpu-single-v1" ? 900 : 600
  };
}

function deterministicBindingMatchesJob(jobId, receipt = {}, publication = {}, binding = {}) {
  const candidate = asNumericJobId(jobId);
  if (candidate === null) {
    return false;
  }
  const values = [
    receipt.submitted_job_id,
    receipt.final_job_id,
    receipt.published_result_job_id,
    receipt.resolved_result_lookup_job_id,
    receipt.result_manifest_job_id,
    publication.submitted_job_id,
    publication.published_result_job_id,
    binding.submitted_job_id,
    binding.published_result_job_id,
    binding.resolved_result_lookup_job_id,
    binding.result_manifest_job_id
  ]
    .map(asNumericJobId)
    .filter((value) => value !== null);
  return values.includes(candidate);
}

async function getHpcDeterministicResultBinding(slug, jobId) {
  const workstreamId = resolveHpcWorkstreamId(slug);
  const [receipt, publication, binding] = await Promise.all([
    proxyDarwinHpc(
      "GET",
      `/api/darwin/workstreams/${workstreamId}/run-result-identity-receipt`,
      { timeoutMs: HPC_READ_TIMEOUT_MS }
    ),
    proxyDarwinHpc(
      "GET",
      `/api/darwin/workstreams/${workstreamId}/run-scoped-publication`,
      { timeoutMs: HPC_READ_TIMEOUT_MS }
    ),
    proxyDarwinHpc(
      "GET",
      `/api/darwin/workstreams/${workstreamId}/deterministic-result-binding`,
      { timeoutMs: HPC_READ_TIMEOUT_MS }
    )
  ]);

  if (!deterministicBindingMatchesJob(jobId, receipt, publication, binding)) {
    throw contractFailure(
      ErrorCode.NOT_FOUND,
      `no deterministic result binding found for job ${jobId} in workstream ${workstreamId}`
    );
  }

  return {
    workstream_id: workstreamId,
    receipt,
    publication,
    binding,
    via: "cockpit-darwin-hpc-deterministic-fallback"
  };
}

function resolveHpcProfileId(body = {}) {
  const explicit =
    cleanString(body.profile_id) ||
    cleanString(body.profileId) ||
    cleanString(body.profile) ||
    cleanString(body.hpc_profile_id) ||
    cleanString(body.hpcProfileId);
  if (explicit) {
    return explicit;
  }

  const legacyKind =
    cleanString(body.kind).toLowerCase() ||
    cleanString(body.job_kind).toLowerCase() ||
    cleanString(body.preset).toLowerCase();
  return HPC_LEGACY_KIND_MAP[legacyKind] || "";
}

function normalizeHpcSubmitRequest(slug, body = {}) {
  const profileId = resolveHpcProfileId(body);
  if (!HPC_ALLOWED_PROFILES.has(profileId)) {
    throw contractFailure(
      ErrorCode.BAD_REQUEST,
      `unsupported HPC profile: ${profileId || "(missing)"}`
    );
  }

  const parameters =
    body.parameters && typeof body.parameters === "object" && !Array.isArray(body.parameters)
      ? { ...body.parameters }
      : {};
  const incomingRunLabel =
    cleanString(parameters.run_label) ||
    cleanString(parameters.runLabel) ||
    cleanString(body.run_label) ||
    cleanString(body.runLabel);

  parameters.run_label = incomingRunLabel || buildDefaultRunLabel(slug, profileId);
  delete parameters.runLabel;

  return {
    profile_id: profileId,
    parameters
  };
}

async function proxyDarwinHpc(method, path, { body, timeoutMs } = {}) {
  const tokenResult = await fetchOperatorToken();
  if (tokenResult.error || !tokenResult.token) {
    throw contractFailure(
      ErrorCode.CLUSTER_UNREACHABLE,
      tokenResult.error || "beagle operator token unavailable"
    );
  }

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${BEAGLE_INTERNAL_URL}${path}`, {
      method,
      headers: {
        Accept: "application/json",
        "content-type": "application/json",
        "X-Beagle-Consumer": "beagle-operator",
        Authorization: `Bearer ${tokenResult.token}`
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: ctrl.signal
    });
    const raw = await res.text();
    const payload = raw ? JSON.parse(raw) : {};
    if (!res.ok) {
      throw contractFailure(
        res.status >= 500 ? ErrorCode.CLUSTER_UNREACHABLE : ErrorCode.BAD_REQUEST,
        payload?.error || payload?.message || `Darwin HPC request failed: ${res.status}`
      );
    }
    return payload;
  } catch (error) {
    if (error.name === "AbortError") {
      throw contractFailure(ErrorCode.TIMEOUT, `Darwin HPC request timed out for ${path}`);
    }
    if (error.code) {
      throw error;
    }
    throw contractFailure(ErrorCode.CLUSTER_UNREACHABLE, error.message);
  } finally {
    clearTimeout(timer);
  }
}

async function proxyDarwinHpcObject(path, { timeoutMs = HPC_OBJECT_TIMEOUT_MS } = {}) {
  const adapter = await fetchDarwinHpcAdapterConfig();
  const baseUrl = adapter.token ? (adapter.url || DARWIN_HPC_GATEWAY_URL) : DARWIN_HPC_GATEWAY_URL;
  const headers = { Accept: "*/*" };
  if (adapter.token) {
    headers.Authorization = `Bearer ${adapter.token}`;
  }
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${baseUrl}${path}`, {
      method: "GET",
      headers,
      signal: ctrl.signal
    });
    const body = Buffer.from(await res.arrayBuffer());
    if (!res.ok) {
      const text = body.toString("utf8");
      let message = `Darwin HPC object request failed: ${res.status}`;
      try {
        const payload = text ? JSON.parse(text) : {};
        message = payload?.error || payload?.message || message;
      } catch {
        message = text || message;
      }
      throw contractFailure(
        res.status >= 500 ? ErrorCode.CLUSTER_UNREACHABLE : ErrorCode.BAD_REQUEST,
        message
      );
    }
    return {
      body,
      contentType: res.headers.get("content-type") || "application/octet-stream",
      contentDisposition: res.headers.get("content-disposition") || null
    };
  } catch (error) {
    if (error.name === "AbortError") {
      throw contractFailure(ErrorCode.TIMEOUT, `Darwin HPC object request timed out for ${path}`);
    }
    if (error.code) {
      throw error;
    }
    throw contractFailure(ErrorCode.CLUSTER_UNREACHABLE, error.message);
  } finally {
    clearTimeout(timer);
  }
}

async function proxyDarwinHpcAdapterJson(path, { timeoutMs = HPC_OBJECT_TIMEOUT_MS } = {}) {
  const artifact = await proxyDarwinHpcObject(path, {
    timeoutMs
  });
  try {
    return JSON.parse(artifact.body.toString("utf8"));
  } catch (error) {
    throw contractFailure(
      ErrorCode.CLUSTER_UNREACHABLE,
      `Darwin HPC JSON artifact decode failed for ${path}: ${error.message}`
    );
  }
}

export async function listHpcProfiles() {
  return proxyDarwinHpc("GET", "/api/darwin/hpc/profiles", { timeoutMs: HPC_READ_TIMEOUT_MS });
}

export async function submitHpcJob(slug, body = {}) {
  const request = normalizeHpcSubmitRequest(slug, body);
  if (hasMappedHpcWorkstream(slug)) {
    const workstreamId = resolveHpcWorkstreamId(slug);
    const orchestration = await proxyDarwinHpc(
      "POST",
      `/api/darwin/workstreams/${workstreamId}/workbench-run`,
      {
        body: buildWorkbenchRunRequest(slug, request),
        timeoutMs: HPC_SUBMIT_TIMEOUT_MS
      }
    );
    return {
      job_id: orchestration.run?.submitted_job_id,
      job_name: `darwin-${request.profile_id}-${request.parameters.run_label}`,
      partition: request.profile_id.startsWith("gpu-") ? "gpu" : "cpu",
      profile_id: request.profile_id,
      remote_workdir: null,
      submitted_at:
        orchestration.run?.lifecycle_transitions?.[0]?.transitioned_at || new Date().toISOString(),
      parameters: request.parameters,
      projectSlug: slug,
      workstream_id: workstreamId,
      published_result_job_id: orchestration.run?.published_result_job_id,
      result_binding_id: orchestration.result_binding?.binding_id,
      run_result_identity_receipt_id: orchestration.run_result_identity_receipt?.receipt_id,
      run_scoped_publication_id: orchestration.run_scoped_publication?.publication_id,
      deterministic_result_binding_id:
        orchestration.deterministic_result_binding?.binding_id,
      via: "cockpit-darwin-hpc-workbench-run"
    };
  }

  const payload = await proxyDarwinHpc("POST", "/api/darwin/hpc/jobs/submit", {
    body: request,
    timeoutMs: HPC_SUBMIT_TIMEOUT_MS
  });
  return {
    ...payload,
    profile_id: payload.profile_id || request.profile_id,
    parameters: payload.parameters || request.parameters,
    projectSlug: slug,
    via: "cockpit-darwin-hpc"
  };
}

export async function getHpcJobStatus(jobId) {
  const payload = await proxyDarwinHpc("GET", `/api/darwin/hpc/jobs/${jobId}`, {
    timeoutMs: HPC_READ_TIMEOUT_MS
  });
  return {
    ...payload,
    via: "cockpit-darwin-hpc"
  };
}

export async function getHpcJobTextArtifact(jobId, stream) {
  const payload = await proxyDarwinHpc("GET", `/api/darwin/hpc/jobs/${jobId}/${stream}`, {
    timeoutMs: HPC_READ_TIMEOUT_MS
  });
  return {
    ...payload,
    stream,
    via: "cockpit-darwin-hpc"
  };
}

export async function getHpcJobArtifactManifest(jobId) {
  const payload = await proxyDarwinHpcAdapterJson(`/jobs/${jobId}/artifact-manifest`, {
    timeoutMs: HPC_READ_TIMEOUT_MS
  });
  return {
    ...payload,
    via: "cockpit-darwin-hpc"
  };
}

export async function getHpcJobObject(jobId, stream) {
  return proxyDarwinHpcObject(`/jobs/${jobId}/${stream}`, {
    timeoutMs: HPC_OBJECT_TIMEOUT_MS
  });
}

export async function listHpcResults(query = {}) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query || {})) {
    const normalized = cleanString(value);
    if (normalized) {
      params.set(key, normalized);
    }
  }
  const suffix = params.size > 0 ? `?${params.toString()}` : "";
  const payload = await proxyDarwinHpc("GET", `/api/darwin/hpc/results${suffix}`, {
    timeoutMs: HPC_READ_TIMEOUT_MS
  });
  return {
    ...payload,
    via: "cockpit-darwin-hpc"
  };
}

export async function getHpcResult(slug, jobId) {
  try {
    const payload = await proxyDarwinHpc("GET", `/api/darwin/hpc/results/${jobId}`, {
      timeoutMs: HPC_READ_TIMEOUT_MS
    });
    return {
      ...payload,
      via: "cockpit-darwin-hpc"
    };
  } catch (error) {
    if (error.code !== ErrorCode.BAD_REQUEST.code && error.code !== ErrorCode.NOT_FOUND.code) {
      throw error;
    }
  }

  const fallback = await getHpcDeterministicResultBinding(slug, jobId);
  return {
    job_id: asNumericJobId(jobId),
    submitted_job_id: fallback.binding.submitted_job_id,
    published_result_job_id: fallback.binding.published_result_job_id,
    resolved_result_lookup_job_id: fallback.binding.resolved_result_lookup_job_id,
    result_manifest_job_id: fallback.binding.result_manifest_job_id,
    profile_id: fallback.publication.published_result_profile_id,
    requested_run_label: fallback.binding.requested_run_label,
    published_result_run_label: fallback.binding.published_result_run_label,
    final_job_state: fallback.publication.final_job_state,
    publication_state: fallback.publication.publication_state,
    result_lookup_scope: fallback.binding.result_lookup_scope,
    published_result_manifest_key: fallback.binding.published_result_manifest_key,
    result_manifest_object_key: fallback.binding.result_manifest_object_key,
    workstream_id: fallback.workstream_id,
    deterministic_result_binding: fallback.binding,
    run_scoped_publication: fallback.publication,
    run_result_identity_receipt: fallback.receipt,
    via: fallback.via
  };
}

export async function getHpcResultManifest(slug, jobId) {
  try {
    const payload = await proxyDarwinHpc("GET", `/api/darwin/hpc/results/${jobId}/manifest`, {
      timeoutMs: HPC_READ_TIMEOUT_MS
    });
    return {
      ...payload,
      via: "cockpit-darwin-hpc"
    };
  } catch (error) {
    if (error.code !== ErrorCode.BAD_REQUEST.code && error.code !== ErrorCode.NOT_FOUND.code) {
      throw error;
    }
  }

  const fallback = await getHpcDeterministicResultBinding(slug, jobId);
  return {
    job_id: asNumericJobId(jobId),
    workstream_id: fallback.workstream_id,
    contract_kind: "cockpit-hpc-result-manifest-fallback",
    contract_version: "cockpit-hpc-result-manifest-fallback-v1",
    result_lookup_scope: fallback.binding.result_lookup_scope,
    published_result_manifest_key: fallback.binding.published_result_manifest_key,
    result_manifest_object_key: fallback.binding.result_manifest_object_key,
    deterministic_result_binding: fallback.binding,
    run_scoped_publication: fallback.publication,
    run_result_identity_receipt: fallback.receipt,
    via: fallback.via
  };
}

// ─── K8s Job manifest rendering ───────────────────────────────────────

function renderK8sJob({ slug, campaign, image, command, resources, dataMounts, timeoutSec, jobId, extraLabels }) {
  const cpuReq = resources?.cpu || "2";
  const memReq = resources?.memory || "8Gi";
  // Default limit = request (avoids NaN when cpuReq is a millicore string like "100m").
  // Caller can override via resources.cpuLimit / memoryLimit.
  const cpuLim = resources?.cpuLimit || cpuReq;
  const memLim = resources?.memoryLimit || memReq;
  const gpu = Number(resources?.gpu || 0);

  const volumes = [];
  const volumeMounts = [];
  for (const profile of (dataMounts || [])) {
    const m = MOUNT_PROFILES[profile];
    if (!m) continue;
    volumes.push(m.volume);
    volumeMounts.push(m.mount);
  }

  // GPU-specific additions
  const nodeSelector = {};
  const tolerations = [
    { key: "node-role.kubernetes.io/control-plane", effect: "NoSchedule", operator: "Exists" }
  ];
  const containerResources = {
    requests: { cpu: cpuReq, memory: memReq },
    limits: { cpu: cpuLim, memory: memLim }
  };

  if (gpu > 0) {
    nodeSelector["sounio.dev/accelerator-class"] = "gpu";
    tolerations.push(
      { key: "sounio.dev/pool", operator: "Equal", value: "gpu-batch", effect: "NoSchedule" },
      { key: "sounio.dev/compute", operator: "Equal", value: "heavy", effect: "NoSchedule" }
    );
    containerResources.requests["nvidia.com/gpu"] = gpu;
    containerResources.limits["nvidia.com/gpu"] = gpu;
  }

  const spec = {
    apiVersion: "batch/v1",
    kind: "Job",
    metadata: {
      name: `job-${slug}-${jobId}`,
      namespace: NAMESPACE,
      labels: {
        "app.kubernetes.io/managed-by": "cockpit",
        project: slug,
        campaign: campaign || "adhoc",
        "cockpit.sounio.dev/job-id": jobId,
        ...(extraLabels || {})
      },
      annotations: {
        "cockpit.sounio.dev/submitted-at": new Date().toISOString()
      }
    },
    spec: {
      backoffLimit: 2,
      ttlSecondsAfterFinished: 86400,  // 24h auto-cleanup
      activeDeadlineSeconds: timeoutSec || 3600,
      template: {
        metadata: {
          labels: {
            "app.kubernetes.io/managed-by": "cockpit",
            project: slug,
            campaign: campaign || "adhoc"
          }
        },
        spec: {
          restartPolicy: "OnFailure",
          // emptyDir mounts default to root:root 0755. Runner images run as
          // uid 1000; fsGroup gives them group ownership so `git clone`
          // into /work succeeds without chown. Harmless on GPU pods too.
          securityContext: { fsGroup: 1000 },
          ...(gpu > 0 && { runtimeClassName: "nvidia" }),
          ...(Object.keys(nodeSelector).length && { nodeSelector }),
          tolerations,
          containers: [{
            name: "job",
            image: image || DEFAULT_IMAGE,
            command: Array.isArray(command) ? command : ["/bin/sh", "-c", String(command)],
            resources: containerResources,
            volumeMounts
          }],
          volumes
        }
      }
    }
  };

  return spec;
}

// ─── Lifecycle operations ────────────────────────────────────────────

export async function submitJob(slug, rawOpts) {
  // Preset expansion: body wins over preset on any shared field; preset
  // stamps sounio.dev/preset label used by the reconciler as kind_label.
  const opts = applyPreset(rawOpts.preset, rawOpts);
  const kind = opts.kind || "k8s";
  const jobId = shortId();

  if (kind === "slurm") {
    // Stub — future Slinky/sbatch integration
    const err = new Error("slurm submission not yet wired (use kind: 'k8s' for now)");
    err.statusCode = 501;
    throw err;
  }

  const manifest = renderK8sJob({
    slug,
    campaign: opts.campaign,
    image: opts.image,
    command: opts.command,
    resources: opts.resources,
    dataMounts: opts.data_mounts || opts.dataMounts,
    timeoutSec: opts.timeout_seconds || opts.timeoutSec,
    jobId,
    extraLabels: opts.labels
  });

  await runKubectl(
    ["-n", NAMESPACE, "apply", "-f", "-"],
    { input: JSON.stringify(manifest) }
  );

  return {
    job_id: jobId,
    job_name: manifest.metadata.name,
    namespace: NAMESPACE,
    kind,
    preset: opts._preset || null,
    status: "submitted",
    status_url: `/api/projects/${slug}/jobs/${jobId}`,
    truthMode: "observed"
  };
}

// Compute a normalized phase from a K8s Job manifest. Shared between the
// single-job status endpoint and the reconciler so state classification
// stays consistent.
export function phaseFromJobManifest(job) {
  const conditions = job.status?.conditions || [];
  const completed = conditions.find((c) => c.type === "Complete" && c.status === "True");
  const failed = conditions.find((c) => c.type === "Failed" && c.status === "True");
  if (completed) return "Succeeded";
  if (failed) return "Failed";
  if ((job.status?.active || 0) === 0 && !completed && !failed) return "Pending";
  return "Running";
}

// Reconciler-facing: list every cockpit-managed Job in the namespace, not
// scoped to a single project slug.
export async function listAllCockpitJobs() {
  try {
    const raw = await runKubectl([
      "-n", NAMESPACE,
      "get", "jobs",
      "-l", "app.kubernetes.io/managed-by=cockpit",
      "-o", "json"
    ]);
    return JSON.parse(raw).items || [];
  } catch {
    return [];
  }
}

// Tail pod logs for a job — used by the reconciler to capture error context
// when a Job terminates in Failed phase. Best-effort; returns empty on any
// kubectl hiccup so a single bad pod doesn't break the whole reconciler tick.
export async function tailJobLogs(jobId, lines = 20) {
  try {
    const raw = await runKubectl([
      "-n", NAMESPACE,
      "logs", `-l`, `cockpit.sounio.dev/job-id=${jobId}`,
      "--tail", String(lines),
      "--all-containers=true"
    ], { timeoutMs: 8000 });
    return raw.trim();
  } catch {
    return "";
  }
}

export async function getJobStatus(slug, jobId) {
  const jobName = `job-${slug}-${jobId}`;
  try {
    const raw = await runKubectl([
      "-n", NAMESPACE,
      "get", "job", jobName,
      "-o", "json"
    ]);
    const job = JSON.parse(raw);

    const phase = phaseFromJobManifest(job);

    // Pull pod list to give more context
    let pods = [];
    try {
      const podsRaw = await runKubectl([
        "-n", NAMESPACE,
        "get", "pods",
        "-l", `cockpit.sounio.dev/job-id=${jobId}`,
        "-o", "json"
      ]);
      pods = (JSON.parse(podsRaw).items || []).map(p => ({
        name: p.metadata.name,
        phase: p.status.phase,
        node: p.spec.nodeName,
        ready: p.status.containerStatuses?.every(c => c.ready) ?? false
      }));
    } catch { /* pods optional */ }

    return {
      job_id: jobId,
      job_name: jobName,
      phase,
      active: job.status?.active || 0,
      succeeded: job.status?.succeeded || 0,
      failed: job.status?.failed || 0,
      startTime: job.status?.startTime,
      completionTime: job.status?.completionTime,
      pods,
      truthMode: "observed"
    };
  } catch (e) {
    if (e.message.includes("NotFound") || e.message.includes("not found")) {
      return { job_id: jobId, phase: "NotFound", truthMode: "declared" };
    }
    throw e;
  }
}

export async function listJobs(slug) {
  try {
    const raw = await runKubectl([
      "-n", NAMESPACE,
      "get", "jobs",
      "-l", `app.kubernetes.io/managed-by=cockpit,project=${slug}`,
      "-o", "json"
    ]);
    const jobs = JSON.parse(raw).items || [];
    return jobs.map(j => ({
      job_id: j.metadata.labels["cockpit.sounio.dev/job-id"],
      job_name: j.metadata.name,
      campaign: j.metadata.labels.campaign,
      submitted_at: j.metadata.annotations?.["cockpit.sounio.dev/submitted-at"],
      active: j.status?.active || 0,
      succeeded: j.status?.succeeded || 0,
      failed: j.status?.failed || 0
    }));
  } catch {
    return [];
  }
}

export async function cancelJob(slug, jobId) {
  const jobName = `job-${slug}-${jobId}`;
  await runKubectl([
    "-n", NAMESPACE,
    "delete", "job", jobName,
    "--ignore-not-found"
  ]);
  return { job_id: jobId, status: "cancelled", truthMode: "observed" };
}

// ─── Route registration ─────────────────────────────────────────────

export function registerJobRoutes(app) {
  app.get(
    "/api/projects/:slug/hpc/profiles",
    withEnvelope(async (req) => ({
      data: {
        projectSlug: req.params.slug,
        ...(await listHpcProfiles())
      }
    }))
  );

  app.post(
    "/api/projects/:slug/hpc/jobs/submit",
    idempotent(),
    withEnvelope(async (req) => ({
      data: await submitHpcJob(req.params.slug, req.body || {})
    }))
  );

  app.get(
    "/api/projects/:slug/hpc/jobs/:jobId",
    withEnvelope(async (req) => ({
      data: {
        projectSlug: req.params.slug,
        ...(await getHpcJobStatus(req.params.jobId))
      }
    }))
  );

  app.get(
    "/api/projects/:slug/hpc/jobs/:jobId/artifact",
    async (req, res, next) => {
      try {
        const artifact = await getHpcJobObject(req.params.jobId, "artifact");
        res.set("Content-Type", artifact.contentType);
        if (artifact.contentDisposition) {
          res.set("Content-Disposition", artifact.contentDisposition);
        }
        res.send(artifact.body);
      } catch (error) {
        next(error);
      }
    }
  );

  app.get(
    "/api/projects/:slug/hpc/jobs/:jobId/artifact-manifest",
    withEnvelope(async (req) => ({
      data: {
        projectSlug: req.params.slug,
        ...(await getHpcJobArtifactManifest(req.params.jobId))
      }
    }))
  );

  app.get(
    "/api/projects/:slug/hpc/jobs/:jobId/stdout-object",
    async (req, res, next) => {
      try {
        const artifact = await getHpcJobObject(req.params.jobId, "stdout");
        res.set("Content-Type", artifact.contentType);
        if (artifact.contentDisposition) {
          res.set("Content-Disposition", artifact.contentDisposition);
        }
        res.send(artifact.body);
      } catch (error) {
        next(error);
      }
    }
  );

  app.get(
    "/api/projects/:slug/hpc/jobs/:jobId/stdout",
    withEnvelope(async (req) => ({
      data: {
        projectSlug: req.params.slug,
        ...(await getHpcJobTextArtifact(req.params.jobId, "stdout"))
      }
    }))
  );

  app.get(
    "/api/projects/:slug/hpc/jobs/:jobId/stderr-object",
    async (req, res, next) => {
      try {
        const artifact = await getHpcJobObject(req.params.jobId, "stderr");
        res.set("Content-Type", artifact.contentType);
        if (artifact.contentDisposition) {
          res.set("Content-Disposition", artifact.contentDisposition);
        }
        res.send(artifact.body);
      } catch (error) {
        next(error);
      }
    }
  );

  app.get(
    "/api/projects/:slug/hpc/jobs/:jobId/stderr",
    withEnvelope(async (req) => ({
      data: {
        projectSlug: req.params.slug,
        ...(await getHpcJobTextArtifact(req.params.jobId, "stderr"))
      }
    }))
  );

  app.get(
    "/api/projects/:slug/hpc/results",
    withEnvelope(async (req) => ({
      data: {
        projectSlug: req.params.slug,
        ...(await listHpcResults(req.query || {}))
      }
    }))
  );

  app.get(
    "/api/projects/:slug/hpc/results/:jobId",
    withEnvelope(async (req) => ({
      data: {
        projectSlug: req.params.slug,
        ...(await getHpcResult(req.params.slug, req.params.jobId))
      }
    }))
  );

  app.get(
    "/api/projects/:slug/hpc/results/:jobId/manifest",
    withEnvelope(async (req) => ({
      data: {
        projectSlug: req.params.slug,
        ...(await getHpcResultManifest(req.params.slug, req.params.jobId))
      }
    }))
  );

  app.post("/api/projects/:slug/jobs/submit", idempotent(), async (req, res) => {
    try {
      const result = await submitJob(req.params.slug, req.body || {});
      res.json({ ...result, requestId: req.requestId });
    } catch (e) {
      res.status(e.statusCode || 500).json({
        error: e.message,
        truthMode: "stale",
        retryable: !e.statusCode || e.statusCode >= 500,
        requestId: req.requestId
      });
    }
  });

  app.get("/api/projects/:slug/jobs/:jobId", async (req, res) => {
    try {
      const status = await getJobStatus(req.params.slug, req.params.jobId);
      res.json(status);
    } catch (e) {
      res.status(500).json({ error: e.message, truthMode: "stale" });
    }
  });

  app.get("/api/projects/:slug/jobs", async (req, res) => {
    try {
      const jobs = await listJobs(req.params.slug);
      res.json({ projectSlug: req.params.slug, jobs, truthMode: "observed" });
    } catch (e) {
      res.status(500).json({ error: e.message, truthMode: "stale" });
    }
  });

  app.get("/api/jobs/presets", (_req, res) => {
    res.json({ presets: listPresets(), truthMode: "observed" });
  });

  app.post("/api/projects/:slug/jobs/:jobId/cancel", idempotent(), async (req, res) => {
    try {
      const result = await cancelJob(req.params.slug, req.params.jobId);
      res.json({ ...result, requestId: req.requestId });
    } catch (e) {
      res.status(500).json({ error: e.message, truthMode: "stale" });
    }
  });
}
