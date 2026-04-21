# Inference Fabric: SGLang + Dynamo

This document records the intended private inference stack for the sovereign
supercomputing playground.

## Primary architecture

- `SGLang` is the GPU inference engine.
- `Dynamo` is the control plane and OpenAI-compatible frontend.
- `vLLM` is compatibility-only and is not the primary direction.

## Why this shape

- `SGLang` gives us a frontier open-source serving engine.
- `Dynamo` gives us a routing/control-plane layer that fits the Beagle-native
  orchestration story better than a single serving engine.
- This keeps serving separate from:
  - Beagle routing and GraphRAG++
  - Sounio scientific/provenance contracts
  - the cockpit shell itself

## Cluster plan

The intended cluster fabric is:

- `sglang-serving`
  - GPU runtime
  - model worker / backend
- `dynamo-control-plane`
  - OpenAI-compatible entrypoint
  - control plane on top of the SGLang runtime

These manifests are now live in the cluster through a first-party runtime image
that layers `ai-dynamo[sglang]` on top of the mirrored `SGLang` base.

## Official references

- SGLang docs:
  - https://docs.sglang.ai/
- NVIDIA Dynamo quickstart:
  - https://docs.nvidia.com/dynamo/getting-started/quickstart

The Dynamo quickstart documents official runtime containers such as:

- `nvcr.io/nvidia/ai-dynamo/sglang-runtime:1.0.0`

and describes running:

- `python3 -m dynamo.frontend`
- `python3 -m dynamo.sglang`

## Product contract

In the cockpit, the private inference lane should expose:

- inference runtime
- inference workload
- inference bootstrap
- model inventory

with the semantics:

- control plane: `Dynamo`
- engine: `SGLang`
- compatibility: optional `vLLM`

## Current cluster checkpoint

As of 2026-04-10 on the `r740-proxmox` GPU node:

- the mirrored `SGLang` image from `ttl.sh` can be pulled successfully
- the pod can be scheduled reliably when:
  - `runtimeClassName: nvidia`
  - `privileged: true`
  - host `libcuda.so.1` and `libnvidia-ml.so.1` are mounted
  - `LD_LIBRARY_PATH=/nvidia-host`
- `nvidia-smi` works inside a CUDA/PyTorch diagnostic pod
- `torch.cuda.is_available()` becomes `True` with that pattern

So the original blocker around:

- registry pull
- scheduling
- CUDA runtime visibility

has been substantially resolved.

The practical network fix on `r740-proxmox` is:

- `hostNetwork: true`
- `dnsPolicy: Default`

With that mode, the `SGLang` pod can:

- resolve `huggingface.co`
- resolve `cas-bridge.xethub.hf.co`
- follow the weight redirect for
  - `Qwen/Qwen2.5-0.5B-Instruct`

So model bootstrap is no longer blocked at DNS/download time.

That runtime now reaches a boring engine-ready state with:

- `1/1 Running`
- `/health -> 200`
- `/v1/models` exposing:
  - `qwen2.5-0.5B-Instruct`

The next step is no longer an NGC-only path. The repo now includes a
first-party `Dynamo+SGLang` runtime image path:

- [build_sglang_dynamo_runtime.sh](/home/devsounio/beagle/scripts/infrastructure/build_sglang_dynamo_runtime.sh)
- [deploy_sglang_dynamo_fabric.sh](/home/devsounio/beagle/scripts/infrastructure/deploy_sglang_dynamo_fabric.sh)
- [Dockerfile](/home/devsounio/beagle/docker/sglang-dynamo/Dockerfile)

This runtime layers `ai-dynamo[sglang]` on top of the known-good mirrored
`SGLang` image and supports:

- `python3 -m dynamo.frontend`
- `python3 -m dynamo.sglang`

So the control-plane path no longer depends on `nvcr.io` just to get started.

## Dynamo bootstrap helper

To make the remaining step mechanical, the repo now includes:

- [setup_dynamo_platform.sh](/home/devsounio/beagle/scripts/infrastructure/setup_dynamo_platform.sh)
- [deploy_sglang_dynamo_fabric.sh](/home/devsounio/beagle/scripts/infrastructure/deploy_sglang_dynamo_fabric.sh)

Usage:

```bash
DYNAMO_PLATFORM_VERSION=1.0.1 /home/devsounio/beagle/scripts/infrastructure/setup_dynamo_platform.sh dynamo-system
/home/devsounio/beagle/scripts/infrastructure/deploy_sglang_dynamo_fabric.sh beagle
```

The cockpit's published inference bootstrap command now points at this helper.

Latest observed state:

- `SGLang` engine: `ready`
  - deployment: `sglang-serving`
  - endpoint: `http://10.100.100.4:30000`
  - model: `qwen2.5-0.5B-Instruct`
- `Dynamo Platform`: `platform-ready`
  - namespace: `dynamo-system`
  - CRDs: present
  - operator: present
- `Dynamo` control plane: `ready`
  - deployment: `dynamo-control-plane`
  - endpoint: `http://10.0.3.241:8000`
- cockpit inference runtime:
  - `status: ready`
  - `truthMode: observed`
  - `engine.status: published-via-control-plane`
  - `engine.accessMode: published-via-control-plane`

Two fixes were required to make the first-party control plane boring:

- run the frontend container with:
  - `privileged: true`
  - `seccompProfile: Unconfined`
  to avoid the `uvloop` / `socketpair` permission failure
- inject pod identity via Downward API:
  - `POD_NAME`
  - `POD_NAMESPACE`
  - `POD_UID`
  - `POD_IP`
  - `NODE_NAME`
  so Kubernetes discovery can initialize cleanly

The frontend pod also uses local `exec` health probes against
`http://127.0.0.1:8000/health`, which avoids kubelet network-probe flakiness and
lets the service endpoint become ready as soon as the process is healthy.

## Public surface validation

The public surfaces are now stable enough to validate mechanically from
`t560-proxmox`.

Two helper smokes exist:

- [check_sounio_tailnet_vips.sh](/home/devsounio/beagle/scripts/infrastructure/check_sounio_tailnet_vips.sh)
- [check_project_cockpit_public_surfaces.sh](/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_public_surfaces.sh)
- [check_project_cockpit_public_assets.sh](/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_public_assets.sh)
- [check_project_cockpit_vision_route_semantics.sh](/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_vision_route_semantics.sh)
- [check_project_cockpit_full_shell.sh](/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_full_shell.sh)

Important notes:

- the cockpit VIP should be checked with `--noproxy '*'`
- the workspace HTTP VIP is on port `8080`, not port `80`

Example:

```bash
/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_public_surfaces.sh
```

That smoke currently verifies:

- cockpit health on `100.107.208.198`
- Vision control room API
- Vision Apple brief API
- Vision packet graph API
- Vision handoff API
- Vision Apple launchpad API
- Vision operator-board API
- Vision runtime-matrix API
- Vision route-atlas API
- Vision mission-timeline API
- Vision sovereign-bridge API
- Vision sovereign-cockpit-preview API
- public showcase API
- public showcase packet graph API
- public showcase sovereign bridge API
- public showcase sovereign cockpit preview API
- workspace HTTP root on `100.103.74.10:8080`

The asset smoke verifies the same routes as HTML pages directly inside the live
pod, so public-shell regressions can be caught even when the external VIP path
from a given host is temporarily noisy.

A private inference smoke now also exists:

- [check_project_cockpit_private_inference.sh](/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_private_inference.sh)

It verifies:

- `GET /api/projects/sounio/inference/runtime`
  - `status: ready`
  - `truthMode: observed`
  - `engine.status: published-via-control-plane`
  - `engine.accessMode: published-via-control-plane`
- `GET /api/projects/sounio/inference/workload`
  - `workload.status: ready`
  - `engine.status: ready`
  - `controlPlane.status: ready`
- `GET /api/projects/sounio/inference/bootstrap`
  - `provider: inference-fabric`
  - `primaryFabric: sglang+dynamo`
  - bootstrap path wired to `deploy_sglang_dynamo_fabric.sh`

For the full public/private shell path, run:

```bash
/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_full_shell.sh
```

The current public/private semantics are intentionally aligned:

- private runtime:
  - `runtime.status: ready`
  - `runtime.engine.status: published-via-control-plane`
  - `runtime.engine.accessMode: published-via-control-plane`
- public surfaces:
  - `inferenceFabric.status: ready`
  - `inferenceFabric.engine.status: published-via-control-plane`

This means the `Dynamo` frontend is the boring published path, while the model
inventory remains observed from the live fabric instead of being a declared
catalog-only fallback.
