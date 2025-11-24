# Beagle-Darwin vs Beagle-Darwin-Core Comparison 🧬

**Date**: 2025-11-23
**Purpose**: Clarify the relationship and differences between two closely related crates

---

## Quick Summary

| Aspect | beagle-darwin | beagle-darwin-core |
|--------|---------------|-------------------|
| **Type** | Core library | HTTP API wrapper |
| **Lines** | 374 lines | 212 lines |
| **Purpose** | GraphRAG + Self-RAG + Plugin logic | REST endpoints for GraphRAG/Self-RAG/Plugins |
| **Framework** | None (pure Rust) | Axum (HTTP) |
| **Usage** | Direct function calls | HTTP POST requests |
| **Tests** | 2 unit tests | 3 HTTP endpoint tests |
| **Dependency** | No internal beagle-*-core | Depends on beagle-darwin |

---

## Architecture Pattern

This follows the classic **library + service wrapper** pattern:

```
┌─────────────────────────────────────────┐
│      beagle-darwin-core (HTTP)          │
│  (Axum routes + JSON serialization)     │
└──────────────┬──────────────────────────┘
               │ depends on
               ↓
┌─────────────────────────────────────────┐
│      beagle-darwin (Core Library)       │
│  (DarwinCore struct + methods)          │
└──────────────┬──────────────────────────┘
               │ depends on
               ↓
┌─────────────────────────────────────────┐
│   beagle-smart-router, beagle-llm, etc. │
└─────────────────────────────────────────┘
```

---

## Detailed Comparison

### beagle-darwin: Core Library 📚

**Primary Purpose**: Implement GraphRAG + Self-RAG + Plugin system logic

**Main Component**: `DarwinCore` struct

```rust
pub struct DarwinCore {
    pub graph_rag_enabled: bool,
    pub self_rag_enabled: bool,
    ctx: Option<Arc<BeagleContext>>,
    vllm_client: VllmClient,
}
```

**Public Methods**:

| Method | Purpose | Returns |
|--------|---------|---------|
| `new()` | Create instance (legacy mode) | `Self` |
| `with_context()` | Create with BeagleContext | `Self` |
| `graph_rag_query()` | Query knowledge graph (neo4j + qdrant) | `String` |
| `self_rag()` | Evaluate confidence + refine | `String` |
| `run_with_plugin()` | Switch LLM backend at runtime | `String` |
| `enhanced_cycle()` | Full pipeline (GraphRAG + Self-RAG) | `Result<DarwinContext>` |

**Features**:

1. **GraphRAG** (lines 79-153)
   - Query vector store (Qdrant) for semantic search
   - Query knowledge graph (Neo4j) for structured relations
   - Combine results into enriched context
   - Pass to LLM for reasoning

2. **Self-RAG** (lines 155-203)
   - Evaluate confidence of initial answer (0-100)
   - If confidence < 85: Generate new search query
   - If confidence >= 85: Accept current answer
   - Optionally refine based on gatekeeper evaluation

3. **Plugin System** (lines 205-232)
   - Support multiple LLM backends:
     - `"grok3"`: Grok 3 via SmartRouter (128k context, unlimited)
     - `"local70b"`: vLLM local Llama-3.3-70B
     - `"heavy"`: Grok 4.1 Heavy (256k context, quota)
   - Switch at runtime without code changes

4. **Enhanced Cycle** (lines 234-289)
   - Orchestrates GraphRAG → Self-RAG → Snippets
   - Returns structured `DarwinContext` with metadata
   - Supports both legacy and BeagleContext modes

**Data Structures**:

```rust
pub struct DarwinContext {
    pub combined_text: String,      // Final answer
    pub snippets: Vec<KnowledgeSnippet>,  // Metadata
    pub confidence: Option<u64>,    // Self-RAG score
}
```

**Usage Example**:

```rust
// Direct library usage
let darwin = DarwinCore::new();
let answer = darwin.graph_rag_query("What is consciousness?").await;
let refined = darwin.self_rag(&answer, "What is consciousness?").await;
```

**Tests**: 2 tests
- `test_darwin_core_creation` - Verify instantiation
- `test_plugin_system` - Verify plugin switching works

---

### beagle-darwin-core: HTTP API Layer 🌐

**Primary Purpose**: Expose `DarwinCore` functionality as REST endpoints

**Main Component**: `darwin_routes()` function

```rust
pub fn darwin_routes() -> Router {
    Router::new()
        .route("/darwin/rag", post(graph_rag_handler))
        .route("/darwin/self-rag", post(self_rag_handler))
        .route("/darwin/plugin", post(plugin_handler))
}
```

**Endpoints**:

| Endpoint | Method | Request | Response |
|----------|--------|---------|----------|
| `/darwin/rag` | POST | `RagRequest` | `RagResponse` |
| `/darwin/self-rag` | POST | `SelfRagRequest` | `RagResponse` |
| `/darwin/plugin` | POST | `PluginRequest` | `PluginResponse` |

**Request/Response Structures**:

```rust
// GraphRAG endpoint
pub struct RagRequest {
    pub question: String,
    pub context_tokens: Option<usize>,
}

pub struct RagResponse {
    pub answer: String,
    pub sources: Vec<String>,  // neo4j, qdrant URLs
    pub confidence: Option<f64>,
}

// Self-RAG endpoint
pub struct SelfRagRequest {
    pub question: String,
    pub initial_answer: Option<String>,
}

// Plugin endpoint
pub struct PluginRequest {
    pub prompt: String,
    pub plugin: String,  // "grok3", "local70b", "heavy"
}

pub struct PluginResponse {
    pub result: String,
    pub plugin_used: String,
}
```

**Handler Implementation**:

1. **graph_rag_handler** (lines 67-81)
   - Receives `RagRequest`
   - Calls `DarwinCore::graph_rag_query()`
   - Returns `RagResponse` with answer + sources

2. **self_rag_handler** (lines 84-112)
   - Receives `SelfRagRequest`
   - If no initial answer: calls GraphRAG first
   - Then calls `DarwinCore::self_rag()`
   - Returns refined answer

3. **plugin_handler** (lines 115-131)
   - Receives `PluginRequest`
   - Calls `DarwinCore::run_with_plugin()`
   - Returns result with plugin name

**Usage Example**:

```rust
// HTTP API usage
POST /darwin/rag
{
  "question": "What is consciousness?"
}

// Response:
{
  "answer": "...",
  "sources": ["neo4j://...", "qdrant://..."],
  "confidence": 85.0
}
```

**Integration**:

Can be merged into any Axum server:

```rust
let app = Router::new()
    .merge(beagle_routes())
    .merge(beagle_darwin_core::darwin_routes());
```

**Tests**: 3 tests
- `test_rag_endpoint` - Verify `/darwin/rag` works
- `test_self_rag_endpoint` - Verify `/darwin/self-rag` works
- `test_plugin_endpoint` - Verify `/darwin/plugin` works

---

## Data Flow Comparison

### beagle-darwin (Library)

```
User Code
   ↓
DarwinCore::graph_rag_query()
   ├─ Vector store (Qdrant): query()
   ├─ Graph store (Neo4j): cypher_query()
   ├─ LLM: complete()
   └─ Returns: String
   ↓
User Code processes result
```

### beagle-darwin-core (HTTP API)

```
HTTP Client (curl, frontend, etc.)
   ↓
POST /darwin/rag {question}
   ↓
graph_rag_handler()
   ├─ Deserialize JSON → RagRequest
   ├─ DarwinCore::graph_rag_query()
   ├─ Serialize → RagResponse JSON
   └─ HTTP 200
   ↓
HTTP Client receives JSON
```

---

## When to Use Each

### Use **beagle-darwin** (Library) when:

✅ You need programmatic access to GraphRAG/Self-RAG in your Rust code
✅ You're building internal tools that don't need HTTP
✅ You want fine-grained control (calling individual methods)
✅ You're integrating into a larger Rust application
✅ You need zero-copy performance

**Example**:
```rust
let darwin = DarwinCore::with_context(ctx);
let result = darwin.enhanced_cycle("question").await?;
process_result(&result);
```

### Use **beagle-darwin-core** (HTTP API) when:

✅ You need to expose Darwin to non-Rust clients (JavaScript, Python, etc.)
✅ You're building a microservice architecture
✅ You want simple HTTP endpoints instead of code integration
✅ You're building a web frontend that needs Darwin
✅ You need to scale Darwin as a separate service

**Example**:
```bash
curl -X POST http://localhost:3000/darwin/rag \
  -H "Content-Type: application/json" \
  -d '{"question": "What is consciousness?"}'
```

---

## Dependency Relationship

```
beagle-darwin-core
  ├─ Depends on: beagle-darwin ✅
  ├─ Depends on: axum (HTTP framework)
  ├─ Depends on: serde_json (serialization)
  └─ Depends on: beagle-smart-router

beagle-darwin
  ├─ Depends on: beagle-core (BeagleContext, KnowledgeSnippet)
  ├─ Depends on: beagle-smart-router (query_smart)
  ├─ Depends on: beagle-llm (VllmClient)
  └─ Does NOT depend on: beagle-darwin-core ✅
```

**Key Point**: beagle-darwin is independent; beagle-darwin-core depends on it. This is the correct dependency direction.

---

## Cargo.toml Dependencies

### beagle-darwin

```toml
[dependencies]
tokio.workspace = true
tracing.workspace = true
serde.workspace = true
serde_json.workspace = true
reqwest.workspace = true
anyhow.workspace = true

# Internal dependencies
beagle-grok-api = { path = "../beagle-grok-api" }
beagle-smart-router = { path = "../beagle-smart-router" }
beagle-agents = { path = "../beagle-agents" }
beagle-llm = { path = "../beagle-llm" }
beagle-core = { path = "../beagle-core" }
beagle-config = { path = "../beagle-config" }
```

**No Axum** - Pure core library

### beagle-darwin-core

```toml
[dependencies]
tokio.workspace = true
axum.workspace = true           # ← Added for HTTP
serde.workspace = true
serde_json.workspace = true
tracing.workspace = true
anyhow.workspace = true

# Internal dependencies
beagle-grok-api = { path = "../beagle-grok-api" }
beagle-smart-router = { path = "../beagle-smart-router" }
beagle-darwin = { path = "../beagle-darwin" }  # ← Uses the library
```

**Includes Axum** - Web framework wrapper

---

## Code Organization

### beagle-darwin (374 lines)

```
Line    Component
────────────────────────────
1-15    Module documentation + usage example
17-21   Imports
23-32   DarwinContext struct definition
34-40   DarwinCore struct definition
42-71   Constructors (new, with_context)
73-153  GraphRAG implementation
155-203 Self-RAG implementation
205-232 Plugin system
234-289 Enhanced cycle orchestration
291-317 vLLM query helper
319-354 Public async function (darwin_enhanced_cycle)
356-374 Tests
```

### beagle-darwin-core (212 lines)

```
Line    Component
────────────────────────────
1-22    Module documentation + usage examples
24-28   Imports
30-64   Request/Response DTOs (6 structs)
67-81   GraphRAG handler
84-112  Self-RAG handler
115-131 Plugin handler
133-142 Router construction
144-212 Endpoint tests
```

---

## Integration Points

### In beagle-bin

Both crates should be integrated:

```rust
// Use library for programmatic access
use beagle_darwin::DarwinCore;

// Use HTTP API for exposing to frontend
use beagle_darwin_core::darwin_routes;

// In main server setup:
let app = Router::new()
    .merge(beagle_routes())
    .merge(darwin_routes());  // ← Adds /darwin/* endpoints

// For internal code:
let darwin = DarwinCore::with_context(ctx);
let result = darwin.enhanced_cycle(question).await?;
```

### In beagle-server

```rust
let app = Router::new()
    .merge(auth_routes())
    .merge(health_routes())
    .merge(darwin_routes())  // ← HTTP endpoints
    .with_state(app_state);
```

---

## Summary Table

| Feature | beagle-darwin | beagle-darwin-core |
|---------|---------------|-------------------|
| **GraphRAG** | ✅ Full implementation | ✅ Exposed as endpoint |
| **Self-RAG** | ✅ Full implementation | ✅ Exposed as endpoint |
| **Plugin System** | ✅ Full implementation | ✅ Exposed as endpoint |
| **BeagleContext** | ✅ Supported | ⚠️ Via library only |
| **HTTP Endpoints** | ❌ None | ✅ `/darwin/*` |
| **REST API** | ❌ No | ✅ Yes |
| **Direct Rust Usage** | ✅ Yes | ⚠️ Via beagle-darwin |
| **Lines of Code** | 374 | 212 |
| **Dependencies** | Core libs | Core libs + Axum + beagle-darwin |
| **Tests** | 2 unit tests | 3 HTTP tests |

---

## Recommendation

**Both crates should exist and be used:**

1. ✅ **beagle-darwin** (library) for:
   - Internal programmatic use
   - Non-HTTP integrations
   - Direct function calls with full control

2. ✅ **beagle-darwin-core** (HTTP) for:
   - External access (frontend, other services)
   - Simple JSON APIs
   - Service-oriented architecture

**Current Status**: 🟢 **Correctly designed**

The separation of concerns is clean:
- Library owns the logic
- HTTP wrapper is thin and focused on HTTP concerns
- No circular dependencies
- Proper layering

No changes needed - this is good architecture!

---

## File References

| File | Purpose |
|------|---------|
| `crates/beagle-darwin/src/lib.rs` | Core GraphRAG/Self-RAG/Plugin logic |
| `crates/beagle-darwin-core/src/lib.rs` | HTTP API endpoints |
| `crates/beagle-darwin/Cargo.toml` | Library dependencies |
| `crates/beagle-darwin-core/Cargo.toml` | HTTP API dependencies |
