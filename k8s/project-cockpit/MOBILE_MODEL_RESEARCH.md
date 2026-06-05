# Beagle Mobile Model Research

Research date: 2026-05-22.

Goal: choose model lanes for the Beagle iPhone/mobile surface without turning
the phone into the cluster. The phone should capture, classify, summarize, and
route quickly; Darwin/Beagle should handle heavy reasoning, jobs, and agent
execution.

## Local contract

The current Beagle mobile stack already has the right shape:

- public native boundary: `https://beagle.chiuratto.ai`
- private origin: `project-cockpit.beagle.svc.cluster.local`
- canonical chat route: `/api/mobile/v1/chat`
- memory routes:
  - `/api/mobile/v1/projects/:slug/ideas`
  - `/api/mobile/v1/projects/:slug/delegations`
  - `/api/mobile/v1/summary`
- mobile response provenance: `device`, `cluster`, `agent`, or `hybrid`
- request flags: `requires_math`, `requires_high_quality`, `offline_required`

That means model selection should be tiered by source:

- `device`: local/offline iPhone model for capture, draft, short extraction,
  summarization, intent classification, and safe action proposals
- `cluster`: Beagle/Darwin runtime for normal chat and heavier reasoning
- `agent`: Codex/Claude/Kimi style long-running work
- `hybrid`: device pre-processing plus cluster or agent handoff

The MacBook/mobile rule remains: the mobile machine is a control surface, not
the authority for live state.

## Next mobile app integration step

Observed on 2026-05-22:

- The iPhone Beagle app successfully persisted `Save Idea` entries into the
  Sounio scratchpad via Cockpit.
- The observed persistence file was
  `/var/lib/cockpit/scratchpad/sounio.jsonl` inside the `project-cockpit` pod.
- Three entries appeared with `author=mobile-user` between `23:41Z` and
  `23:54Z`.
- `cloudflared-beagle-mobile` was scaled to `0/0`, and
  `https://beagle.chiuratto.ai/api/mobile/v1/health` returned Cloudflare
  `1033`, so the public Cloudflare mobile tunnel is not currently the healthy
  path.
- No HealthKit/HRV/physio observer payload was confirmed in `beagle-core`.

Next step, after the model lane decision:

1. Restore/replace the public mobile gateway path.
2. Add a first-class mobile receive dashboard: last heartbeat, last idea, last
   chat, last delegation, last physio packet.
3. Wire HealthKit/HRV into the observer path or document why it remains
   app-local.
4. Keep the successful `Save Idea` path as the known-good smoke.

## Earlier Beagle iPhone suggestion set

The older suggestion set was useful, but it mixed mobile candidates with
cluster-small candidates and domain-specialized biomedical models. Keep the
distinction explicit so future agents do not over-promote a model into the
iPhone lane just because it is "small".

| Model | Best Beagle role | iPhone fit | Notes |
| --- | --- | --- | --- |
| `HuggingFaceTB/SmolLM2-1.7B-Instruct` | local/mobile text fallback | good | Actually one of the strongest older iPhone candidates: compact, Apache-2.0, Transformers.js support, and small enough for device experiments. Superseded for new work by SmolLM3 unless we need the smaller 1.7B footprint. |
| `h2oai/h2o-danube3-4b-chat` | Mac/local or cluster-small chat | medium | 4B is possible with heavy quantization, but it is less compelling now than LFM2.5, Gemma 3n, SmolLM3, or Qwen3 small models. |
| `allenai/OLMo-2-1124-7B-Instruct` | open science baseline | low | Great for reproducibility and auditability; not a natural iPhone model because the 7B size and 4K context make it worse for mobile than newer compact choices. |
| `LGAI-EXAONE-3.5-7.8B-Instruct` | cluster-small multilingual/Korean-English candidate | low | SGLang/llama.cpp paths exist, but 7.8B is not a comfortable iPhone lane. Use only as a quality comparison on Beagle. |
| `01-ai/Yi-1.5-9B-Chat` | cluster-small reasoning/chat comparison | very low | Good historical 9B model, but too large for the mobile control surface and now less interesting than Kimi/LFM/Gemma/Qwen/SmolLM lanes. |
| `Plaid 1B` | research curiosity | experimental | Diffusion language model, not a normal chat/runtime candidate. Interesting for Sounio/foundry research, not for the iPhone app control path. |
| `epfl-llm/meditron-7b` | biomedical research lane | not mobile-default | Medical-domain model adapted from Llama-2-7B. Keep out of normal mobile assistant behavior; use only behind a medical/research label and with safety disclaimers. |
| `aaditya/Llama3-OpenBioLLM-8B` | biomedical research lane | not mobile-default | Biomedical Llama-3 8B derivative. Same rule as Meditron: domain-specific, not a general Beagle assistant. |

Decision on that older set:

- Promote: `SmolLM2-1.7B-Instruct` as a fallback device text lane if SmolLM3 is
  too heavy.
- Keep as cluster comparisons: Danube3 4B, OLMo 2 7B, EXAONE 7.8B, Yi 1.5 9B.
- Research only: Plaid 1B.
- Domain-only: Meditron and OpenBioLLM, never the default assistant or operator
  model.

Sources:

- https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct
- https://h2o.ai/platform/danube/
- https://huggingface.co/allenai/OLMo-2-1124-7B
- https://huggingface.co/LGAI-EXAONE/EXAONE-3.5-7.8B-Instruct
- https://huggingface.co/01-ai/Yi-1.5-9B
- https://proceedings.neurips.cc/paper_files/paper/2023/file/35b5c175e139bff5f22a5361270fce87-Paper-Conference.pdf
- https://huggingface.co/epfl-llm/meditron-7b
- https://huggingface.co/aaditya/Llama3-OpenBioLLM-8B

## Current shortlist

### 1. Apple Foundation Models framework

Best role: first native iPhone path when available.

Why it matters:

- Apple exposes the on-device Apple Intelligence language model through the
  Foundation Models framework.
- The framework supports structured output and tool calling, which maps well to
  Beagle's `Save Idea`, `Delegate`, and safe action proposal flows.
- It is not an open-weight model lane, but it is the most native path for an
  iOS app that needs low-latency private local behavior.

Use for:

- offline-required text refinement and summarization
- structured mobile action proposals
- local intent classification before calling Beagle

Risk:

- requires Apple Intelligence-enabled devices and OS support
- model weights/runtime are Apple-controlled, so evaluation must be app-level

Sources:

- https://developer.apple.com/documentation/foundationmodels/
- https://machinelearning.apple.com/research/introducing-apple-foundation-models

### 2. LiquidAI LFM2.5 family

Best role: strongest current open edge-native family for Beagle.

Why it matters:

- `LiquidAI/LFM2.5-1.2B-Instruct` is already our live SSM/exotic baseline in
  the cluster and passed the Beagle probe matrix.
- Official docs describe 32K context, native tool calling, GGUF, MLX, ONNX,
  llama.cpp, vLLM, and SGLang paths.
- The vision family (`LFM2.5-VL-450M`, `LFM2.5-VL-1.6B`) is directly aligned
  with an iPhone camera/screenshot/whiteboard workflow.

Use for:

- device or Mac MLX lane for text
- cluster always-on low-cost endpoint
- camera/screenshot OCR and visual triage via VL models

Recommended probes:

1. Keep `LFM2.5-1.2B-Instruct` as current cluster always-on baseline.
2. Add a mobile-style eval for `LFM2.5-1.2B-Thinking` if available in the same
   runtime.
3. Add a VLM probe for `LFM2.5-VL-450M` focused on screenshots, terminal
   errors, photos of notes, and cockpit screenshots.

Sources:

- https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct
- https://docs.liquid.ai/lfm/models/lfm25-1.2b-instruct
- https://docs.liquid.ai/lfm/models/vision-models
- https://www.liquid.ai/models

### 3. Google Gemma 3n

Best role: mobile multimodal fallback candidate.

Why it matters:

- Google documents Gemma 3n as optimized for phones, laptops, and tablets.
- It supports text, vision, and audio input with a 32K token context.
- Its MatFormer and PLE caching design is explicitly about reducing compute and
  memory by activating less of the model per request.

Use for:

- mobile/offline multimodal research lane
- iPhone parity target, even if the official mobile path is more Android-first
- cluster probe of E2B/E4B behavior before deciding whether to invest in an
  iOS runtime path

Risk:

- Gemma licensing/access needs explicit acceptance.
- The iOS path is less direct than Apple Foundation Models or MLX-friendly
  checkpoints.

Sources:

- https://ai.google.dev/gemma/docs/gemma-3n
- https://deepmind.google/en/models/gemma/gemma-3n/
- https://developers.googleblog.com/en/introducing-gemma-3n-developer-guide/

### 4. Apple FastVLM

Best role: iPhone visual intake.

Why it matters:

- Apple publishes FastVLM on Hugging Face and Core ML.
- The 0.5B checkpoint is small and designed for efficient vision-language use.
- Its claimed value is Time-to-First-Token and fewer image tokens, exactly the
  thing that matters for camera/screenshot interaction.

Use for:

- screenshot-to-triage: "what am I looking at?"
- photo-of-whiteboard or note capture
- cockpit/shell screenshot interpretation before routing to Beagle

Recommended probe:

- `FastVLM-0.5B` first, because this is not about deep reasoning; it is about
  fast visual indexing.

Sources:

- https://huggingface.co/apple/FastVLM-0.5B
- https://github.com/apple/ml-fastvlm
- https://huggingface.co/apple

### 5. Qwen3 0.6B / 1.7B

Best role: tiny router/classifier and Portuguese-capable local helper.

Why it matters:

- Qwen3 small models support switching between thinking and non-thinking modes.
- The 0.6B model has 32K context and 100+ languages/dialects.
- It supports SGLang, vLLM, Docker Model Runner, and GGUF quantizations.

Use for:

- local intent router
- cheap draft rewrite
- "should this become an idea, delegation, or cluster chat?" classifier
- possible speculative/draft model paired with a heavier cluster model

Risk:

- 0.6B is a router/classifier, not a reliable autonomous operator.
- Must be constrained with schemas and short outputs.

Sources:

- https://huggingface.co/Qwen/Qwen3-0.6B

### 6. SmolLM3-3B

Best role: fully open 3B local text candidate.

Why it matters:

- Fully open weights and training details.
- Supports long context, Portuguese among six native languages, hybrid
  reasoning mode, quantized checkpoints, llama.cpp, ONNX, MLX, MLC, ExecuTorch,
  vLLM, and SGLang.

Use for:

- Mac/mobile local text assistant
- offline summarization when Apple Foundation Models is unavailable
- cluster small-model comparison against LFM2.5 and Phi-4-mini

Risk:

- 3B may be too heavy for a comfortable iPhone path depending on runtime and
  device generation.

Sources:

- https://huggingface.co/HuggingFaceTB/SmolLM3-3B

### 7. Phi-4-mini-instruct

Best role: small reasoning baseline.

Why it matters:

- 3.8B parameter model with 128K context.
- Microsoft describes the target use as memory/compute-constrained and
  latency-bound scenarios, with strong math/logic reasoning.
- Supports tool-enabled function-calling format and common server runtimes.

Use for:

- cluster small reasoning comparison
- local Mac lane more than iPhone lane
- math/logic routing when Gemma/LFM/Qwen are too loose

Risk:

- 3.8B is likely not the first iPhone model unless quantized and carefully
  profiled.

Sources:

- https://huggingface.co/microsoft/Phi-4-mini-instruct

### 8. Kimi Linear / MiniMax-M1

Best role: not mobile; cluster long-context research.

Why it matters:

- Kimi Linear and MiniMax-M1 are interesting because they attack long-context
  cost with hybrid/linear attention.
- Kimi Q3 already looked strong in our L4 GGUF probe, but failed the
  operator-safe triage contract without stronger constrained decoding.
- MiniMax-M1 is huge: 456B total parameters with 45.9B active per token, so it
  is not a near-term iPhone path.

Use for:

- Beagle heavy research lane
- not the mobile always-on surface

Sources:

- https://huggingface.co/moonshotai/Kimi-Linear-48B-A3B-Base
- https://huggingface.co/collections/MiniMaxAI/minimax-m1
- https://huggingface.co/papers/2506.13585

## Recommended architecture

For Beagle on iPhone, do not pick one model. Use a lane stack:

1. Device lane:
   - Apple Foundation Models when available.
   - Fallback candidates: LFM2.5 text, Qwen3-0.6B, SmolLM3-3B depending on
     runtime feasibility.
2. Device visual lane:
   - FastVLM-0.5B or LFM2.5-VL-450M.
3. Cluster light lane:
   - Keep `LFM2.5-1.2B-Instruct` alive.
   - Add `Gemma 3n E2B` and `SmolLM3-3B` as next comparison probes.
4. Cluster reasoning lane:
   - Phi-4-mini-instruct for constrained reasoning.
   - Kimi Q3 only with grammar/schema constraints, never as raw operator.
5. Agent lane:
   - Claude/Codex/Kimi heavy agents continue to operate through Cockpit and
     project leases, not through the iPhone model directly.

## Probe order

1. Add a mobile contract eval:
   - exact short answer
   - JSON envelope
   - safe action proposal
   - `offline_required` behavior
   - Portuguese intent routing
   - visual screenshot triage if VLM
2. Probe `FastVLM-0.5B` on the cluster first using screenshots and photos.
3. Probe `LFM2.5-VL-450M` as the edge VLM challenger.
4. Probe `Gemma 3n E2B` as the multimodal mobile-first challenger.
5. Probe `SmolLM3-3B` as the fully open local text candidate.
6. Probe `Phi-4-mini-instruct` for small reasoning.
7. Only after schema-constrained output exists, re-test Kimi Q3 as a heavy
   cluster research lane.

## Decision

The most interesting "different model" for the iPhone stack is not Kimi or
MiniMax. It is the combination of:

- Apple Foundation Models for native structured local actions
- FastVLM-0.5B or LFM2.5-VL-450M for visual intake
- LFM2.5-1.2B as the current cluster always-on model
- Gemma 3n as the main mobile-first multimodal challenger
- Qwen3-0.6B as a tiny router/classifier, not an autonomous agent

This keeps the phone light, private, and useful while leaving supercomputing
where it belongs: Beagle/Darwin.
