# SSM Probe Lane

Experimental SSM inference lane for Sounio/Beagle agents.

## Current endpoint

- Service: `ssm-probe-serving.beagle.svc.cluster.local:8002`
- API shape: OpenAI-like `/v1/models`, `/v1/chat/completions`, `/v1/completions`
- Node: `5860-proxmox`
- GPU lease label: `sounio.dev/gpu-owner=ssm-probe`
- Current model: `LiquidAI/LFM2.5-1.2B-Instruct`

## Purpose

This is a probe, not the default reasoning endpoint.

Use it to measure whether small SSM, linear-recurrent, or hybrid efficient
models can become cheap always-on agent helpers. Keep Transformer inference as
the default heavy reasoning fallback until an efficient model clears quality
checks.

## Smoke

```bash
/home/devsounio/beagle/scripts/infrastructure/check_ssm_probe_inference.sh
/home/devsounio/beagle/scripts/infrastructure/run_ssm_probe_matrix.sh
```

Current LFM2.5 verified shape:

- idle VRAM: about 2867 MiB
- post-request VRAM after smoke: about 2929 MiB
- matrix high-water VRAM: about 3225 MiB
- exact instruction: pass
- compact JSON: pass
- agent risk marker: pass in the current matrix
- 3.5k-token recall: pass
- matrix average decode speed: about 72.2 tokens/s
- current matrix run: `/tmp/sounio-ssm-probe/ssm-probe-20260522T191525Z.summary.json`

Previous `state-spaces/mamba-130m-hf` result:

- idle VRAM: about 917 MiB, post-request about 957 MiB
- quality: not agent-ready; the base model repeated simple instruction prompts

## Known limits

- The current live model is efficient and exotic/hybrid, but not a pure SSM.
- `typeof/mamba-130m-instruct` was tested and rejected for this deployment: the
  checkpoint has architecture/vocab mismatches under current Transformers.
- `tiiuae/Falcon-H1-7B-Instruct` loads in 4-bit on the RTX 4000 Ada, but the
  current Transformers path falls back to slow Mamba kernels. Strict prompt
  following failed and a 3k-token context request hit CUDA OOM while trying to
  allocate 24 GiB. Treat this as a runtime failure, not a model rejection.
- `tiiuae/Falcon-H1-7B-Instruct` with SGLang plus `bitsandbytes` is installed
  in the probe runtime image, but it currently fails during SGLang weight
  loading, before serving requests:
  `param_data.shape=torch.Size([18874368, 1])` versus
  `loaded_weight.shape=torch.Size([3072, 12288])` in
  `sglang.srt.models.falcon_h1`. Treat this as a SGLang Falcon-H1 loader /
  quantization incompatibility, not a memory failure.
- `tiiuae/Falcon3-Mamba-7B-Instruct` also loads in 4-bit and behaves better:
  exact answer starts correctly, agent risk and long-context recall pass, but
  strict exact/JSON checks fail under the current wrapper and average decode is
  only about 10.3 tokens/s. It needs vLLM/SGLang or proper Mamba kernels before
  promotion.
- `Zyphra/Zamba2-2.7B-Instruct-v2` loads cleanly in BF16 with current
  Transformers and does not require remote custom code, but it does not beat the
  live LFM2.5 baseline:
  - exact instruction: pass
  - compact JSON: fail, wraps JSON in markdown fences
  - agent risk marker: pass
  - 3.5k-token recall: fail with CUDA OOM in the naive Zamba2/Mamba path
  - idle VRAM: about 8175 MiB; high-water before long-context OOM about
    10835 MiB
  - matrix run:
    `/tmp/sounio-ssm-probe/zamba2-transformers-20260522T191739Z.summary.json`
  - debug run:
    `/tmp/sounio-ssm-probe/zamba2-debug-20260522T191945Z.summary.json`
- `nvidia/NVIDIA-Nemotron-3-Nano-4B-FP8` loads successfully through SGLang on
  the RTX 4000 Ada using the current SGLang/Dynamo runtime image. This is a
  real infrastructure win, but not an agent-contract win yet:
  - runtime: SGLang, ModelOpt FP8 checkpoint, FlashInfer attention, Triton
    Mamba backend
  - exact instruction: fail, model verbalizes the instruction instead of
    obeying it exactly
  - compact JSON: fail, model exposes reasoning text before the JSON
  - agent risk marker: fail, reasoning text consumes the budget and does not
    satisfy the marker contract
  - 3.5k-token recall: pass
  - startup VRAM after rollout: about 8314 MiB
  - matrix run:
    `/tmp/sounio-ssm-probe/nemotron3-sglang-20260522T192803Z.summary.json`
- `moonshotai/Kimi-Linear-48B-A3B-Instruct` can run locally only through a more
  aggressive GGUF path today. The first local probe used
  `bartowski/moonshotai_Kimi-Linear-48B-A3B-Instruct-GGUF` with `Q3_K_S`
  through `llama.cpp` on the `r770-proxmox` L4:
  - runtime: `ghcr.io/ggml-org/llama.cpp:server-cuda`, GGUF Q3_K_S,
    OpenAI-compatible `llama-server`
  - exact instruction: pass
  - compact JSON: pass
  - agent risk marker: fail; response recommended broad RBAC mutation and
    exceeded the compact 3-action contract
  - 3k-token recall: pass
  - GPU at rollout: about 21169 MiB used / 1398 MiB free on the 24 GiB L4
  - wall-clock average decode proxy: about 33.2 completion tokens/s
  - matrix run:
    `/tmp/sounio-ssm-probe/kimi-linear-q3-llamacpp-20260522T230132Z.summary.json`
  - second operator-safe run:
    `/tmp/sounio-ssm-probe/kimi-linear-q3-operator-safe-20260522T231931Z.summary.json`
    passed exact and JSON policy (`decision=ask-human`), but still failed
    safe triage because it mentioned `ClusterRoleBinding` / grant language and
    truncated before the exact 3-line contract
  - cleanup verified: probe removed, L4 returned to 0 MiB used, local
    `emptyDir` GGUF storage released
- Next serious 7B quality probes should use a serving runtime with documented
  support for Falcon-H1/FalconMamba, not the minimal FastAPI/Transformers probe.

## Node storage note

The `5860-proxmox` registry push storage was moved off the root filesystem:

- original bind path: `/srv/service-fabric/registry/data/push`
- current target: `/var/lib/orangefs-lab/service-fabric-registry-push`

The original path is now a symlink so Docker Compose continues to work while the
node stays below kubelet disk-pressure thresholds.

Current observed `5860-proxmox` local storage posture:

- root: `/dev/mapper/pve-root`, about 96 GiB, 41% used after cleanup
- OrangeFS lab LV: `/var/lib/orangefs-lab`, about 128 GiB, 44% used
- containerd runtime LV: `/var/lib/containerd-runtime`, about 96 GiB, 82% used
- boot NVMe: Micron 3500 1 TB with Proxmox/LVM
- second Micron 3500 1 TB is currently a Ceph OSD, not free local scratch
