// job-presets.mjs
//
// Named job templates so agents don't have to hand-assemble image + command +
// mounts every time. `cockpit_submit_job` accepts a `preset` param; the
// preset's fields are deep-merged under the caller's body (caller wins on
// conflict). Each preset stamps `labels["sounio.dev/preset"]` so the
// reconciler can render a clean kind label into cognitive state.

// The active workspace PVC is RWO/RWOP (ceph-rbd-ssd-rwop), attached to
// the sounio-workspace-habitat StatefulSet — it can't be mounted by a
// second pod. Presets therefore clone the sounio repo from GitHub into an
// emptyDir at runtime. The runner image ships git + bash; for presets that
// need the `souc` compiler, bake it into a fatter image as a follow-up.

const IMAGE = () =>
  process.env.PROJECT_COCKPIT_SOUNIO_RUNNER_IMAGE || "ttl.sh/beagle-sounio:latest";
const REPO = process.env.PROJECT_COCKPIT_SOUNIO_REPO
  || "https://github.com/sounio-lang/sounio.git";
const BRANCH = process.env.PROJECT_COCKPIT_SOUNIO_BRANCH
  || "integration/sounio-dev-ready-base";

export const JOB_PRESETS = {
  // Smoke preset — actually exercises the baked-in souc compiler on a
  // bundled example. Closes the full agent → cockpit → K8s → beagle →
  // cognitive state loop with a real compiler invocation.
  "sounio-compile-example": {
    image: IMAGE(),
    command: [
      "bash",
      "-lc",
      `set -euo pipefail; souc info | head -3; souc check /opt/sounio/examples/hello.sio && echo "souc-check-ok"`
    ],
    resources: { cpu: "1", memory: "2Gi", gpu: 0 },
    data_mounts: ["work-tmp"],
    timeout_seconds: 180,
    campaign: "sounio-smoke"
  },

  // Full test suite — runs against the baked sounio tree at /opt/sounio.
  // Scripts are relative to that root, SOUC_BIN points at the wrapper.
  "sounio-test-suite": {
    image: IMAGE(),
    command: [
      "bash",
      "-lc",
      `set -euo pipefail; cd /opt/sounio && export SOUC_BIN=/opt/sounio/bin/souc && bash scripts/run_sio_test_suite.sh`
    ],
    resources: { cpu: "2", memory: "4Gi", gpu: 0 },
    data_mounts: ["work-tmp"],
    timeout_seconds: 900,
    campaign: "sounio-ci"
  },

  // Stdlib hyper-execution gate — same pattern, longer budget.
  "sounio-stdlib-gate": {
    image: IMAGE(),
    command: [
      "bash",
      "-lc",
      `set -euo pipefail; cd /opt/sounio && export SOUC_BIN=/opt/sounio/bin/souc && bash scripts/stdlib_hyper_execution_gate.sh`
    ],
    resources: { cpu: "4", memory: "8Gi", gpu: 0 },
    data_mounts: ["work-tmp"],
    timeout_seconds: 1800,
    campaign: "sounio-ci"
  }
};

export function applyPreset(presetName, body) {
  if (!presetName) return body;
  const preset = JOB_PRESETS[presetName];
  if (!preset) {
    const err = new Error(
      `unknown preset "${presetName}". Available: ${Object.keys(JOB_PRESETS).join(", ")}`
    );
    err.statusCode = 400;
    throw err;
  }
  // Caller body wins on conflict; preset provides defaults.
  const merged = { ...preset, ...body };
  merged.labels = { ...(preset.labels || {}), ...(body.labels || {}), "sounio.dev/preset": presetName };
  merged._preset = presetName;
  return merged;
}

export function listPresets() {
  return Object.keys(JOB_PRESETS).map((name) => ({
    name,
    image: JOB_PRESETS[name].image,
    campaign: JOB_PRESETS[name].campaign,
    timeout_seconds: JOB_PRESETS[name].timeout_seconds,
    resources: JOB_PRESETS[name].resources
  }));
}
