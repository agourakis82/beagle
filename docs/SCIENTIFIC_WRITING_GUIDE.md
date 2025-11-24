# Scientific Writing Guide for BEAGLE Documentation

**Purpose**: Establish consistent standards for scientific language and avoid the hallucinations, overclaims, and metaphorical confusion identified in the documentation audit.

**Version**: 1.0
**Last Updated**: November 24, 2025

---

## Golden Rule

> **Only document what has been implemented and tested. Everything else goes to "Future Work" or "Proposed."**

If you can't run code to demonstrate it, don't claim it exists.

---

## Critical Rules by Category

### 1. PERFORMANCE CLAIMS

#### ❌ WRONG: "~30s per iteration"
```markdown
❌ "LoRA training: ~30-60s per iteration"
```

**Problem**:
- "~" (approximately) is vague
- No hardware specification
- No test methodology specified
- Appears to be estimate not measurement

#### ✓ RIGHT:
```markdown
✓ "LoRA training latency (measured): 42±8s per iteration
   - Hardware: NVIDIA RTX 4090, batch size 8
   - Dataset: 500 examples, dim 768
   - Method: Averaged over 10 runs, error bars ±1 SD
   - Conditions: GPU utilization 85%, no other processes"
```

**Rules for All Performance Claims**:
1. Always include hardware specification
2. Always include test conditions (batch size, dataset, environment)
3. Report actual measured values, not estimates
4. Include variance (±standard deviation or confidence interval)
5. Specify sample size (how many runs/tests?)
6. Never use "~" for specifications; use ranges or "typical"

#### ❌ WRONG: "50-100x faster than Python"
```markdown
❌ "Julia: 50-100x faster than Python"
```

**Problem**:
- Generic claim not specific to BEAGLE
- No context for what's being optimized
- BEAGLE bottleneck is LLM API, not numeric computation
- Misleading about where actual speedup comes from

#### ✓ RIGHT:
```markdown
✓ "Julia provides C-like performance for numerical computation
   (see https://julialang.org/benchmarks/). However, BEAGLE's
   primary bottleneck is LLM API latency (~500-2000ms per request),
   not numerical computation. Julia was selected for symbolic
   reasoning and metaprogramming capabilities rather than raw speed."
```

**Rules**:
- Avoid generic language; contextualize to YOUR system
- Admit what your bottleneck actually is
- Cite any external benchmarks; don't repeat them as fact

---

### 2. BIOLOGICAL/HEALTH CLAIMS

#### ❌ WRONG: "Adapt AI agent behavior based on user physiological state (HRV metrics)"
```markdown
❌ "Adapt AI agent behavior based on user physiological state"
```

**Problem**:
- Implies HRV reliably measures physiological state
- Implies adaptation based on HRV actually works
- No evidence provided
- Overstates what HRV can measure

#### ✓ RIGHT:
```markdown
✓ "Exploratory integration of HRV data (from Apple Watch) as
   optional input to strategy selection. This approach is based
   on prior research suggesting HRV may correlate with cognitive
   state (Laborde et al., 2018), though correlations are weak
   (r=0.15-0.45) and highly variable between individuals.

   IMPORTANT LIMITATIONS:
   - HRV-cognition link is NOT validated for BEAGLE use case
   - HRV influence is capped at 10% of routing decision (by design)
   - Not suitable for any health/medical applications
   - No user study has validated effectiveness"
```

**Rules for Health/Biological Claims**:
1. **Cite the research** - Don't claim correlations without sources
2. **State the weakness** - If literature shows weak correlation, say so
3. **Admit you haven't validated it for your system** - "Suggested by prior work" ≠ "validated in our system"
4. **Add disclaimer** - "This is experimental; do not use for clinical applications"
5. **Specify design constraints** - Show how you mitigated risks (e.g., low weight in decisions)
6. **Never claim health outcomes** - No "improves cognitive performance" without user studies

#### Example: HRV Documentation (WRONG)
```markdown
❌ "HRV-Aware Strategy Selection: Complete Implementation Guide

### Key Benefits
- 15-40% quality improvement per HRV zone (estimated)
- Measurable improvement in output consistency
- Adaptive performance tuning"
```

#### Example: HRV Documentation (RIGHT)
```markdown
✓ "HRV-Based Strategy Selection: Exploratory Integration

### STATUS: EXPERIMENTAL / UNVALIDATED

This module explores HRV as an optional input signal, based on
prior research suggesting HRV may correlate with cognitive states
(Laborde et al., 2018; Thayer & Lane, 2000).

### CRITICAL LIMITATIONS
1. HRV-cognition correlations in prior research are weak (r=0.15-0.45)
2. Apple Watch HRV is estimated (optical sensor, ±5-10% accuracy)
3. No individual calibration (one-size-fits-all thresholds)
4. No BEAGLE-specific validation exists
5. Correlation ≠ causation (HRV may not drive strategy success)

### Measured Impact
- Implementation works without crashes ✓
- HRV zone thresholds map correctly ✓
- Strategy modifier applies without error ✓
- User benefits from HRV adaptation? UNKNOWN

### What Would Validate This
- User study: N=30+ with HRV-aware vs. baseline routing
- Measurement: Output quality (expert + user), consistency
- Control: Counterbalanced design, significance testing
- Status: Not yet started

### Current Recommendation
This is a research exploration tool, NOT a validated component.
Suitable for: Internal testing, research papers (with caveats)
NOT suitable for: Production use, health claims, quality guarantees"
```

---

### 3. AI/CAPABILITY CLAIMS

#### ❌ WRONG: "ATHENA - Research specialist, high accuracy focus"
```markdown
❌ "ATHENA - Research specialist"
❌ "ARGOS - Detects bias and reasoning errors"
❌ "Agents understand research gaps"
```

**Problem**:
- Uses anthropomorphic language (specialist, understand, detect)
- Implies agents have capabilities they don't have
- "Bias detection" is actually keyword matching
- Conflates pattern matching with understanding

#### ✓ RIGHT:
```markdown
✓ "ATHENA - LLM-based document processor using specialized prompting
   for literature analysis. Input: academic papers. Output: Structured
   analysis via Grok API. Note: This is prompt-based processing, not
   autonomous understanding."

✓ "ARGOS - LLM-based critical reviewer using adversarial prompting.
   Generates critiques via Grok 4 Heavy API. Output: Structured
   critique for human review. Note: System does not 'understand'
   bias; it applies critical reasoning prompts."

✓ "Topic Detection for High-Risk Concepts - System flags requests
   mentioning specific topics (e.g., consciousness, quantum effects)
   and routes to higher-capability model. This is topic-matching,
   not bias detection. Flagged topics may include legitimate research
   areas, fringe science, or pseudoscience; expert review needed."
```

**Rules for AI/Agent Claims**:
1. **Replace anthropomorphic verbs**:
   - ❌ "understand" → ✓ "process using prompts"
   - ❌ "reason" → ✓ "generate text using model"
   - ❌ "detect" (for abstract concepts) → ✓ "flag" or "classify" or "match"
   - ❌ "think" → ✓ "compute" or "process"

2. **Be explicit about mechanism**:
   - Don't just say "ATHENA analyzes papers"
   - Say "ATHENA sends paper + analysis prompt to Grok API, processes response"

3. **Admit limitations**:
   - "LLM-based agents do not possess understanding or reasoning"
   - "Outputs are pattern matching, not genuine analysis"
   - "All outputs require human review"

4. **Use "optional" for unproven benefits**:
   - ❌ "Improves output quality"
   - ✓ "Optionally applies multi-agent review; impact unvalidated"

5. **Never claim consciousness or genuine intelligence**:
   - ❌ "Collective consciousness emergence"
   - ✓ "Multi-agent coordination using LLM-based text generation"

---

### 4. SPECULATIVE/METAPHORICAL LANGUAGE

#### ❌ WRONG: "Quantum-Inspired Reasoning Engine"
```markdown
❌ "Quantum-inspired reasoning with superposition of hypotheses"
❌ "Quantum interference patterns guide inference"
❌ "Entropy synchronization for collective emergence"
```

**Problem**:
- Quantum terminology used metaphorically without clarification
- Readers may think actual quantum effects are involved
- "Entropy" misused (it's a thermodynamic/information concept)
- Adds jargon without adding precision

#### ✓ RIGHT:
```markdown
✓ "Multi-Hypothesis Ensemble Reasoning

   Our approach maintains multiple hypothesis evaluations in parallel
   and uses Bayesian fusion to combine them. This is inspired by
   quantum mechanics concepts (hence 'quantum-inspired') but is purely
   algorithmic, implemented via standard matrix operations.

   Specifically:
   - Hypotheses: Candidate answers to research question
   - Weights: Posterior probabilities (computed via Bayes rule)
   - Fusion: Combine results via weighted average

   This is equivalent to standard ensemble methods in machine learning."
```

**Rules for Metaphorical Language**:
1. **If using physics/math metaphors, clarify immediately**:
   - "Our 'entropy-like' metric measures state uncertainty (formula: ...)"
   - "Inspired by quantum superposition; implemented as: [actual code/algorithm]"

2. **Better: Just use clear terms**:
   - ❌ "Superposition of states" → ✓ "Set of possible states"
   - ❌ "Entropy level" → ✓ "Uncertainty metric"
   - ❌ "Quantum annealing" → ✓ "Stochastic optimization"

3. **If metaphor isn't helping, remove it**:
   - "Quantum-inspired" in the title implies quantum computing
   - Clearer: "Ensemble-based hypothesis evaluation"

4. **Define any neologisms**:
   - ❌ "noetic network detection" (undefined)
   - ✓ "Knowledge graph inference system (also called noetic, from Greek: relating to knowing)"

---

### 5. UNVALIDATED EFFECTIVENESS CLAIMS

#### ❌ WRONG: "Iteratively refines to quality ≥ 98.5%"
```markdown
❌ "Loop refines until quality >= 98.5%"
❌ "Produces 99.5% accurate outputs"
❌ "15-40% quality improvement from HRV adaptation"
```

**Problem**:
- "Quality score" from LLM is not objective measurement
- 98.5% is arbitrary with no grounding
- No evidence that loop improves quality
- No baseline comparison

#### ✓ RIGHT:
```markdown
✓ "Multi-round refinement process:
   - Round 1: Generate initial output using base model
   - Round 2-N: Apply adversarial critique, generate revised output
   - Stopping criteria: Either max iterations OR researcher approval

   Status: FUNCTIONAL but NOT VALIDATED
   - System successfully generates multiple revisions
   - No evidence that later revisions are higher quality
   - Expert human review required to assess actual improvement
   - Effectiveness varies by domain and question type"
```

**Rules**:
1. **Distinguish system behavior from effectiveness**:
   - "System generates X outputs" ✓ (observable fact)
   - "System improves quality" ❌ (requires validation)

2. **Never use percentages for unquantified concepts**:
   - ❌ "98.5% quality"
   - ✓ "95/100 expert rating (from N=3 reviewers, may be biased)"

3. **Always say "unvalidated" if you haven't tested it**:
   - "Iteratively refines (effectiveness unvalidated)"
   - "Produces outputs (quality unvalidated via user testing)"

4. **When claiming improvement, show the data**:
   - ❌ "Improves consistency"
   - ✓ "Tested on 100 prompts: baseline σ=0.15, refined σ=0.12 (paired t-test, p=0.03)"

---

### 6. "CONSCIOUSNESS" & FRINGE SCIENCE CLAIMS

#### ❌ WRONG: "Distributed collective consciousness emergence"
```markdown
❌ "System orchestrates emergence of transindividual consciousness"
❌ "Ego dissolution level: [0.0-1.0] measured via consciousness metrics"
❌ "Collective consciousness detection via noetic network analysis"
```

**Problem**:
- "Consciousness" is not defined, not measured, not validat
- Uses consciousness language to describe LLM text generation
- Gives pseudoscientific aura to what is just prompt engineering
- Would be extremely embarrassing in peer review

#### ✓ RIGHT:
```markdown
✓ "Collective Intelligence Simulation (Research Exploration)

   STATUS: EXPLORATORY / RESEARCH ONLY

   This module explores philosophical frameworks for thinking about
   collective intelligence and distributed knowledge integration.

   IMPORTANT CLARIFICATION: This module does NOT:
   - Create, detect, or measure actual consciousness
   - Claim any emergent properties beyond text generation
   - Provide evidence for consciousness in systems
   - Violate any principles of cognitive science

   WHAT IT DOES:
   - Generates text simulating philosophical perspectives on
     collective thinking
   - Maintains multiple agent-based prompts that each output text
   - Integrates outputs via concatenation/averaging
   - This is purely algorithmic text generation

   LIMITATIONS:
   - All text is generated by language models via prompting
   - No consciousness exists; system doesn't 'think' or 'know'
   - Philosophical exploration ≠ engineering contribution
   - Not suitable for consciousness-related claims

   APPROPRIATE USE:
   - Research exploration of collective intelligence metaphors
   - Science fiction / speculative design
   - Philosophical inquiry frameworks

   NOT APPROPRIATE USE:
   - Claims of consciousness emergence
   - Philosophical arguments about AI sentience
   - Publications in consciousness studies (without massive caveats)
   - User-facing features suggesting system has consciousness"
```

**Rules**:
1. **Never use consciousness language for LLM outputs**:
   - ❌ "System becomes conscious"
   - ❌ "Emergent consciousness"
   - ❌ "Self-aware module"
   - ✓ "Multi-agent text generation"

2. **If exploring philosophical ideas, be explicit**:
   - "This explores philosophical frameworks" ✓
   - "This demonstrates consciousness" ❌

3. **Add disclaimer to any consciousness module**:
   - "This does NOT create consciousness"
   - "All output is text generation via prompt engineering"

4. **Separate legitimately fringe topics from pseudoscience**:
   - Some research topics are genuinely cutting-edge (consciousness studies)
   - Some are pseudoscience (scalar waves, cellular consciousness)
   - Don't conflate them; be explicit about which is which

---

## Specific Terms to Avoid or Clarify

| Term | Problem | Solution |
|------|---------|----------|
| "~" | Vague approximation | Use specific ranges: "15-22ms" or "typical: 18ms" |
| "quality %" | Undefined measure | Specify: "expert rating (1-10 scale, N=5 reviewers)" |
| "understands" | Anthropomorphizes LLM | Use "processes" or "generates text about" |
| "thinks" | Implies reasoning | Use "generates" or "computes" |
| "bias detection" | Overstates keyword matching | Use "topic flagging" |
| "quantum-inspired" | Implies quantum effects | Clarify: "inspired by but purely algorithmic" |
| "consciousness" | Undefined for software | Use "collective intelligence simulation" |
| "entity" | Vague about implementation | Specify: "LLM-based prompt" or "database record" |
| "100% REAL" | Implies full validation | Use "fully implemented" or "working prototype" |
| "obviously" | Skips explanation | Remove; explain explicitly |
| "should" | Speculative | Use "we propose" or "future work" |

---

## Checklist Before Publishing Any Docs

Before releasing documentation, check every major claim:

### Performance Claims ✓
- [ ] Do I include hardware specs? (CPU, GPU, RAM)
- [ ] Do I specify test conditions? (batch size, data size, network)
- [ ] Do I report actual measured values, not estimates?
- [ ] Do I include variance/error bars?
- [ ] Do I specify sample size?
- [ ] Would another team reproduce these numbers?

### Biological/Health Claims ✓
- [ ] Do I cite the relevant research? (full citations)
- [ ] Do I state the limitations of that research?
- [ ] Do I admit whether we validated this for our system? (probably no)
- [ ] Do I add a disclaimer about clinical applications?
- [ ] Would a doctor be comfortable with this language?

### AI/Capability Claims ✓
- [ ] Did I replace anthropomorphic language? (understand → process, etc.)
- [ ] Do I explain the actual mechanism? (prompt + API call, not magic)
- [ ] Do I state that this is pattern matching, not reasoning?
- [ ] Do I recommend human review for all outputs?
- [ ] Would a skeptical AI researcher accept this description?

### Speculative/Future Work ✓
- [ ] Do I mark this as "Future Work," not current capability?
- [ ] Do I explain the preconditions? (what must be true first?)
- [ ] Do I avoid quantum/consciousness language unless clarifying it's metaphorical?
- [ ] Would this be embarrassing if misquoted out of context?

### Overall ✓
- [ ] Would I be comfortable with this in a peer review?
- [ ] Would an external skeptic find this credible?
- [ ] Did I err on the side of understating, not overstating?
- [ ] Are all claims backed by evidence or marked as unvalidated?

---

## Examples: Before and After

### Example 1: HRV Module

**BEFORE (Problematic)**:
```markdown
# HRV-Aware Strategy Selection - Complete Implementation

Adapt AI agent behavior based on user physiological state (HRV metrics).

## Key Benefits
- **High impact** - 15-40% quality improvement per HRV zone (estimated)
- **Measurable improvement** - 15-40% quality gain per zone
- **Fully integrated** - Works seamlessly with core routing

## Implementation
- Zone mapping: VeryLow < 20ms, Normal 20-50ms, High > 50ms
- Strategy selection: Automatically adjusted per zone
- Validation: [None mentioned]

## Status: READY FOR PRODUCTION
```

**AFTER (Scientifically Sound)**:
```markdown
# HRV-Based Strategy Selection: Exploratory Module

## STATUS: EXPERIMENTAL / UNVALIDATED

### What This Is
An exploratory integration of Apple Watch HRV data as an optional input
to agent strategy selection. Based on prior research suggesting HRV may
correlate with cognitive state (Laborde et al., 2018; Thayer & Lane, 2000).

### Critical Limitations
1. **Weak empirical basis**: Literature shows HRV-cognition r = 0.15-0.45
2. **Low device accuracy**: Apple Watch ±5-10% vs. medical ECG
3. **No per-user calibration**: Uses population thresholds
4. **Not validated for BEAGLE**: No user studies demonstrating benefit
5. **Correlation ≠ causation**: HRV may not drive strategy success

### Implementation Status
- ✓ HRV data collection: WORKING
- ✓ Zone mapping: WORKING (thresholds: VeryLow <20ms, Normal 20-50ms, High >50ms)
- ✓ Strategy integration: WORKING (10% weight cap to prevent overinfluence)
- ✗ Validation: NONE

### Measured Impact
- System stability: Excellent (no crashes)
- Data collection reliability: ~97% vs. Apple Health app
- User benefit from HRV adaptation: **UNKNOWN** (never tested)

### Validation Requirements (Not Yet Completed)
1. User study: N=30+, HRV-aware vs. baseline routing
2. Measurement: Output quality (expert rating), user satisfaction
3. Statistical test: t-test for significance (p<0.05)
4. Timeline: 3-4 months after IRB approval

### Suitable For
- ✓ Research and internal exploration
- ✓ Demo purposes with proper caveats
- ✓ Basis for future validation studies

### NOT Suitable For
- ✗ Production systems
- ✗ Health/medical applications
- ✗ Claims of improved outcomes in publications
- ✗ Unevaluated user-facing features

### How to Reference This in Papers
> "We explored HRV-based strategy selection as an experimental component.
> This integration is not yet validated; see source code documentation for
> limitations. We recommend against citing this as a validated contribution."
```

### Example 2: Adversarial Debate

**BEFORE (Problematic)**:
```markdown
# Triad Adversarial Debate System

Three-agent debate for robust decision making:
- ATHENA: Research specialist (high accuracy)
- HERMES: Clarity expert
- ARGOS: Bias detector

## Iterative Refinement Loop
Loop iteratively refines output until quality >= 98.5% or max iterations.

## Benefits
- Improves output quality
- Reduces bias and errors
- Ensures robustness

## Status: PRODUCTION READY
```

**AFTER (Scientifically Sound)**:
```markdown
# Triad Adversarial Debate System

## STATUS: FULLY IMPLEMENTED / UNVALIDATED

### What This System Does
Three LLM-based prompts generate text from different perspectives:
- **ATHENA**: Literature analysis focused (via specialized prompt)
- **HERMES**: Communication/clarity focused (via specialized prompt)
- **ARGOS**: Critical review focused (via specialized prompt)

Outputs are combined and optionally revised via iterative refinement.

### What This System Does NOT Do
- This does NOT guarantee "better" outputs (never tested)
- This does NOT eliminate bias (all agents are LLMs with dataset bias)
- This does NOT reason (agents generate text via pattern matching)
- This does NOT provide a "quality score" (any scoring is arbitrary)

### Implementation Status
- ✓ All three agent prompts: IMPLEMENTED
- ✓ Debate flow: WORKING
- ✓ Iterative refinement: WORKING (stops at max iterations or user approval)
- ✗ Quality validation: NONE

### What Evidence Supports This Approach?
**In literature**:
- Ensemble methods can reduce variance (Kuncheva & Whitaker, 2003)
- Multiple reviewers catch more errors (meta-analysis in Goodman et al., 2011)

**For BEAGLE specifically**:
- No validation studies exist
- No evidence that LLM-based debate improves quality
- No evidence that our specific prompts create useful diversity

### Validation Needed (Not Yet Done)
1. Baseline test: Same questions → single Grok vs. Triad debate
   - Measure: Expert rating of outputs (1-10 scale, blinded)
   - Sample size: N=50 questions, M=3-5 expert raters
   - Success criterion: Triad avg > Baseline avg (p<0.05)

2. Mechanism test: Do agents disagree usefully?
   - Analyze: Where do ATHENA/HERMES/ARGOS disagree?
   - Check: Do disagreements improve final output?

3. Cost-benefit: Is debate worth 3x latency?
   - Compare: Single agent (fast) vs. Triad (slow)
   - Measure: Is quality improvement worth the latency cost?

### Current Recommendation
- **Suitable for**: Research, exploration, demo (with caveats)
- **NOT suitable for**: Claims of improved quality in publications
- **Next step**: Run validation study before production deployment

### How to Reference This in Papers
> "We implemented a three-agent debate system for exploratory purposes.
> This architecture is not yet validated against single-agent baselines.
> All outputs require expert review. See methodology section for caveats."
```

---

## Style Guidelines

### Tone
- **Objective**: Report facts without hype
- **Humble**: Acknowledge limitations, unknowns
- **Precise**: Avoid vague language; be specific
- **Honest**: Admit what you don't know

### Structure
- Lead with status (what's implemented vs. validated)
- Then explain what it does
- Then explain what it doesn't do
- Then show evidence
- Then describe limitations
- Then recommend appropriate use

### Hedging Language
✓ Good hedging (accurate):
- "This approach is based on..."
- "We propose..."
- "This suggests..."
- "In preliminary testing..."
- "Further validation is needed..."

❌ Bad hedging (false confidence):
- "Obviously..."
- "As everyone knows..."
- "100% REAL"
- "Proven to..."
- "Will definitely..."

---

## References

This guide was informed by:
- [IEEE Standard for System and Software Verification (1012-2004)](https://standards.ieee.org/)
- [APA Ethical Guidelines for Research](https://www.apa.org/ethics/code)
- [Mooney et al., "The Replication Crisis and the Epistemology of Experimental Psychology", *Nature Neuroscience*](https://doi.org/10.1038/nrn.2017.107)
- BEAGLE Documentation Audit (Nov 2025)

---

**Version History**
| Version | Date | Change |
|---------|------|--------|
| 1.0 | Nov 24, 2025 | Initial guide with rules for avoiding hallucinations |
