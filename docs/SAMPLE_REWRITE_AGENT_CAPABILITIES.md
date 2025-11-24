# Agent Architecture: Capability-Based LLM Orchestration (Sample Rewrite)

**Version**: 2.0 (Scientific Rewrite)
**Date**: November 24, 2025
**Status**: ✓ IMPLEMENTED / ⚖ PRELIMINARY VALIDATION
**Focus**: Accurate description of agent mechanisms and capabilities

---

## Quick Reference: Before and After

### BEFORE (Problematic Language)
```
Agents are intelligent specialists:
- ATHENA: Research specialist with high accuracy focus
- HERMES: Communication expert providing clarity
- ARGOS: Bias detector identifying errors

The system improves output quality through adversarial debate.
Debate reduces bias and ensures robustness.
```

**Problems**: Anthropomorphic language, unsupported claims, "specialist" suggests understanding

---

### AFTER (Scientifically Accurate)
```
Agents are LLM-based prompt templates:
- ATHENA: Sends literature-focused prompt to Grok/Claude API
  - Input: Research question
  - Processing: LLM completes prompt
  - Output: Text response
  - Note: This is text generation via prompting, not domain expertise

- HERMES: Sends clarity-focused prompt to LLM
  - Input: Previous output + original question
  - Processing: LLM refines for clarity
  - Output: Rephrased text
  - Note: No guarantee of improved clarity (subjective)

- ARGOS: Sends critical review prompt to LLM
  - Input: Proposed answer + review criteria
  - Processing: LLM generates critiques
  - Output: Critique text
  - Note: Does not detect bias (just applies critical prompting)

Combining outputs may provide linguistic diversity.
Debate effectiveness is UNVALIDATED - no evidence it improves quality.
```

---

## 1. What Agents Actually Are

### Accurate Technical Description

**Agent = LLM-based Prompt Template + API Call + Output Parser**

Each "agent" consists of:
1. **Prompt Template** (String)
   - Fixed text that frames a request to the LLM
   - Different template for each agent type
   - Example ATHENA template:
     ```
     "You are a research literature expert analyzing this question: {question}
     Provide a literature-based response focusing on peer-reviewed sources."
     ```

2. **LLM API Call** (Network Request)
   - Send prompt + parameters to Grok/Claude/other API
   - Receive text output
   - Handle errors/timeouts

3. **Output Parsing** (String Processing)
   - Extract structured data from response (if JSON expected)
   - Validate format
   - Return to coordinator

### What This Means
- Agents do NOT have domain expertise, understanding, or intelligence
- Agents are NOT autonomous; they execute when prompted
- Agents do NOT reason; they pattern-match on training data
- Agents do NOT detect bias; they apply prompts that might seem critical

### Why This Distinction Matters
Using accurate language prevents:
- ✗ Mistaken belief that agents "understand" domains
- ✗ Over-reliance on agent outputs without human review
- ✗ Claims of improved quality without validation
- ✗ Marketing hype that misleads users

---

## 2. Individual Agent Descriptions

### ATHENA: Literature Analysis (Accurate Version)

#### What This Is
An LLM prompt that asks the language model to generate text analyzing a research question from a literature perspective.

#### Implementation
```rust
pub struct AthenAgent {
    llm_client: Arc<dyn LlmClient>,
    template: String,  // Fixed prompt template
}

pub async fn analyze(&self, question: &str) -> Result<String> {
    // 1. Create prompt by substituting {question}
    let prompt = self.template
        .replace("{question}", question);

    // 2. Call LLM (send text, get text back)
    let response = self.llm_client.complete(&prompt).await?;

    // 3. Return text output (no parsing needed for this agent)
    Ok(response)
}
```

#### What ATHENA Produces
- ✓ Text referencing academic sources
- ✓ Structured analysis (if prompt engineering succeeds)
- ✗ Does NOT evaluate source quality objectively
- ✗ Does NOT detect misinformation
- ✗ Does NOT possess domain expertise

#### Key Limitation
**LLM can hallucinate citations.**
Example: If prompted for papers on a topic, LLM might cite plausible-sounding papers that don't exist. This is a known limitation of language models. ATHENA outputs REQUIRE verification against actual sources.

#### Validation Status
| Aspect | Status |
|--------|--------|
| Does it call the LLM? | ✓ YES |
| Does it format text nicely? | Depends on prompt quality |
| Does it improve output quality? | **UNKNOWN** (never A/B tested) |
| Does it detect good sources? | **NO** (LLMs hallucinate) |

#### Recommended Use
- ✓ Draft generation (input to expert review)
- ✓ Prompt engineering research
- ✗ Final outputs without human verification
- ✗ Critical decision-making

---

### HERMES: Clarity Enhancement (Accurate Version)

#### What This Is
An LLM prompt that asks the language model to rewrite text for clarity and structure.

#### Implementation
```rust
pub async fn enhance_clarity(&self, text: &str, question: &str) -> Result<String> {
    let prompt = format!(
        "Rewrite this for clarity and structure:\n\
        Original question: {}\n\
        Original response:\n{}\n\
        Rewritten response:\n",
        question, text
    );

    let response = self.llm_client.complete(&prompt).await?;
    Ok(response)
}
```

#### What HERMES Produces
- ✓ Reformatted text
- ✓ Often shorter/clearer (subjectively)
- ✗ Does NOT guarantee improved clarity (subjective judgment)
- ✗ Does NOT improve factual accuracy
- ✗ Can introduce errors while "improving" clarity

#### Key Limitation
**Clarity is subjective; LLMs optimize for plausibility, not accuracy.**
Example: LLM might make a confusing paragraph clearer but less precise, or introduce false confidence.

#### Validation Status
| Aspect | Status |
|--------|--------|
| Does it reformat text? | ✓ YES |
| Is rewritten text clearer? | Depends on human judgment |
| Does it improve quality? | **UNKNOWN** |
| Does it introduce errors? | **POSSIBLY** (can hallucinate while clarifying) |

#### Recommended Use
- ✓ Draft improvement (still needs expert review)
- ✓ Prompt engineering research
- ✗ As validation of truth claims
- ✗ As confidence booster for outputs

---

### ARGOS: Critical Review (Accurate Version)

#### What This Is
An LLM prompt that asks the language model to generate critiques of a proposed answer.

#### Implementation
```rust
pub async fn generate_critiques(&self, answer: &str, question: &str) -> Result<String> {
    let prompt = format!(
        "Critically review this answer. Identify:\n\
        - Missing nuance\n\
        - Potential errors\n\
        - Controversial claims needing evidence\n\
        - Alternative perspectives\n\
        \n\
        Question: {}\n\
        Answer:\n{}\n\
        Critiques:\n",
        question, answer
    );

    let response = self.llm_client.complete(&prompt).await?;
    Ok(response)
}
```

#### What ARGOS Produces
- ✓ Text suggesting potential weaknesses
- ✓ Alternative perspectives (textual)
- ✗ Does NOT detect actual bias
- ✗ Does NOT validate claims
- ✗ Does NOT possess critical judgment

#### Critical Limitation
**ARGOS cannot detect bias; it applies critical prompting.**
- Bias is systematic error in training data and reasoning
- Language models inherit biases from training data
- Asking LLM to "detect bias" just generates text about bias (which can itself be biased)
- **This is circular**: asking a biased model to detect bias doesn't reduce bias

#### Validation Status
| Aspect | Status |
|--------|--------|
| Does it generate critical text? | ✓ YES |
| Are critiques accurate? | **UNKNOWN** (never validated) |
| Does it detect bias? | **NO** (contradicts AI ethics literature) |
| Does it improve final outputs? | **UNKNOWN** |

#### Recommended Use
- ✓ Brainstorming alternative perspectives
- ✓ Identifying potential weaknesses to investigate
- ✗ As bias detection (doesn't work)
- ✗ As validation of claims

---

## 3. Multi-Agent Debate (Accurate Version)

### What This Is
Sequential text generation: one agent produces text → next agent reviews/refines → outputs combined.

### Current Process
```
User Question
    ↓
ATHENA (literature analysis prompt) → Text A
    ↓
HERMES (clarify prompt) → Text B
    ↓
ARGOS (critique prompt) → Text C
    ↓
Combine A, B, C (concatenation or averaging)
    ↓
Final Output (ensemble of texts)
```

### What This Actually Achieves
- ✓ Multiple textual perspectives on same question
- ✓ Linguistic diversity in outputs
- ✗ NOT improved accuracy (unless diversity happens to help)
- ✗ NOT reduced bias (all perspectives come from same LLM family)
- ✗ NOT "adversarial debate" (agents don't argue; they independently generate text)

### Validation Status
| Claim | Evidence |
|-------|----------|
| "Debate improves quality" | UNVALIDATED - no A/B test exists |
| "Diversity is beneficial" | UNKNOWN - depends on task |
| "Ensemble is better than single" | MAYBE - established for some ML tasks, untested for LLMs |

### Key Limitation: Circular Reasoning Risk
All agents use same underlying LLM (Grok). They don't represent true diverse perspectives:
- ATHENA asks for literature focus
- HERMES asks for clarity
- ARGOS asks for criticism
- **But all three use same LLM, which generates plausible text**

This is not debate; it's applying different prompts to the same model.

### What Would Actually Be Adversarial
TRUE adversarial approach would:
1. Use different LLM models (Grok vs. Claude vs. Gemini)
2. Have models explicitly argue against each other
3. Measure whether diversity improves outcome quality
4. Validate against human expert judgment

**Current implementation**: None of these.

---

## 4. Honest Capability Statement

### What Agents CAN Do ✓
- ✓ Generate text on demand
- ✓ Apply specific prompt frameworks
- ✓ Provide multiple textual perspectives
- ✓ Process questions efficiently
- ✓ Work as architectural components in pipelines

### What Agents CANNOT Do ✗
- ✗ Understand domain expertise (they pattern-match)
- ✗ Detect bias (they embody biases from training)
- ✗ Validate factual claims (they hallucinate)
- ✗ Reason about causality (they predict tokens)
- ✗ Guarantee quality improvements (unvalidated)
- ✗ Replace human expert review (they need it)

### Validation Status: What We Know vs. Don't Know

| Question | Status | Evidence |
|----------|--------|----------|
| Do agents generate text? | ✓ YES | Working implementation |
| Is text sometimes useful? | ✓ LIKELY | Anecdotal observation |
| Do agents improve accuracy? | ⚖ UNKNOWN | Never A/B tested |
| Do agents reduce bias? | ❌ NO | Contradicts AI ethics research |
| Can users trust agent outputs? | ❌ NO | Always requires expert review |
| Should agent output be published? | ❌ NO | Not validated |

---

## 5. Recommended Framework for Agent Documentation

### Section 1: Mechanism (Be Explicit)
```markdown
### How This Agent Works

This agent is implemented as:
1. LLM prompt template (stored as string)
2. API call to language model (Grok 3 or vLLM)
3. Response parsing (JSON if structured output needed)

Example data flow:
Question → [Prompt Template] → LLM API → Text Response → Parser → Output
```

### Section 2: Limitations (Be Honest)
```markdown
### Important Limitations

This agent:
- Does NOT understand the domain (it pattern-matches)
- Does NOT guarantee accuracy (LLMs hallucinate)
- Does NOT validate claims (it generates plausible text)
- Does NOT improve quality automatically (unvalidated)

All outputs require human expert review.
```

### Section 3: Validation Status (Be Clear)
```markdown
### Validation Status

| Metric | Status | Evidence |
|--------|--------|----------|
| Implementation | ✓ WORKING | Code compiles and runs |
| Usefulness | ⚖ PRELIMINARY | Internal testing suggests value, not rigorously tested |
| Quality Impact | ⚠ UNVALIDATED | No A/B tests, no benchmark comparison |
| Publication Readiness | ❌ NO | Not validated for research claims |
```

### Section 4: Appropriate Uses (Don't Oversell)
```markdown
### Recommended Uses

✓ Suitable for:
- Draft generation (input to expert refinement)
- Prompt engineering research
- Architectural exploration
- Internal decision support (with expert review)

✗ NOT suitable for:
- Final publication without human review
- Clinical or medical decisions
- Safety-critical systems
- Claims about effectiveness (unvalidated)
```

---

## 6. How to Cite Agents in Papers

### WRONG (Overstated)
> "Our agent system improves response quality by 15-40% through adversarial debate."

**Problems**:
- No evidence for 15-40% improvement
- Not actually adversarial (all from same LLM)
- Misleads readers

### BETTER (Accurate)
> "We implemented multi-agent text generation for architectural exploration.
> Agents apply different prompt templates to the same language model.
> This approach produces diverse textual outputs; impact on actual quality
> is not yet validated."

### CONDITIONAL ACCEPTABLE (If Data Exists)
> "In internal testing with [N] questions, we observed subjective quality
> improvements with multi-agent review compared to single-agent baselines.
> Statistical significance testing is pending. Full validation against
> expert benchmarks would be required before publication claims."

---

## 7. Common Mistakes to Avoid

| ❌ DON'T SAY | ✅ DO SAY |
|---|---|
| Agents "understand" research | Agents apply literature-focused prompts |
| Agents "detect" bias | Agents apply critical-thinking prompts |
| Debate "improves" quality (without validation) | Multi-agent approach produces diverse perspectives (unvalidated for quality) |
| This is "robust" | This is exploratory architecture |
| Agents have "expertise" | Agents apply domain-specific prompt templates |
| System "guarantees" accuracy | System generates text; human review required |

---

## 8. Validation Roadmap

### Phase 1: Establish Baseline
**What**: Measure single-agent performance
- **Method**: Sample 30 questions, get single-agent (ATHENA only) responses
- **Metric**: Have domain experts rate (1-10 scale, blinded)
- **Timeline**: 2 weeks
- **Cost**: Expert review hours

### Phase 2: Multi-Agent Comparison
**What**: Does multi-agent debate improve on single?
- **Method**: Same 30 questions, get multi-agent responses
- **Metric**: Expert rating comparison (blinded)
- **Statistical Test**: Paired t-test
- **Success Criterion**: Multi > Single, p < 0.05
- **Timeline**: 2 weeks
- **Cost**: Expert review hours

### Phase 3: Identify Mechanism
**What**: Does improvement come from diversity or something else?
- **Method**: Analyze where agents disagree
- **Check**: When multi > single, does it correlate with agent disagreement?
- **Timeline**: 1 week
- **Cost**: Analysis time

### Phase 4: Generalize
**What**: Do results hold across domains?
- **Method**: Test on 3-5 different question types
- **Check**: Does agent approach generalize?
- **Timeline**: 4-6 weeks
- **Cost**: Expanded expert review

### Phase 5: Publish
**Only After Phases 1-4**: Write methodology, results, analysis
- Don't publish claims before validation
- Be honest about limitations in results

---

## Summary: Responsible Agent Documentation

**Key Principles**:
1. ✓ Explain HOW agents work (mechanism)
2. ✓ State WHAT we don't know (validation gaps)
3. ✓ List WHERE they're appropriate (use cases)
4. ✓ Show EVIDENCE if claiming improvement (data required)
5. ✗ Don't use anthropomorphic language without clarification
6. ✗ Don't claim capabilities beyond what's validated
7. ✗ Don't publish without expert review

This approach is honest, scientifically sound, and sustainable.

---

## References

[1] Openai. (2023). GPT-4 Technical Report. *arXiv preprint arXiv:2303.08774*.
- Documents LLM limitations and hallucination risks

[2] Bender, E. M., Gebru, T., McMillan-Major, A., & Shmitchell, S. (2021). On the dangers of stochastic parrots. *In Proceedings of the 2021 ACM Conference on Fairness, Accountability, and Transparency* (pp. 610-623).
- Clarifies what LLMs are (pattern matching, not understanding)

[3] Kuncheva, L. I., & Whitaker, C. J. (2003). Measures of diversity in classifier ensembles and their relationship with the ensemble accuracy. *Machine Learning*, 51(2), 181–207.
- Establishes when ensemble methods help (established for ML, not validated for LLMs)

---

**Version History**
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Original | Initial documentation with anthropomorphic language |
| 2.0 | Nov 24, 2025 | Scientific rewrite per documentation standards |

---

**Document Purpose**: Sample rewrite demonstrating how to accurately document LLM agents
**Intended Audience**: Development team reviewing documentation rewrite approach
**Status**: SAMPLE - Ready for feedback
