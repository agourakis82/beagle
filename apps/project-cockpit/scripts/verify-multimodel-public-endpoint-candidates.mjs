#!/usr/bin/env node

import { spawn } from "node:child_process";

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

function run(command, args = [], { timeoutMs = 5000 } = {}) {
  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      resolve({ code: 124, stdout, stderr: stderr || `timeout after ${timeoutMs}ms` });
    }, timeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ code, stdout, stderr });
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({ code: 1, stdout, stderr: error.message });
    });
  });
}

async function fetchJson(url) {
  const res = await fetch(url);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const error = new Error(`${res.status} ${payload?.error || res.statusText}`);
    error.detail = payload;
    throw error;
  }
  return payload;
}

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");

try {
  const url = `${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/public-endpoint/candidates`;
  const payload = await fetchJson(url);
  const candidates = Array.isArray(payload.candidates) ? payload.candidates : [];
  const localTailscale = await run("bash", ["-lc", "command -v tailscale"], { timeoutMs: 3000 });
  const localCloudflared = await run("bash", ["-lc", "command -v cloudflared"], { timeoutMs: 3000 });

  assert(payload.mutates === false, "candidate doctor must be non-mutating", payload);
  assert(payload.truthMode === "observed-non-mutating-public-endpoint-candidates", "unexpected truth mode", payload);
  assert(candidates.some((candidate) => candidate.id === "loopback"), "loopback candidate missing", payload);
  assert(candidates.every((candidate) => candidate.mutates === false), "a candidate did not declare mutates=false", payload);
  if (localTailscale.code === 0 && cleanString(localTailscale.stdout)) {
    assert(payload.observations?.tailscale?.available === true, "tailscale exists locally but doctor did not observe it", payload);
    assert(candidates.some((candidate) => candidate.id === "tailscale-dns"), "tailscale DNS candidate missing", payload);
  }
  const cloudflaredCandidate = candidates.find((candidate) => candidate.id === "cloudflared");
  assert(cloudflaredCandidate, "cloudflared candidate missing", payload);
  const observedCloudflared = payload.observations?.cloudflared || {};
  const localCloudflaredAvailable = localCloudflared.code === 0 && cleanString(localCloudflared.stdout);
  const observedCloudflaredAvailable = observedCloudflared.available === true;
  if (localCloudflaredAvailable || observedCloudflaredAvailable) {
    assert(observedCloudflaredAvailable, "cloudflared exists locally but doctor did not observe it", payload);
    assert(["ready", "waiting", "configured"].includes(cloudflaredCandidate.status), "available cloudflared has unexpected status", cloudflaredCandidate);
    if (cloudflaredCandidate.status === "ready") {
      assert(cleanString(cloudflaredCandidate.url).startsWith("https://"), "ready cloudflared candidate needs an HTTPS URL", cloudflaredCandidate);
      assert(cloudflaredCandidate.hostedClientReachable === true, "ready cloudflared candidate must be hosted-client reachable", cloudflaredCandidate);
    }
  } else {
    assert(cloudflaredCandidate.status === "missing", "missing cloudflared was not reported", payload);
  }

  console.log(JSON.stringify({
    ok: true,
    schema: "beagle.multimodel-public-endpoint-candidates-verification.v1",
    projectSlug,
    candidateCount: candidates.length,
    tailscaleAvailable: payload.observations?.tailscale?.available === true,
    cloudflaredAvailable: observedCloudflaredAvailable,
    cloudflaredStatus: cloudflaredCandidate.status,
    cloudflaredUrl: cloudflaredCandidate.url || null,
    cloudflaredHostedReachable: cloudflaredCandidate.hostedClientReachable === true,
    selected: payload.selected || null,
    verifiedAt: new Date().toISOString(),
    mutates: false,
    truthMode: "observed-public-endpoint-candidates"
  }, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
