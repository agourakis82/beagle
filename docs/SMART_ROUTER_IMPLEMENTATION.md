# SMART ROUTER CORRECTED IMPLEMENTATION
**Using Claude Code (Max), Codex (PRO), Grok, and DeepSeek**

**Date:** 2024-11-24  
**Status:** Implementation Ready  
**Priority:** CRITICAL - Blocks Phase 2  

---

## 🎯 ROUTER ARCHITECTURE

### Core Decision Matrix

```
┌─────────────────────────────────────────────────────────────────┐
│                    TASK CLASSIFICATION                          │
├─────────────────────────────────────────────────────────────────┤
│  Code Generation        → Claude Code → Codex → DeepSeek       │
│  Complex Reasoning      → Claude Code → Grok → DeepSeek        │
│  Large Context (>100k)  → Grok → Claude Code → DeepSeek        │
│  Paper Writing          → Claude Code → Grok → DeepSeek        │
│  Cost Optimized         → DeepSeek → Codex → Grok → Claude     │
│  Unknown/Default        → Claude Code → Grok → DeepSeek        │
└─────────────────────────────────────────────────────────────────┘
```

### Provider Capabilities

| Provider | Code | Reasoning | Max Context | Speed | Cost | Primary Use |
|----------|------|-----------|-------------|-------|------|------------|
| Claude Code | ★★★★★ | ★★★★★ | 200k | Medium | High | Complex tasks |
| Codex | ★★★★ | ★★★ | 8k-16k | ★★★★★ | Medium | Quick fixes |
| Grok | ★★★ | ★★★★ | 256k | ★★★★ | Medium | Huge context |
| DeepSeek | ★★★ | ★★★★ | 128k | ★★★★ | ★★★★★ | Fallback |

---

## 📋 ROUTING LOGIC RULES

### Rule 1: Code Generation
```
IF task == CodeGeneration:
  IF prompt complexity > HIGH AND claude_code_available():
    ROUTE TO: Claude Code
  ELSE IF is_small_fix AND codex_available():
    ROUTE TO: Codex
  ELSE IF deepseek_available():
    ROUTE TO: DeepSeek
  ELSE:
    ROUTE TO: Grok (fallback)
```

### Rule 2: Reasoning Tasks
```
IF task == Reasoning:
  IF context_size > 100_000 AND grok_available():
    ROUTE TO: Grok
  ELSE IF claude_code_available():
    ROUTE TO: Claude Code
  ELSE IF deepseek_available():
    ROUTE TO: DeepSeek
  ELSE:
    ROUTE TO: Codex (minimum fallback)
```

### Rule 3: Large Context
```
IF context_size > 128_000:
  IF grok_available() AND context_size <= 256_000:
    ROUTE TO: Grok
  ELSE IF claude_code_available() AND context_size <= 200_000:
    ROUTE TO: Claude Code
  ELSE:
    ERROR: Context too large
```

### Rule 4: Paper Writing (HERMES)
```
IF task == PaperWriting:
  IF claude_code_available() AND context_size <= 200_000:
    ROUTE TO: Claude Code (best writing quality)
  ELSE IF grok_available() AND context_size <= 256_000:
    ROUTE TO: Grok (can hold entire sections)
  ELSE IF deepseek_available():
    ROUTE TO: DeepSeek (section by section)
```

### Rule 5: Cost Optimization
```
IF mode == CostOptimized:
  PREFERENCE: DeepSeek > Codex > Grok > Claude Code
  FALLBACK CHAIN: DeepSeek → Codex → Grok → Claude Code
  STOP: When task completes
```

### Rule 6: Emergency Fallback
```
IF provider_error OR rate_limited OR timeout:
  IF provider == Claude Code:
    TRY: Grok → DeepSeek → Codex
  ELSE IF provider == Grok:
    TRY: Claude Code → DeepSeek → Codex
  ELSE IF provider == Codex:
    TRY: Claude Code → DeepSeek → Grok
  ELSE IF provider == DeepSeek:
    TRY: Claude Code → Codex → Grok
  ELSE:
    FAIL: All providers exhausted
```

---

## 🔧 IMPLEMENTATION CHECKLIST

### Phase 1: Client Initialization
- [ ] Create `AnthropicCodeClient` for Claude Code
- [ ] Create `OpenAICodexClient` for Codex extension
- [ ] Create `GrokClient` (already exists, update)
- [ ] Create `DeepSeekClient` for DeepSeek API
- [ ] Add all to `AppState` struct
- [ ] Initialize from environment variables

### Phase 2: Routing Engine
- [ ] Define `TaskType` enum
- [ ] Define `Priority` enum (high/normal/cost-optimized)
- [ ] Implement `SmartRouter` struct
- [ ] Implement routing decision logic
- [ ] Add rate limit tracking per provider
- [ ] Add automatic fallback chain

### Phase 3: Provider Detection
- [ ] Check each provider availability
- [ ] Track rate limit status
- [ ] Monitor error rates
- [ ] Log provider performance

### Phase 4: Monitoring & Logging
- [ ] Track tokens used per provider
- [ ] Log cost per request
- [ ] Generate provider utilization reports
- [ ] Alert when rate limits approached

---

## 💾 ENVIRONMENT VARIABLES REQUIRED

```bash
# Anthropic Claude Code (Max subscriber)
ANTHROPIC_API_KEY=sk-ant-xxxxx
CLAUDE_CODE_ENABLED=true
CLAUDE_CODE_MAX_TOKENS=4000

# OpenAI Codex (PRO subscriber)
OPENAI_API_KEY=sk-xxxxx
CODEX_ENABLED=true
CODEX_MAX_TOKENS=1000

# X.AI Grok
XAI_API_KEY=xxxxx
GROK_ENABLED=true
GROK_MODEL=grok-3  # or grok-4
GROK_MAX_TOKENS=8192

# DeepSeek
DEEPSEEK_API_KEY=xxxxx
DEEPSEEK_ENABLED=true
DEEPSEEK_MAX_TOKENS=2048

# Router Configuration
ROUTER_COST_MODE=balanced  # balanced, quality, cost
ROUTER_LOG_COSTS=true
ROUTER_FALLBACK_ENABLED=true
```

---

## 🎯 TASK TYPE DETECTION

### How to determine task type automatically:

```
CodeGeneration IF:
  - Prompt contains keywords: "code", "function", "class", "implement"
  - Request type == "implementation"
  - File extension suggests code file

Reasoning IF:
  - Prompt contains keywords: "explain", "analyze", "why", "understand"
  - Request type == "analysis"
  - Requires multi-step thinking

LargeContext IF:
  - context_size > 50_000 tokens
  - Request contains file uploads
  - Multiple files referenced

PaperWriting IF:
  - Prompt contains keywords: "paper", "article", "write", "abstract"
  - Request type == "writing"
  - output format == "markdown" or "pdf"

CostOptimized IF:
  - User preference set to cost_first
  - Running in batch mode
  - Non-critical task
```

---

## 📊 COST TRACKING STRUCTURE

```rust
struct RequestMetrics {
    provider: LlmProvider,
    task_type: TaskType,
    timestamp: DateTime<Utc>,
    input_tokens: usize,
    output_tokens: usize,
    estimated_cost: f64,
    latency_ms: u64,
    success: bool,
    fallback_count: u32,
}

struct DailyCostReport {
    date: Date,
    claude_code_cost: f64,
    codex_cost: f64,
    grok_cost: f64,
    deepseek_cost: f64,
    total_cost: f64,
    requests_by_type: HashMap<TaskType, usize>,
    top_providers: Vec<(LlmProvider, usize)>,
}
```

---

## ⚡ PERFORMANCE TARGETS

| Provider | Target Latency | Success Rate | Cost/1k tokens |
|----------|---|---|---|
| Claude Code | <2s | >99% | $2.50-5.00 |
| Codex | <1s | >99% | $0.01-0.02 |
| Grok | <1.5s | >95% | Variable |
| DeepSeek | <2s | >98% | $0.15-0.30 |

---

## 🚨 ERROR HANDLING

### Rate Limit Handling
```
IF rate_limit_error:
  LOG: Provider rate limited
  RECORD: Time of limit
  FALLBACK: Next provider in chain
  WAIT: Exponential backoff (if retry)
  ALERT: If primary provider repeatedly limited
```

### Timeout Handling
```
IF timeout > THRESHOLD:
  LOG: Timeout occurred
  FALLBACK: Next provider
  TRACK: Provider performance
  ALERT: If latency > 10s consistently
```

### API Error Handling
```
IF api_error:
  IF error_code == 429:
    HANDLE: Rate limit (see above)
  ELSE IF error_code == 5xx:
    RETRY: Exponential backoff (max 3x)
    FALLBACK: If retries exhausted
  ELSE IF error_code == 4xx:
    LOG: Client error
    FALLBACK: Next provider (don't retry same)
  ELSE:
    LOG: Unknown error
    FALLBACK: Next provider
```

---

## 📝 FILES TO MODIFY

### 1. `crates/beagle-smart-router/src/lib.rs`
**Changes:**
- Remove Grok4Heavy references (already done)
- Add AnthropicCodeClient
- Add OpenAICodexClient
- Add DeepSeekClient
- Rewrite SmartRouter with new routing logic
- Add TaskType enum
- Add Priority enum
- Implement routing decision matrix

### 2. `crates/beagle-server/src/main.rs`
**Changes:**
- Add all 4 LLM clients to AppState
- Initialize from environment variables
- Add rate limit tracking
- Add cost logging

### 3. `crates/beagle-server/src/api/routes/llm.rs`
**Changes:**
- Update endpoint to use new router
- Return provider info in response
- Track costs per request

### 4. `.env.template`
**Changes:**
- Add all new environment variables
- Document provider setup instructions
- Add cost tracking options

---

## ✅ VERIFICATION STEPS

After implementation:

```bash
# 1. Verify compilation
cargo check --package beagle-smart-router
cargo check --package beagle-server

# 2. Test routing logic
cargo test --package beagle-smart-router

# 3. Test with each provider individually
PROVIDER=claude_code cargo run --bin test_router
PROVIDER=codex cargo run --bin test_router
PROVIDER=grok cargo run --bin test_router
PROVIDER=deepseek cargo run --bin test_router

# 4. Test fallback chain
PROVIDER=claude_code_disabled cargo run --bin test_router

# 5. Monitor costs
curl http://localhost:8080/api/metrics/costs
```

---

## 🎯 SUCCESS CRITERIA

- [ ] All 4 providers integrated
- [ ] Routing logic matches decision matrix
- [ ] Rate limiting works for all providers
- [ ] Fallback chain functions correctly
- [ ] Cost tracking accurate
- [ ] Task type detection works
- [ ] No compilation errors
- [ ] All tests pass
- [ ] Documentation updated

---

## ⏱️ ESTIMATED TIMELINE

| Task | Time |
|------|------|
| Client implementations | 2-3 hours |
| Routing logic | 1-2 hours |
| Integration & testing | 1 hour |
| Documentation | 30 minutes |
| **TOTAL** | **5-7 hours** |

---

## 🚀 NEXT STEPS

1. **Answer configuration questions** (see LLM_ROUTING_CORRECT.md)
2. **Implement client structs** (Claude, Codex, DeepSeek)
3. **Add routing decision matrix**
4. **Integrate into AppState**
5. **Test each provider individually**
6. **Test fallback chains**
7. **Deploy and monitor**

---

**Status:** Ready to implement  
**Confidence:** HIGH (clear architecture defined)  
**Blocker:** Awaiting provider preference answers  

*This is the correct foundation for BEAGLE's LLM routing. Once implemented, the system will intelligently use your subscriptions to maximum effect!*