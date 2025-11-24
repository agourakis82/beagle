# Documentation Status Guide for BEAGLE

**Purpose**: Provide consistent, unambiguous labels for implementation status across all documentation.

**Version**: 1.0
**Last Updated**: November 24, 2025

---

## Status Labels

Use these labels to mark the maturity level of every major component in documentation.

### Implementation Status

These indicate how much of the component is actually built and working.

#### ✓ FULL
- All planned features are implemented
- Code is committed and tested
- Can be executed end-to-end
- Can be demonstrated to users

**Usage**: Only use FULL if honestly every promised feature works.

```markdown
### Implementation Status: ✓ FULL

The HRV data collection module is fully implemented:
- iOS HealthKit integration complete
- Server endpoints functional
- Client-server communication tested
```

#### ⚙ PARTIAL
- Some features implemented, others not
- Core functionality works; advanced features missing
- May have known bugs or limitations in edge cases

**Usage**: Always specify which parts work and which don't.

```markdown
### Implementation Status: ⚙ PARTIAL

- ✓ PBPK model structure defined
- ✓ Parameter parsing implemented
- ✓ Single-compartment models work
- ✗ Multi-compartment scaling not implemented
- ✗ Numerical solver incomplete
```

#### ⚠ EXPERIMENTAL (or PROTOTYPE)
- Proof-of-concept exists
- May work in demo but not robust
- Significant design changes expected
- Not suitable for production

**Usage**: Use for exploratory work.

```markdown
### Implementation Status: ⚠ EXPERIMENTAL

Consciousness emergence detection is a proof-of-concept exploration.
Core infrastructure exists but scalability, robustness, and design
are expected to change significantly.
```

#### 📋 SPEC-ONLY (or PROPOSED)
- Design document exists
- No code yet, or code is skeleton only
- Included for roadmap visibility
- Not ready for any use

**Usage**: Be clear this doesn't exist yet.

```markdown
### Implementation Status: 📋 SPEC-ONLY

Quantum-inspired reasoning engine is specified in ROADMAP.md.
No implementation exists. See Future Work section.
```

#### ❌ NOT IMPLEMENTED
- Was planned but work stopped
- Explicitly removed from roadmap
- Do not mention as if it exists

**Usage**: Use when appropriate to clarify something was abandoned.

```markdown
### Implementation Status: ❌ NOT IMPLEMENTED

Real-time neural network training was deprecated due to memory constraints.
Use batch training approach instead (see beagle-lora/README.md).
```

---

### Validation Status

These indicate what evidence exists that the component actually works.

#### ✓ VALIDATED
- Peer-reviewed publication or
- Extensive user testing (N>30, with statistics) or
- Professional benchmark validation
- Results reproducible by independent group

**Conditions**:
- Must have >95% confidence that implementation matches specification
- Must document testing methodology
- Must include error bars/confidence intervals
- Must cite all evidence

```markdown
### Validation Status: ✓ VALIDATED

HRV collection reliability: Verified against Apple Health readings
on 10 devices, 100+ hours. Data consistency 97% ±1.2% (N=10, 95% CI).
Published in proceedings: [citation]
```

#### ⚖ PRELIMINARY
- Initial validation completed
- Small sample size (N=5-30)
- Shows promise but needs larger studies
- Sufficient for internal use; not for publications

**Conditions**:
- Must show specific data, not just "works"
- Must acknowledge limitations of sample size
- Must specify what larger study would need

```markdown
### Validation Status: ⚖ PRELIMINARY

Performance tested on 5 datasets (internal). Inference latency
~120ms ±30ms. Effect size suggests potential improvement but
requires n=30+ user study for statistical significance.
```

#### 🔬 IN PROGRESS
- Validation study actively running
- Some preliminary data available
- Results not yet analyzed/published
- Timeline expected in N months

**Conditions**:
- Be specific about what's being measured
- Provide interim results if available
- Never present in-progress as validated

```markdown
### Validation Status: 🔬 IN PROGRESS

User study active: 20 participants, 4 weeks each. Preliminary
feedback positive but statistical analysis pending. Completion
target: Q1 2026. See issue #342 for progress tracking.
```

#### ⚠ UNVALIDATED
- No testing performed or
- Implementation matches design but user impact unknown or
- Only anecdotal/informal feedback
- Not suitable for claims of effectiveness

**Conditions**:
- Be honest about lack of validation
- Don't say "works well" without data
- Specify what validation would be needed

```markdown
### Validation Status: ⚠ UNVALIDATED

Consciousness emergence detection is exploratory. No quantitative
validation exists. Anecdotal observations from 2 internal users
suggest the system produces interesting outputs, but this is far
below statistical significance. Validation would require:
1. Definition of measurable "consciousness" indicator
2. User study with N=30+ participants
3. Expert panel evaluation of outputs
4. Comparison against baseline
```

#### ❌ FAILED
- Validation study showed it doesn't work or
- Performance below acceptable threshold or
- Doesn't solve stated problem

**Conditions**:
- Be clear about failure
- Document what went wrong
- Explain what's being done instead

```markdown
### Validation Status: ❌ FAILED

Quantum annealing approach for hypothesis optimization showed
no improvement over classical methods (N=100 test cases, p=0.73).
Results published in [citation]. Current approach uses classical
Bayesian optimization instead (see component X).
```

---

## Implementation + Validation Status Matrix

Combine implementation and validation status to tell complete story:

| Implementation | Validation | Maturity | Suitable For |
|---|---|---|---|
| ✓ FULL | ✓ VALIDATED | **PRODUCTION** | Publications, production use, user documentation |
| ✓ FULL | ⚖ PRELIMINARY | **BETA** | Internal deployment, early adopters, with caveats |
| ✓ FULL | 🔬 IN PROGRESS | **MATURE PROTOTYPE** | Research, demo, internal testing |
| ✓ FULL | ⚠ UNVALIDATED | **PROTOTYPE** | Research, internal testing only |
| ⚙ PARTIAL | ✓ VALIDATED | **LIMITED RELEASE** | Specific validated features only |
| ⚙ PARTIAL | ⚖ PRELIMINARY | **ALPHA** | Research and internal testing |
| ⚙ PARTIAL | ⚠ UNVALIDATED | **EARLY STAGE** | Internal exploration only |
| ⚠ EXPERIMENTAL | Any | **EXPLORATION** | Research only, not for external use |
| 📋 SPEC-ONLY | Any | **ROADMAP** | Show in roadmap, never as working feature |
| ❌ NOT IMPLEMENTED | Any | **ABANDONED** | Don't mention as if exists |

**Example Analysis**:
```markdown
## Module Status Summary

### HRV Strategy Selection
- Implementation: ✓ FULL (all features coded and integrated)
- Validation: ⚠ UNVALIDATED (no user studies)
- **Maturity: PROTOTYPE**
- **Suitable for**: Research and internal testing only
- **NOT suitable for**: Publications claiming improved outcomes, user-facing features
- **Recommended action**: Conduct validation study before public release

### Query Router
- Implementation: ✓ FULL (all routing logic working)
- Validation: ⚖ PRELIMINARY (tested on 3 datasets, 1500 queries)
- **Maturity: BETA**
- **Suitable for**: Internal deployment, early adopter testing
- **Recommended action**: Expand to 10 datasets before publication

### PBPK Integration
- Implementation: ⚙ PARTIAL (data model works, solver incomplete)
- Validation: 📋 SPEC-ONLY (not implemented in solver)
- **Maturity: SPEC-ONLY**
- **Suitable for**: Roadmap discussion only
- **Recommended action**: Complete implementation, then validate
```

---

## How to Document Status in README/Docs

### Option 1: Formal Status Table (Recommended)

```markdown
## Component Status

| Component | Implementation | Validation | Maturity |
|-----------|---|---|---|
| HRV Collection | ✓ FULL | ⚠ UNVALIDATED | PROTOTYPE |
| Query Router | ✓ FULL | ⚖ PRELIMINARY | BETA |
| PBPK Solver | ⚙ PARTIAL | 📋 SPEC-ONLY | ALPHA |

**Details**: See sections below.

### HRV Collection Status
- Implementation: ✓ FULL
- Validation: ⚠ UNVALIDATED
- Maturity: PROTOTYPE

[Description, usage, known issues]
```

### Option 2: Inline Status Badges

```markdown
## Query Router ✓ FULL | ⚖ PRELIMINARY | BETA

This router handles...

### Known Limitations
- Tested on 3 datasets; larger validation needed
- Not suitable for critical queries without review
```

### Option 3: Status Section at End of Doc

```markdown
### Status

**Implementation**: ✓ FULL
**Validation**: ⚠ UNVALIDATED
**Maturity**: PROTOTYPE

This component is suitable for:
- ✓ Research and exploration
- ✗ Production systems
- ✗ Published claims of effectiveness
```

---

## Rules for Status Labels

### DO:
- ✓ Use labels consistently across all documentation
- ✓ Update status when implementation or validation changes
- ✓ Be conservative (when in doubt, downgrade status)
- ✓ Link each status to specific evidence/test results
- ✓ Explain what would be needed to upgrade status

### DON'T:
- ✗ Use "FULL" if any key features are missing
- ✗ Use "VALIDATED" without actual test data
- ✗ Mark as "FULL" + "UNVALIDATED" if that's embarrassing (be honest instead)
- ✗ Upgrade status without documented evidence
- ✗ Use different labels in different files for same component

---

## Upgrading Status

### To Upgrade Implementation → ✓ FULL
1. Implement all planned features
2. Pass code review
3. Pass unit + integration tests
4. Document all features
5. Test end-to-end in realistic environment

### To Upgrade Validation → ⚖ PRELIMINARY
1. Run small validation study (N=5-30)
2. Collect quantitative metrics
3. Document methodology
4. Run statistical tests
5. Write results section with limitations

### To Upgrade Validation → ✓ VALIDATED
1. Complete larger validation study (N=30+)
2. Achieve statistical significance (p<0.05)
3. Peer review or external validation
4. Reproduce results independently
5. Publish results (preferably peer-reviewed)

---

## Real-World Examples

### Example 1: Adversarial Debate Module

**Current Honest Status**:
```markdown
## Adversarial Debate (Triad System)

| Status | Level |
|--------|-------|
| Implementation | ✓ FULL - All three agents implemented, debate flow working |
| Validation | ⚠ UNVALIDATED - No A/B tests, no quality metrics |
| Maturity | PROTOTYPE |

### What This Means
- Code is complete and functional
- System generates outputs through debate
- No evidence that debate improves quality vs. single LLM
- Not suitable for claiming "improved accuracy" in papers

### What Evidence Would Be Needed
- A/B test: N=30 users, same questions, with/without debate
- Expert evaluation: Blind review of outputs
- Quality metric: Define "quality" objectively (not "99.5%")
- Statistical test: t-test for significance

### Current Recommendation
Use for research and exploration. Don't claim improvements in publications.
```

### Example 2: HRV Integration

**Current Honest Status**:
```markdown
## HRV-Based Strategy Selection

| Status | Level |
|--------|-------|
| Implementation | ✓ FULL - Data collection, zone mapping, strategy selection working |
| Validation | ⚠ UNVALIDATED - No user studies, no outcome measurements |
| Maturity | PROTOTYPE |

### What This Means
- All features are coded and integrated
- System successfully reads HRV and modifies strategy
- Unknown if this actually improves user experience or outputs
- Cannot claim health benefits or cognitive benefits

### Known Limitations
- HRV-cognition correlation in literature is weak (r=0.15-0.45)
- Apple Watch accuracy is ~±5-10% vs medical devices
- No per-user calibration (one-size-fits-all thresholds)
- Correlation ≠ causation (HRV may not drive outcomes)

### What Evidence Would Be Needed
1. Baseline study: Does our population show HRV-cognition correlation?
2. Feasibility: Can strategy selection work despite correlation limits?
3. Efficacy: Do users actually benefit (A/B test, N=30+)?
4. Clinical: Any health/safety implications (expert review)?

### Current Recommendation
For research only. Do not deploy to users. Do not claim cognitive benefits.
```

---

## Annual Status Review

Every year (or quarterly for fast-moving components):

1. **Review each component's status**
   - Did implementation change?
   - Did validation progress?
   - Do labels still match reality?

2. **Update documentation**
   - Fix any outdated status labels
   - Link to new validation results
   - Update maturity assessments

3. **Generate status report**
   - What moved from SPEC-ONLY to implementation?
   - What failed validation?
   - What needs attention?

---

## Questions to Ask Before Publishing

Before releasing documentation with a component:

- [ ] Is the implementation status honest? (Admit what's missing)
- [ ] Is the validation status supported? (Link to evidence)
- [ ] Do the two statuses make sense together? (Can you validate something not fully implemented?)
- [ ] Would an external reviewer agree with this status? (If not sure, downgrade)
- [ ] Would we be comfortable with this status in a peer review? (If not, it's too high)

---

## Contact & Updates

Questions about status labels? File an issue with:
- Current status
- What evidence you have
- What you think the status should be

The documentation team will review and update standards as needed.

---

**Version History**
| Version | Date | Change |
|---------|------|--------|
| 1.0 | Nov 24, 2025 | Initial guide |
