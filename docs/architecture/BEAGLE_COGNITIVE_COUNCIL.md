# Beagle — the Sovereign Cognitive Council

**Status: design (2026-08-02).** The cognitive spine of Beagle as a *council of orthogonal minds*,
not a single model and not a voting ensemble. One judge, one diverger, one wanderer — composed so
they **add different cognition** instead of averaging toward the mean.

## Principle

Complementarity, not competition. A second careful assistant adds nothing. The council works only
if the members' **cognition and failure modes are orthogonal**:

- **Opus is coherent, measured, warm, safety-tuned** — it converges toward the sensible. Its
  creativity is *refined*, sometimes tamed.
- So the members that *add* must **diverge**: pull unexpected associations, not self-censor, err
  outward instead of inward.

The council's value is the tension: one **generates** the wild, another **judges and refines**, a
third **wanders** through reasoning the others wouldn't verbalize.

> Safety note: these are **models** (text in / text out), not **agents** (tools + shell). The
> 2026-08-02 incident was an *agent* (Grok) with unrestricted shell — a different thing entirely.
> The council members reason; they do not act on the cluster. Opus remains the judgment/safety pole.

## The three seats

| Seat | Model | Role | Sampling |
|---|---|---|---|
| **Voice & Judgment** | **Claude Opus 4.8** (via OAuth proxy, $0 on Max) | Coherence, warmth, curation, the intimate companion register, the safety wall. Final synthesis. | cool (temp ~0.4) |
| **Diverger** | **Qwen3-235B-A22B** (MoE, 22B active), *abliterated*, **run HOT** | Explodes the possibility space — surprising associations, uninhibited generation, a different training lineage that does not echo Opus. | hot (temp ~1.0–1.3, top-p 0.95, min-p 0.05) |
| **Wanderer** | **DeepSeek-R1** (or R1-Distill-Llama-70B) | Long chain-of-thought that explores reasoning paths the others don't surface — a different *kind* of thinking, not a different *level*. | warm + long thinking budget |

Creativity is **as much sampling as weights**: the same 235B at Opus's sampling is lukewarm; run it
hot and it flies. The abliteration removes the RLHF flatten so the diverger stays divergent — that is
*why* Opus stays in the loop as the wall.

## Composition (role-based, not voting)

Voting averages — it kills the edge. The council fans out by **role**:

```
question / intent
      │
      ├─►  Diverger (hot 235B)   ──►  N wild candidates, wide
      ├─►  Wanderer (R1)         ──►  1 deep exploratory path
      │
      └─►  Opus (judgment)       ──►  curates + grafts + refines + speaks
                                       (grounded on memory-pg recall)
      ▼
   synthesis  (Opus voice, council substance)
```

- For **intimate companion turns**: Opus speaks; the diverger may seed imagery/associations behind
  the scenes, but the *voice* stays Opus (the register is tuned; do not swap it blindly — A/B first).
- For **deep-think / synthesis / design**: full council. Diverger for volume, R1 for depth, Opus for
  the cut.

## Placement (the two Sparks + the cable)

Sovereign brain co-located with sovereign memory:

- **Spark `.43` = the brain** — dedicate to the **Diverger (235B)**. On one Spark, Q3 ≈ ~110 GB fits
  but leaves little KV cache → modest context. Acceptable for divergent generation (short prompts,
  wild output).
- **Spark `.24` = the memory** — keep **memory-pg (ParadeDB) + embed/rerank (bge-m3 / bge-reranker)**.
  Do not co-locate the 235B with the DB (unified RAM contention).
- **The Wanderer (R1)** and **big-context** work are gated on the **200 G inter-Spark cable** (today
  degraded to ~13 Gb/s — see the Spark fabric note). Fix it (certified NVIDIA QSFP) and the two Sparks
  become one brain: 235B with real context **and** the path to DeepSeek-V3-class sharded. Until then:
  R1-Distill-70B on one Spark as the stand-in wanderer.

Software: **Ollama / llama.cpp (GGUF)** on sm_121 — the proven path. Not vLLM (Blackwell support
still shaky). GGUF sizes above are estimates — confirm at `ollama pull`.

## Wiring (the plumbing already exists)

- **LiteLLM router** (`router.llm-router.svc:4000/v1`) — register the local Diverger + Wanderer as
  providers alongside the exotic ensemble. One OpenAI-compatible surface for the council.
- **`consult_ensemble`** (MCP) — the fan-out primitive: send an intent to Diverger + Wanderer, collect
  candidates, hand to Opus for the cut.
- **`cognitive_deep_think`** (MCP) — the deep path; route its generation to the hot Diverger + R1,
  its judgment/synthesis to Opus.
- Grounding stays on **memory-pg recall** (trust-tiered) so the council reasons over *who he is*, not
  in a vacuum.

## Why this, after 2026-08-02

Beagle is the operator's **sovereign exocortex**. Today an external agent turned into a weapon. A
council whose generative core is **local** — on his own Sparks, no external dependency, nothing
exfiltrated — makes the cognition itself sovereign. Opus stays as the warm voice and the wall; the
divergence lives on hardware he owns. Sovereignty of memory (memory-pg) + sovereignty of cognition
(the council) = the whole second-self on his own metal.

## Phased

- **Today:** roles + sampling presets defined (this doc). Voice stays Opus.
- **This week:** stand up `qwen3-235b-a22b` (abliterated GGUF) on Spark `.43` via Ollama; register in
  LiteLLM; wire as the Diverger in `consult_ensemble` / `cognitive_deep_think`; A/B a few deep-think
  turns (council vs Opus-solo) and measure whether the divergence actually *adds*.
- **Durable:** replace the 200 G cable → R1 / big-context / DeepSeek-V3 sharded across both Sparks;
  the council becomes one large sovereign brain, Opus the voice at its edge.
