// job-reconciler.mjs
//
// Periodic reconciler that bridges K8s Job lifecycle to beagle-server's
// ScienceJobRegistry. Without this, cockpit-submitted jobs are invisible
// to `/api/v1/cognitive/state` (iOS widget, dashboards) — they complete
// silently. Every RECONCILE_INTERVAL_MS:
//
//   1. List all `app.kubernetes.io/managed-by=cockpit` Jobs in the namespace.
//   2. Compute current phase (Running / Pending / Succeeded / Failed).
//   3. Diff against lastKnownPhase Map — only POST on change.
//   4. First sight OR phase change → POST /api/jobs/external/register.
//   5. Terminal transition (Succeeded/Failed) → POST /api/jobs/external/complete
//      with tailed pod logs as error context if Failed.
//
// Auth: reuses fetchOperatorToken() from auth-bridge.mjs (same path as the
// /api/auth/beagle-token route). Cache TTL is 5min; we refresh implicitly.

import { fetchOperatorToken } from "./auth-bridge.mjs";
import { listAllCockpitJobs, phaseFromJobManifest, tailJobLogs } from "./job-routes.mjs";

const INTERVAL_MS = Number(process.env.PROJECT_COCKPIT_RECONCILE_INTERVAL_MS || 15000);
const BEAGLE_URL = process.env.PROJECT_COCKPIT_BEAGLE_URL
  || process.env.BEAGLE_URL
  || "http://beagle-core.beagle.svc.cluster.local:8080";
const CONSUMER = process.env.PROJECT_COCKPIT_BEAGLE_CONSUMER || "beagle-operator";

// jobId → { phase, registered, completed }
const lastState = new Map();

function kindLabelFromJob(job) {
  const labels = job.metadata?.labels || {};
  return labels["sounio.dev/preset"]
    || labels.campaign
    || labels.project
    || "cockpit-job";
}

function jobIdFromJob(job) {
  return job.metadata?.labels?.["cockpit.sounio.dev/job-id"] || job.metadata?.name;
}

async function postBeagle(path, body) {
  const tok = await fetchOperatorToken();
  if (tok.error) {
    throw new Error(`auth: ${tok.error}`);
  }
  const resp = await fetch(`${BEAGLE_URL}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Beagle-Consumer": CONSUMER,
      "Authorization": `Bearer ${tok.token}`
    },
    body: JSON.stringify(body)
  });
  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    throw new Error(`${path} → ${resp.status}: ${text.slice(0, 200)}`);
  }
  return resp.json().catch(() => ({}));
}

function mapPhaseToStatus(phase) {
  switch (phase) {
    case "Pending": return "created";
    case "Running": return "running";
    case "Succeeded": return "done";
    case "Failed": return "error";
    default: return "running";
  }
}

async function reconcileOnce() {
  const jobs = await listAllCockpitJobs();
  const seen = new Set();

  for (const job of jobs) {
    const jobId = jobIdFromJob(job);
    if (!jobId) continue;
    seen.add(jobId);

    const phase = phaseFromJobManifest(job);
    const label = kindLabelFromJob(job);
    const prev = lastState.get(jobId) || {};
    const startedAt = job.status?.startTime || job.metadata?.creationTimestamp;

    // First sight → register.
    if (!prev.registered) {
      try {
        await postBeagle("/api/jobs/external/register", {
          job_id: jobId,
          kind: label,
          status: mapPhaseToStatus(phase),
          started_at: startedAt
        });
        console.log(`[reconciler] registered ${jobId} kind=${label} phase=${phase}`);
        prev.registered = true;
      } catch (e) {
        console.warn(`[reconciler] register failed for ${jobId}: ${e.message}`);
        continue;
      }
    }

    // Phase change — upsert current status (handles Pending→Running and
    // any terminal transition below).
    if (prev.phase !== phase) {
      try {
        await postBeagle("/api/jobs/external/register", {
          job_id: jobId,
          kind: label,
          status: mapPhaseToStatus(phase),
          started_at: startedAt
        });
      } catch (e) {
        console.warn(`[reconciler] update failed for ${jobId}: ${e.message}`);
      }
    }

    // Terminal transition → complete (once).
    const terminal = phase === "Succeeded" || phase === "Failed";
    if (terminal && !prev.completed) {
      let errorContext = null;
      let exitCode = null;
      if (phase === "Failed") {
        const logs = await tailJobLogs(jobId, 20);
        errorContext = logs ? logs.slice(-1500) : "job failed (no logs)";
        // Extract exit code if pod status carries it (best effort)
        const condFailed = (job.status?.conditions || []).find((c) => c.type === "Failed");
        if (condFailed?.reason) {
          errorContext = `${condFailed.reason}: ${condFailed.message || ""}\n${errorContext}`;
        }
      }
      try {
        await postBeagle("/api/jobs/external/complete", {
          job_id: jobId,
          kind: label,
          status: phase === "Succeeded" ? "done" : "error",
          error: errorContext,
          exit_code: exitCode
        });
        console.log(`[reconciler] completed ${jobId} phase=${phase}`);
        prev.completed = true;
      } catch (e) {
        console.warn(`[reconciler] complete failed for ${jobId}: ${e.message}`);
      }
    }

    prev.phase = phase;
    lastState.set(jobId, prev);
  }

  // Garbage-collect state for jobs that no longer exist in cluster (TTL
  // cleanup removed them). Keeps the map bounded over long uptimes.
  for (const jobId of lastState.keys()) {
    if (!seen.has(jobId)) lastState.delete(jobId);
  }
}

export function startJobReconciler() {
  if (process.env.PROJECT_COCKPIT_DISABLE_RECONCILER === "1") {
    console.log("[reconciler] disabled via PROJECT_COCKPIT_DISABLE_RECONCILER=1");
    return;
  }
  console.log(`[reconciler] starting, interval=${INTERVAL_MS}ms, beagle=${BEAGLE_URL}`);
  // Run immediately so first tick happens on boot, not after the interval.
  reconcileOnce().catch((e) => console.warn(`[reconciler] boot tick failed: ${e.message}`));
  setInterval(() => {
    reconcileOnce().catch((e) => console.warn(`[reconciler] tick failed: ${e.message}`));
  }, INTERVAL_MS);
}
