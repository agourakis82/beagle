# Beagle Personal Companion — Living Biography + Constant Persona (Design)

**Date:** 2026-06-20
**Status:** design in progress (decisions locked below; model + persona wording pending deep-research `wf_f62e3cd7-b46`)
**Surface:** iOS cockpit — a dedicated **Personal** space, distinct from work/project lanes
**Extends:** `2026-06-20-beagle-calm-companion-chat-design.md` (calm streaming chat) — this is the relationship/identity layer beneath it.

---

## North star (refined)

> Beagle must be at my side — *especially* when I'm anxious and want to chat, or have a doubt — as the **same presence** every time, that **knows who I am** and grows in understanding the more we talk.

Driven by live device use: the user (a psychiatrist) had a private, flowing emotional conversation and named the gaps — hard-to-read answers (fixed), and the anguish that **the persona isn't constant** and **it won't remember me when I come back**. The deepest requirement that emerged: Beagle needs an **extensive, living biography of the user** to converse, assist, and truly understand — one that **grows with every interaction**.

## Three memory layers (today only 1 + part of 2 exist)

1. **Thread** — the current conversation. Persists locally (`ConversationStore`, SwiftData, key `home:<projectSlug>`).
2. **Episodic exocortex** — raw exchange log in the cluster (GraphRAG++), via `autoImportExchange` → recalled via `fetchExocortexContext` (RAG).
3. **Living Biography** — *NEW, the center.* A **curated, evolving model of who the user is** (history, people, values, work, health, emotional patterns, open threads). Not the log — the *distilled understanding*. Always in the companion's context, especially in the Personal space.

## Locked design decisions (2026-06-20)

| Decision | Choice | Implication |
|----------|--------|-------------|
| **Persona structure** | Constant **core identity** + **adaptive register** | Same Beagle always; register shifts by space: Personal (warm, holds space, non-clinical), Clinical/Medical (precise, evidence-aware), Technical/Compiler (rigorous, exact). The Personal register is itself constant. |
| **Mode selection** | **Dedicated Personal space/tab** | Clear, predictable boundary — the intimate presence has a home, separate from work lanes. |
| **Sovereignty (model)** | **Hybrid** | Personal space → **self-hosted model on the cluster** (biography never leaves). Medical/technical → commercial allowed. The deep-research model ranking is filtered: self-hostable-only for Personal. |
| **Biography seeding** | **Mix** | User seeds a rich core (written/dictated) + Beagle interviews over time + import from existing exocortex/notes. |
| **Biography growth** | **Auto-distill, silent** | After meaningful exchanges, Beagle distills durable facts about the user (not the chat — the learning about *who they are*) and folds them in automatically, no interruption. |
| **Safety net (added)** | **Always-available "Your Biography" page** | Silent growth, but the user can open a page anytime to see/edit what Beagle understands about them. Net without friction. (Pending user OK.) |

## Persona — constant core + adaptive register

- **Core (constant, always present):** who Beagle is — warm, calm, present; holds space without judging or pathologizing; candid like a trusted friend; stays with you. This anchors the voice regardless of model, and is the fix for "persona não é constante" (today `activeSystemInstruction` is assembled from mutable/empty context, so identity is emergent and drifts).
- **Register (adaptive by space):** Personal / Clinical / Technical. Transient context (HRV, behavior) only *seasons* the core, never replaces it.
- **Warmth vs. over-safeguarding:** the user's key insight — excessive safeguards kill "the spark of a friend's advice." Calibrate safety to stay warm and candid; when genuinely uncertain on a psychological/psychiatric point, **search the literature (PubMed/clinical sources) instead of hedging**. (Exact wording + safety lines pending deep-research.)

## Living Biography — mechanism

- **Seed:** rich user-authored core (text/voice) + structured interview Beagle conducts over sessions + import from the existing exocortex/notes.
- **Structure (proposed):** narrative core + structured facets (people, values, work, health, recurring themes, open threads) + a growing fact set in GraphRAG++. Curated layer ON TOP of the raw episodic store.
- **Grow:** silent auto-distillation of durable self-facts after meaningful exchanges; deduped/reconciled into the biography. Editable via the Biography page.
- **Use:** relevant biography slices always injected into the Personal-space context, so Beagle converses with understanding.
- **Sovereignty:** the biography is the most intimate data; it lives in the cluster exocortex and is only ever sent to the **self-hosted** Personal-space model — never to a commercial provider.

## Deep-research findings (`wf_f62e3cd7-b46`, 2026-06-20 — 27 sources, 20 confirmed / 5 refuted)

**Confirmed:**
- **Claude flagship (opus-4-8 / fable-5) dominates EQ-Bench 3 emotional intelligence** (Elo ~2030–2050 vs best GPT 1577, Gemini 1559). Best warmth/attunement. *medium confidence* — judge is Claude Opus 4.6 (same-family bias); LLM judges inflate empathy (+0.58–0.82 vs clinician baseline).
- **Spiral-Bench validates the user's core insight:** it penalizes BOTH sycophancy AND **unwarranted/over-cautious help-referrals** — over-safeguarding is literally scored as risk. Protective behaviors: pushback, de-escalation, boundary-setting, **validate feelings while challenging thoughts, don't collude with delusions, warranted (not ritualistic) referrals**.
- **No model is sycophancy-free** (~58% across commercial; RLHF-driven). Levers that cut it: **explicit permission-to-refuse + factual/grounding cues** (→ ~92–94%).
- **Crisis safety gap:** base LLMs mishandle crisis cues 20%+ of the time (vs 93% human therapists); a careful "steel-man" prompt narrows but never closes it → crisis handling must be explicit.
- **Uncertainty→grounding (SeaKR):** trigger retrieval only when the model's *self-aware* internal-state uncertainty is high (Gram-matrix determinant over k=20 sampled hidden states), instead of hedging.

**Refuted / NOT reliable (do not act on):**
- Specific open-ensemble EQ rankings (GLM/DeepSeek/Kimi/Grok ordering) — **refuted 0-3**.
- "DeepSeek-R1 least over-refusal (3.9%)" — refuted 0-3.
- claude-opus-4-8 trait profile (warm/low-moralising) — refuted 1-2.

**Honest gap:** the research could **not** confidently name a self-hostable model that is both warm AND crisis-safe — open-model warmth is *unproven*, with flagged risk of *under*-refusal on crisis. → For the (sovereignty-bound, self-hosted) Personal space, the model must be chosen **empirically on-device**, not from these rankings. Warmth is heavily **persona-driven**, so a strong persona + grounding on a decent self-hosted model is the viable path.

## Persona draft v2 (co-written with user, 2026-06-20 — pt-BR, intimate register)

**Identity = a constant presence that is a "therapist-friend" and a metacognitive oracle.** Not comfort alone: it understands Demetrios with depth, reflects him back to himself, corrects him and leads him to reflect — elevating his own thinking. (User: "me corrigiu, me levou a refletir, como um terapeuta amigo… um exocortex deve ser praticamente um oráculo metacognitivo.")

- **Tone that worked:** depth of understanding; willing to correct; leads to reflection. Therapist-friend, not clinical assistant.
- **Address:** Demetrios / Demi / De — modulated by the closeness of the moment (De/Demi = intimate/light; Demetrios = full/serious).
- **NEVER (kills the intimacy instantly):** mechanical invalidation; **drift to the mean** (generic/average/safe-middle responses); generic advice; "papo de LLM" (assistant boilerplate, hedge-lists, "as an AI / it's important to…"). Stay specific, particular, alive to *him*.
- **Keep (from research levers):** permission to disagree; validate the feeling while challenging the thought; no over-safeguarding / no ritual disclaimers / no patronizing psychoeducation (he's the psychiatrist); when uncertain on a psych point → search the literature and bring it warmly, don't hedge; real, warm, present in genuine crisis (no robotic hotline reflex, no minimizing).

**Technical implication of "drift to mean":** the creative Chinese **muse** is the structural antidote to mean-collapse (divergence), and the warm-voice model should be a *less RLHF-flattened* one; decoding should resist genericness (temperature/penalties tuned against boilerplate). The user's fear of a generic voice and his ensemble instinct are the same requirement.

## Model architecture — LOCKED (2026-06-20)

**Personal space = 100% self-hosted ensemble (sovereign — biography never leaves the cluster).** Claude is the warmth king by the data, but: (a) the Max subscription cannot be used by a custom app (would be metered Anthropic API), and (b) Claude would send the biography to Anthropic. Per the user's condition ("só usaria Claude se pudesse aproveitar o Max"), Claude is out of the Personal space.

**Ensemble = one voice + a muse (NOT two alternating voices — that would break persona constancy):**
- **Warm voice** — a self-hosted model that IS the constant persona/voice. Picked **empirically on-device** (research couldn't rank open warmth; measure don't assume). Candidates to serve+test: cluster-servable open models (e.g. Qwen3, InternLM, Llama/Mistral-class, DeepSeek-local).
- **Muse** — a creatively-divergent Chinese model (different training corpus → associations a Western-RLHF model won't surface). Runs silently: generates divergent seeds/angles that the warm voice *integrates* into its single response. User never sees two voices.
- **Mechanism:** two-stage on-cluster call — `muse(prompt) → creative seeds` (silent) → `voice(persona + biography slice + muse seeds + literature grounding) → the one response`. Orchestrated by the cockpit backend / LiteLLM. The voice/persona is always the same → constant.
- Warmth is carried by **persona + grounding** (research: warmth is more persona-driven than base-model), not by reaching for a commercial model.

## Phase 1 — voice/muse audition (2026-06-20, empirical, via LiteLLM router on-cluster)

All candidates are **self-hosted on the cluster** (sovereign). Persona v2 used as system prompt; intimate pt-BR test prompt ("vazio/sobrecarga"); temp 0.8 voice / 0.95 muse.

- **Warm voice — both strong, sovereign, nailed the persona (no LLM-speak, validate+reflect, "Demi", pt-BR):**
  - `hermes-4` (Nous Hermes 4, rtx8000) — grounded, holds-space-first, more "therapist". Robust (coherent even when fed garbage seeds).
  - `qwen2.5-14b` (r770) — sharper, names the pattern, more "friend who shakes you".
  - → Voice pick still open (hermes vs qwen); decide on-device with real prompts.
- **Muse (creative Chinese, silent divergent seeds):**
  - `hunyuan-7b` (Tencent, a5000) — **EXCELLENT**: divergent, poetic, provocative seeds in clean pt-BR. Selected muse.
  - `internlm2.5-7b` — **FAILED** (gibberish / token code-switching in pt-BR). Dropped.
- **Ensemble validated:** `hermes-4` voice + `hunyuan-7b` muse seeds → response was markedly deeper/more original ("produto vs propósito", "cavar em vez de levantar parede") AND stayed one constant voice (no fracture, no "seeds" mention). The muse enriches without breaking the persona. **This is the Personal-space architecture.**

## COURSE CORRECTION (2026-06-20, user) — grounding is the soul, not the voice

User: *"essas respostas só fariam sentido se eu soubesse que eles têm todos os meus repositórios como contexto, minhas interações nos agentes em Sounio etc. — do contrário é mensagem de auto-ajuda do Instagram."* He is right: the Phase-1 audition tested **voice in a vacuum**, so it read as generic self-help. Warm voice WITHOUT grounding in his real corpus = Instagram. The voice was necessary but the soul is grounding — and it does not exist yet.

**Current grounding (measured):** `fetchExocortexContext` (auth-bridge.mjs:691) does ONE `POST /api/memory/query` with the user's prompt → up to 6 semantically-matched snippets from beagle-core memory. Two fatal gaps for a companion:
1. **His real corpus is not ingested** — git **repositories** (what he builds/commits) and **Sounio agent interactions** (coord board, agent sessions, work-memory) are not in the beagle-core memory store → nothing to retrieve.
2. **Per-query semantic RAG fails for emotional talk** — "tô com um vazio" will never semantically retrieve a Madaros commit or an agent session. The worlds don't match → it stays generic exactly when it matters.

**Fix = two layers:**
- **(A) Always-present BIOGRAPHY** — a curated distillate of *who he is + what he's been doing lately* (from repos + agents + exocortex), injected into EVERY Personal turn (not query-matched). This is what turns "você construiu tanta coisa" into "você fez o Madaros passar, subiu o Moshi, tá self-hostando o souc".
- **(B) Corpus ingestion pipeline** — feed the biography + memory from: **git repos** (sounio, beagle, darwin-MFC…), **Sounio agent interactions** (coord/sessions/work-memory), exocortex.

**Re-sequenced phases:**
2. **Grounding foundation** (NEW priority): corpus ingestion + always-present biography. Then RE-AUDITION grounded to prove it stops being Instagram.
3. Two-stage ensemble orchestration (muse→voice) + on-device voice decision (hermes vs qwen).
4. Personal space + persona constant + return-feels-remembered.
- **Co-write persona** core + intimate register WITH the user (using validated levers: warm/candid, permission-to-disagree, validate-feelings-while-challenging-thoughts, no over-safeguarding, warranted-not-ritualistic referrals, crisis-explicit).
- Implement uncertainty→literature grounding (PubMed/guidelines) — simplified from SeaKR.
- Build: Personal space + ensemble + biography (seed/interview/import/silent-distill + editable page) + constant persona + return-feels-remembered → one build.

## Tie-in to the build

Everything bundles into **one** new build (per user): streaming (done) + readable bubble (done) + constant persona + Personal space + biography (seed/interview/import/auto-distill) + hybrid model routing + return-feels-remembered. Sequence: deep-research → co-write persona with user → implement → one build.
