# BEAGLE LLM ROUTING STRATEGY - CORRECTED
**Based on actual available models and subscriptions**

**Date:** 2024-11-24  
**Status:** CORRECTION TO IMPLEMENTATION  
**Priority:** CRITICAL - Affects core pipeline  

---

## 🎯 AVAILABLE MODELS & SUBSCRIPTIONS

### Claude Code (Max Subscriber)
- **Provider:** Anthropic
- **Model:** Claude 3.5 Sonnet with Code Interpreter
- **Best For:** 
  - Code generation and fixes
  - Complex reasoning tasks
  - Context-aware development tasks
- **Strengths:** Deep code understanding, accurate implementations
- **Limitations:** Rate limited by subscription tier
- **Integration:** Via Anthropic API with special Claude Code extension

### Codex Extension (PRO Subscriber)
- **Provider:** OpenAI
- **Model:** GPT-4 Codex variant
- **Best For:**
  - Code completions and snippets
  - Quick code fixes
  - Boilerplate generation
- **Strengths:** Fast, efficient for smaller tasks
- **Limitations:** PRO tier rate limits
- **Integration:** Via OpenAI API with Codex extension headers

### Grok (X.AI)
- **Model:** Grok-3 or Grok-4
- **Best For:**
  - Large context windows (128k-256k)
  - Unlimited queries (on certain tiers)
  - Reasoning over large documents
  - Creative/unconventional thinking
- **Strengths:** Massive context, fast iteration
- **Limitations:** API quota dependent on plan
- **Integration:** Via X.AI API (XAI_API_KEY)

### DeepSeek
- **Model:** DeepSeek-V3 or similar
- **Best For:**
  - Efficient reasoning
  - Cost-effective completions
  - Mathematical/scientific tasks
  - Fallback when others rate limited
- **Strengths:** High quality, efficient, low cost
- **Limitations:** Smaller context window
- **Integration:** Via DeepSeek API

---

## 📊 INTELLIGENT ROUTING STRATEGY

### Decision Matrix

#### Task Type: Code Generation
**Routing Priority:**
1. **Claude Code** (Max) - If available & not rate limited
   - Best for complex refactoring, multi-file changes
   - Use for: architecture decisions, design patterns
2. **Codex** (PRO) - For quick, focused code generation
   - Use for: single functions, completions, small fixes
3. **DeepSeek** - Fallback for efficiency
   - Use for: boilerplate, repetitive patterns
4. **Grok** - Last resort (overkill for code)
   - Use if others fail

#### Task Type: Reasoning & Analysis
**Routing Priority:**
1. **Claude Code** (Max) - Superior reasoning
   - Use for: complex analysis, multi-step problems
2. **Grok** - Large context reasoning
   - Use if context > 50k tokens
3. **DeepSeek** - Efficient fallback
   - Use for: faster iteration when accuracy acceptable

#### Task Type: Large Context (>50k tokens)
**Routing Priority:**
1. **Grok** (128k-256k) - Unlimited context
   - Use for: full codebase analysis, paper processing
2. **Claude Code** (Max) - 200k context (if available)
   - Use for: long documentation, multi-file context
3. **DeepSeek** - Smaller context
   - Use if Grok not available

#### Task Type: Paper Generation (HERMES)
**Routing Priority:**
1. **Claude Code** (Max) - Better writing quality
   - Use for: academic writing, citations, structure
2. **Grok** (large context) - Can hold entire paper
   - Use for: coordinating multi-section generation
3. **DeepSeek** - For sections with smaller context needs

#### Task Type: Cost-Sensitive Operations
**Routing Priority:**
1. **DeepSeek** - Lowest cost, good quality
   - Use for: iterative improvements, draft rounds
2. **Codex** (PRO) - Fast & efficient
   - Use for: small completions
3. **Grok** - Only if context size requires
4. **Claude Code** (Max) - Only when necessary

---

## 🔧 IMPLEMENTATION STRATEGY

### Phase 1: Replace Smart Router Logic

**Current (Wrong):**
```rust
// Using Grok as primary, vLLM as fallback
// No support for Claude Code, Codex, or DeepSeek
```

**Correct Implementation:**
```rust
pub enum LlmProvider {
    ClaudeCode,      // Claude 3.5 Sonnet with Code Interpreter
    Codex,           // GPT-4 Codex (OpenAI PRO)
    Grok,            // Grok-3/4 (X.AI)
    DeepSeek,        // DeepSeek-V3
}

pub enum TaskType {
    CodeGeneration,
    Reasoning,
    LargeContext,
    PaperWriting,
    CostOptimized,
}

pub struct SmartRouter {
    claude_code_client: Option<AnthropicClient>,
    codex_client: Option<OpenAIClient>,
    grok_client: Option<GrokClient>,
    deepseek_client: Option<DeepSeekClient>,
}

impl SmartRouter {
    pub async fn route_task(
        &self,
        task_type: TaskType,
        context_size: usize,
        priority: Priority,
    ) -> Result<LlmProvider> {
        // Decision logic based on:
        // 1. Task type
        // 2. Context size
        // 3. Current rate limit status
        // 4. Cost vs quality tradeoff
    }
}
```

### Phase 2: Environment Configuration

**Required API Keys:**
```bash
# Anthropic (Claude Code)
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_CODE_ENABLED=true

# OpenAI (Codex)
OPENAI_API_KEY=sk-...
CODEX_EXTENSION_ENABLED=true

# X.AI (Grok)
XAI_API_KEY=...
GROK_ENABLED=true

# DeepSeek
DEEPSEEK_API_KEY=...
DEEPSEEK_ENABLED=true
```

### Phase 3: Rate Limiting & Monitoring

**Track per provider:**
- Request count
- Last request time
- Rate limit status
- Success/failure rates

**Automatic fallback when:**
- Rate limit approached (80% of quota)
- Provider error rate > 5%
- Timeout > acceptable threshold

### Phase 4: Cost Tracking

**Log per request:**
- Provider used
- Task type
- Tokens used
- Cost incurred
- Task success

**Daily/Weekly reports:**
- Cost by provider
- Cost by task type
- Provider performance
- ROI analysis

---

## 📋 CONFIGURATION QUESTIONS FOR YOU

Please answer these to finalize the LLM routing:

1. **Claude Code (Max)**
   - What's your preferred use case? (code/reasoning/both)
   - Any rate limits you've observed?
   - Max tokens you want to use per request?

2. **Codex (PRO)**
   - Mainly for code completions?
   - How fast do you need responses?
   - Any specific task types?

3. **Grok**
   - Primary use: large context or unlimited queries?
   - Preferred model: Grok-3 or Grok-4?
   - Context size threshold where you prefer it?

4. **DeepSeek**
   - When should we use this (cost saving, speed, both)?
   - Acceptable quality threshold?
   - Main use cases?

5. **General**
   - Cost vs Quality preference? (how much premium for better quality?)
   - Latency requirements? (critical for real-time?)
   - Fallback strategy priority? (cost savings vs quality)

---

## 🎯 IMMEDIATE NEXT STEPS

1. **Answer the configuration questions above**
2. **Update `crates/beagle-smart-router/src/lib.rs` with correct routing logic**
3. **Implement all 4 provider clients properly**
4. **Add rate limiting and monitoring**
5. **Test routing with your actual subscriptions**

---

## 📊 ROUTING LOGIC PSEUDOCODE

```rust
async fn route_request(
    task_type: TaskType,
    prompt: &str,
    context_size: usize,
) -> Result<(String, LlmProvider)> {
    match task_type {
        TaskType::CodeGeneration => {
            if is_complex_task(prompt) && claude_code_available() {
                use_claude_code(prompt).await
            } else if is_quick_fix(prompt) && codex_available() {
                use_codex(prompt).await
            } else {
                use_deepseek(prompt).await
            }
        }
        
        TaskType::Reasoning => {
            if context_size > 100_000 && grok_available() {
                use_grok(prompt).await
            } else if claude_code_available() {
                use_claude_code(prompt).await
            } else {
                use_deepseek(prompt).await
            }
        }
        
        TaskType::LargeContext => {
            if context_size > 150_000 {
                use_grok(prompt).await  // Only Grok handles 256k+
            } else if context_size > 100_000 && claude_code_available() {
                use_claude_code(prompt).await
            } else {
                use_deepseek(prompt).await
            }
        }
        
        TaskType::PaperWriting => {
            if claude_code_available() {
                use_claude_code(prompt).await  // Better writing
            } else if grok_available() && context_size > 50_000 {
                use_grok(prompt).await  // Can hold full sections
            } else {
                use_deepseek(prompt).await
            }
        }
        
        TaskType::CostOptimized => {
            if deepseek_available() {
                use_deepseek(prompt).await  // Cheapest
            } else if codex_available() {
                use_codex(prompt).await  // Fast & cheap
            } else {
                use_claude_code_or_grok(prompt).await
            }
        }
    }
}
```

---

## ⚠️ CRITICAL FIXES NEEDED

In `crates/beagle-smart-router/src/lib.rs`:
- [ ] Remove Grok-only routing
- [ ] Add Claude Code client
- [ ] Add Codex/OpenAI client  
- [ ] Add DeepSeek client
- [ ] Implement TaskType enum
- [ ] Implement routing decision matrix
- [ ] Add rate limit tracking
- [ ] Add cost tracking
- [ ] Remove vLLM fallback (replace with actual models)

In `crates/beagle-server/src/`:
- [ ] Add all 4 LLM clients to AppState
- [ ] Initialize from environment variables
- [ ] Implement provider selection logic

---

## 🚀 OUTCOME

After implementing this correct strategy, BEAGLE will:
- ✅ Use Claude Code for complex tasks (leveraging your Max subscription)
- ✅ Use Codex for quick code completions (PRO efficiency)
- ✅ Use Grok for massive context & unlimited queries
- ✅ Use DeepSeek as intelligent fallback
- ✅ Automatically route based on task type and context
- ✅ Track costs and optimize spending
- ✅ Never get blocked by rate limits (fallback chain)
- ✅ Maximize quality while minimizing costs

---

**Status:** Awaiting your answers to configuration questions  
**Impact:** Core system functionality  
**Priority:** CRITICAL - Blocks Phase 2  

*Please answer the configuration questions so we can implement the correct LLM routing strategy!*