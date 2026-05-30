// job-presets.mjs
//
// Named job templates so agents don't have to hand-assemble image + command +
// mounts every time. `cockpit_submit_job` accepts a `preset` param; the
// preset's fields are deep-merged under the caller's body (caller wins on
// conflict). Each preset stamps `labels["sounio.dev/preset"]` so the
// reconciler can render a clean kind label into cognitive state.

// The active workspace PVC is RWO/RWOP (ceph-rbd-ssd-rwop), attached to
// the sounio-workspace-control StatefulSet — it can't be mounted by a
// second pod. Presets therefore clone the sounio repo from GitHub into an
// emptyDir at runtime. The runner image ships git + bash; for presets that
// need the `souc` compiler, bake it into a fatter image as a follow-up.

const IMAGE = () =>
  process.env.PROJECT_COCKPIT_SOUNIO_RUNNER_IMAGE || "ttl.sh/beagle-sounio:latest";
const GPU_SMOKE_IMAGE = () =>
  process.env.PROJECT_COCKPIT_GPU_SMOKE_IMAGE
  || "192.168.3.207:5003/sounio-ssm-probe:hybrid-probe-cc-20260522T180123Z";
const GPU_TRAIN_IMAGE = () =>
  process.env.PROJECT_COCKPIT_GPU_TRAIN_IMAGE
  || "192.168.3.207:5003/sounio/pytorch-rdma:2.7.1-cuda12.8-rdma";
const REPO = process.env.PROJECT_COCKPIT_SOUNIO_REPO
  || "https://github.com/sounio-lang/sounio.git";
const BRANCH = process.env.PROJECT_COCKPIT_SOUNIO_BRANCH
  || "integration/sounio-dev-ready-base";

// Compact PyTorch GPU canary: trains a tiny MLP, writes metrics + checkpoint
// under /orangefs/sounio/kimi-canary/<run-id>/ (K8s mount path).
const PYTORCH_ORANGEFS_CANARY = `set -euo pipefail
export LD_LIBRARY_PATH=/nvidia-host:\${LD_LIBRARY_PATH:-}
OUT="/orangefs/sounio/kimi-canary/$(date +%Y%m%d-%H%M%S)-$(hostname)"
mkdir -p "$OUT"
export OUT
export PYTHONUNBUFFERED=1
python3 - <<'PY'
import json, os, socket, time
from pathlib import Path
import torch

out = Path(os.environ["OUT"])
if not torch.cuda.is_available():
    raise SystemExit("CUDA unavailable")
device = torch.device("cuda:0")
torch.manual_seed(7)
model = torch.nn.Sequential(
    torch.nn.Linear(1024, 1024),
    torch.nn.ReLU(),
    torch.nn.Linear(1024, 512),
).to(device)
opt = torch.optim.AdamW(model.parameters(), lr=1e-3)
x = torch.randn(64, 1024, device=device)
y = torch.randn(64, 512, device=device)
torch.cuda.synchronize()
t0 = time.perf_counter()
losses = []
for _ in range(8):
    opt.zero_grad(set_to_none=True)
    loss = torch.nn.functional.mse_loss(model(x), y)
    loss.backward()
    opt.step()
    losses.append(float(loss.detach().cpu()))
torch.cuda.synchronize()
elapsed = time.perf_counter() - t0
payload = {
    "hostname": socket.gethostname(),
    "device": torch.cuda.get_device_name(device),
    "steps": len(losses),
    "final_loss": losses[-1],
    "elapsed_seconds": round(elapsed, 3),
}
(out / "metrics.json").write_text(json.dumps(payload, indent=2) + "\\n", encoding="utf-8")
torch.save({"payload": payload, "model": model.state_dict()}, out / "checkpoint.pt")
print(json.dumps(payload), flush=True)
PY
echo "artifacts=$OUT"`;

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
  },

  // GPU smoke — nvidia-smi on a batch GPU node (no OrangeFS required).
  "gpu-nvidia-smoke": {
    image: GPU_SMOKE_IMAGE(),
    command: ["bash", "-lc", "nvidia-smi && hostname && date -u"],
    resources: { cpu: "2", memory: "8Gi", gpu: 1 },
    data_mounts: ["work-tmp"],
    timeout_seconds: 600,
    campaign: "gpu-smoke"
  },

  // GPU training canary — PyTorch micro-loop + checkpoint on OrangeFS.
  "gpu-pytorch-orangefs-canary": {
    image: GPU_TRAIN_IMAGE(),
    command: ["bash", "-lc", PYTORCH_ORANGEFS_CANARY],
    resources: { cpu: "4", memory: "16Gi", gpu: 1 },
    data_mounts: ["orangefs-training", "work-tmp"],
    timeout_seconds: 1800,
    campaign: "kimi-gpu-canary",
    privileged: true,
    container_env: [
      { name: "PYTHONUNBUFFERED", value: "1" },
      { name: "LD_LIBRARY_PATH", value: "/nvidia-host" }
    ]
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
