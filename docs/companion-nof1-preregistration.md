# Pre-Registration — Beagle Companion N-of-1 Idiographic Study

**Status:** DRAFT for the researcher to finalize and formally register (OSF / AsPredicted)
**Pre-registration timestamp:** _to be stamped at external registration — data collected before that timestamp is exploratory, not confirmatory_
**Single subject / researcher:** Demetrios Agourakis (self-experiment)
**Related programme:** Hyperbolic Semantic Networks (HSN) → Computational Psychiatry Conference (Yale 2026)

> **Why this document exists.** The companion already captures a multimodal personal time series
> (affect, body, environment) and is gaining a server-side psychometric coupling (per-turn
> text-derived measures). For that series to be *publishable as confirmatory* — not just a
> post-hoc story — the design, hypotheses, instruments, and analysis must be fixed **before** the
> data counts. This is the non-negotiable gate.

---

## 1. Framing (read first)

- **Idiographic, single-subject (N-of-1).** Inference is about *this individual's* within-person
  dynamics over time. It is **hypothesis-generating** and **generalization is scoped to the
  individual** — NOT population/nomothetic inference.
- **Ergodicity caveat (Molenaar).** Between-person structure ≠ within-person structure; we make no
  ergodic assumption. Findings describe one person's process.
- **Power comes from the number of observations**, not subjects: dense sampling (every chat turn +
  event-contingent EMA) over months, not many participants.

## 2. Hypotheses (a priori, directional where stated)

Environmental / physiological → affect & cognition (within-person, lagged):
- **H1 (place).** A change of place (event-contingent trigger) is associated with a shift in
  reported affect (valence/arousal) at the next EMA.
- **H2 (geomagnetic).** Higher geomagnetic disturbance (higher Kp, **more negative Dst**) is
  associated with lower self-reported readiness/affect and/or lower HRV — *researcher's hypothesis,
  treated as a hypothesis, not a fact*. Dst weighted at least as strongly as Kp.
- **H3 (sleep/HRV).** Poorer prior-night sleep and lower morning HRV are associated with lower
  same-day affect.

Enabled by the server-side psychometric coupling (§4.4):
- **H4 (convergent validity).** Text-derived affect (valence/arousal scored server-side from the
  user's messages) tracks the HKStateOfMind ground-truth EMA within-person.
- **H5 (linguistic markers).** Psycholinguistic markers (e.g., first-person singular pronoun rate,
  negative-emotion word rate, cognitive-process words) covary with HRV / sleep / geomagnetic state.

All hypotheses are **within-person, time-lagged**; the lag structure is estimated (§6), not assumed.

## 3. Design

- **Intensive longitudinal / EMA**, two complementary streams:
  1. **Event-contingent EMA** — triggered by *place change* (learned via CLVisit / significant-
     location change). Rich instrument (§4.1).
  2. **Dense passive capture** — *every companion chat turn* is an observation (§4.4).
- **Duration:** minimum _N_ days/weeks to be fixed at registration (target dense coverage over
  ≥ 8–12 weeks); stopping rule pre-specified.
- **Sampling cadence & expected observation count** stated at registration.

## 4. Measures / Instruments

### 4.1 Primary EMA (ground truth) — `HKStateOfMind`
- Valence, arousal (circumplex), descriptor labels, associations, kind (iOS 17+).
- Written to Apple Health (subject owns it) **and** the research store.

### 4.2 Passive physiology (HealthKit)
- HRV (SDNN/RMSSD ms), sleep (stage ratios → quality), resting HR, wrist temperature, respiratory rate.

### 4.3 Environment
- Geomagnetic **Kp** and **Dst** (NOAA SWPC / Kyoto), weather (temp/pressure), and **place**.
- **Place is recorded as raw coordinates + timestamp self-hosted** (research data); the
  companion/LLM receives **only a coarse place label** (e.g., "clínica"/"casa"/"Sounio").

### 4.4 Server-side psychometric coupling (NEW — the addendum)
Computed **server-side**, on the **user-authored text only**, for each chat turn:
- **(a) Text-derived affect** — valence & arousal scored by a fixed, versioned model/prompt on the
  local LiteLLM fleet. Model + prompt + version frozen at registration; changes are logged
  amendments (§9).
- **(b) Psycholinguistic markers** — LIWC-style category rates (pronouns, affect, cognitive
  process, social, temporal). Lexicon + version fixed at registration.
- **(c) (optional) embedded micro-items** — at most one ultra-brief item folded into a new
  conversation, only if it does not harm the companion experience.
- **Provenance:** each derived score is stamped with instrument + version + `prov_actor=system`
  in the memory spine, distinct from user-stated content.

**Hard data-governance rule:** all raw coordinates, transcripts, and psychometric scores are stored
**self-hosted**; **none of the raw coordinates or psychometric scores are ever sent to
Anthropic/Claude.** Only the coarse place label + the companion-facing summary reach the LLM path.
The biography never leaves the self-hosted boundary.

## 5. Validation of derived measures (pre-specified)
- **Concurrent validity:** text-derived affect (4.4a) validated against the HKStateOfMind EMA (4.1)
  using **within-person** agreement (within-person correlation + Bland–Altman limits of agreement),
  computed only on turns with a near-in-time EMA.
- Derived measures are **secondary** until validated; if agreement is poor, they are reported as
  exploratory and not used for confirmatory tests.

## 6. Analysis plan
- **Handle autocorrelation + non-stationarity** — NO naive t-tests/correlations on raw series.
- **Idiographic dynamic models:** lag-1 **VAR** / **graphical VAR** (contemporaneous + temporal
  networks), per-variable detrending, and a pre-specified lag scan for H1–H3.
- **Stationarity checks** (trend, variance) + sensitivity analyses (detrending choices, outlier
  handling) pre-specified.
- **Multiple comparisons:** the confirmatory hypotheses (H1–H5) are the pre-registered set; any
  network edge beyond them is exploratory and labeled as such.
- Power framed by **observation count**, with a simulation-based sensitivity note.

## 7. Measurement vs. intervention separation (critical confound)
The companion **adapts its tone to the user's state** — that adaptation is an **intervention**, not
a measurement. To avoid the series measuring the AI instead of the person:
- **Measure only user-authored text** for 4.4; never score the assistant's output as the subject's
  affect.
- **Log the companion's adaptation** (e.g., the `## Agora`-driven pacing/warmth) as a **covariate**,
  so its effect can be modeled/partialled out.
- Pre-specify the conceptual split: chat turns are **observations of the user**; the companion's
  reply is the **intervention arm**.

## 8. Reactivity & ethics
- **Reactivity:** measurement (and the EMA itself) can change behavior; time trends and an EMA-onset
  marker are modeled.
- **Ethics:** subject = researcher; **IRB-exempt as personal self-experimentation but explicitly
  declared**. Intimate content; right to delete any datum; self-hosted sovereignty (§4.4).
- No clinical claims; H2 (geomagnetic) framed as a felt hypothesis, never a diagnosis.

## 9. Reporting & amendments
- **Reporting standard:** **CENT** (CONSORT extension for N-of-1 trials, 2015) + **SCRIBE**
  (single-case reporting).
- **Amendments log:** any change to instruments (incl. the 4.4 model/prompt/lexicon versions),
  hypotheses, or analysis after registration is recorded here with date + rationale; analyses after
  an amendment are exploratory unless re-registered.

## 10. Open items to fix before registration
- [ ] Exact duration + stopping rule + expected observation count.
- [ ] Freeze the 4.4a scoring model + prompt + version, and the 4.4b lexicon + version.
- [ ] Decide whether 4.4c micro-items are included (default: no, to protect the companion feel).
- [ ] Final variable list + lag set for the VAR/network.
- [ ] Register externally (OSF / AsPredicted) and **stamp the timestamp at the top of this file**.

---

_Builds on the companion `## Agora` consolidation + memory provenance/trust work. The psychometric
coupling rides the existing turn → `ingestPersonalTurn` → memory-pg pipeline; it must not reach the
Anthropic path._
