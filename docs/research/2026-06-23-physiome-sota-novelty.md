---
title: Sovereign Personal Physiome with Geometric Computational-Psychiatry State Modeling — SOTA & Novelty Positioning
date: 2026-06-23
kind: deep-research-brief
generated_by: multi-agent deep-research workflow (physiome-sota-novelty)
run_id: wf_cbe250a7-c68
method: 6 parallel SOTA domain sweeps (sonnet) → 3 adversarial prior-art refutations (sonnet) → synthesis (opus)
verdict: full_prior_art_found=0 — the 5-pillar conjunction is unoccupied; novelty survives when scoped
status: machine-generated; citations marked verified/unverified — RE-CONFIRM DOIs before publication
related: [[project_beagle_physiome]], [[project_hsn_cpp2026]], [[project_beagle_personal_companion]]
---

> Machine-generated SOTA + novelty brief from a multi-agent deep-research run. Two independent
> adversarial searches converged: no retrievable academic/open-source/commercial system integrates
> all five pillars. Treat the Honesty Ledger (§7) as binding — several citations are unverified and
> recent closed commercial entrants (SolarHealth, Attunio) constrain the scoping.

I have everything I need. Writing the brief now.

---

# Sovereign Personal Physiome with Geometric Computational-Psychiatry State Modeling: SOTA and Novelty Positioning

## 1. Executive summary

We position a **sovereign personal physiome**: a self-hosted system that continuously fuses HealthKit-grade consumer wearable physiology (HRV, sleep, activity) with real-time local weather *and* space-weather/geomagnetic indices (minimally Kp and F10.7), feeding these as explicit observations into a **formal personalized computational-psychiatry state model** (Bayesian / state-space) whose psychopathology-relevant state space is represented in a **hyperbolic/geometric manifold**, all inside a biographical AI companion where health and life-story data never leave user-owned infrastructure. Each constituent pillar is individually anticipated by partial prior art — geomagnetic→HRV coupling is well documented (Normative Aging Study; HeartMath/Alabdulgader), hyperbolic embedding of brain networks is established (Brain-HGCN; FHNN), sovereign wearable data layers exist (Open Wearables), and agentic personal-health reasoning is demonstrated (PHIA; Personal Health Agent) — but **the conjunction of all five pillars as a single deployed, sovereign, geometry-grounded system is not found in any retrievable academic, open-source, or commercial prior art as of mid-2026.** Two independent adversarial searches converged on the same verdict: the integration survives, provided the claim is scoped to (i) *architectural* sovereignty rather than the bare Kp↔HRV correlation, (ii) a *formal* state model rather than LLM coaching, and (iii) hyperbolic representation as the explicit state language.

---

## 2. SOTA by domain

### 2.1 Heliobiology — space-weather effects on human physiology and psychiatry
The most reproducible signal is HRV suppression during geomagnetic storms. The best-controlled evidence is the **Normative Aging Study (NAS)** series: a 75th-percentile Kp increase over 15 h was associated with −14.7 ms rMSSD and −8.2 ms SDNN, controlling for PM2.5 and 12+ confounders (Alahmad/Zilli Vieira et al., 2022); the same cohort links solar/geomagnetic activity to endothelial activation (sICAM-1 +10.1%, sVCAM-1 +15.3%; Tracy 2022), reduced WBC (Tracy 2021), and ~19% higher odds of low MMSE (Alahmad 2024). At the population level, **Feigin et al. 2014** (11,453 strokes, 16M person-years) found 19% excess stroke during Kp≥60 storms (52% in <65), and a 2025 meta-analysis (Gaisenok) pooled RR 1.3–1.5 (MI/ACS) and 1.25–1.6 (stroke). **Rezende et al. 2025** (Communications Medicine) is the first Southern-Hemisphere sex-stratified MI study (women 31–60, up to 3× on disturbed days). Psychiatric associations (suicide attempts, depression admissions) are geographically robust but ecological and unphenotyped (Nishimura 2020, Taiwan). Candidate mechanisms — melatonin/pineal suppression, cryptochrome radical-pair magnetoreception (Denton/Nature Comms 2024, quantum Zeno effect), VGCC activation, Schumann-resonance/EEG coupling — are plausible but **no human intervention has blocked a pathway and attenuated outcomes**. After autocorrelation correction, many HRV correlations shrink; **no causality is established for any outcome.**

### 2.2 HRV and autonomic signals as psychiatric biomarkers
HRV is the best-validated non-invasive autonomic biomarker. The **2025 umbrella review (Moretto et al., Translational Psychiatry; 21 reviews, 442 studies, N=34,625)** confirms broadly reduced vmHRV across 19 disorders (SMD −0.26 panic to −0.97 schizophrenia HF-HRV), but no two disorders share an identical profile and I²>50% in ~79% of comparisons — limiting diagnostic specificity. Recording duration is a major moderator (PTSD meta-analysis, Tucker 2026). Dynamical modeling is emerging: **Corponi et al. 2024 (npj)** Bayesian state-space tracking of lnRMSSD shows 95.2% posterior probability of recovery-associated increase in bipolar disorder; UK Biobank ECG clustering (2025) shows subtypes outperform mean HRV. Important caveats: **Polyvagal Theory is largely refuted** (38/39-expert consensus, 2025); LF/HF is invalid as sympathovagal balance; a 2025 LMIC study (N=1,107) found *no* HRV–psychopathology association, exposing WEIRD-sample bias. Active-inference / allostatic accounts (Stephan 2016) are theoretically rich but empirically nascent.

### 2.3 Digital phenotyping / personal sensing
Matured from StudentLife (2014) and GLOBEM (NeurIPS 2022) to large programs. **Liu et al. (Cell 2024/2025, ABCD N=3,538)** achieved ADHD AUROC 0.89 and 16 GWAS loci, showing continuous wearable phenotypes exceed binary labels. **Lipschitz et al. 2025 (Acta Psychiatrica Scandinavica, N=54 BD)** is the best real-world episodic mood model (AUC 0.86 depression / 0.85 hypomania). All of Us shows activity declines precede MDD by 4–5 months. The dominant shift is toward N-of-1 personalized models and behavioral foundation models (**Erturk et al. ICML 2025, 2.5B hours, 162K subjects**). A 2026 meta-analysis reports pooled AUC 0.96 but I²>96% with 69% of studies reusing one dataset — i.e., **external validation is nearly absent (2% of studies)**, HealthKit-grade multimodal fusion is underexplored, and no passive-sensing-triggered JITAI has been validated in a large RCT.

### 2.4 Sovereign / on-device personal health AI and the exocortex paradigm
On-device inference has crossed a practical threshold (MobileFineTuner, MobiSys 2026; HealthSLM-Bench, 2025; Menta, 2024). Agentic personal-health reasoning is demonstrated but **cloud-bound**: **PHIA (Nature Communications 2025)** reaches 84% factual / 83% open-ended accuracy on 4,000+ questions; PhysioLLM (CHI 2024) beat baselines in a 24-user RCT. Exocortex memory is maturing (Second Me, MemMachine 93.0% LongMemEvalS, MemOS, EpisTwin PKG). Privacy-preserving training is proven cross-institution (PHT/Vantage6 12 hospitals; FedMentor DP-LoRA). Critical evaluations (HealthBench; IatroBench — 76.6% of AI clinical errors are omissions) reveal a *safety paradox* for sovereign deployment. **No published system combines local inference + local personalization + longitudinal biographical memory + true data ownership + clinically validated health accuracy.**

### 2.5 Multimodal time-series fusion of physiology + environmental exposome + space weather
Each stream is individually at foundation-model scale (SleepFM, Nature Medicine 2026, 130 diseases C-index ≥0.75; behavioral wearable FMs). Physiology + air-quality fusion exists at pilot/dataset stage (**DigitalExposome**, 40 participants/40-min walks; Zounemat-Kermani 2025 AAE+LSTM). Space-weather signals remain **purely epidemiological or small-lab** (NAS Kp→HRV; Alabdulgader 2018 HRV vs solar wind/Kp/Schumann; Didkovsky 2019, 263 US cities). The central finding: **no published ML system jointly ingests real-time Kp/F10.7/solar wind alongside continuous wearable physiology and local exposome for individual-level prediction.** No personalized forward-prediction model, no temporal-alignment methodology for the three-resolution problem, no causal-inference framework, no consumer wearable with a health-calibrated geomagnetic sensor.

### 2.6 Geometric / hyperbolic representation learning for psychiatry
Brain graphs are scale-free and tree-like, embedding with far lower distortion in negative curvature. **Brain-HGCN (ICASSP 2026)** reaches ADHD-200 83.6% acc / 90.7% AUC; **FHNN on MEG (Alzheimer's & Dementia 2025)** shows hyperbolic radii outperform graph-theoretic aging biomarkers; hyperbolic embeddings forecast seizures (Chen 2024) and detect AD-disrupted regions (Yin 2024). The dynamical-systems view (**Scheffer et al., JAMA Psychiatry 2024**; Lemos et al., Neuropsychopharmacology 2025) frames psychopathology as geometry distortion of neurobehavioral manifolds; GeoDynamics (NeurIPS 2025) tracks SPD-manifold trajectories. Multimodal hyperbolic fusion is just beginning (HCFSLN anxiety 88%; EEG-MoCE, ICML 2026). **No published work maps raw wearable/environmental streams into a hyperbolic psychiatric state space, embeds symptom networks hyperbolically, or tracks individual longitudinal trajectories through such a space** — the explicit central gap of this field.

---

## 3. The white space

Synthesizing the six sweeps and both adversarial searches, the unoccupied intersection is precise:

> **A continuously-updated, individual-level psychiatric state model whose observation vector simultaneously contains (i) HealthKit-grade physiology, (ii) local weather, and (iii) space-weather indices; whose latent state lives in a hyperbolic/geometric manifold; and whose entire inference + biographical store runs on user-owned infrastructure.**

The gap is the *conjunction* of five separately-occupied territories:

1. **Space-weather → individual psychiatric-state inference is an open loop.** Heliobiology proves group-level Kp↔HRV and Kp↔admissions associations; *no system closes the loop from Kp/F10.7 to a per-individual computational-psychiatry state estimate* (heliobiology white-space #1–4; fusion white-space #1, #8).
2. **Three-layer fusion (physiology + exposome + space weather) has never been modeled together** — every system uses at most two layers (fusion white-space #1).
3. **Geometric psychiatry has no physiological/environmental instantiation** — hyperbolic methods operate on neuroimaging, never on wearable/environmental streams or longitudinal individual trajectories (hyperbolic white-space #1, #3, #5).
4. **Sovereignty + biographical companion + formal psychiatric model have never co-resided on user infrastructure** — PHIA/Oura are cloud-bound; Open Wearables is a data layer with no model; Second Me has no health grounding (sovereign-health white-space #1–2).
5. **A formal psychiatric state model (vs. LLM coaching / heuristic color score) fed by this multimodal stream is absent** from every closest competitor.

---

## 4. Defensible novelty claim (scoped)

The maximally defensible claim, scoped exactly as both refutations require:

> *A **self-hosted** system — where all biographical, health, and psychiatric-state data persist **exclusively on user-owned infrastructure** (bare-metal / private cluster / user-controlled edge), with no raw data or embeddings transmitted to any third-party cloud, even encrypted — that continuously fuses **HealthKit-grade consumer-wearable physiology** (HRV, sleep stages, activity) with **real-time local weather** and **space-weather indices (minimally Kp and F10.7; optionally Dst, Bz/Bt, solar wind)** as **explicit inputs to a formal personalized computational-psychiatry state model** (Bayesian / state-space mapping multimodal observations to latent psychiatric variables), where the **psychopathology-relevant state space is embedded in a hyperbolic manifold** (Poincaré ball or Lorentz model), inside a **biographical AI companion** whose retrieval is continuously updated from both a life-narrative corpus and real-time physiome telemetry.*

**Pillar-by-pillar defensibility (do not overclaim):**

| Sub-claim | Status | Required scoping |
|---|---|---|
| Geomagnetic indices correlate with individual HRV | **NOT novel** — extensive prior art (NAS, Alabdulgader) | Do not claim the correlation; claim the *architectural integration* |
| Sovereignty | Novel only as **architectural** (compute-on-user-hardware), not policy | Must exclude Bionico (Swiss server), MentalHealthAI (federated weights leave device) |
| Space-weather → individual psychiatric *state* inference | **Novel** (open loop in literature) | Indices must enter the *state model*, not merely a dashboard (SolarHealth displays Kp = prior art for display only) |
| Formal computational-psychiatry state model fed by this stream | **Novel** (weakest pillar in competitors) | Must be Bayesian/SSM, not LLM coaching or color score |
| Hyperbolic psychopathology state representation in a personal companion | **Novel and intact** (strongest pillar) | Specify manifold + psychopathology taxonomy being embedded |
| Biographical + health + environmental memory, sovereign | **Novel at the sovereignty boundary** | Both biography AND physiome AND state model on user hardware simultaneously |

---

## 5. Closest prior art

| System | Pillars covered | Critical lacks |
|---|---|---|
| **SolarHealth** (app, 2026) | Space weather (Kp, solar wind, Bz/Bt) + smartwatch HRV + on-device storage claim | No full HealthKit (sleep/respiratory), no weather-vs-air-quality fusion, **no psychiatric state model**, no hyperbolic representation, no exocortex; "AI algorithm" undescribed; not self-hostable backend. *Closest single system; integrates Kp display only, not into a state model.* |
| **HeartMath / GCI + Alabdulgader 2018** (PMC5805718) | HRV + geomagnetic (Kp/Ap/F10.7/solar wind/Schumann) scientific coupling | Research collective, not personal system; data uploaded to HeartMath cloud (**not sovereign**); no state model, no hyperbolic, no companion, no HealthKit. *Strongest scientific precedent for the coupling pillar; partly non-public — residual invalidation risk.* |
| **Personal Health Agent** (arXiv 2508.20148, 2025) | Full wearable pipeline + AI state-reasoning + coaching companion | **No space weather**, no weather fusion, no hyperbolic representation, **no sovereignty** (presumed cloud). *Most architecturally complete health-AI agent.* |
| **PHIA** (Nature Communications 2025) | Agentic reasoning over wearable physiology (84%/83%) | Cloud-only; no space weather; no psychiatric state model; no hyperbolic; no sovereignty. *Performance reference / the gap to close on-device.* |
| **Open Wearables** (MIT, 2025–26) | **True sovereignty** (self-hosted, MCP-to-LLM), HRV/sleep/recovery | Data API only — **no companion, no psychiatric model, no space weather, no hyperbolic.** *Provides the sovereign data layer; not an integrated system.* |
| **Beiwe / MindLamp** (Harvard) | Rigorous deployed digital phenotyping / EMA | Institutional servers (**not sovereign**); no space weather; no hyperbolic; no biographical companion. |
| **Oura Ring + Oura Advisor** (2025) | Full physiology + biographical AI companion | Cloud-processed (**not sovereign**); no space weather; LLM coaching, **not a formal psychiatric model**; no hyperbolic. |
| **Synheart Emotion** (arXiv 2511.06231, 2025) | On-device HRV emotion recognition (sovereign + wearable) | Zero geomagnetic/space weather; valence/arousal only, **not a psychiatric state model**; no biographical memory; no hyperbolic. |
| **Bionico** (2025–26) | Wearable + AI coach, "sovereign" branding | Swiss *server-side* (**not user-infrastructure sovereign**); no space weather; no psychiatric model; no hyperbolic; coach grounded in biomarkers, not biography. |
| **MentalHealthAI** (Rashidian, AMIA 2024) | On-device psychiatric mood prediction, federated | No companion; no biography; no space weather; no hyperbolic; no HealthKit; model weights leave device (**not fully sovereign**). |

**Strongest hypothetical attacker:** a *stack* of Open Wearables (sovereignty) + Personal Health Agent / Bionico (physiome + companion) + MentalHealthAI (psychiatric signal) + custom space-weather ingest. No one has assembled this stack as a deployed, integrated, sovereign system — and none of the parts carries hyperbolic state representation.

---

## 6. Recommended framing & contribution

**Venue positioning.** Frame for a **Computational Psychiatry / heliobiology** audience (e.g., Computational Psychiatry Conference; *Biological Psychiatry: CNNI*; *International Journal of Biometeorology*; *npj Mental Health Research*) as a **methods + systems contribution that closes the open loop** from space-weather exposure to an *individual-level* psychiatric state estimate — the loop the heliobiology field explicitly calls for (Belenko/Cureus 2025 and IJB 2026 both demand prospective designs with simultaneous biomarker + geomagnetic monitoring).

**Recommended contribution structure (in priority order of novelty strength):**
1. **Lead with the hyperbolic psychiatric state representation** — the strongest, fully-intact pillar; first instantiation mapping wearable + environmental + space-weather observations into a hyperbolic psychopathology manifold, enabling hierarchical nosology encoding and longitudinal individual trajectory tracking (directly fills hyperbolic white-space #1, #3, #5).
2. **The closed space-weather → individual-state inference loop** as the second pillar — a per-individual Bayesian/SSM update with Kp/F10.7 as explicit covariates (fills heliobiology #1–4, fusion #1, #8).
3. **Architectural sovereignty** as the deployment thesis — sovereign biography + physiome + state model co-resident on user hardware (fills sovereign-health #1, #2).
4. Position the three-layer fusion (physiology + weather + space weather) as the enabling data substrate (fusion #1).
5. Be explicit that this is a **systems + prospective-design contribution**, not a causal claim — frame heliobiological inputs as *candidate covariates under prospective test*, embracing the standardized prospective N-of-1 design the field demands.

**Strongest citation anchors (verified):**
- **Alahmad/Zilli Vieira et al. 2022**, *Sci. Total Environ.* (PMC9233046) — best-controlled individual-level Kp→HRV effect (−14.7 ms rMSSD).
- **Scheffer et al. 2024**, *JAMA Psychiatry* 81(6):618–623 — psychopathology as attractor states / critical transitions (the dynamical-systems frame).
- **Corponi et al. 2024**, *npj Mental Health Research* — Bayesian state-space HRV trajectory modeling (the methodological template; code open-sourced).
- **Brain-HGCN (Zhang et al. 2025/ICASSP 2026)** + **FHNN (Ramirez-Toscano et al. 2025, *Alzheimer's & Dementia*)** — hyperbolic brain-network SOTA.
- **PHIA (Merrill et al., Nature Communications 2025)** — the cloud performance ceiling the sovereign system targets.
- **Moretto et al. 2025**, *Translational Psychiatry* — the definitive HRV-psychiatry effect-size synthesis (frames the biomarker's promise and its specificity limits).

---

## 7. Honesty ledger

**Works the source agents could NOT independently verify (marked `verified:false` in the sweeps) — cite with care, confirm before publication:**
- Thayer & Lane (2000), *J. Affective Disorders* — Neurovisceral Integration Model (foundational but unverified in sweep).
- Porges (1995/2007) — Polyvagal Theory (and note: **major tenets refuted** by 38/39-expert consensus, 2025; cite only as historical framing, not mechanism).
- Bassett et al. (2016) GRAPH guidelines; Schutte/Brosschot & Thayer (2015) transdiagnostic; Kemp & Quintana (2013); Chalmers et al. (2014); Critchley & Garfinkel (2017); Stephan et al. (2016). All `verified:false` — verify DOIs before citation.

**Open risks to the novelty:**
1. **Non-public prior art (highest residual risk).** HeartMath's internal research pipeline is partially non-public; a private HRV+geomagnetic fusion product cannot be fully excluded from public search. State this limitation explicitly in any patent/publication framing.
2. **Very recent commercial entrants with no technical disclosure** — Attunio Health (announced June 2026, precision psychiatry, closed-loop) and SolarHealth (active development). No public technical detail; cannot be fully adjudicated. SolarHealth in particular already does real-time Kp + HRV with on-device storage, so the *display* of space weather alongside HRV is prior art — novelty must rest on integration into the state model.
3. **No causal claim is defensible.** Heliobiology establishes *associations only*; after autocorrelation correction many HRV–geomagnetic correlations shrink. The state model must treat space-weather inputs as candidate covariates under prospective test, not established causes.
4. **Generalizability caveat.** The 2025 LMIC null finding (N=1,107) and WEIRD-sample bias mean the HRV→psychopathology mapping may not transfer; an N-of-1 personalized-baseline design partly mitigates but does not eliminate this.
5. **Sovereignty is a contested term.** "Self-hosted"/"sovereign" is claimed by server-side (Bionico) and federated (MentalHealthAI) systems; the claim is only defensible if scoped to *compute-and-storage-on-user-hardware with zero raw-data/embedding egress*.
6. **Citation-detail uncertainty in the sweeps.** Some arXiv IDs, DOIs, and authorship attributions in the source material (e.g., several 2026 preprints, "Authors anonymous" entries, the Zhang et al. JAD DOI with placeholder digits) should be re-confirmed against the live record before submission.