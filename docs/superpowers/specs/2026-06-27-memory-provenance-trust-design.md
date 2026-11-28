# Memory Provenance & Trust — Design Spec

**Date:** 2026-06-27
**Status:** Design (awaiting user review → implementation plan)
**Owner:** Beagle exocortex / memory-pg pipeline

## Motivation

A fabricated test fixture ("Teobaldo Quinzé, my teddy bear since 1989") was ingested
as if the user had stated it. The distill step then **amplified** the single fabrication
into 10 `records`, 7 graph `entities`, and 15 `facts` — inventing intimate claims the
user never made ("my most faithful confidant", "silent witness to my late nights").
Nothing in the pipeline distinguished **what the user asserted** from **what the model
generated** from **what the distill inferred**, so model fiction entered the sovereign
biography as fact.

This is the structural flaw behind the user's long-standing "the memory pipeline is
garbage" judgment: **there is no provenance.** This spec adds it, and on top of it a
trust model so a claim only becomes "known about the user" through corroboration —
model inferences can never masquerade as the user's truth.

## Goal

Every memory carries *who asserted it* and *what it derives from*; a fact about the user
is only asserted as fact after independent corroboration from user-stated sources. Model
generations and distilled inferences are first-class but trust-ranked, never promoted to
biography on their own.

## Non-Goals

- Re-architecting the embedding/rerank/graph-fusion retrieval (already shipped, working).
- Changing the canonical store (Postgres+pgvector / memory-pg stays).
- A general-purpose ACL/sharing model — this is about *epistemic* trust, not access control.

## Current State (grounded)

Canonical store: `memory-pg` (StatefulSet `memory-pg-0`, db `memory`). Relevant tables:

- `records` — `id, source_type, content, metadata(jsonb), occurred_at, created_at, content_sha256, privacy_class, decay_class`. **No provenance fields.**
- `chunks` — `id, record_id→records(CASCADE), chunk_index, text, content_sha256`.
- `embeddings` — `chunk_id→chunks(CASCADE), embedding, model_version, is_current`.
- `entities` — `id, name, norm_name, type, embedding, summary, content_sha256, ...`.
- `facts` — `id, subject_id, predicate, object_id, object_literal, statement, embedding, valid_from, valid_to, occurred_at, recorded_at, source_record_id→records(SET NULL), provenance, confidence, content_sha256`. **Already has `provenance` + `confidence` columns** (currently unstructured/unused for trust).

Write paths that create memories:
- **beagle-core** `/api/memory/ingest_chat` → writes `records` (one per turn/passage) + dual-writes here.
- **distill** (`apps/project-cockpit/server/memory-ingest.mjs` `distillSalient`/`ingestPersonalTurn`, Spark qwen2.5-14b) → writes distilled-atom `records`.
- **memory-pg-graph-worker** → reads records, writes `entities` + `facts`.
- **memory-pg-embed-worker** → writes `embeddings`.

Recall consumers:
- `memory-pg-serve` `/query` (companion grounding via cockpit `mobile-routes`).
- beagle-core `/api/memory/query` (the Claude Desktop bridge `beagle_memory_query`).

## Design

### 1. Provenance on every record and fact

A single canonical provenance object, stored structurally. On `records`, add columns
(not buried in `metadata`, so they are indexable and enforceable):

```
records.prov_actor       text     -- 'user_stated' | 'model_generated' | 'model_distilled' | 'external_import' | 'system'
records.prov_surface     text     -- 'companion-ios' | 'claude-desktop' | 'assisted-import' | 'agent-session' | ...
records.prov_derived_from uuid[]   -- parent record id(s); distilled atom → its source user turn
records.prov_confidence  real     -- 0.0–1.0 (model-reported or 1.0 for user_stated)
records.prov_asserted_at timestamptz
```

`facts` already has `provenance jsonb` + `confidence real` — formalize `provenance` to:
```json
{ "actor": "...", "surface": "...", "derived_from": ["<record_id>", ...], "support_records": ["..."] }
```

**Actor taxonomy** (closed set, enforced):
| actor | meaning | trust floor |
|---|---|---|
| `user_stated` | the user said it (turn role=user, any surface) | high |
| `external_import` | imported from the user's own past records (assisted-import of his convos/files) | medium |
| `model_generated` | an assistant turn / model output | low |
| `model_distilled` | the distill step inferred/condensed it | low |
| `system` | pipeline metadata | n/a (never biography) |

**Invariant:** a `model_distilled` record MUST have a non-empty `prov_derived_from`
pointing to ≥1 ancestor. A distilled atom whose ancestry contains **no** `user_stated`
record is *orphaned* and can never rise above `unverified` (§2). This single rule kills
the Teobaldo class: my fabrication entered as `model_generated`/`user_stated` *without a
genuine user origin* — under this design the distilled amplifications would be orphaned.

### 2. Trust tiers (the quorum)

A derived `trust_tier` computed from provenance + corroboration, not stored raw but
materialized (a column refreshed by the promotion job, §3, so recall can filter cheaply):

```
unverified    model_* with NO user_stated ancestor                 (Teobaldo dies here)
claimed       exactly 1 independent user_stated source             ("you said it once")
corroborated  ≥ N independent user_stated sources                  (default N = 2)
known         corroborated AND stable over time (≥ D days span)    (default D = 7)
```

**Independence rule** (the crux — prevents self-amplification):
two supporting `user_stated` records count as *independent* iff they have a **distinct
`session_id` AND a distinct calendar day** (UTC). Therefore:
- One long session restating a thing 10× = **1** independent source.
- The distill emitting 10 atoms from one user turn = **1** source (they share ancestry).
- The same claim across the companion (one day) and Claude Desktop (another day) = **2**.

This is computed over the *claim*, grouped by a normalized claim key (entity + predicate
for facts; a content-hash/semantic key for free records — see §3).

### 3. Promotion job (quorum tiering)

A periodic job (extend `memory-pg-graph-worker`, or a new `memory-pg-promotion-worker`)
that, per claim cluster:
1. Gathers supporting records (for a fact: `support_records`; for a free claim: records
   sharing a normalized claim key / near-duplicate cluster).
2. Counts **independent** `user_stated` supports (§2 rule).
3. Assigns `trust_tier` and writes it to `records.trust_tier` and `facts.trust_tier`
   (new column) + a `corroboration_count` + `independent_sources` for transparency.
4. Orphaned `model_distilled` (no user_stated ancestor) → forced `unverified`.

Idempotent, re-runnable; bounded per-cycle. Promotion is monotonic per cycle but can
demote if supporting records are deleted (e.g., a purge like the Teobaldo cleanup).

### 4. Trust-weighted recall + enforcement

`memory-pg-serve /query` and beagle-core `/api/memory/query` responses include per-hit
`trust_tier`, `prov_actor`, `corroboration_count`.

Grounding consumers (companion `mobile-routes`, the MCP bridge) apply, **for claims about
the user / biography**:
- `tier ≥ corroborated` → may be asserted as fact ("seu X é Y").
- `tier == claimed` → may be used but **hedged** ("você mencionou que..."). *(default)*
- `tier == unverified` → **excluded** from "what I know about you"; may still appear as
  raw conversational context but never as biography, never asserted.

Ranking multiplies relevance by a tier weight (e.g. known 1.0 / corroborated 0.85 /
claimed 0.6 / unverified 0.3) so trusted memories surface first. This is additive to the
existing graph-fusion ranking, not a replacement.

### 5. Backfill of existing ~81.6K records

Forward-path is authoritative; backfill is a one-shot best-effort heuristic:
- `source_type='ConversationPassage'` + turn role=user → `user_stated`.
- distilled-atom source types → `model_distilled` (derived_from best-effort: link to the
  nearest same-session user turn; if none, mark orphaned/`unverified`).
- assisted-import / disk sources → `external_import`.
- assistant turns → `model_generated`.
Then run the promotion job once over the backfilled set. Records that cannot be classified
default to `model_generated` (conservative: never auto-promoted to biography).

### 6. Phasing

- **P1 — Provenance data model + write-path tagging.** Migration (new columns), and
  every write path stamps `prov_*`. *Immediately prevents new Teobaldos* (distilled
  orphans are flagged at write time). Backfill heuristic (§5) runs here.
- **P2 — Promotion / quorum tiering.** The promotion worker (§3), `trust_tier`
  materialization, independence rule.
- **P3 — Trust-weighted recall + grounding enforcement.** §4 in `/query` responses and
  the companion/bridge consumers.

Each phase is independently shippable and testable; P1 alone closes the acute hole.

## Data Flow (after)

```
user turn ─┬─► record{actor=user_stated, conf=1.0}
           │
assistant ─┼─► record{actor=model_generated}
           │
distill  ──┴─► record{actor=model_distilled, derived_from=[user turn id], conf=m}
                     │  (orphan check: no user_stated ancestor ⇒ unverified)
                     ▼
graph-worker ─► entities + facts{provenance, support_records, confidence}
                     ▼
promotion-worker ─► trust_tier (independence-counted quorum)
                     ▼
/query ─► {hit, trust_tier, prov_actor} ─► grounding enforcement (assert / hedge / exclude)
```

## Error Handling & Edge Cases

- **Missing provenance on write** → default `model_generated` (never silently `user_stated`).
- **Distill orphan** → `unverified`, logged; never promoted.
- **Purge/deletion** → promotion job demotes claims that lose supporting records (so a
  cleanup like Teobaldo cascades to tier loss, not stale "known" facts).
- **Surface spoofing** → `prov_surface`/`actor` are set server-side from the authenticated
  ingest path, never trusted from client free-text.
- **Backfill ambiguity** → conservative default (`model_generated`), never auto-biography.

## Testing Strategy

- **Unit:** independence counter (10 atoms from 1 turn ⇒ 1 source; 2 surfaces/2 days ⇒ 2);
  orphan detection (distilled w/o user ancestor ⇒ unverified); tier assignment table.
- **Property:** no `model_*`-only claim ever reaches `corroborated`.
- **Regression (the Teobaldo test):** ingest a fabricated distilled cluster with no
  user_stated ancestor → assert it stays `unverified` and is excluded from biography recall.
- **Integration:** ingest user_stated claim across 2 sessions/2 days → promotes to
  `corroborated` → asserted as fact in grounding.
- **Migration:** backfill heuristic on a sample → spot-check actor classification.

## Open Decisions (defaults chosen; adjust in review)

1. **Quorum N = 2**, independence = distinct session_id AND distinct day.
2. **Backfill now** (one-shot heuristic over the 81.6K), not forward-only.
3. **`claimed` hedges** (not excluded) in recall.
4. **`known` stability window D = 7 days.**
