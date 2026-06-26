# Dialogue Tapestry — Sovereign Cognitive Telemetry (Functor F + live/historical consumption) — Design

**Date:** 2026-06-23
**Author:** Demetrios Chiuratto Agourakis (with Claude)
**Status:** design — pending review
**Related:** deep-research brief `docs/research/2026-06-23-ocssm-exocortex-novelty-deep.md`; theory docs `sounio/docs/research/ocssm_*`; [[project_hsn_cpp2026]], [[project_beagle_physiome]], [[project_beagle_personal_companion]]

## Motivation — utility first, paper as consequence

The deep-research verdict is that the O-CSSM/Tapestry novelty is real but **"asserted, not constructed"**:
it converts to a contribution exactly when the **functor F is written down** and the **FP64/J_n contradiction
is resolved**. Rather than build F as a paper exercise, we build it as a **real instrument over Demetrios'
own dialogue**: a sovereign, bit-exact telemetry of *coherence*, *speaker-directional asymmetry*, and
*dissociative incomposability* computed over his actual conversations, consumable **live by the companion**
and **historically as a dashboard** (and correlated with the Physiome body/environment signals). The paper
figures fall out of an instrument that is useful in his life — which is the whole exocortex thesis.

This simultaneously discharges three deep-research action items: (1) **instantiate F** (the #1 attack
surface); (2) **resolve FP64/J_n** by computing the zero-divisor signal in Sounio's bit-exact Cayley–Dickson
arithmetic; (5) make the **sovereign exocortex the n-of-1 instrument** on real data.

## What already exists (build on, don't duplicate)

Sounio stdlib already provides the algebra and a *single-state* clinical mapping:
- `math::sedenion` — `Sedenion, sed, sed_zero, sed_basis, sed_mul, sed_add, sed_sub` (bit-exact CD arithmetic).
- `stdlib/gpu/sedenion_kernels.sio` — `sed_associator(a,b,c)`, `sed_l1_norm`, `sed_triple_l1` (Fano-orbit associator mass).
- `stdlib/cybernetic/psychiatry.sio` — `patient_as_sedenion(ClinicalState)->[f64;16]`, `zero_divisor_proximity(state)->f64`, the "168 theorem" (‖[eᵢ,eⱼ,eₖ]‖ ∈ {0,2}, 168 nonzero = |PSL(2,7)|; 0 = on the zero-divisor variety = dissociation).
- `stdlib/nn/octonion.sio`, `stdlib/nn/g2_equivariant.sio` — octonion type + G2 machinery.

**The gap** (= the program's novelty, currently asserted): all of the above act on a *single* state. There is
no **functor from a dyadic conversational TRAJECTORY** to an 𝕊-valued *sequence* carrying the three
correspondences as a time series, and nothing runs it over the real exocortex dialogue corpus.

## Goals

- **F instantiated** as a Sounio module: `trajectory of annotated dyadic turns → 𝕊-valued sequence`, computing
  per-turn/per-exchange telemetry for all **three correspondences**, bit-exact.
- **Real utility**: the companion can say true things about Demetrios' own dialogue ("coherence dropped here",
  "this looks like a rupture/dissociation pattern"), and there is a historical view correlated with Physiome.
- **One source, two consumers** (the chosen design): a single telemetry stream in the exocortex feeds (a) live
  companion grounding and (b) the historical dashboard + Physiome correlation.
- **FP64/J_n resolved**: the load-bearing zero-divisor signal is computed in Sounio exact arithmetic; any
  continuous proximity is clearly separated from the exact `ab=0` regime.
- **Falsifiable**: each correspondence is independently testable on the corpus.

## Non-Goals

- Human-annotated psychotherapy corpora (v1 uses Demetrios' own agent dialogues + auto-derived affect/rupture
  labels; human annotation is later).
- Training a model. F is a *deterministic constructive map*, not a learned network.
- The full publication (this builds the instrument + the F artifact the paper requires; writing is downstream).

## The functor F (operational definitions)

**Source category** `Dyad`: objects are annotated dyadic conversational trajectories — a finite sequence of
turns `(speaker ∈ {self, other}, embedding v ∈ ℝ^d, affect_uncertainty u ∈ ℝ^8)`; morphisms are
order-preserving trajectory prefixes/refinements. **Target**: 𝕊-valued dynamical sequences (one sedenion per
turn) + the derived telemetry. `F` lifts each turn and carries the three correspondences:

1. **(i) Associator coherence** — lift each turn to a pure-imaginary octonion `o_t` (project the bge-m3
   embedding `v_t` to the 7 imaginary octonion coords via a fixed seeded projection, normalize). Per
   consecutive triple, `coherence_t = ‖[o_{t-1}, o_t, o_{t+1}]‖` (the octonion associator; reuse the
   `sed_associator` machinery on the octonion sub-block). High associator norm = strong context-dependent
   re-parenthesization of meaning = a coherence *event*; the time series IS the telemetry. (Magnitude, not
   presence/absence — the defensibly-novel pillar.)

2. **(ii) L/R speaker-directional asymmetry** — *the operational definition the brief flagged as missing.*
   For an adjacent exchange `(o_a by speaker X, o_b by speaker Y)`, the running dialogue product orders factors
   by who spoke: the speaker's turn left-multiplies the accumulated state. The directional signal is the
   **commutator norm** `lr_t = ‖o_a·o_b − o_b·o_a‖`, *attributed by speaker order*; because 𝕆 is
   non-commutative the swap is observable, and which **Fano-line subalgebra** the ordering activates
   (`label(a,b)=e_{(a+b) mod 7 + 1}`, the existing encoding) is recorded as the mode. Defended **only coupled**
   to (i)+(iii) per the refutations.

3. **(iii) Zero-divisor proximity (dissociation)** — build a per-turn sedenion `s_t = lift(value=v_t,
   uncertainty=u_t)` exactly as `patient_as_sedenion` does (octonion half = normalized content, sedenion half =
   normalized affect-uncertainty), and compute `zd_t = zero_divisor_proximity(s_t)` **in exact arithmetic**.
   `zd_t → 0` = on the zero-divisor variety = co-present states that algebraically annihilate = dissociative /
   rupture candidate. **Rupture event** := `zd_t` below threshold; classified up to **G2-orbit** via the
   existing g2 machinery (a coarse orbit invariant in v1).

**Output of F**: per turn `t`, a telemetry record `{idx, speaker, coherence, lr_asymmetry, fano_mode,
zd_proximity, rupture, g2_class}`. The whole sequence is the 𝕊-valued dynamical trajectory.

## Architecture (3 phases)

### Phase A — F in Sounio (`stdlib/cybernetic/dialogue_tapestry.sio`)
Pure, bit-exact, testable in the Sounio test suite. Reuses `math::sedenion`, `sed_associator`, `octonion`,
`g2_equivariant`, and the `psychiatry.sio` lift/proximity. Reads a trajectory (turns as embedding+uncertainty
arrays) and emits the telemetry sequence. **Branch from `integration/sounio-dev-ready-base` (never main).**

### Phase B — telemetry pipeline (beagle, `apps/cognitive-telemetry/`)
Pulls Demetrios' dyadic conversations from the exocortex export (`omni_conversations`: turns with
role=user/assistant = the dyad), gets per-turn embeddings from the sovereign embedder
(`beagle-sovereign-embeddings`, bge-m3) + a per-turn affect-uncertainty vector (v1: a cheap deterministic
proxy from token-level features; later a real affect head), runs F via the `souc` binary over a generated
input, and **writes the telemetry back to the exocortex** as a first-class stream (tagged
`cognitive-telemetry`, privacy `sensitive`, sovereign — never leaves the cluster). Idempotent per session.

### Phase C — two consumers
- **Live**: companion grounding (cockpit Personal space) injects a compact recent-telemetry digest
  (coherence trend, last rupture/dissociation episodes) alongside the biography + physiome digests — same
  best-effort pattern as `fetchPhysiomeDigest`.
- **Historical**: a report + **extend the Physiome correlation engine** (`apps/physiome/src/correlate.mjs`)
  to ingest the cognitive telemetry as additional series, so correlations span
  `coherence × dissociation × HRV × sleep × Kp × mood` — the full body↔mind↔environment instrument.

## Data flow

```
exocortex omni_conversations (self↔assistant turns)
  └─ Phase B: per-turn bge-m3 embedding + affect-uncertainty proxy
       └─ generate F input → souc run dialogue_tapestry.sio  (Phase A, bit-exact)
            └─ telemetry sequence {coherence, lr, zd, rupture, g2}
                 ├─ write back → exocortex stream `cognitive-telemetry` (sovereign)
                 ├─ live: companion grounding digest (cockpit Personal)
                 └─ historical: dashboard + correlate.mjs (× Physiome HRV/sleep/Kp/mood)
```

## Falsifiability (on Demetrios' own corpus)

- (i) coherence: associator-norm should track human-annotated re-parenthesization / topic-rupture points
  better than chance; failure bounds the correspondence.
- (ii) L/R: the commutator-norm asymmetry should correlate with speaker-directional influence annotations;
  if not, (ii) is decoration (a result, not a failure, per the theory).
- (iii) zd: low `zd_proximity` episodes should co-occur with self-annotated dissociative/incoherent moments
  (and, via Phase C, with physiological markers). The exact-vs-FP comparison is the negative control.

## J_n / FP64 resolution

The recorded `zd_proximity` (the load-bearing signal) is computed in **Sounio exact CD arithmetic**. If a fast
FP path is ever added for live UI latency, it is labeled `zd_proximity_approx` and is **never** the published
number. This is the explicit separation the brief requires (exact `ab=0` regime vs continuous proximity).

## Testing

- **Phase A (.sio)**: known-answer tests — associator of a known non-associative octonion triple equals the
  168-theorem value; commutator asymmetry is zero for equal turns and grows with divergence; a constructed
  zero-divisor sedenion yields `zd_proximity≈0` and a generic one yields `>0`; F over a 3-turn fixture returns
  the expected telemetry shape. Run via `bash scripts/run_sio_test_suite.sh dialogue_tapestry`.
- **Phase B (Node)**: pipeline unit tests (export→F-input generation; telemetry write contract) with a stub
  `souc`; idempotency.
- **Phase C (Node)**: correlate.mjs extension tests (cognitive series flow into the correlation matrix);
  grounding digest formatting.

## Risks / honesty

- The **embedding→octonion/sedenion lift is a modeling choice, not the theory** — the seeded projection must be
  fixed + documented; results are reported relative to it. State this in any paper.
- v1 affect-uncertainty is a proxy; weak labels limit (iii)'s strength until real affect annotation exists.
- (ii) L/R remains the weakest pillar; report coupled to (i)+(iii), never standalone.
- G2-orbit classification is coarse in v1; the full isometry/Stiefel refinement (Reggiani 2024) is a v2 stretch.
- Authority boundary: Phase A is **Sounio** (language/stdlib) on `integration/sounio-dev-ready-base`; Phase B/C
  are **Beagle** (platform). Do not blur.
