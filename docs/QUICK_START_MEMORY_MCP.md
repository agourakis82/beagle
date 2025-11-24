# BEAGLE Memory + MCP Quick Start Guide

**TL;DR:** Your LLM/LAM (ChatGPT, Claude, Grok) can now use BEAGLE as a persistent scientific hippocampus via MCP.

---

## 🚀 5-Minute Setup

### Step 1: Start BEAGLE Core

```bash
cd /mnt/e/workspace/beagle-remote

# Ensure .env is configured with:
# DATABASE_URL=postgresql://...
# REDIS_URL=redis://...
# QDRANT_URL=http://localhost:6333 (optional but recommended)

cargo run --bin beagle-monorepo --features memory
```

### Step 2: Configure Your LLM Client

#### For Claude Desktop:

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "beagle": {
      "command": "node",
      "args": ["/mnt/e/workspace/beagle-remote/beagle-mcp-server/dist/index.js"],
      "env": {
        "BEAGLE_CORE_URL": "http://localhost:8080",
        "CLAUDE_DESKTOP_ENABLED": "true"
      }
    }
  }
}
```

Restart Claude Desktop.

#### For ChatGPT (Apps SDK):

Create an OpenAI App with this config:

```json
{
  "name": "BEAGLE",
  "mcpServers": {
    "beagle": {
      "command": "node",
      "args": ["/mnt/e/workspace/beagle-remote/beagle-mcp-server/dist/index.js"],
      "env": {
        "BEAGLE_CORE_URL": "http://localhost:8080",
        "OPENAI_APPS_SDK_ENABLED": "true"
      }
    }
  }
}
```

### Step 3: Test It!

In Claude Desktop or ChatGPT:

```
You: "Use beagle_query_memory to find recent work on PBPK modeling"
```

Expected: BEAGLE returns summarized context from past conversations and runs.

---

## 📚 Available MCP Tools

### Memory Tools

#### `beagle_query_memory`
Query BEAGLE's persistent memory (conversations, runs, experiments).

**Input:**
```json
{
  "query": "PBPK modeling with DMT",
  "scope": "scientific",  // optional: "general" | "scientific" | "pcs" | "pbpk" | "fractal"
  "max_items": 5          // optional: 1-20, default 5
}
```

**Output:**
```json
{
  "summary": "Found 3 relevant items about PBPK modeling...",
  "highlights": [
    {
      "text": "PBPK model for DMT with brain compartment...",
      "source": "conversation_xyz",
      "relevance": 0.92
    }
  ],
  "links": [
    {"type": "session", "id": "abc123", "label": "Session abc123"}
  ]
}
```

**Use when:** Starting a new session, need context about past work.

#### `beagle_ingest_chat`
Store a conversation into BEAGLE's memory for future retrieval.

**Input:**
```json
{
  "source": "chatgpt",    // "chatgpt" | "claude" | "local"
  "session_id": "conv_123",
  "turns": [
    {"role": "user", "content": "How do I implement PBPK?"},
    {"role": "assistant", "content": "Start with compartmental model..."}
  ],
  "tags": ["pbpk", "modeling"],     // optional
  "metadata": {"project": "dmt"}    // optional
}
```

**Output:**
```json
{
  "status": "ok",
  "num_turns": 2,
  "num_chunks": 2,
  "session_id": "conv_123"
}
```

**Use when:** End of important session, want to preserve conversation.

### Pipeline Tools

#### `beagle_run_pipeline`
Generate a scientific draft using BEAGLE's pipeline with Triad review.

**Input:**
```json
{
  "question": "Review PBPK models for psychedelic compounds",
  "with_triad": true  // optional, default true
}
```

**Output:**
```json
{
  "run_id": "run_abc123",
  "status": "started"
}
```

#### `beagle_get_run_summary`
Get summary and artifacts from a completed pipeline run.

**Input:**
```json
{
  "run_id": "run_abc123"
}
```

**Output:**
```json
{
  "run_id": "run_abc123",
  "question": "Review PBPK models...",
  "draft_md": "# PBPK Models for Psychedelics\n\n...",
  "triad_final_md": "# [Reviewed] PBPK Models...",
  "status": "completed"
}
```

### Feedback Tools

#### `beagle_tag_run`
Tag a pipeline run with human feedback.

**Input:**
```json
{
  "run_id": "run_abc123",
  "accepted": true,
  "rating": 9,        // optional: 0-10
  "notes": "Excellent review, very thorough"  // optional
}
```

#### `beagle_tag_experiment_run`
Tag a run as part of an experiment (e.g., Triad vs Single).

**Input:**
```json
{
  "experiment_id": "expedition_001",
  "run_id": "run_abc123",
  "condition": "triad",   // "triad" | "single" | "control"
  "notes": "Triad caught 2 factual errors"  // optional
}
```

---

## 💡 Common Workflows

### Workflow 1: Start New Project Session

```
You: "Use beagle_query_memory to find past work on PCS consciousness modeling"

[BEAGLE returns context from 3 past conversations]

You: "Great! Now use beagle_run_pipeline to generate a review of neural correlates in PCS"

[BEAGLE starts pipeline, returns run_id]

You: "Use beagle_get_run_summary with that run_id"

[BEAGLE returns completed draft]

You: "Use beagle_tag_run to mark this as accepted with rating 8"

You: "At the end, use beagle_ingest_chat to store this entire conversation with tags 'pcs' and 'neural-correlates'"
```

### Workflow 2: Experiment Tracking

```
You: "Use beagle_run_pipeline with question 'PBPK for 5-MeO-DMT' and with_triad=true"

[Run completes]

You: "Use beagle_tag_experiment_run with experiment_id='expedition_001', condition='triad'"

You: "Now run the same question with with_triad=false"

[Run completes]

You: "Tag that one with condition='single'"

You: "Use beagle_query_memory to find all runs tagged with expedition_001"
```

### Workflow 3: Knowledge Accumulation

Every few sessions:

```
You: "Use beagle_ingest_chat to store this conversation with tags matching the project"
```

Then in future sessions:

```
You: "Use beagle_query_memory to find what we decided about X"
```

This builds a **persistent research memory** across all your LAM interactions.

---

## 🔧 Troubleshooting

### BEAGLE Core Not Responding

```bash
# Check if running
curl http://localhost:8080/health

# If not, start it
cd /mnt/e/workspace/beagle-remote
cargo run --bin beagle-monorepo --features memory
```

### Memory Feature Not Working

Check `.env` has:
```bash
DATABASE_URL=postgresql://beagle_user:password@localhost:5432/beagle_dev
REDIS_URL=redis://localhost:6379/0
```

Start services:
```bash
# PostgreSQL
sudo systemctl start postgresql

# Redis
sudo systemctl start redis
```

### MCP Server Not Connecting

```bash
# Rebuild MCP server
cd /mnt/e/workspace/beagle-remote/beagle-mcp-server
npm run build

# Check it starts
node dist/index.js
```

### Query Returns No Results

- Memory needs time to index (wait 5-10 seconds after ingestion)
- Qdrant must be running if configured
- Try broader queries first ("PBPK" vs "PBPK modeling for 5-MeO-DMT with brain compartment")

---

## 🚨 Security Notes

### MCP-UPD Protection

BEAGLE implements **MCP Unintended Privacy Disclosure** protection:
- Memory query results are wrapped in `BEGIN_MEMORY_SUMMARY` / `END_MEMORY_SUMMARY` delimiters
- All outputs are sanitized to prevent prompt injection
- Input validation via Zod schemas

### Authentication

For production, set:
```bash
MCP_AUTH_TOKEN=your-secure-random-token
MCP_ENABLE_AUTH=true
```

### Rate Limiting

Built-in rate limiting prevents abuse (100 req/min per client).

---

## 📖 More Information

- **Full Documentation:** See `MEMORY_MCP_STATUS.md` for complete implementation details
- **API Reference:** See `beagle-mcp-server/README.md`
- **Test Script:** Run `./TEST_MEMORY_INTEGRATION.sh` to verify setup
- **Architecture:** See `docs/BEAGLE_v0_3_RELEASE_NOTES.md`

---

**Ready to use BEAGLE as your scientific hippocampus! 🧠🚀**
