# Scientific Documentation Template for BEAGLE

**Purpose**: Ensure all BEAGLE documentation meets Q1 journal standards for clarity, rigor, and transparency about what is validated vs. speculative.

**Version**: 1.0
**Last Updated**: November 24, 2025

---

## Template Structure

Every major BEAGLE component documentation should follow this structure:

---

## 1. Introduction

**Purpose**: Establish context and motivation without overstating claims.

**What to include**:
- Problem statement (what gap does this component address?)
- Scope limitation (what does it NOT do?)
- Design philosophy (why this approach?)

**What NOT to include**:
- Performance claims without data
- Capability claims beyond current implementation
- Speculative future capabilities as if implemented

**Example**:

```markdown
### Introduction

#### Problem Statement
Traditional research assistant systems lack integration with physiological data streams
that may correlate with cognitive state. This module explores whether heart rate
variability (HRV) measurements from consumer wearables can inform agent prompt
selection and parameter tuning.

#### Scope
This component is an **experimental interface** for HRV data collection and analysis.
It does NOT provide clinical-grade measurements or medical-grade analysis.

#### Design Philosophy
We adopt a conservative approach: HRV data is treated as one optional input signal,
not as a primary decision driver. All recommendations remain subject to explicit
human validation.
```

---

## 2. State of the Art (SOTA)

**Purpose**: Ground the work in existing research and explicitly state what's novel.

**What to include**:
- Relevant published research in domain
- What prior work exists and what it achieved
- Gap this component addresses
- Limitations of existing approaches

**What NOT to include**:
- Dismissing related work without evidence
- Overclaiming novelty
- Ignoring contradictory research

**Example**:

```markdown
### State of the Art

#### HRV in Cognitive Science
Heart rate variability has been studied as a correlate of autonomic nervous system
activity and psychological state. Key prior work:

- **Thayer & Lane (2000)**: Foundational neurovisceral integration model. Found HRV
  correlations with emotional regulation and attention.
  - Limitations: Correlational, not causal. High inter-individual variability.

- **Laborde et al. (2018)**: Meta-analysis of 31 studies on HRV and cognitive
  performance. Found weak to moderate correlations (r = 0.15-0.45).
  - Key finding: "Relationship between HRV and cognitive performance varies
    substantially by task type and individual differences."

- **Apple HealthKit Technical Documentation**: HRV estimation from optical sensors.
  - Accuracy: ±5-10% on healthy individuals (not ECG-grade).
  - Limitations: Requires stable contact, affected by motion artifacts.

#### Gap
No prior work integrates HRV with multi-agent LLM systems for adaptive prompt selection.
However, the weak empirical foundation for HRV-cognition links suggests caution.

#### Our Approach
Conservative integration: HRV is one optional input signal, never a binding decision
criterion. All decisions remain explicable and auditable.
```

---

## 3. Methods

**Purpose**: Make implementation completely reproducible and transparent about design choices.

**What to include**:
- Detailed algorithm/approach descriptions
- Data flow diagrams (even text-based)
- Configuration parameters and defaults
- Dependency specifications (versions, APIs, etc.)
- Assumptions and limitations

**What NOT to include**:
- Vague descriptions ("uses AI to decide")
- Hand-waving about why something should work
- Hidden assumptions presented as facts

**Example**:

```markdown
### Methods

#### HRV Data Collection
HRV measurements are obtained via Apple HealthKit API on iOS.

**Data Source**: `HKQuantityTypeIdentifierHeartRateVariabilitySDNN`
- **Unit**: Milliseconds (standard deviation of normal-to-normal intervals)
- **Sampling**: Collected during background operation via HKObserverQuery
- **Accuracy Specification**: Apple Watch Series 4+
  - Optical sensor with ±5-10% margin of error vs. ECG
  - Requires ~5-10 minutes of stable heart rate measurement
- **Refresh Rate**: Updated approximately every 24 hours per Apple documentation

**Data Transmission**: HRV values sent to core_server endpoint via HTTPS with
authentication. No raw data stored locally; only summary statistics retained.

#### HRV-to-Strategy Mapping (Exploratory)
HRV values in milliseconds are mapped to three categorical zones:

| Zone | HRV Range (ms) | Interpretation | Suggested Action |
|------|---|---|---|
| Low | < 20 | High sympathetic tone (may indicate stress/load) | Optional: use more conservative prompts, shorter outputs |
| Normal | 20-50 | Balanced autonomic state | No adjustment |
| High | > 50 | High parasympathetic tone (may indicate relaxation) | No adjustment needed |

**Important Caveat**: These zone boundaries are **ARBITRARY AND UNVALIDATED**.
They are based on general HRV literature thresholds, not BEAGLE-specific studies.

#### Strategy Selection Algorithm
```
function select_strategy(request, current_hrv_zone, hrv_weight=0.1):
    base_strategy = router.choose_strategy(request)  // Normal routing

    if hrv_zone == "Low" and request.requires_precision:
        // Apply light modifier: reduce output length, increase validation
        return apply_modifier(base_strategy, "conservative", weight=0.1)
    else:
        return base_strategy
```

**Parameters**:
- `hrv_weight = 0.1`: HRV influence as fraction of total decision (10%). Routing
  decisions are 90% based on request properties, 10% on HRV zone.
- Modifiable via `BEAGLE_HRV_WEIGHT` environment variable.
- Default conservative to prevent HRV overinfluence on critical decisions.

#### Limitations by Design
1. **Single wearable**: Apple Watch data only. No ECG, chest strap, or medical-grade
   devices.
2. **No individual baseline**: No per-user calibration. Zone thresholds are
   population-level.
3. **High variability**: Inter-individual HRV variability is well-documented.
   Same HRV value may indicate different states across individuals.
4. **Correlation ≠ Causation**: Even if HRV correlates with cognitive state (unproven
   for BEAGLE use case), adjusting prompts based on HRV may not improve outcomes.
```

---

## 4. Results

**Purpose**: Report what was actually tested and what the data shows.

**What to include**:
- Benchmark/test results with error bars, sample sizes, statistical tests
- Examples of system behavior with real data
- Failure cases and edge cases
- Performance metrics if applicable

**What NOT to include**:
- Hypothetical performance ("should be ~20% faster")
- Unquantified claims ("works well")
- Absent validation presented as achieved

**Example**:

```markdown
### Results

#### Status: NOT YET VALIDATED

As of November 2025, HRV-based strategy selection has NOT been empirically validated.
This section describes planned validation rather than completed results.

#### Planned Validation Approach
1. **Baseline comparison** (10 users, 2 weeks each):
   - Collect 50+ interactions per user with/without HRV-based strategy selection
   - Measure: Output quality (external expert rating), user satisfaction, consistency
   - Hypothesis: No significant difference expected initially (conservative threshold)

2. **Inter-individual variability analysis**:
   - Classify users by baseline HRV ranges
   - Check if HRV zone thresholds correlate with strategy effectiveness
   - Expected finding: High variance; simple thresholds may not transfer

3. **Correlation study** (optional, external collaboration):
   - Measure user cognitive state via standard tools (PANAS, NASA-TLX)
   - Correlate with HRV measurements and BEAGLE output quality
   - Current expectation: Weak correlations (r < 0.4 based on literature)

#### Current Implementation Status
- ✓ HRV data collection interface working
- ✓ HRV zone mapping implemented
- ✓ Strategy modifier functional (no-op by default)
- ✗ Validation data: None
- ✗ Performance impact quantified: No
- ✗ User study completed: No

#### Preliminary Observations (Anecdotal)
From internal testing (N=2 users, ~10 interactions):
- HRV data collection works reliably
- Zone mapping transitions smoothly
- No crashes or stability issues
- User experience impact: Imperceptible (modifier weights are low)

**Caveat**: N=2 is far below statistical significance. These observations do NOT
support claims about effectiveness.
```

---

## 5. Validation

**Purpose**: Describe exactly what evidence would be required to claim something works.

**What to include**:
- Validation methodology and success criteria
- Required sample sizes and statistical tests
- External validation sources (published benchmarks, expert review, etc.)
- Current validation status

**What NOT to include**:
- Vague "we tested it" statements
- Presenting future work as completed
- Impossible standards

**Example**:

```markdown
### Validation Requirements

#### Criterion 1: HRV Collection Reliability
**Goal**: Verify HRV data collection is consistent with Apple HealthKit specification.

**Validation Method**:
- Sync against Apple Health app readings (Apple Watch Series 5+)
- Test across 10 devices and 100+ hours of monitoring
- Success Criteria: ≥95% data consistency with Apple Health (allowing ±2% drift)

**Status**: Not started
**Timeline**: 2-3 weeks of device testing

#### Criterion 2: Zone Threshold Validity
**Goal**: Verify HRV zone thresholds (Low/Normal/High) correlate with any observable
cognitive state measure.

**Validation Method**:
- User study: 20 participants, 4 weeks, 3 interactions/week
- Collect: HRV zones during interaction, user self-report of fatigue/focus (Likert 1-5),
  expert rating of output quality (1-10)
- Statistical Test: Spearman correlation between HRV zone and outcome measures
- Success Criteria: Statistically significant correlation (p < 0.05) with r > 0.3

**Status**: Experimental protocol drafted, IRB review pending
**Timeline**: 3-4 months (pending approvals)

#### Criterion 3: Strategy Selection Impact
**Goal**: Verify that HRV-based strategy selection improves measurable outcomes
(compared to HRV-agnostic baseline).

**Validation Method**:
- A/B test with counterbalanced design: 30 users, 2 weeks each
- Randomize: 50% with HRV-aware routing, 50% with baseline routing
- Measure: Output quality (expert + user rating), consistency, latency
- Statistical Test: Two-sample t-tests (Bonferroni corrected for multiple comparisons)
- Success Criteria: Statistically significant improvement (p < 0.05) with effect size d > 0.4

**Status**: Awaiting completion of Criteria 1-2
**Timeline**: 4-5 months after Criterion 2

#### Current Evidence Status
- **Peer-reviewed literature support**: WEAK
  - Cited studies show only weak HRV-cognition correlations (Laborde et al. 2018)
  - No prior work validates HRV for LLM prompt selection

- **BEAGLE-specific validation**: NONE
  - No user studies completed
  - No benchmark comparisons
  - No statistical evidence of effectiveness

#### Conclusion
**Current validation status**: PRE-VALIDATION (Concept stage)

This component is suitable for:
- ✓ Internal research and experimentation
- ✓ Demonstration of architectural integration
- ✓ Foundation for proper user studies

This component is NOT suitable for:
- ✗ Production deployment
- ✗ Health/medical applications
- ✗ Claims of improved outcomes in published materials
```

---

## 6. Limitations

**Purpose**: Be explicit about what can go wrong and when this component shouldn't be used.

**What to include**:
- Assumptions that might not hold
- Known failure modes
- Populations/conditions where it doesn't apply
- Fundamental limitations (not just "future work")

**What NOT to include**:
- Minimizing real limitations
- Treating fundamental limits as trivial

**Example**:

```markdown
### Limitations

#### Fundamental Limitations (Not Fixable by Better Engineering)

1. **HRV-Cognition Link is Weak**
   - Literature shows r = 0.15-0.45 between HRV and cognitive performance
   - This means HRV explains 2-20% of variance in cognition; 80-98% is other factors
   - No amount of engineering improves the underlying signal quality

2. **Consumer Wearables are Inherently Low-Accuracy**
   - Apple Watch optical sensor has ±5-10% accuracy vs. ECG
   - Environmental factors (motion, skin tone, tattoos) degrade accuracy
   - Medical-grade devices (ECG, chest strap) are not consumer-accessible

3. **No Individual Calibration**
   - HRV baselines vary 10-100x between individuals
   - Population-level thresholds (Low/Normal/High) don't generalize
   - Proper validation requires per-user calibration, multiplying complexity

4. **Reverse Causality Possible**
   - If we detect "Low HRV zone" and select conservative prompt, does that cause
     better output, or does the conservative prompt itself cause it?
   - Cannot distinguish HRV effect from prompt effect without careful control groups

#### Technical Limitations (Potentially Improvable)

5. **Limited Data Stream**
   - Only HRV available; no cortisol, EEG, or other biomarkers
   - Single modality limits correlation with cognitive state
   - Improvement: Integrate other sensors (future work)

6. **No Temporal Dynamics**
   - Current implementation uses instantaneous HRV reading
   - Cognitive states have temporal structure (fatigue accumulates)
   - Improvement: Model HRV time series; apply dynamic adjustment (future work)

7. **Coupling Between Components**
   - If LLM output quality depends on HRV-based prompting, but user perception
     of HRV depends on output quality, system has circular feedback
   - Not currently problematic (low weights), but becomes risk as weights increase

#### Population Limitations

8. **Not Applicable For**:
   - Users with cardiac conditions (arrhythmias, pacemakers)
   - Medications affecting heart rate (beta-blockers, stimulants)
   - Individuals with extremely low/high baseline HRV (genetic, disease-related)
   - Exercise immediately before use (temporary HRV elevation)

#### Scope Limitations

9. **Decision Weight Constrained**
   - HRV is 10% of strategy decision (by design)
   - Even if HRV-cognition link improves, impact on system outcomes is capped
   - To maximize benefit would require overweighting HRV, increasing risk
```

---

## 7. Status

**Purpose**: Unambiguous statement of what exists, works, and is validated.

**What to include**:
- Implementation status: STUB / PARTIAL / FULL
- Validation status: NONE / PRELIMINARY / VALIDATED
- Test coverage: Percentage and test types
- Known issues: Bugs, limitations, design problems

**What NOT to include**:
- Wishful thinking ("should be ready soon")
- Ambiguous states

**Example**:

```markdown
### Status

#### Implementation Status: **FULL**
- ✓ HRV data collection interface (iOS HealthKit)
- ✓ HRV zone mapping algorithm
- ✓ Strategy modifier implementation
- ✓ Server endpoints for HRV data transmission
- ✓ Integration with core routing system

#### Validation Status: **NONE**
- ✗ No user studies (0 participants)
- ✗ No benchmark comparisons (0 datasets)
- ✗ No statistical analysis (0 tests)
- ✗ No peer review

#### Test Coverage
- Unit tests: 45% (HRV zone mapping, data validation)
- Integration tests: 20% (server endpoints)
- End-to-end tests: 0% (requires user study)
- Manual testing: Yes (2 devices, informal)

#### Known Issues
| Issue | Severity | Status |
|-------|----------|--------|
| Zone threshold boundaries are arbitrary | HIGH | ACKNOWLEDGED - Requires validation study |
| No individual baseline calibration | HIGH | BY DESIGN - Kept simple for MVP |
| Apple Watch accuracy undocumented for this use case | MEDIUM | ACKNOWLEDGED - Documented as limitation |
| Circular dependency with output quality | MEDIUM | MITIGATED - HRV weight capped at 10% |

#### Maturity Level: **PROTOTYPE**
This component is suitable for:
- Research and experimentation
- Architectural exploration
- Basis for future validation studies

Not suitable for:
- Production deployment
- Health/medical use
- Claims of effectiveness in publications

#### Recommended Citation Status
For publications, use:
> "We implemented an exploratory HRV-aware strategy selection module as part of
> architectural exploration. This component is not yet validated and should be
> considered a proof-of-concept rather than a validated contribution."

#### Next Steps
1. Complete Validation Criterion 1 (collection reliability)
2. Initiate user study for Criterion 2 (zone threshold validity)
3. Based on Criterion 2 results, decide whether to proceed with Criterion 3
```

---

## 8. Future Work

**Purpose**: Distinguish current state from speculative improvements.

**What to include**:
- Proposed enhancements with clear preconditions
- Longer-term research directions
- Dependencies ("Can't do X until we validate Y")
- Why this was out of scope

**What NOT to include**:
- Disguising unfinished work as "future"
- Obvious next steps (those are maintenance, not research)

**Example**:

```markdown
### Future Work

#### Short-Term (6 months)

1. **Validation Studies (Prerequisites for any further work)**
   - Criteria 1-2 as described in Validation section
   - Required for credible claims about HRV utility
   - Dependency: Institutional Review Board approval

2. **Time-Series HRV Analysis**
   - Requirement: Criterion 2 completion showing zone thresholds are valid
   - Approach: Model HRV as temporal signal; use moving averages or filtering
   - Expected benefit: Reduce noise from instantaneous measurements
   - Risk: Increased latency; correlation does not imply causation

#### Medium-Term (12-18 months)

3. **Multi-Modal Biomarker Integration**
   - Add: Cortisol (via wearable), skin conductance, or EEG
   - Requirement: Validation of individual HRV sensors first
   - Expected improvement: More variance explained in cognitive state
   - Challenge: Sparse wearable support for other biomarkers

4. **Per-User Calibration**
   - Approach: Estimate individual HRV baseline; personalize zone thresholds
   - Requirement: 2+ weeks of baseline data per user
   - Expected improvement: Better transfer across populations
   - Challenge: Cold-start problem for new users

#### Long-Term (18+ months, Speculative)

5. **Causal Inference**
   - Question: Does modifying prompts based on HRV improve outcomes?
   - Approach: Randomized controlled trial with stratification by HRV sensitivity
   - Complexity: High; requires statistical power analysis
   - Only viable if short-term validation shows promise

6. **Clinical Translation** (Conditional)
   - Precondition: Evidence that HRV-guided strategies improve cognitive load tolerance
   - Domain: Assistive AI for cognitively disabled populations
   - Regulatory: FDA review if any health claims made
   - **Status**: Highly speculative; do not mention in current publications

#### Out of Scope (Why We're Not Doing This)

- **Real-time HRV feedback loops** - Would create circular dependency with system performance
- **Prediction of future HRV** - Insufficient data; would overfit to individual noise
- **Conversion to medical biomarker** - Outside our domain expertise; requires clinical validation
```

---

## 9. References

**Purpose**: Credit prior work and provide readers means to verify claims.

**What to include**:
- All cited papers, with full citations
- Links to APIs and technical specifications
- Relevant datasets or benchmarks
- Tools/libraries used

**Standard Format**: IEEE (standard in systems papers), APA (social sciences), or ACM

**Example**:

```markdown
### References

#### Peer-Reviewed Literature

[1] K. Thayer, J., & R. Lane, D. (2000). A model of neurovisceral integration in
    emotion regulation and dysregulation. *Journal of Affective Disorders*, 61(3),
    201–216. https://doi.org/10.1016/S0165-0327(00)00338-4

[2] Laborde, S., Moseley, E., & Thayer, J. F. (2018). Heart rate variability and the
    self-regulation of negative emotions: A meta-analysis. *Biological Psychology*,
    139, 159–166. https://doi.org/10.1016/j.biopsycho.2018.08.004

[3] Heart Rate Variability: Apple HealthKit Documentation. Apple Developer.
    https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifierheartratevariabilitysdnn

#### Technical Specifications

[4] Axum: Ergonomic and modular web framework. Tokio Project.
    https://github.com/tokio-rs/axum

[5] SQLx: Compile-time checked SQL queries for Rust.
    https://github.com/launchbadger/sqlx

#### Datasets (If Used)

[6] [Dataset Name]. [Source]. Retrieved from [URL]. (If applicable)

#### Tools & Libraries

- **Rust**: Edition 2021, compiler version 1.73+
- **Apple HealthKit**: iOS 14.0+ (HKObserverQuery)
- **PostgreSQL**: 14.0+ (database backend)
```

---

## How to Apply This Template

### Step 1: Choose Your Target Component
Pick one BEAGLE module (crate, subsystem, or major feature).

### Step 2: Follow the Order
Write sections in order: Intro → SOTA → Methods → Results → Validation → Limitations → Status → Future Work → References.
This order tells a scientific story.

### Step 3: Default to "Not Validated"
Unless you have actual data, assume Status is "PROTOTYPE" or "NONE". You're not being negative; you're being honest.

### Step 4: Use the `STATUS:` Prefix
For inline claims in existing documentation, use:

```markdown
**STATUS: PROPOSED** - [Component] is planned to [achieve X].
Validation required: [specific test/study needed].
Current evidence: [what you actually have].
```

### Step 5: Get External Review
At least one peer should review documentation for:
- ✓ Unsupported claims
- ✓ Missing limitations
- ✓ Circular logic
- ✓ Undefined terms

---

## Red Flags Checklist

Before publishing any documentation, check for:

- [ ] Do we claim something works without showing data?
- [ ] Do we use percentage improvements (15%, 50%) without methodology?
- [ ] Do we say agents/AI "understand" or "reason"?
- [ ] Do we present unvalidated health/biological claims?
- [ ] Do we use metaphors (quantum, entropy, consciousness) without explaining they're metaphors?
- [ ] Do we say something is "100% REAL" or imply full validation?
- [ ] Do we skip mentioning a major limitation?
- [ ] Do we avoid discussing contradictory research?
- [ ] Is the status unclear (is this a prototype, production, or speculative)?

**If any box is checked, the documentation needs revision.**

---

## Version History

| Version | Date | Change |
|---------|------|--------|
| 1.0 | Nov 24, 2025 | Initial template creation |

---

**For questions or clarifications on this template, contact the BEAGLE documentation team.**
