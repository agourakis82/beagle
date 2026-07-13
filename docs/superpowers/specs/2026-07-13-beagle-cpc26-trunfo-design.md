# Beagle as a CPC26 Trump Card — Design Spec

**Date:** 2026-07-13
**Deadline:** CPC26 Yale pre-conference, 2026-07-14 (tomorrow). Owner actively participating.
**Bar:** "funcionar direito" — at a conference, half-working is worse than absent. Reliability > features.
**Scope decision (approved):** Core #1+#2+#3 hardened + #4 on-demand (NOT real-time) + **Sounio woven through**.

## 1. Goal

Make Beagle a real intellectual advantage for the owner at CPC26: recall his own work sharply,
answer hard questions with cited depth on demand, be demonstrable to peers, and let him capture
during talks and synthesize afterward — grounded in his corpus AND his Sounio work.

## 2. Ground truth (measured live 2026-07-13, not assumed)

- **#1 Intellectual partner ALREADY works.** Live companion (`space:personal`, claude-opus-4-8,
  `grounded:true`) led with his own ORC framing: "Ollivier-Ricci curvature as a dynamic biomarker
  across scales, application-novelty not method-novelty; sign changes / phase transitions of ORC in
  random regular graphs; Experimento 06 = ORC↔spectral-gap link; bridge to comp-psych via semantic
  networks." It self-flagged where it was stitching fragments (anti-confabulation working).
- **#2 Deep-think ALREADY works.** Live `deepThink:true` ran ToolSearch + multiple WebSearch,
  returned in ~76s, HTTP 200, cited a real source (Farooq et al. 2019, *Network curvature as a
  hallmark of brain structural connectivity*, Nat Commun 10:4937, with URL) and WARNED against
  overclaiming (Ricci-in-schizophrenia literature is sparse). This is the trunfo, already functional.
- **Corpus is rich:** ORC/HSN/comp-psych = 2,718 records / 1,958 facts; his ORC paper already
  `deep_fetch`-read into memory (37,329 chars). **Sounio = 30,300 records** (SounioCommit + SounioState
  + MemoryAtom + ConversationPassage channels live).
- **The ONE grounding gap:** O-CSSM/Tapestry **internal construction detail** is NOT grounded — the
  companion has his *claims/framing* about it but not the internals. Closing this is the highest-value
  content improvement for the showcase.

**Design consequence:** do NOT rebuild #1/#2 — they are conference-grade. Tonight = HARDEN + close the
one gap + build #4 on-demand + prepare the demo.

## 3. Workstreams

### A. Reliability hardening (the foundation — this is "funcionar direito")
The biggest tomorrow-risk is the live path dropping, not a missing feature. History: the t560:9500
claude proxy died on a reboot before; the cockpit pod silently wedged today.

- **A1. Preflight command** — `scripts/beagle-cpc26-preflight.sh` (beagle repo). One command → GREEN/RED
  with specifics. Checks, in order, via the EXTERNAL path the phone uses (`https://beagle.chiuratto.ai`):
  1. `/healthz` 200
  2. authed `POST /api/mobile/v1/chat` `{space:personal}` → 200 + `grounded:true`
  3. authed deep-think `{deepThink:true}` → 200 + response contains a citation/URL
  4. memory recall sanity: ORC records count > 0 AND Sounio records count > 0 (via memory-pg)
  5. proxy `t560:9500/v1/models` 200 (deep-think brain up)
  Prints a one-line verdict + per-check status. Run it tomorrow morning before leaving.
- **A2. Deep-think fallback** — in `proxyDeepThinkAgentic` (mobile-routes.mjs), on fetch failure to the
  agentic proxy, fall back to the LiteLLM router `claude-opus-4-8` (proven reachable) so a proxy death
  degrades to a still-cited answer instead of a 503. Log which path served.
- **A3. Proxy durability check** — confirm `claude-oauth-proxy.service` (systemd-user, linger) is
  enabled + self-healing; the preflight already surfaces it (check 5).

### B. #1 Intellectual partner — sharpen (mostly verify)
- **B1. Verify recall** across his key results with live probes: ORC (done ✓), O-CSSM/Tapestry,
  Experimento 06, spectral gap, HSN, Sounio epistemic core. Record which are sharp vs thin.
- **B2. Conference-mode nudge** — a lightweight bias toward precision + citation + HIS formulation +
  explicit anti-overclaim, activatable per-request (the companion already does this; make it reliable,
  not a new subsystem). Delivered as a request-level system addendum, not a new mode surface.

### C. #2 Deep-think — harden (mostly verify + A2 fallback)
- **C1.** Ensure it ALWAYS cites in the deep-think path (system addendum: "cite sources or say the
  literature is thin — never a bare claim"). It already behaves this way; make it explicit + verified.
- **C2.** Progress legibility: the `⟜ ToolSearch / WebSearch` stream already shows life during the ~76s.
  Verify it surfaces in the app so it never looks frozen in front of a peer.

### D. #3 Showcase — demo runbook (prep, not build)
- **D1.** A written 2-minute demo script (`docs/cpc26-demo-runbook.md`): the exact sequence — living
  memory with anti-confabulation provenance → live recall of his ORC → deep-think citing a real paper →
  temporal graph → **Sounio**: `souc` epistemic types / `smt.check` / the packaged stats suite as a
  language built FOR uncertainty-aware science, and the Tapestry functor as the formal comp-psych bridge.
- **D2.** Verify each screen/step in the runbook actually works end-to-end before it's "demoable."

### E. #4 Capture → synthesis (on-demand) — the new build, scoped robust
- **E1.** Confirm capture reliability — the drawer "Capturar pensamento" writes to memory (MemoryAtom).
  Verify a capture round-trips and is recallable.
- **E2.** On-demand synthesis flow — a request that pulls the session's/day's captures and synthesizes
  them against his corpus + ORC/HSN + **Sounio state**, using the ALREADY-WORKING recall+deep-think
  pipeline. Server-side: gather recent capture records (by source_type + recency window), feed as
  grounding, ask for a structured synthesis ("what connects, what's new, what contradicts my prior work,
  what to follow up"). Triggered explicitly (button/command), end-of-session — NOT real-time during talks.
- **Out of scope (explicit):** real-time during-talk synthesis (fragile), and any new capture UI.

### S. Sounio integration (woven through B/C/D/E)
- **S1.** Recall: Sounio epistemic core is already sharp (proven). Keep it first-class in B1 verification.
- **S2. Close the gap:** ingest the O-CSSM/Tapestry **internal construction** (the bit-exact Sounio build:
  octonion/sedenion zero-divisor ↔ dissociation functor) into memory via the existing
  `deep_fetch`/assisted-import path, so the companion can discuss internals, not just his claims. This is
  the single highest-value content task. Source = the Sounio repo files + any Tapestry writeup.
- **S3.** Showcase Sounio as the comp-psych-relevant artifact (D1): a language that puts uncertainty in
  the type (`Knowledge[T]`+GUM), decides claims (`smt.check`), and formally maps hypercomplex algebra to
  psychopathology (Tapestry). This is genuinely novel in a comp-psych room.
- **S4.** Synthesis (E2) also grounds against live SounioState (the poller already feeds commits/state).

## 4. Success criteria (verifiable tonight)
1. `beagle-cpc26-preflight.sh` prints GREEN with all 5 checks passing.
2. Deep-think fallback (A2): killing the agentic proxy still yields a cited answer via router.
3. Live probes (B1) confirm sharp recall on ≥5 of his key results, including the Tapestry internals
   AFTER S2 ingest (before S2 it's thin — that's the acceptance test for S2).
4. On-demand synthesis (E2) takes 2–3 captured notes and returns a synthesis that references his actual
   ORC/HSN/Sounio work with at least one real citation or grounded connection.
5. Demo runbook (D1) walked end-to-end with every step working.

## 5. Risks & mitigations
- **Conference network** → the path is public Cloudflare; preflight tests it; deep-think fallback (A2)
  covers proxy death. If cluster itself dies, nothing helps — preflight tells him early.
- **Deep-think latency (~76s)** → acceptable for "let me look that up"; progress stream (C2) keeps it
  from looking dead. Not for mid-sentence use.
- **S2 ingest quality** → if the Tapestry internals don't ingest cleanly tonight, the showcase falls back
  to his *claims* (still honest, the companion self-flags). Non-blocking for the rest.
- **Test pollution** → live probes write test records to memory; clean them after (as done earlier today).

## 6. Out of scope
Real-time during-talk synthesis; new capture UI; any rebuild of #1/#2 (they work); re-deriving Tapestry
(only ingest what exists); #4 beyond on-demand.
