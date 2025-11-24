# BEAGLE Architecture: Embedded CLI + No API Keys

## Overview

BEAGLE uses **embedded CLI tools** instead of API keys, leveraging your paid subscriptions directly through local command-line interfaces.

## LLM Provider Strategy (Priority Order)

### 1. Claude Code CLI (PRIMARY)
**Status:** ✅ Integrated  
**Subscription:** Claude MAX  
**Location:** `/mnt/e/workspace/beagle-remote/crates/beagle-llm/src/clients/claude_cli.rs`

```bash
# Installation
# Download from https://claude.ai/download
# Login: claude auth login
```

**How it works:**
- Executes local `claude` command
- Reads OAuth session from `~/.claude/.credentials.json`
- No API key needed
- Uses your MAX subscription rate limits

**Implementation:**
- `ClaudeCliClient` - Wraps `claude` CLI command
- `AnthropicClient::from_claude_code_session()` - OAuth token reader
- `ClaudeCodeSessionReader` - Parses credentials JSON

### 2. OpenAI Codex CLI (SECONDARY)
**Status:** ⚠️ Needs to be ported from beagle v0.4  
**Subscription:** ChatGPT Pro/Genius ($200/month)  
**Location (old):** `/mnt/e/workspace/beagle/crates/beagle-llm/src/openai/codex_cli.rs`

```bash
# Installation
npm install -g @openai/codex-cli
codex auth login  # Uses ChatGPT Pro subscription
```

**How it works:**
- Executes local `codex exec` command
- Uses ChatGPT Pro subscription authentication
- No API key needed
- Configurable reasoning effort (low, medium, high)

**Implementation (from v0.4):**
- `CodexCliClient` - Wraps `codex exec` command
- Auto-detects CLI with `which codex`
- Supports reasoning effort levels
- Fallback for non-git repos

### 3. API Key Fallback (OPTIONAL)
**Status:** ✅ Implemented  
**Purpose:** Backup when CLI tools unavailable

Environment variables (optional):
- `ANTHROPIC_API_KEY` - Anthropic API fallback
- `XAI_API_KEY` - Grok API (Tier 1/2 from TieredRouter)
- `DEEPSEEK_API_KEY` - DeepSeek V3/R1

## Current Integration Status

### ✅ Working Now (Nov 24, 2025)
1. **LLMOrchestrator** - Multi-provider routing
2. **Claude Code OAuth** - Session reader from credentials.json
3. **Claude CLI Client** - Command execution wrapper
4. **AppState Integration** - Orchestrator initialized on startup
5. **/chat/adaptive Endpoint** - Personality-aware routing

### ⚠️ To Be Added
1. **OpenAI Codex CLI** - Port from v0.4 to beagle-remote
2. **Orchestrator Priority Update** - Add Codex as tier 2
3. **DeepSeek Integration** - Requires API adapter (different interface)
4. **Grok Integration** - XAI API client

## Orchestrator Priority Logic

```rust
// Current (Anthropic only)
Priority: Claude Code OAuth > Anthropic API Key

// Target (Multi-CLI)
Priority: 
  1. Claude CLI (MAX subscription)
  2. Codex CLI (Pro subscription)  
  3. Anthropic API (fallback)
  4. Grok API (fallback)
  5. DeepSeek API (fallback)
```

## Benefits of Embedded CLI Approach

### ✅ Advantages
1. **No API Key Management** - Uses existing subscriptions
2. **Higher Rate Limits** - MAX/Pro subscription limits
3. **Cost Effective** - Unlimited (MAX) or bundled (Pro)
4. **Simpler Auth** - One-time login, persistent session
5. **Local Execution** - No network calls for auth

### ⚠️ Considerations
1. **CLI Dependency** - Requires `claude` and `codex` installed
2. **Session Expiry** - OAuth tokens expire (handled gracefully)
3. **Platform Specific** - CLI paths vary (Linux/macOS/Windows)

## Next Steps to Complete

### Phase 2A: Port Codex CLI (15-30 min)
1. Copy `/mnt/e/workspace/beagle/crates/beagle-llm/src/openai/codex_cli.rs`
2. Add to beagle-remote: `crates/beagle-llm/src/clients/openai_cli.rs`
3. Update orchestrator to include Codex in priority chain
4. Test with `codex exec` command

### Phase 2B: Update Orchestrator (10 min)
```rust
pub fn auto_configure() -> Self {
    // 1. Try Claude CLI
    let claude_cli = ClaudeCliClient::new().ok();
    
    // 2. Try Codex CLI  
    let codex_cli = CodexCliClient::new().ok();
    
    // 3. Try Claude OAuth
    let anthropic_oauth = AnthropicClient::from_claude_code_session().ok();
    
    // 4. Try API keys (fallback)
    let anthropic_api = env::var("ANTHROPIC_API_KEY")...;
    
    Self { claude_cli, codex_cli, anthropic_oauth, anthropic_api, ... }
}
```

### Phase 2C: Test Integration
```bash
# 1. Verify CLI tools installed
claude --version
codex --version

# 2. Check sessions valid
cat ~/.claude/.credentials.json
codex auth status

# 3. Start BEAGLE
cargo run --package beagle-server

# 4. Test adaptive endpoint
curl -X POST http://localhost:8080/api/v1/chat/adaptive \
  -H "Content-Type: application/json" \
  -d '{"message": "Explain PBPK modeling", "max_tokens": 512}'
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│              BEAGLE HTTP Server                 │
│            (beagle-server crate)                │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │  LLMOrchestrator   │
         │  (Multi-Provider)  │
         └────────┬───────────┘
                  │
    ┌─────────────┼─────────────┬──────────────┐
    ▼             ▼             ▼              ▼
┌─────────┐  ┌──────────┐  ┌─────────┐   ┌─────────┐
│Claude   │  │Codex CLI │  │Anthropic│   │API Key  │
│CLI      │  │(OpenAI)  │  │OAuth    │   │Fallback │
│         │  │          │  │Session  │   │(HTTP)   │
└────┬────┘  └────┬─────┘  └────┬────┘   └────┬────┘
     │            │             │             │
     ▼            ▼             ▼             ▼
  `claude`    `codex exec`  ~/.claude/    HTTPS APIs
  command      command      credentials   (backup)
```

## Configuration Files

### Claude Code Session
```
~/.claude/.credentials.json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-...",
    "refreshToken": "...",
    "expiresAt": 1234567890,
    "scopes": ["user:inference"],
    "subscriptionType": "max",
    "rateLimitTier": "default_claude_max_5x"
  }
}
```

### Environment (Optional)
```bash
# Only needed if CLI tools not available
export ANTHROPIC_API_KEY=sk-ant-api03-...
export XAI_API_KEY=...
export DEEPSEEK_API_KEY=sk-...
```

## Related Files

### Core Integration
- `crates/beagle-llm/src/orchestrator.rs` - Multi-provider router
- `crates/beagle-llm/src/clients/claude_cli.rs` - Claude CLI wrapper
- `crates/beagle-llm/src/anthropic/claude_code_session.rs` - OAuth reader
- `crates/beagle-llm/src/anthropic/client.rs` - HTTP client with OAuth
- `crates/beagle-server/src/state.rs` - AppState with orchestrator

### To Be Added
- `crates/beagle-llm/src/clients/openai_cli.rs` - Codex CLI wrapper (TODO)

### Documentation
- `CLAUDE.md` - Project instructions
- `RELEASE_NOTES_v0.10.0.md` - Version history

---

**Last Updated:** 2025-11-24  
**Status:** Phase 1 Complete (Claude CLI), Phase 2 Pending (Codex CLI)
