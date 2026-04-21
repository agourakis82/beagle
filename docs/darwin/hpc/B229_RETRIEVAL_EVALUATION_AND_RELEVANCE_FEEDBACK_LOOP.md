# B22.9 — Retrieval Evaluation & Relevance Feedback Loop

## Objective

Promote the live retrieval stack from component availability to measured,
evidence-backed operation. This phase adds:

- a routed retrieval evaluation report
- a bounded relevance feedback loop on top of current retrieval
- an evidence-backed retrieval policy artifact

## Canonical stance

- `Qdrant` remains the canonical store direction
- `voyage-4-large` remains the canonical general dense backend
- `voyage-code-3` remains the bounded code lane
- `bge-m3` remains the sovereign lane
- sparse lexical retrieval remains complementary
- reranking remains bounded, not global

## What is live

- `POST /api/memory/retrieval/evaluate`
- `POST /api/memory/retrieval/feedback`
- `POST /api/memory/retrieval/policy/derive`

## Bounded feedback design

The feedback loop does not redesign retrieval. It:

1. runs the current routed retrieval path
2. accepts explicit judgments over the returned top-k
3. applies bounded score adjustment
4. compares pre-feedback vs post-feedback ordering and relevance proxy

This keeps the feedback path auditable and suitable for tool-assisted or
human-assisted refinement without introducing hidden state.
