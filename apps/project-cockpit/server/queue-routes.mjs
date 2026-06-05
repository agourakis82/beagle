// queue-routes.mjs
//
// /api/jobs/queue — unified view of cluster compute queues.
// Aggregates:
//   - K8s Jobs labeled app.kubernetes.io/managed-by=cockpit (cockpit-submitted)
//   - K8s Jobs broadly (all scheduled jobs, optional)
//   - Slurm queue via `sinfo` / `squeue` (when slurm-client installed in pod)
//   - Kueue ClusterQueue status (if Kueue installed)
//
// Returns a single timeline-friendly shape the iOS Jobs panel can render.

import { spawn } from "node:child_process";

const NAMESPACE = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";
const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "kubectl";
const SLURM_LOGIN_HOST = process.env.PROJECT_COCKPIT_SLURM_LOGIN || ""; // empty = Slurm not available

function runKubectl(args, { timeoutMs = 10000 } = {}) {
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

async function runSsh(host, cmd, timeoutMs = 8000) {
  if (!host) return null;
  return new Promise((resolve) => {
    const child = spawn("ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=3", host, cmd], { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    const timer = setTimeout(() => { child.kill("SIGKILL"); resolve(null); }, timeoutMs);
    child.stdout.on("data", d => stdout += d.toString());
    child.on("close", () => { clearTimeout(timer); resolve(stdout); });
    child.on("error", () => { clearTimeout(timer); resolve(null); });
  });
}

// ─── K8s Jobs harvest ─────────────────────────────────────────────

async function harvestK8sJobs() {
  try {
    const raw = await runKubectl(["-n", NAMESPACE, "get", "jobs", "-o", "json"]);
    const parsed = JSON.parse(raw);
    return (parsed.items || []).map(j => {
      const active = j.status?.active || 0;
      const succeeded = j.status?.succeeded || 0;
      const failed = j.status?.failed || 0;
      let phase = "Pending";
      if (succeeded > 0) phase = "Succeeded";
      else if (failed > 0) phase = "Failed";
      else if (active > 0) phase = "Running";

      return {
        source: "k8s",
        job_id: j.metadata.labels?.["cockpit.sounio.dev/job-id"] || j.metadata.name,
        name: j.metadata.name,
        namespace: j.metadata.namespace,
        submitted_by: j.metadata.labels?.["app.kubernetes.io/managed-by"] || "unknown",
        project: j.metadata.labels?.project,
        campaign: j.metadata.labels?.campaign,
        phase,
        active, succeeded, failed,
        submitted_at: j.metadata.creationTimestamp,
        started_at: j.status?.startTime,
        completed_at: j.status?.completionTime,
        gpu_allocated: inferGpuAllocation(j),
        truthMode: "observed"
      };
    });
  } catch (e) {
    return { __error: e.message, source: "k8s" };
  }
}

function inferGpuAllocation(job) {
  const containers = job.spec?.template?.spec?.containers || [];
  const gpuReq = containers.reduce((sum, c) => {
    const g = c.resources?.requests?.["nvidia.com/gpu"] || c.resources?.limits?.["nvidia.com/gpu"] || 0;
    return sum + (Number(g) || 0);
  }, 0);
  return gpuReq;
}

// ─── Slurm harvest (if available) ─────────────────────────────────

async function harvestSlurm() {
  if (!SLURM_LOGIN_HOST) return [];
  const out = await runSsh(SLURM_LOGIN_HOST, 'squeue --format="%i|%P|%j|%u|%T|%M|%l|%R" --noheader 2>/dev/null || true');
  if (!out) return [];
  const lines = out.trim().split("\n").filter(Boolean);
  return lines.map(line => {
    const [jobid, partition, name, user, state, timeUsed, timeLimit, reason] = line.split("|");
    return {
      source: "slurm",
      job_id: jobid,
      name,
      user,
      partition,
      phase: state,
      time_used: timeUsed,
      time_limit: timeLimit,
      reason,
      truthMode: "observed"
    };
  });
}

// ─── Kueue queue state ────────────────────────────────────────────

async function harvestKueue() {
  try {
    const raw = await runKubectl(["get", "clusterqueues", "-o", "json"], { timeoutMs: 5000 });
    const parsed = JSON.parse(raw);
    return (parsed.items || []).map(q => ({
      name: q.metadata.name,
      pending: q.status?.pendingWorkloads || 0,
      admitted: q.status?.admittedWorkloads || 0,
      reserving: q.status?.reservingWorkloads || 0,
      flavor_usage: q.status?.flavorsUsage || [],
      truthMode: "observed"
    }));
  } catch {
    // Kueue not installed or not reachable
    return [];
  }
}

// ─── Unified endpoint ────────────────────────────────────────────

export function registerQueueRoutes(app) {
  app.get("/api/jobs/queue", async (_req, res) => {
    const startedAt = Date.now();
    const [k8sJobs, slurmJobs, kueueQueues] = await Promise.all([
      harvestK8sJobs(),
      harvestSlurm(),
      harvestKueue()
    ]);

    const k8s = Array.isArray(k8sJobs) ? k8sJobs : [];
    const slurm = Array.isArray(slurmJobs) ? slurmJobs : [];

    // Merge + sort by submitted_at descending
    const timeline = [...k8s, ...slurm].sort((a, b) => {
      const ta = Date.parse(a.submitted_at || a.started_at || 0) || 0;
      const tb = Date.parse(b.submitted_at || b.started_at || 0) || 0;
      return tb - ta;
    });

    // Summary
    const summary = {
      total: timeline.length,
      running: timeline.filter(j => j.phase === "Running" || j.phase === "RUNNING").length,
      pending: timeline.filter(j => j.phase === "Pending" || j.phase === "PENDING").length,
      completed: timeline.filter(j => j.phase === "Succeeded" || j.phase === "COMPLETED").length,
      failed: timeline.filter(j => j.phase === "Failed" || j.phase === "FAILED").length,
      gpu_allocated: k8s.reduce((sum, j) => sum + (j.gpu_allocated || 0), 0),
      slurm_available: slurm.length > 0 || !!SLURM_LOGIN_HOST
    };

    res.json({
      generatedAt: new Date().toISOString(),
      latency_ms: Date.now() - startedAt,
      summary,
      timeline,
      queues: {
        kueue: kueueQueues
      },
      truthMode: (k8sJobs.__error || slurmJobs.__error) ? "remembered" : "observed"
    });
  });

  // Single-job detail with richer context — works for both K8s and Slurm IDs
  app.get("/api/jobs/:jobId/detail", async (req, res) => {
    const { jobId } = req.params;
    try {
      // Try K8s first by label
      const raw = await runKubectl([
        "-n", NAMESPACE,
        "get", "job",
        "-l", `cockpit.sounio.dev/job-id=${jobId}`,
        "-o", "json"
      ]);
      const parsed = JSON.parse(raw);
      if (parsed.items?.length) {
        return res.json({ source: "k8s", job: parsed.items[0], truthMode: "observed" });
      }
    } catch { /* fall through to slurm */ }

    // Try Slurm scontrol
    if (SLURM_LOGIN_HOST) {
      const out = await runSsh(SLURM_LOGIN_HOST, `scontrol show job ${jobId} 2>/dev/null`);
      if (out) return res.json({ source: "slurm", detail: out, truthMode: "observed" });
    }

    res.status(404).json({ error: "job not found", jobId, truthMode: "stale" });
  });
}
