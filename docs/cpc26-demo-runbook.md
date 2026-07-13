# CPC 2026 Demo Runbook (2 minutes)

Live-system demo of Beagle for the Computational Psychiatry Conference talk. Six steps,
each backed by a capability that was verified GREEN before this runbook was written
(see preflight below). No step here claims anything the preflight didn't check.

**Run preflight first, always, before you go live.** If any check is not GREEN, fall
back to the manual path in Step 6 rather than improvising on stage.

---

## Preflight (run before the room fills up)

```
1. External /healthz     → GET  https://beagle.chiuratto.ai/healthz            → expect 200
2. Companion (personal)  → POST /api/mobile/v1/chat  (ping)                    → expect grounded:true
3. Deep-think citations  → deepThink:true query                                → expect a citation-like pattern (url/doi/year)
4. Memory recall         → orc≈939 rows (ollivier|hyperbolic|HSN),
                            sounio≈22949 rows (sounio|souc|tapestry)
5. Claude proxy t560:9500 → GET  http://127.0.0.1:9500/v1/models              → expect 200
```

All five were GREEN at last check. If (3) or (5) go amber/red on the day, do not
debug live — jump straight to the Step 6 fallback.

---

## Step 1 — Living memory + provenance (15s)

Open the companion chat, ask a plain grounding question (e.g. "what have we been
working on this week"). Point out: the response carries `grounded:true` and is
built from a provenance-tagged record store (memory-pg), not a static prompt —
every fact it surfaces traces back to an ingested record with an actor and a
confidence value, not to model memory.

## Step 2 — Live ORC recall (20s)

Ask: **"Minha descoberta central com Ollivier-Ricci, precisa."**

Expect the system to lead with the presenter's own formulation — Ollivier-Ricci
curvature as a *dynamic* geometric biomarker, contrasted with a static-topology
read — and to self-flag any place it's stitching sources together. This is
recall against ~939 matching records, not a canned answer.

Optional second prompt if time allows: **"O que é o Experimento 06 e o elo
ORC↔gap espectral?"** — expect it to name Experiment 06 directly and state the
ORC↔spectral-gap link, tied to the conference's core claim.

## Step 3 — Deep-think citing a real paper (25s)

Trigger a `deepThink:true` query on the ORC/spectral-gap topic. The response
should contain an actual citation-like pattern (a URL, DOI, or year-anchored
reference), not a hallucinated one — this was checked in preflight (3). If the
citation looks thin or generic on stage, say so out loud rather than overselling
it; the honest framing is part of the demo's credibility.

## Step 4 — Sounio epistemic types + smt.check, and the Tapestry functor (30s)

Ask: **"O núcleo epistêmico do Sounio: Knowledge[T], GUM, smt.check — o que EU
construí?"**

Expect the three pillars stated in the presenter's own construction terms:
`Knowledge[T]` as a first-class epistemic type, GUM-style provenance/confidence/
evidence-boundary tracking, and `smt.check` as an explicit unwrap/verification
step (this has independently been verified as UNSAT/SAT-checking in production
use, not just a doc claim).

Then ask: **"O interno do funtor O-CSSM/Tapestry (divisor de zero ↔
dissociação)."** Expect it to go past the surface claim into construction
internals — octonions as a normed division algebra (Moufang, alternative,
zero-divisor-free), with zero divisors only appearing one Cayley-Dickson step
later at the sedenions, once multiplicative normativity is lost. This is the
strongest, most precise recall in the set — use it as the technical high point.

**Framing note for the room:** when you bridge this to computational
psychiatry ("HSN → psiquiatria computacional"), lead with *your own* claim
verbally rather than asking the system to state the bridge — live recall on
that specific bridging question came back thin (it correctly declines to
confabulate and asks for the acronym to be confirmed, but doesn't volunteer
the HSN = Hyperbolic Semantic Networks → Computational Psychiatry connection
on its own). State the bridge yourself, then let the system fill in the
octonion/Tapestry mechanics behind it — that part it does well.

## Step 5 — On-demand synthesis (20s)

Ask for a synthesis across the last few days of work (Sounio commits + ORC
findings + Tapestry). Expect `grounded:true` and an honest opening caveat —
the system will note it's synthesizing from the observed record (commits,
recall, conference continuity) rather than a separate "notes corpus," and will
flag where it's stitching. That self-flagging is a feature, not a gap — point
it out as evidence the system doesn't overclaim its own grounding.

## Step 6 — Manual fallback

If deep-think is slow, times out, or the proxy check (5) is not GREEN on the
day:

- Skip Step 3 entirely, or
- Route the same question through normal chat (non-deep-think) via the LiteLLM
  router instead of the deep-think path — same grounded answer quality for
  recall-style questions, just without the citation-fetch latency.

Do not retry a hung deep-think call repeatedly on stage; switch to the fallback
and move on. If memory recall itself looks stale or empty, do not attempt a
live ingest during the talk — ingestion is a separate, sequential, single-writer
operation and is out of scope for a live demo window.
