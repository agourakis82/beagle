# BEAGLE Integration Documentation Index

This directory contains comprehensive documentation for the BEAGLE Memory + MCP integration and Darwin/GraphRAG hardening instructions.

---

## 📚 Documentation Files

### 1. Memory + MCP Integration (COMPLETED)

#### **INTEGRATION_COMPLETE.md**
Executive summary confirming that the Memory + MCP integration is fully operational.

**Key Points:**
- ✅ All Rust core components implemented (MemoryEngine, HTTP endpoints, BeagleContext)
- ✅ All MCP server tools implemented (beagle_query_memory, beagle_ingest_chat, etc.)
- ✅ Full transport support (Claude Desktop, ChatGPT Apps SDK)
- ✅ Build validation passed

**Status:** PRODUCTION READY

---

#### **MEMORY_MCP_STATUS.md**
Complete 350+ line technical status report.

**Contents:**
- Architecture diagrams
- Implementation checklist (all ✅)
- Component details:
  - Rust: ChatSession, MemoryEngine, HTTP endpoints
  - TypeScript: BeagleClient, MCP tools, transports
- Configuration requirements
- Testing guide
- Performance & scalability notes
- Security considerations (MCP-UPD protection)
- Optional enhancements

**Audience:** Technical contributors, system architects

---

#### **QUICK_START_MEMORY_MCP.md**
User-friendly quick start guide.

**Contents:**
- 5-minute setup instructions
- Configuration for Claude Desktop & ChatGPT
- Complete tool reference with examples:
  - beagle_query_memory
  - beagle_ingest_chat
  - beagle_run_pipeline
  - beagle_tag_run
  - beagle_tag_experiment_run
- Common workflows (3 scenarios)
- Troubleshooting guide
- Security notes

**Audience:** End users, researchers

---

#### **TEST_MEMORY_INTEGRATION.sh**
Automated end-to-end test script.

**Tests:**
1. Health endpoint validation
2. Chat ingestion (POST /api/memory/ingest_chat)
3. Memory query (POST /api/memory/query)
4. Keyword-specific query validation

**Usage:**
```bash
./TEST_MEMORY_INTEGRATION.sh
```

**Audience:** QA, DevOps, CI/CD

---

#### **beagle-mcp-server/.env.example**
Configuration template for MCP server.

**Variables:**
- BEAGLE_CORE_URL
- MCP_AUTH_TOKEN
- MCP_TRANSPORT
- MCP_CLIENT_TYPE
- OPENAI_APPS_SDK_ENABLED
- CLAUDE_DESKTOP_ENABLED
- Experimental feature flags
- Logging configuration

**Audience:** System administrators, deployment engineers

---

### 2. Darwin Integration & GraphRAG Hardening (TODO)

#### **CLAUDE_CODE_ZED_PROMPT_DARWIN_INTEGRATION.md**
Surgical instructions for Claude Code in Zed to implement Darwin/GraphRAG hardening.

**Objectives:**
1. Complete Qdrant & Neo4j integration (real data, not stubs)
2. Wire DarwinCore into pipeline (eliminate duplication)
3. Implement robust degraded modes (no panics)
4. Close memory loop (pipeline → hypergraph/vector store)
5. Add auto-Triad support in pipeline
6. Maintain 100% Rust/Julia stack
7. Preserve all existing tests/experiments

**Deliverables:**
- Working Qdrant/Neo4j adapters with KnowledgeSnippet abstraction
- Unified DarwinCore API (GraphRAG + Self-RAG)
- Graceful fallbacks (NoOpVectorStore, NoOpGraphStore, Observer disabled)
- MemoryIngestor for pipeline/triad runs
- Auto-Triad configuration flag
- Updated documentation (BEAGLE_CORE_v0_3.md, DARWIN_CORE.md)

**Audience:** Claude Code in Zed, core contributors

---

## 🗺️ Integration Architecture

### Current State (Memory + MCP)

```
┌─────────────────────────────────────────┐
│  LLM/LAM Clients                       │
│  (ChatGPT, Claude Desktop, Grok, etc.) │
└────────────┬────────────────────────────┘
             │ MCP Protocol (STDIO/HTTP)
             ▼
┌─────────────────────────────────────────┐
│  BEAGLE MCP Server (TypeScript)        │
│  - @modelcontextprotocol/sdk v1.22.0   │
│  - Tools: query_memory, ingest_chat    │
└────────────┬────────────────────────────┘
             │ HTTP/JSON
             ▼
┌─────────────────────────────────────────┐
│  BEAGLE Core HTTP API (Rust/Axum)      │
│  - POST /api/memory/ingest_chat        │
│  - POST /api/memory/query              │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│  MemoryEngine (Rust)                   │
│  - ContextBridge (hypergraph)          │
│  - Embeddings → Qdrant (vectors)       │
│  - Postgres + Redis (storage + cache)  │
└─────────────────────────────────────────┘
```

### Target State (Darwin + Memory Loop)

```
┌─────────────────────────────────────────┐
│  Pipeline / Triad Run                  │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│  Context Building (Ordered)            │
│  1. Memory RAG (past sessions)         │
│  2. Darwin GraphRAG (Qdrant + Neo4j)   │
│  3. Serendipity (optional)             │
│  4. Observer (HRV-aware)               │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│  HERMES (Draft Generation)             │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│  Auto-Triad (Optional)                 │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│  Memory Ingestion                      │
│  - MemoryIngestor::ingest_pipeline_run │
│  - Store in Qdrant + Hypergraph        │
└─────────────────────────────────────────┘
```

---

## 📋 Next Steps

### Immediate (Darwin Integration)

1. **Run the Darwin prompt in Zed:**
   ```bash
   # Open Zed in beagle-remote
   cd /mnt/e/workspace/beagle-remote
   
   # Paste CLAUDE_CODE_ZED_PROMPT_DARWIN_INTEGRATION.md into Claude Code
   ```

2. **Validate implementation:**
   ```bash
   cargo check --workspace
   cargo test --workspace
   ./TEST_MEMORY_INTEGRATION.sh
   ```

3. **Review generated docs:**
   - `docs/BEAGLE_CORE_v0_3.md`
   - `docs/DARWIN_CORE.md`

### Medium-Term (Production Deployment)

1. **Configure services:**
   - PostgreSQL (for hypergraph)
   - Redis (for caching)
   - Qdrant (for vector search)
   - Neo4j (optional, for graph traversal)

2. **Deploy BEAGLE Core:**
   ```bash
   cargo run --bin beagle-monorepo --features memory --release
   ```

3. **Configure LLM clients:**
   - Claude Desktop: Edit `~/Library/Application Support/Claude/claude_desktop_config.json`
   - ChatGPT: Create OpenAI App with MCP server

4. **Monitor & iterate:**
   - Track memory ingestion quality
   - Validate Darwin context relevance
   - Monitor HRV-aware behavior
   - Collect experiment results (Expedition 001)

### Long-Term (Research & Extensions)

1. **Enhanced summarization:**
   - Use BEAGLE router for LLM-based memory summaries
   - Implement query expansion

2. **Advanced filtering:**
   - Date ranges
   - Source filters
   - Tag-based queries
   - Project scopes

3. **Graph traversal:**
   - Neo4j-based concept expansion
   - Multi-hop reasoning

4. **Auto-ingestion:**
   - Automatic MCP session capture
   - Intelligent deduplication

---

## 🔗 Cross-References

### Related Documentation

- **Core Architecture:** `docs/BEAGLE_v0_3_RELEASE_NOTES.md`
- **Experiments:** `docs/BEAGLE_EXPERIMENTS_v1.md`
- **Expedition 001:** `docs/BEAGLE_EXPEDITION_001.md`
- **Observer 2.0:** `crates/beagle-observer/README.md`
- **MCP Server:** `beagle-mcp-server/README.md`

### Configuration Files

- **BEAGLE Core:** `.env.example`
- **MCP Server:** `beagle-mcp-server/.env.example`
- **Workspace:** `Cargo.toml`

### Test Scripts

- **Memory Integration:** `TEST_MEMORY_INTEGRATION.sh`
- **Experiments:** `scripts/run_experiment.sh` (if exists)

---

## 📞 Support & Contact

For questions or issues:

1. **Check documentation:** Start with `QUICK_START_MEMORY_MCP.md`
2. **Run tests:** `./TEST_MEMORY_INTEGRATION.sh`
3. **Review logs:** Check BEAGLE Core and MCP Server logs
4. **Consult architecture:** See `MEMORY_MCP_STATUS.md`

---

**Last Updated:** 2025-11-22  
**Status:** Memory + MCP ✅ COMPLETE | Darwin Integration ⏳ READY FOR IMPLEMENTATION
