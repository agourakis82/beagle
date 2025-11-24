# Beagle-Agents Crate Architecture Analysis: HRV Integration (v2.0)

**Status**: Scientific revision for journal readiness
**Scope**: Technical architecture analysis for HRV-aware strategy selection
**Key Note**: This documents the solid technical foundation. Effectiveness is unvalidated.

---

## Overview

This document provides deep technical understanding of `beagle-agents` crate architecture to enable HRV-aware strategy selection integration. The crate has excellent design patterns and clear extension points.

### What This Shows
- How the agent system currently works
- Where HRV can be integrated (5 clear integration points)
- What's technically sound
- What remains to be validated

### What This Doesn't Claim
- That HRV integration improves outcomes (unvalidated)
- That zone mappings are optimal (arbitrary)
- That system effectiveness is proven (requires user studies)

---

## 1. Core Architecture Structure

### Location
`/crates/beagle-agents/src/lib.rs`

### Module Organization

**Infrastructure (Production-Ready)**:
- `agent_trait` - Core Agent trait definition (solid abstraction)
- `coordinator` - Multi-agent orchestrator (well-designed)
- `models` - Data structures for results/metrics
- `researcher` - Sequential research workflow
- `specialized_agents` - Focused capability agents

**Advanced Techniques (Research-Grade)**:
- `debate` - Debate system
- `reasoning` - Reasoning patterns
- `deep_research` - Deep research implementation
- `adversarial` - Adversarial strategies
- `metacognitive` - Self-monitoring
- `neurosymbolic` - Hybrid neural-symbolic
- `quantum` - Quantum-inspired algorithms

### Key Design Strength
The crate uses **trait-based abstraction**, making it easy to add HRV-aware variants without breaking existing code. This is genuinely good architecture.

---

## 2. Agent Trait Definition (Extensible)

### Core Trait (76 lines)

```rust
#[async_trait]
pub trait Agent: Send + Sync {
    fn id(&self) -> &str;
    fn capability(&self) -> AgentCapability;
    async fn execute(&self, input: AgentInput) -> Result<AgentOutput>;
    async fn health_check(&self) -> AgentHealth {
        AgentHealth::Healthy
    }
}
```

**Why This Works for HRV**:
- Metadata is flexible JSON `Value` type—can carry HRV state
- Async design integrates cleanly with HRV state lookups
- Health checks can eventually monitor HRV availability

### Agent Capabilities (Well-Defined)

```rust
pub enum AgentCapability {
    ContextRetrieval,
    FactChecking,
    QualityAssessment,
    ResponseGeneration,
    Coordination,
    Synthesis,
}
```

**Each capability can have HRV-aware variants:**
- Retrieval: HRV-aware confidence thresholds
- FactChecking: HRV-aware validation strictness
- QualityAssessment: HRV-aware quality floors

### Input/Output Structures (Ready for Extension)

```rust
pub struct AgentInput {
    pub query: String,
    pub context: Vec<String>,
    pub metadata: Value,  // ← HRV state can go here
}

pub struct AgentOutput {
    pub agent_id: String,
    pub result: Value,
    pub confidence: f32,
    pub duration_ms: u64,
    pub metadata: Value,  // ← Can store HRV-related tracking
}
```

---

## 3. Coordinator Agent (Central Hub)

### Location
`/crates/beagle-agents/src/coordinator.rs` (312 lines)

### Structure

```rust
pub struct CoordinatorAgent {
    anthropic: Arc<AnthropicClient>,
    personality: Arc<PersonalityEngine>,
    context_bridge: Arc<ContextBridge>,
    agents: Vec<Arc<dyn Agent>>,  // Registered agents
}
```

### Multi-Agent Orchestration Workflow

**Current Flow** (Sequential Steps):
1. **Domain Detection** (~49ms) - Uses PersonalityEngine
2. **Session Management** (~70ms) - Create/reuse conversation
3. **Context Retrieval** (~82-110ms) - Parallel via RetrievalAgent
4. **System Prompt Composition** (~114-125ms) - Personality + context
5. **Primary LLM Call** (~128-139ms) - AnthropicClient completion
6. **Parallel Specialized Agents** (~148-204ms) - FactChecking + QualityAssessment
7. **Metric Aggregation** - Combine results
8. **Persistence** (~250-280ms) - Store in ContextBridge

### Key Parallelism Pattern (Worth Keeping)

```rust
let mut join_set = JoinSet::new();
for agent in &self.agents {
    match capability {
        AgentCapability::FactChecking | AgentCapability::QualityAssessment => {
            let agent = Arc::clone(agent);
            join_set.spawn(async move { /* execute */ });
        }
        _ => {}
    }
}

while let Some(result) = join_set.join_next().await {
    // Handle results as they complete
}
```

### Integration Point 1: Agent Selection

**Current** (Line ~305):
```rust
fn get_agent(&self, capability: AgentCapability) -> Option<Arc<dyn Agent>> {
    self.agents.iter().find(|agent| agent.capability() == capability)
}
```

**With HRV Enhancement** (Non-Breaking):
```rust
fn get_agent_for_hrv(
    &self,
    capability: AgentCapability,
    hrv_state: &HRVState
) -> Option<Arc<dyn Agent>> {
    // Select agent based on capability AND HRV state
    // Example: Low HRV → use conservative retrieval variant
    // High HRV → use thorough retrieval variant
    self.agents.iter().find(|agent| {
        agent.capability() == capability &&
        agent.is_suitable_for_hrv_zone(&hrv_state.zone)
    })
}
```

### Integration Point 2: Metadata Injection

**Current** (Lines 84-89):
```rust
agent.execute(
    AgentInput::new(query.to_string())
        .with_metadata(json!({
            "session_id": session_id.to_string()
        }))
)
```

**With HRV Enhancement**:
```rust
agent.execute(
    AgentInput::new(query.to_string())
        .with_metadata(json!({
            "session_id": session_id.to_string(),
            "hrv_state": {
                "zone": hrv_state.zone.to_string(),
                "confidence": hrv_state.confidence,
                "trend": hrv_state.trend.to_string(),
            }
        }))
)
```

---

## 4. Research-Related Agents

### ResearcherAgent (574 lines)

**Location**: `/crates/beagle-agents/src/researcher.rs`

#### Current Capabilities
- Self-RAG (Retrieval-Augmented Generation)
- Paper search (PubMed + arXiv)
- Reflexion loop (critique → refine → iterate)
- Fixed quality thresholds: `QUALITY_THRESHOLD = 0.7`, `MAX_REFINEMENTS = 3`

#### Current Workflow
1. Domain detection
2. Scientific paper search
3. Context retrieval
4. System prompt composition
5. **Main LLM call**
6. **Reflexion loop**:
   - Critique via LLM
   - Calculate quality score from critique response
   - Refine if score < 0.7 (up to 3 iterations)
7. Persist conversation turn

#### Quality Assessment Method (Current)

```rust
// Parse "SCORE: [0.0-1.0]" from critic response
// Fallback: count positive/negative words
// Formula: ((pos_count - neg_count) / 10.0 + 0.5).clamp(0.0, 1.0)
```

**Note**: Quality score is LLM-generated, not objectively measured. Current implementation reasonable for iterative refinement.

#### Integration Point 3: Dynamic Parameters

**Current** (Fixed Values):
```rust
const QUALITY_THRESHOLD: f32 = 0.7;
const MAX_REFINEMENTS: usize = 3;
```

**With HRV Enhancement** (Optional):
```rust
fn get_parameters_for_hrv(hrv_zone: &HRVZone) -> ResearchParameters {
    match hrv_zone {
        HRVZone::VeryLow => ResearchParameters {
            quality_threshold: 0.50,
            max_refinements: 1,
            llm_temperature: 0.5,
            max_tokens: 800,
        },
        HRVZone::Medium => ResearchParameters {
            quality_threshold: 0.70,  // Current default
            max_refinements: 3,       // Current default
            llm_temperature: 0.8,
            max_tokens: 1200,
        },
        // ... other zones
    }
}
```

**Important Caveat**: These parameter mappings are **exploratory**. No validation that they improve outcomes.

---

## 5. Specialized Agents (Modular Design)

**Location**: `/crates/beagle-agents/src/specialized_agents.rs` (238 lines)

### RetrievalAgent (ContextRetrieval)
- **Input**: `session_id` in metadata
- **Output**: 6 most recent conversation turns
- **Confidence**: 0.9 if chunks found, 0.3 otherwise

**With HRV**: Could adapt to return more/fewer chunks based on HRV zone

### ValidationAgent (FactChecking)
- **Method**: LLM-based fact-checking against context
- **Prompt**: "Is answer supported by context? YES or NO"
- **Output**: `is_supported` boolean

**Note**: LLM-based validation is prone to biases. Not a replacement for expert review.

**With HRV**: Could adjust confidence threshold for what counts as "valid"

### QualityAgent (QualityAssessment)
- **Method**: LLM rates response 0.0-1.0
- **Prompt**: "Rate quality 0.0-1.0. Answer ONLY with the number."
- **Output**: Parsed f32 score

**With HRV**: Could adjust quality floor based on zone

---

## 6. Integration Points Summary

| # | Component | File | Lines | Integration Type | Risk |
|---|-----------|------|-------|---|---|
| 1 | **CoordinatorAgent** | `coordinator.rs` | 312 | Agent selection + metadata injection | Low |
| 2 | **ResearcherAgent** | `researcher.rs` | 574 | Dynamic parameter adaptation | Low |
| 3 | **Specialized Agents** | `specialized_agents.rs` | 238 | Threshold adjustment | Low |
| 4 | **Strategy Evolution** | `adversarial/strategy.rs` | 100+ | Fitness functions, mutation ranges | Medium |
| 5 | **Performance Monitor** | `metacognitive/monitor.rs` | 380+ | HRV-performance tracking | Low |

**Overall Risk**: LOW - All changes can be non-breaking with careful design.

---

## 7. New Module Structure (Proposed)

```
crates/beagle-agents/src/hrv_aware/
├─ mod.rs              # Public API exports
├─ state.rs            # HRVZone enum, HRVState tracking
├─ config.rs           # HRVConfig, ParameterSet defaults
├─ selector.rs         # Strategy selection logic
├─ correlation.rs      # Analytics (HRV-performance relationships)
├─ integration.rs      # Adapter functions for existing agents
└─ tests.rs            # Unit tests
```

**Estimated new code**: 800-1000 lines
**Modified existing code**: 50-100 lines across 7 files
**New public API**: ~10 functions

---

## 8. Design Quality Assessment

### What's Excellent
✅ Trait-based abstraction (easy to extend)
✅ Metadata as flexible JSON (can carry HRV state)
✅ Async-first design (integrates well)
✅ Parallelism pattern (JoinSet for concurrent agents)
✅ Clear separation of concerns

### What's Exploratory (Needs Validation)
⚠ Quality scoring via LLM (works, but subjective)
⚠ Zone-to-parameter mappings (arbitrary thresholds)
⚠ Reflexion loop effectiveness (unvalidated)
⚠ Performance metrics (collected, not benchmarked)

### What Would Strengthen the System
🔄 Per-user parameter tuning (currently one-size-fits-all)
🔄 External quality validation (not just LLM-based)
🔄 Actual benchmarking (we have metrics infrastructure, not data)
🔄 A/B testing framework (for comparing strategies)

---

## 9. Status

### Implementation Status ✓ FULL
- ✓ Core agent trait is stable and well-designed
- ✓ CoordinatorAgent orchestration is robust
- ✓ Integration points are clear and minimal-impact
- ✓ Parallel execution infrastructure is solid

### Validation Status ⚠ PARTIAL
- ✓ Code compiles and runs without errors
- ✓ Basic tests pass
- ✗ Effectiveness of agent combinations not validated
- ✗ HRV integration would add untested capability

### Maturity Level 🟡 PRODUCTION-READY WITH CAVEATS
The agent architecture itself is solid. HRV integration would add exploratory capability on top.

---

## 10. References

### Design Patterns Used
- [Trait-based abstraction](https://doc.rust-lang.org/book/ch10-02-traits.html)
- [Arc for shared ownership](https://doc.rust-lang.org/std/sync/struct.Arc.html)
- [async_trait](https://docs.rs/async-trait/latest/async_trait/)
- [JoinSet for task composition](https://docs.rs/tokio/latest/tokio/task/struct.JoinSet.html)

### Crate Dependencies (Relevant)
- `tokio` - Async runtime
- `serde_json` - Metadata handling
- `async_trait` - Trait async support
- `anyhow` - Error handling

---

## Conclusion

The `beagle-agents` crate demonstrates **excellent architectural decisions** that make HRV integration straightforward and non-breaking. The system is ready for extension.

Whether HRV-aware strategy selection **improves outcomes** is an open research question requiring validation studies.

---

**Version History**
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Original | Initial architecture analysis |
| 2.0 | Nov 24, 2025 | Scientific revision: clarity on what's validated vs. exploratory |
