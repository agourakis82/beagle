// cluster-ops-routes.mjs
//
// Darwin Cluster Ops: readback-first supercomputing control lane.
// Mutating actions are allowlisted and require an Action Ledger receipt that
// has already been confirmed by a human/operator.

import fsp from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";
import { idempotent } from "./contract.mjs";
import { listActionLedgerEntries } from "./action-ledger-routes.mjs";

const ROOT = process.env.PROJECT_COCKPIT_ROOT || "/home/devsounio";
const BEAGLE_ROOT = process.env.PROJECT_COCKPIT_BEAGLE_ROOT || path.join(ROOT, "beagle");
const HPC_ROOT =
  process.env.PROJECT_COCKPIT_HPC_ROOT || path.join(BEAGLE_ROOT, "k8s", "hpc-sota");
const GPU_LEASE_BIN =
  process.env.PROJECT_COCKPIT_GPU_LEASE_BIN || path.join(HPC_ROOT, "ops", "gpu-lease");
const GPU_DOMAINS_FILE =
  process.env.PROJECT_COCKPIT_GPU_DOMAINS_FILE || path.join(HPC_ROOT, "GPU_RESOURCE_DOMAINS.yaml");
const DATA_DIR =
  process.env.CLUSTER_OPS_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  "/var/lib/cockpit";
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "kubectl";
const ACTION_PROJECT = process.env.PROJECT_COCKPIT_CLUSTER_OPS_PROJECT || "beagle";
const DEFAULT_TIMEOUT_MS = 30_000;

const HOSTS = {
  "r770-proxmox": "root@10.100.100.1",
  "t560-proxmox": "root@10.100.100.2",
  "5860-proxmox": "root@10.100.100.3",
  "r740-proxmox": "root@10.100.100.4"
};

const WORKER_HOSTS = new Set(["r770-proxmox", "5860-proxmox", "r740-proxmox"]);

function cleanValue(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  return String(value).trim();
}

function safeId(value, fallback = "unknown") {
  return cleanValue(value, fallback).replace(/[^a-zA-Z0-9_.:-]/g, "_").slice(0, 180);
}

function nowIso() {
  return new Date().toISOString();
}

function runCommand(command, args = [], options = {}) {
  const timeoutMs = options.timeoutMs || DEFAULT_TIMEOUT_MS;
  const cwd = options.cwd || ROOT;
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd,
      env: { ...process.env, ...(options.env || {}) },
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, timeoutMs);
    child.stdout.on("data", (data) => {
      stdout += data.toString();
    });
    child.stderr.on("data", (data) => {
      stderr += data.toString();
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({
        ok: false,
        command,
        args,
        cwd,
        code: null,
        timedOut,
        stdout,
        stderr: stderr || error.message
      });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({
        ok: code === 0 && !timedOut,
        command,
        args,
        cwd,
        code,
        timedOut,
        stdout,
        stderr
      });
    });
  });
}

async function runJson(command, args = [], options = {}) {
  const result = await runCommand(command, args, options);
  if (!result.ok) {
    return { ok: false, error: result.stderr || result.stdout || `exit ${result.code}`, result };
  }
  try {
    return { ok: true, data: JSON.parse(result.stdout), result };
  } catch (error) {
    return { ok: false, error: error.message, result };
  }
}

function bash(script, options = {}) {
  return runCommand("bash", ["-lc", script], options);
}

function hpcBash(script, options = {}) {
  return bash(script, { cwd: HPC_ROOT, ...options });
}

function runGpuLease(args = [], options = {}) {
  return runCommand(GPU_LEASE_BIN, args, {
    cwd: HPC_ROOT,
    ...options,
    env: {
      ...(options.env || {}),
      NODE: "",
      ACTION: ""
    }
  });
}

function parseThinPoolPct(output) {
  const dataLine = String(output || "")
    .split("\n")
    .find((line) => line.trim().startsWith("data,"));
  if (!dataLine) return null;
  const pct = Number.parseFloat(dataLine.split(",")[2]);
  return Number.isFinite(pct) ? pct : null;
}

function summarizeNodes(nodes = []) {
  return nodes.map((node) => {
    const labels = node.metadata?.labels || {};
    const capacity = node.status?.capacity || {};
    const allocatable = node.status?.allocatable || {};
    const ready = (node.status?.conditions || []).find((item) => item.type === "Ready");
    return {
      name: node.metadata?.name || "",
      ready: ready?.status === "True",
      role: labels["node-role.kubernetes.io/control-plane"] !== undefined ? "control-plane" : "worker",
      version: node.status?.nodeInfo?.kubeletVersion || "",
      kernel: node.status?.nodeInfo?.kernelVersion || "",
      osImage: node.status?.nodeInfo?.osImage || "",
      containerRuntime: node.status?.nodeInfo?.containerRuntimeVersion || "",
      gpu: {
        capacity: Number(capacity["nvidia.com/gpu"] || 0),
        allocatable: Number(allocatable["nvidia.com/gpu"] || 0),
        accelerator: labels["sounio.dev/accelerator"] || "",
        acceleratorClass: labels["sounio.dev/accelerator-class"] || ""
      },
      labels: {
        pool: labels["sounio.dev/pool"] || "",
        runtimeRole: labels["sounio.dev/runtime-role"] || "",
        orangefsClient: labels["sounio.dev/orangefs-client"] || "",
        slurmGpuOrangefs: labels["sounio.dev/slurm-worker-gpuorangefs"] || "",
        storageProfile: labels["sounio.dev/storage-profile"] || ""
      }
    };
  });
}

function summarizePods(pods = []) {
  return pods.map((pod) => ({
    namespace: pod.metadata?.namespace || "",
    name: pod.metadata?.name || "",
    phase: pod.status?.phase || "",
    node: pod.spec?.nodeName || "",
    reason: pod.status?.reason || ""
  }));
}

function parsePodRows(output = "") {
  return String(output)
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [namespace = "", name = "", phase = "", node = "", reason = ""] = line.split(/\s+/);
      return {
        namespace: namespace === "<none>" ? "" : namespace,
        name: name === "<none>" ? "" : name,
        phase: phase === "<none>" ? "" : phase,
        node: node === "<none>" ? "" : node,
        reason: reason === "<none>" ? "" : reason
      };
    });
}

async function readKubernetesLane() {
  const [nodesRaw, pendingRaw, unknownRaw, failedRaw, ciliumConfigRaw, ciliumDsRaw, ciliumEnvoyRaw] = await Promise.all([
    runJson(KUBECTL, ["get", "nodes", "-o", "json"], { timeoutMs: 10_000 }),
    runJson(
      KUBECTL,
      ["get", "pods", "-A", "--field-selector=status.phase=Pending", "-o", "json"],
      { timeoutMs: 10_000 }
    ),
    runJson(KUBECTL, ["get", "pods", "-A", "--field-selector=status.phase=Unknown", "-o", "json"], {
      timeoutMs: 10_000
    }),
    runCommand(
      KUBECTL,
      [
        "get",
        "pods",
        "-A",
        "--field-selector=status.phase=Failed",
        "-o",
        "custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,NODE:.spec.nodeName,REASON:.status.reason",
        "--no-headers"
      ],
      { timeoutMs: 10_000 }
    ),
    runJson(KUBECTL, ["-n", "kube-system", "get", "cm", "cilium-config", "-o", "json"], { timeoutMs: 10_000 }),
    runJson(KUBECTL, ["-n", "kube-system", "get", "ds", "cilium", "-o", "json"], { timeoutMs: 10_000 }),
    runJson(KUBECTL, ["-n", "kube-system", "get", "ds", "cilium-envoy", "-o", "json"], { timeoutMs: 10_000 })
  ]);
  const nodes = summarizeNodes(nodesRaw.data?.items || []);
  const activeUnhealthyPods = [
    ...summarizePods(pendingRaw.data?.items || []),
    ...summarizePods(unknownRaw.data?.items || [])
  ];
  const historicalFailedPods = failedRaw.ok ? parsePodRows(failedRaw.stdout) : [];
  const ciliumContainer = (ciliumDsRaw.data?.spec?.template?.spec?.containers || []).find(
    (container) => container.name === "cilium-agent"
  );
  const envoyContainer = (ciliumEnvoyRaw.data?.spec?.template?.spec?.containers || [])[0];
  const config = ciliumConfigRaw.data?.data || {};
  const errors = [nodesRaw, pendingRaw, unknownRaw, failedRaw, ciliumConfigRaw, ciliumDsRaw, ciliumEnvoyRaw]
    .filter((item) => !item.ok)
    .map((item) => item.error || item.stderr || item.stdout || `exit ${item.code}`);
  return {
    status:
      nodes.length && nodes.every((node) => node.ready) && activeUnhealthyPods.length === 0 && errors.length === 0
        ? "healthy"
        : "attention",
    nodes,
    counts: {
      nodes: nodes.length,
      ready: nodes.filter((node) => node.ready).length,
      unhealthyPods: activeUnhealthyPods.length,
      activeUnhealthyPods: activeUnhealthyPods.length,
      historicalFailedPods: historicalFailedPods.length,
      gpuCapacity: nodes.reduce((sum, node) => sum + node.gpu.capacity, 0),
      gpuAllocatable: nodes.reduce((sum, node) => sum + node.gpu.allocatable, 0)
    },
    unhealthyPods: activeUnhealthyPods,
    historicalFailedPods: historicalFailedPods.slice(0, 25),
    cilium: {
      status: ciliumDsRaw.ok && ciliumEnvoyRaw.ok ? "observed" : "stale",
      version: ciliumContainer?.image || "",
      envoyImage: envoyContainer?.image || "",
      kubeProxyReplacement: config["kube-proxy-replacement"] || "",
      routingMode: config["routing-mode"] || "",
      autoDirectNodeRoutes: config["auto-direct-node-routes"] || "",
      devices: config.devices || "",
      bpfLbSock: config["bpf-lb-sock"] || ""
    },
    errors
  };
}

async function readSlurmLane() {
  const [ping, sinfo, sacct] = await Promise.all([
    hpcBash("source ops/lab-ops.sh && lab_slurm_exec scontrol ping", { timeoutMs: 12_000 }),
    hpcBash("source ops/lab-ops.sh && lab_slurm_exec sinfo --noheader --format='%P|%a|%D|%t|%N'", {
      timeoutMs: 12_000
    }),
    hpcBash(
      "source ops/lab-ops.sh && lab_slurm_exec sacct -S now-6hours --noheader --parsable2 --format=JobID,JobName,Partition,Account,QOS,State,ExitCode,Start,End,NodeList | tail -n 24",
      { timeoutMs: 15_000 }
    )
  ]);
  const partitions = sinfo.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [partition, availability, nodes, state, nodeList] = line.split("|");
      return { partition, availability, nodes: Number(nodes || 0), state, nodeList };
    });
  const recentJobs = sacct.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [jobId, jobName, partition, account, qos, state, exitCode, start, end, nodeList] = line.split("|");
      return { jobId, jobName, partition, account, qos, state, exitCode, start, end, nodeList };
    });
  return {
    status: ping.ok && /UP/.test(ping.stdout) ? "healthy" : "stale",
    ping: ping.stdout.trim() || ping.stderr.trim(),
    partitions,
    recentJobs,
    errors: [ping, sinfo, sacct].filter((item) => !item.ok).map((item) => item.stderr || item.stdout)
  };
}

async function readOrangefsLane() {
  const status = await hpcBash("source ops/lab-ops.sh && lab_orangefs_status", { timeoutMs: 30_000 });
  const thinPoolPct = parseThinPoolPct(status.stdout);
  const risk =
    thinPoolPct === null
      ? "unknown"
      : thinPoolPct >= 95
        ? "red"
        : thinPoolPct >= 85
          ? "yellow"
          : "green";
  const workerMounts = [...status.stdout.matchAll(/-- (slurm-pilot-worker-gpuorangefs-[^\s]+) \(([^)]+)\) --([\s\S]*?)(?=\n-- |== OrangeFS server backends ==|$)/g)]
    .map((match) => ({
      pod: match[1],
      node: match[2],
      mounted: match[3].includes("type pvfs2"),
      df: (match[3].split("\n").find((line) => line.includes("/orangefs/training")) || "").trim()
    }));
  return {
    status: status.ok && risk !== "red" ? "healthy" : status.ok ? "attention" : "stale",
    risk,
    thinPoolPct,
    workerMounts,
    capacityNote:
      "OrangeFS export size follows the smallest effective server backing store; 5860 server02 is the current growth ceiling.",
    stdout: status.stdout.slice(0, 12_000),
    stderr: status.stderr,
    error: status.ok ? "" : status.stderr || status.stdout
  };
}

async function readHostFreshness() {
  const entries = await Promise.all(
    Object.entries(HOSTS).map(async ([node, host]) => {
      const result = await runCommand(
        "ssh",
        [
          "-4",
          "-o",
          "BatchMode=yes",
          "-o",
          "ConnectTimeout=5",
          host,
          "test -f /var/run/reboot-required && echo reboot_required=yes || echo reboot_required=no; apt list --upgradable 2>/dev/null | tail -n +2 | wc -l"
        ],
        { timeoutMs: 12_000 }
      );
      const lines = result.stdout.trim().split("\n");
      return {
        node,
        status: result.ok ? "observed" : "blocked",
        rebootRequired: result.ok ? lines[0]?.replace("reboot_required=", "") || "unknown" : "unknown",
        aptUpgradable: result.ok ? Number(lines[1] || 0) : null,
        error: result.ok ? "" : cleanValue(result.stderr || result.stdout || "ssh unavailable")
      };
    })
  );
  return {
    status: entries.every((entry) => entry.status === "observed") ? "observed" : "partial",
    entries
  };
}

async function buildClusterOpsSummary() {
  const [kubernetes, slurm, orangefs, hosts] = await Promise.all([
    readKubernetesLane().catch((error) => ({ status: "stale", error: error.message })),
    readSlurmLane().catch((error) => ({ status: "stale", error: error.message })),
    readOrangefsLane().catch((error) => ({ status: "stale", error: error.message })),
    readHostFreshness().catch((error) => ({ status: "blocked", error: error.message, entries: [] }))
  ]);
  const risks = [];
  if (orangefs.risk === "red") {
    risks.push({
      severity: "red",
      layer: "orangefs",
      code: "ORANGEFS_5860_THIN_POOL_HIGH",
      summary: `5860 pve/data thin pool is ${orangefs.thinPoolPct?.toFixed?.(1) || orangefs.thinPoolPct}% full`
    });
  }
  if (hosts.status !== "observed") {
    risks.push({
      severity: "yellow",
      layer: "host",
      code: "HOST_FRESHNESS_BLOCKED",
      summary: "host apt/reboot freshness requires root/sudo SSH path"
    });
  }
  if (kubernetes.status !== "healthy") {
    risks.push({
      severity: "yellow",
      layer: "kubernetes",
      code: "K8S_ATTENTION",
      summary: "Kubernetes lane is not fully green"
    });
  }
  if (slurm.status !== "healthy") {
    risks.push({
      severity: "yellow",
      layer: "slurm",
      code: "SLURM_ATTENTION",
      summary: "Slurm lane is not fully green"
    });
  }
  return {
    schema: "darwin.cluster-ops.v0",
    generatedAt: nowIso(),
    title: "Darwin Cluster Ops",
    status: risks.some((risk) => risk.severity === "red") ? "red" : risks.length ? "yellow" : "green",
    policy: {
      mutationRule: "allowlisted actions require Action Ledger intent, confirmed:true, idempotency, and readback",
      controlPlaneProtection: "t560 host mutations are propose-only in v1",
      primaryRisk: "OrangeFS server02 on 5860 is the current storage growth ceiling"
    },
    lanes: { kubernetes, slurm, orangefs, hosts },
    risks,
    actions: listClusterOpsActions()
  };
}

function listClusterOpsActions() {
  return [
    action("route-doctor", "Route doctor", "readback", "Run hpc-route-doctor.", "low"),
    action("surface-doctor", "Surface doctor", "readback", "Run hpc-surface-doctor.", "low"),
    action("slurmdbd-doctor", "SlurmDBD doctor", "readback", "Run slurmdbd-backend-doctor.", "low"),
    action("workspace-doctor", "Workspace doctor", "readback", "Run workspace-platform-doctor.", "low"),
    action("orangefs-status", "OrangeFS status", "readback", "Read OrangeFS worker mounts and server backend ceiling.", "low"),
    action("slurm-nvidia-smi-smoke", "Slurm GPU smoke", "smoke", "Run a tiny nvidia-smi smoke through Slurm gpu-orangefs.", "medium"),
    action("orangefs-text-r740", "Text probe r740", "smoke", "Run the OrangeFS text-integrity probe on r740.", "medium"),
    action("orangefs-text-r770", "Text probe r770", "smoke", "Run the OrangeFS text-integrity probe on r770.", "medium"),
    action("orangefs-artifact-r740", "Artifact probe r740", "smoke", "Run the OrangeFS artifact probe on r740.", "medium"),
    action("orangefs-artifact-r770", "Artifact probe r770", "smoke", "Run the OrangeFS artifact probe on r770.", "medium"),
    action("host-apt-dry-run", "Host apt dry-run", "host", "Run apt-get -s upgrade on a worker host.", "medium", true),
    action("host-cordon", "Cordon worker", "host", "Cordon a worker node.", "high", true),
    action("host-drain-dry-run", "Drain dry-run", "host", "Dry-run a Kubernetes drain for a worker.", "high", true),
    action("host-drain", "Drain worker", "host", "Drain a worker node with ignore-daemonsets/delete-emptydir-data.", "high", true),
    action("host-uncordon", "Uncordon worker", "host", "Uncordon a worker node.", "medium", true),
    action("host-apt-upgrade", "Host apt upgrade", "host", "Run apt update and noninteractive upgrade on a worker.", "high", true),
    action("host-reboot", "Host reboot", "host", "Reboot a worker host after explicit confirmation.", "critical", true)
  ];
}

function action(id, label, kind, summary, risk, requiresTarget = false) {
  return {
    id,
    label,
    kind,
    summary,
    risk,
    requiresTarget,
    route: `/api/cluster/ops/actions/${id}/run`,
    requiresConfirmation: true,
    requiresLedger: true
  };
}

const GPU_LEASE_TRANSITIONS = {
  "serving-to-batch": {
    id: "gpu-lease-serving-to-batch",
    label: "GPU serving to batch",
    risk: "high",
    summary: "Park the node serving deployment and admit the GPU node to Slurm batch."
  },
  "batch-to-serving": {
    id: "gpu-lease-batch-to-serving",
    label: "GPU batch to serving",
    risk: "high",
    summary: "Require an idle Slurm node, quarantine it from batch, and restore the serving deployment."
  },
  "admit-batch": {
    id: "gpu-lease-admit-batch",
    label: "GPU admit batch",
    risk: "medium",
    summary: "Admit a GPU node to the Slurm gpu-orangefs batch pool."
  },
  quarantine: {
    id: "gpu-lease-quarantine",
    label: "GPU quarantine",
    risk: "high",
    summary: "Require no active Slurm jobs, then remove the GPU node from the Slurm batch pool."
  }
};

function getAction(id) {
  return listClusterOpsActions().find((item) => item.id === id);
}

function ensureConfirmed(body = {}, label = "cluster action") {
  if (body.confirmed === true) return;
  const error = new Error(`${label} requires confirmed: true`);
  error.statusCode = 400;
  throw error;
}

function ensureWorkerTarget(actionId, body = {}) {
  const target = cleanValue(body.targetNode || body.node || body.target);
  if (!target) {
    const error = new Error(`${actionId} requires targetNode`);
    error.statusCode = 400;
    throw error;
  }
  if (!WORKER_HOSTS.has(target)) {
    const error = new Error(`${actionId} target must be a worker node; t560 is propose-only in v1`);
    error.statusCode = 400;
    throw error;
  }
  return target;
}

function requireLedger(ledgerId) {
  const id = cleanValue(ledgerId);
  if (!id) {
    const error = new Error("cluster ops actions require ledgerId from a confirmed Action Ledger intent");
    error.statusCode = 400;
    throw error;
  }
  const record = listActionLedgerEntries(ACTION_PROJECT, { limit: 200 }).find(
    (entry) => entry.ledger_id === id
  );
  if (!record) {
    const error = new Error(`unknown Action Ledger id for ${ACTION_PROJECT}: ${id}`);
    error.statusCode = 404;
    throw error;
  }
  if (record.status !== "intent-confirmed") {
    const error = new Error(`Action Ledger id ${id} is ${record.status}; expected intent-confirmed`);
    error.statusCode = 409;
    throw error;
  }
  return record;
}

function requireLedgerForAction(ledgerId, expectedActionId) {
  const record = requireLedger(ledgerId);
  const actualActionId = cleanValue(record.actionId || record.proposal?.actionId);
  if (actualActionId !== expectedActionId) {
    const error = new Error(
      `Action Ledger id ${record.ledger_id} is for ${actualActionId || "unknown action"}; expected ${expectedActionId}`
    );
    error.statusCode = 409;
    throw error;
  }
  return record;
}

function parseYamlScalar(raw) {
  const value = cleanValue(raw);
  if (value === "\"\"" || value === "''") return "";
  if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }
  if (/^\d+$/.test(value)) return Number(value);
  return value;
}

function parseGpuDomainsYaml(text) {
  const domains = [];
  let inDomains = false;
  let current = null;
  for (const line of String(text || "").split("\n")) {
    if (/^domains:\s*$/.test(line)) {
      inDomains = true;
      continue;
    }
    if (!inDomains) continue;
    if (/^\S/.test(line) && !/^domains:\s*$/.test(line)) break;
    const item = line.match(/^  - name:\s*(.*)$/);
    if (item) {
      current = { name: parseYamlScalar(item[1]) };
      domains.push(current);
      continue;
    }
    const prop = line.match(/^    ([a-zA-Z0-9_]+):\s*(.*)$/);
    if (current && prop) {
      current[prop[1]] = parseYamlScalar(prop[2]);
    }
  }
  return domains;
}

async function readGpuDomains() {
  const raw = await fsp.readFile(GPU_DOMAINS_FILE, "utf8");
  return {
    schema: "darwin.gpu_resource_domains.v1",
    source: GPU_DOMAINS_FILE,
    domains: parseGpuDomainsYaml(raw)
  };
}

async function readGpuLeaseState() {
  const result = await runGpuLease(["json"], { timeoutMs: 60_000 });
  if (!result.ok) {
    const error = new Error(result.stderr || result.stdout || `gpu-lease json exited ${result.code}`);
    error.statusCode = 503;
    throw error;
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    error.statusCode = 502;
    error.message = `gpu-lease returned invalid JSON: ${error.message}`;
    throw error;
  }
}

async function buildGpuLeasePacket(projectSlug = "sounio") {
  const [state, domainDoc] = await Promise.all([readGpuLeaseState(), readGpuDomains()]);
  const domainsByNode = new Map((domainDoc.domains || []).map((domain) => [domain.node, domain]));
  const leases = (state.leases || []).map((lease) => {
    const domain = domainsByNode.get(lease.node) || null;
    return {
      ...lease,
      gpu_resource_domain: domain?.name || "",
      kueue_resource_flavor: domain?.kueue_resource_flavor || "",
      current_policy: domain?.current_policy || ""
    };
  });
  return {
    schema: "darwin.gpu_lease_control.v1",
    generatedAt: state.generated_at || nowIso(),
    projectSlug,
    stateFile: state.state_file || "/home/devsounio/projects/sounio/GPU_LEASES.json",
    leaseSchema: state.schema || "darwin.gpu_lease.v1",
    domains: domainDoc.domains || [],
    leases,
    policy: {
      authority: "gpu-lease wrapper today; Cockpit/Beagle API and Action Ledger for operator-facing transitions",
      kueueScope: "Kueue governs Kubernetes workloads only until a Slurm bridge exists.",
      mutationRule: "preview is dry-run/readback; apply requires confirmed Action Ledger intent and idempotency."
    },
    transitions: Object.values(GPU_LEASE_TRANSITIONS).map((transition) => ({
      ...transition,
      route: "/api/cluster/ops/gpu-leases/{node}/apply",
      previewRoute: "/api/cluster/ops/gpu-leases/{node}/preview",
      requiresLedger: true,
      requiresConfirmation: true
    })),
    truthMode: "observed"
  };
}

function getGpuTransition(body = {}) {
  const transitionId = cleanValue(body.transition || body.action || body.actionId);
  const transition = GPU_LEASE_TRANSITIONS[transitionId];
  if (!transition) {
    const error = new Error(`unknown GPU lease transition: ${transitionId || "(missing)"}`);
    error.statusCode = 400;
    throw error;
  }
  return { transitionId, transition };
}

async function resolveGpuLeaseArgs(node, body = {}, { dryRun = false } = {}) {
  const targetNode = cleanValue(node);
  if (!WORKER_HOSTS.has(targetNode)) {
    const error = new Error(`GPU lease target must be one of: ${[...WORKER_HOSTS].join(", ")}`);
    error.statusCode = 400;
    throw error;
  }
  const { transitionId, transition } = getGpuTransition(body);
  const domainDoc = await readGpuDomains();
  const domain = (domainDoc.domains || []).find((item) => item.node === targetNode) || null;
  const deployment = cleanValue(body.deployment || body.servingDeployment || domain?.preferred_serving_deployment);
  const args = [];
  if (dryRun) args.push("--dry-run");
  args.push(transitionId, targetNode);
  if (transitionId === "batch-to-serving") {
    if (!deployment) {
      const error = new Error("batch-to-serving requires deployment or a preferred_serving_deployment domain mapping");
      error.statusCode = 400;
      throw error;
    }
    args.push(deployment);
  }
  return { targetNode, transitionId, transition, domain, deployment, args };
}

async function previewGpuLeaseTransition(node, body = {}) {
  const resolved = await resolveGpuLeaseArgs(node, body, { dryRun: true });
  const result = await runGpuLease(resolved.args, { timeoutMs: 90_000 });
  return {
    schema: "darwin.gpu_lease_preview.v1",
    generatedAt: nowIso(),
    ok: result.ok,
    targetNode: resolved.targetNode,
    transition: resolved.transitionId,
    actionId: resolved.transition.id,
    risk: resolved.transition.risk,
    command: [GPU_LEASE_BIN, ...resolved.args].join(" "),
    domain: resolved.domain,
    deployment: resolved.deployment,
    proposal: {
      id: resolved.transition.id,
      actionId: resolved.transition.id,
      label: `${resolved.transition.label}: ${resolved.targetNode}`,
      kind: "gpu-lease",
      risk: resolved.transition.risk,
      summary: resolved.transition.summary,
      route: `/api/cluster/ops/gpu-leases/${resolved.targetNode}/apply`,
      command: [GPU_LEASE_BIN, ...resolved.args.filter((arg) => arg !== "--dry-run")].join(" "),
      requiresConfirmation: true
    },
    actionLedger: {
      projectSlug: ACTION_PROJECT,
      proposeRoute: `/api/projects/${ACTION_PROJECT}/actions/propose`,
      confirmIntentRoute: `/api/projects/${ACTION_PROJECT}/actions/{ledger_id}/confirm-intent`
    },
    result: {
      code: result.code,
      timedOut: result.timedOut,
      stdout: result.stdout.slice(0, 20_000),
      stderr: result.stderr.slice(0, 20_000)
    },
    truthMode: "observed"
  };
}

async function applyGpuLeaseTransition(node, body = {}) {
  const resolved = await resolveGpuLeaseArgs(node, body, { dryRun: false });
  ensureConfirmed(body, resolved.transition.label);
  const ledger = requireLedgerForAction(body.ledgerId || body.ledger_id, resolved.transition.id);
  const result = await runGpuLease(resolved.args, {
    timeoutMs: Number(body.timeoutMs || 0) || 900_000
  });
  const readback = await buildGpuLeasePacket("sounio");
  const receipt = await writeReceipt({
    action: {
      id: resolved.transition.id,
      label: resolved.transition.label,
      kind: "gpu-lease",
      summary: resolved.transition.summary,
      risk: resolved.transition.risk,
      route: `/api/cluster/ops/gpu-leases/${resolved.targetNode}/apply`,
      requiresConfirmation: true,
      requiresLedger: true
    },
    body: { ...body, targetNode: resolved.targetNode },
    ledger,
    result,
    readback
  });
  return {
    ok: result.ok,
    schema: "darwin.gpu_lease_apply_result.v1",
    targetNode: resolved.targetNode,
    transition: resolved.transitionId,
    actionId: resolved.transition.id,
    ledger: {
      projectSlug: ACTION_PROJECT,
      ledger_id: ledger.ledger_id,
      status: ledger.status
    },
    result: {
      code: result.code,
      timedOut: result.timedOut,
      stdout: result.stdout.slice(0, 20_000),
      stderr: result.stderr.slice(0, 20_000)
    },
    receipt,
    readback,
    truthMode: "observed"
  };
}

async function executeAction(actionId, body = {}) {
  const target = cleanValue(body.targetNode || body.node || body.target);
  const common = { timeoutMs: Number(body.timeoutMs || 0) || undefined };
  switch (actionId) {
    case "route-doctor":
      return hpcBash("./ops/hpc-route-doctor.sh", { timeoutMs: common.timeoutMs || 25_000 });
    case "surface-doctor":
      return hpcBash("./ops/hpc-surface-doctor.sh", { timeoutMs: common.timeoutMs || 25_000 });
    case "slurmdbd-doctor":
      return hpcBash("./ops/slurmdbd-backend-doctor.sh", { timeoutMs: common.timeoutMs || 30_000 });
    case "workspace-doctor":
      return hpcBash("bash ./ops/workspace-platform-doctor.sh", { timeoutMs: common.timeoutMs || 30_000 });
    case "orangefs-status":
      return hpcBash("source ops/lab-ops.sh && lab_orangefs_status", { timeoutMs: common.timeoutMs || 35_000 });
    case "slurm-nvidia-smi-smoke":
      return hpcBash(
        "source ops/lab-ops.sh && lab_slurm_exec srun -p gpu-orangefs -N1 -n1 --gres=gpu:1 --time=00:01:00 nvidia-smi -L",
        { timeoutMs: common.timeoutMs || 90_000 }
      );
    case "orangefs-text-r740":
      return hpcBash("bash orangefs-hybrid/run-k8s-orangefs-text-integrity-probe.sh r740-proxmox", {
        timeoutMs: common.timeoutMs || 120_000
      });
    case "orangefs-text-r770":
      return hpcBash("bash orangefs-hybrid/run-k8s-orangefs-text-integrity-probe.sh r770-proxmox", {
        timeoutMs: common.timeoutMs || 120_000
      });
    case "orangefs-artifact-r740":
      return hpcBash("bash orangefs-hybrid/run-k8s-orangefs-artifact-probe.sh r740-proxmox", {
        timeoutMs: common.timeoutMs || 120_000
      });
    case "orangefs-artifact-r770":
      return hpcBash("bash orangefs-hybrid/run-k8s-orangefs-artifact-probe.sh r770-proxmox", {
        timeoutMs: common.timeoutMs || 120_000
      });
    case "host-apt-dry-run":
      return runCommand(
        "ssh",
        ["-4", "-o", "BatchMode=yes", HOSTS[ensureWorkerTarget(actionId, body)], "apt-get -s upgrade"],
        { timeoutMs: common.timeoutMs || 60_000 }
      );
    case "host-cordon":
      return runCommand(KUBECTL, ["cordon", ensureWorkerTarget(actionId, body)], {
        timeoutMs: common.timeoutMs || 20_000
      });
    case "host-drain-dry-run":
      return runCommand(
        KUBECTL,
        ["drain", ensureWorkerTarget(actionId, body), "--ignore-daemonsets", "--delete-emptydir-data", "--dry-run=server"],
        { timeoutMs: common.timeoutMs || 30_000 }
      );
    case "host-drain":
      return runCommand(
        KUBECTL,
        ["drain", ensureWorkerTarget(actionId, body), "--ignore-daemonsets", "--delete-emptydir-data", "--timeout=10m"],
        { timeoutMs: common.timeoutMs || 660_000 }
      );
    case "host-uncordon":
      return runCommand(KUBECTL, ["uncordon", ensureWorkerTarget(actionId, body)], {
        timeoutMs: common.timeoutMs || 20_000
      });
    case "host-apt-upgrade":
      return runCommand(
        "ssh",
        [
          "-4",
          "-o",
          "BatchMode=yes",
          HOSTS[ensureWorkerTarget(actionId, body)],
          "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade"
        ],
        { timeoutMs: common.timeoutMs || 1_800_000 }
      );
    case "host-reboot":
      return runCommand("ssh", ["-4", "-o", "BatchMode=yes", HOSTS[ensureWorkerTarget(actionId, body)], "systemctl reboot"], {
        timeoutMs: common.timeoutMs || 20_000
      });
    default: {
      const error = new Error(`unknown cluster ops action: ${actionId}`);
      error.statusCode = 404;
      throw error;
    }
  }
}

async function writeReceipt({ action, body, ledger, result, readback }) {
  const runId = `${new Date().toISOString().replace(/[-:.]/g, "").replace("T", "T").replace("Z", "Z")}-${safeId(action.id)}`;
  const root = path.join(DATA_DIR, "cluster-ops", runId);
  await fsp.mkdir(root, { recursive: true, mode: 0o755 });
  const runPacket = {
    schema: "darwin.cluster-ops-run.v0",
    run_id: runId,
    action,
    targetNode: cleanValue(body.targetNode || body.node || body.target),
    ledger: {
      projectSlug: ACTION_PROJECT,
      ledger_id: ledger.ledger_id,
      status: ledger.status,
      actionId: ledger.actionId || ledger.proposal?.actionId || ""
    },
    requestId: cleanValue(body.idempotencyKey || body.idempotency_key),
    actor: cleanValue(body.actor || "operator"),
    source: cleanValue(body.source || "cluster-ops"),
    createdAt: nowIso()
  };
  await Promise.all([
    fsp.writeFile(path.join(root, "run_packet.json"), `${JSON.stringify(runPacket, null, 2)}\n`),
    fsp.writeFile(path.join(root, "stdout.log"), result.stdout || ""),
    fsp.writeFile(path.join(root, "stderr.log"), result.stderr || ""),
    fsp.writeFile(path.join(root, "readback.json"), `${JSON.stringify(readback, null, 2)}\n`)
  ]);
  return { runId, artifactRoot: root, runPacket };
}

function jsonError(res, error) {
  res.status(error.statusCode || 500).json({
    ok: false,
    error: error.message,
    truthMode: "stale"
  });
}

export function registerClusterOpsRoutes(app) {
  app.get("/api/cluster/ops/summary", async (_req, res) => {
    try {
      res.json(await buildClusterOpsSummary());
    } catch (error) {
      jsonError(res, error);
    }
  });

  app.get("/api/cluster/ops/actions", (_req, res) => {
    res.json({
      schema: "darwin.cluster-ops-actions.v0",
      generatedAt: nowIso(),
      actionLedgerProject: ACTION_PROJECT,
      actions: listClusterOpsActions(),
      truthMode: "declared"
    });
  });

  app.get("/api/cluster/ops/gpu-leases", async (_req, res) => {
    try {
      res.json(await buildGpuLeasePacket("sounio"));
    } catch (error) {
      jsonError(res, error);
    }
  });

  app.get("/api/projects/:slug/gpu-leases", async (req, res) => {
    try {
      res.json(await buildGpuLeasePacket(req.params.slug));
    } catch (error) {
      jsonError(res, error);
    }
  });

  app.post(
    "/api/cluster/ops/gpu-leases/:node/preview",
    idempotent({ ttlMs: 60_000 }),
    async (req, res) => {
      try {
        res.status(200).json(await previewGpuLeaseTransition(req.params.node, req.body || {}));
      } catch (error) {
        jsonError(res, error);
      }
    }
  );

  app.post(
    "/api/cluster/ops/gpu-leases/:node/apply",
    idempotent({ ttlMs: 60_000, requireHeader: true }),
    async (req, res) => {
      try {
        const response = await applyGpuLeaseTransition(req.params.node, req.body || {});
        res.status(response.ok ? 200 : 500).json(response);
      } catch (error) {
        jsonError(res, error);
      }
    }
  );

  app.post(
    "/api/cluster/ops/actions/:actionId/run",
    idempotent({ ttlMs: 60_000, requireHeader: true }),
    async (req, res) => {
      try {
        const action = getAction(req.params.actionId);
        if (!action) {
          const error = new Error(`unknown cluster ops action: ${req.params.actionId}`);
          error.statusCode = 404;
          throw error;
        }
        ensureConfirmed(req.body || {}, action.label);
        const ledger = requireLedger(req.body?.ledgerId || req.body?.ledger_id);
        const result = await executeAction(action.id, req.body || {});
        const readback = await buildClusterOpsSummary();
        const receipt = await writeReceipt({ action, body: req.body || {}, ledger, result, readback });
        res.status(result.ok ? 200 : 500).json({
          ok: result.ok,
          schema: "darwin.cluster-ops-run-result.v0",
          action,
          targetNode: cleanValue(req.body?.targetNode || req.body?.node || req.body?.target),
          ledger: {
            projectSlug: ACTION_PROJECT,
            ledger_id: ledger.ledger_id,
            status: ledger.status
          },
          result: {
            code: result.code,
            timedOut: result.timedOut,
            stdout: result.stdout.slice(0, 20_000),
            stderr: result.stderr.slice(0, 20_000)
          },
          receipt,
          readback,
          truthMode: "observed"
        });
      } catch (error) {
        jsonError(res, error);
      }
    }
  );
}

export { buildClusterOpsSummary, listClusterOpsActions };
