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

## Open / pending (deep-research `wf_f62e3cd7-b46`)

- Ranked **self-hostable** model pick for the Personal space (warmth/attunement, low over-refusal/sycophancy) + commercial pick for non-sensitive.
- Persona + safety wording that preserves warmth (do/don'ts, crisis handling, clinician-self case).
- Uncertainty→literature-grounding mechanism (triggers, RAG over psych literature, citation without breaking warmth).

## Tie-in to the build

Everything bundles into **one** new build (per user): streaming (done) + readable bubble (done) + constant persona + Personal space + biography (seed/interview/import/auto-distill) + hybrid model routing + return-feels-remembered. Sequence: deep-research → co-write persona with user → implement → one build.
