# BEAGLE MCP Server

**Production-ready Model Context Protocol (MCP) server** exposing BEAGLE exocortex functionality to:
- **Claude Desktop** (via STDIO transport)
- **ChatGPT Apps** (via Apps SDK / HTTP transport)

## Overview

This MCP server acts as a **thin, type-safe adapter** between AI assistants (Claude, ChatGPT) and the BEAGLE Core HTTP API, providing:

- ✅ **6 canonical tools** for memory, pipelines, and LLM routing
- ✅ **Automatic retries** with exponential backoff
- ✅ **Configurable timeouts** (default: 60s)
- ✅ **Graceful degradation** when BEAGLE core is unavailable
- ✅ **Dual transport support** (STDIO + HTTP)
- ✅ **Type-safe schemas** with Zod validation
- ✅ **Production logging** and error handling

---

## Canonical Tools

| Tool | Description | Key Inputs | Outputs |
|------|-------------|-----------|---------|
| `beagle_llm_complete` | Proxy LLM via TieredRouter | `prompt`, `requires_math`, `requires_high_quality` | `text`, `provider`, `llm_stats` |
| `beagle_pipeline_run` | Start BEAGLE pipeline | `question`, `with_triad`, `hrv_aware` | `run_id`, `status` |
| `beagle_pipeline_status` | Check pipeline status | `run_id` | `status`, `artifacts`, `llm_stats` |
| `beagle_memory_query` | Memory RAG search | `query`, `top_k` | `results[]` with snippets |
| `beagle_memory_ingest_chat` | Ingest conversation | `source`, `conversation_id`, `role`, `text` | `stored`, `memory_id` |
| `beagle_feedback_tag` | Tag run with feedback | `run_id`, `accepted`, `rating_0_10` | `status`, `run_id` |

---

## Installation

### Prerequisites

- **Node.js** >= 18.0.0
- **BEAGLE Core** running at `http://localhost:8080` (or custom URL)

### Setup

```bash
# Clone or navigate to the MCP server directory
cd beagle-mcp-server

# Install dependencies
npm install

# Copy environment template
cp .env.example .env

# Edit .env to set BEAGLE_CORE_URL (if not localhost:8080)
nano .env

# Build TypeScript
npm run build
```

---

## Usage

### For Claude Desktop

#### 1. Configure Claude Desktop MCP

Create or edit `~/.config/Claude/claude_desktop_config.json` (macOS/Linux) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "beagle": {
      "command": "node",
      "args": ["/absolute/path/to/beagle-mcp-server/dist/index.js"],
      "env": {
        "BEAGLE_CORE_URL": "http://localhost:8080"
      }
    }
  }
}
```

#### 2. Restart Claude Desktop

The MCP server will start automatically when you open a conversation.

#### 3. Verify Connection

In Claude Desktop, type:
```
Use beagle_memory_query to search for "test"
```

If the tool is available, you'll see it in the autocomplete.

---

### For ChatGPT Apps (Apps SDK)

#### 1. Set Environment Variables

```bash
export BEAGLE_CORE_URL=http://localhost:8080
export OPENAI_APPS_SDK_ENABLED=true
export MCP_TRANSPORT=http
export MCP_HTTP_PORT=3000
```

#### 2. Start HTTP Server

```bash
npm run start
# Server listening on http://localhost:3000/mcp
```

#### 3. Configure ChatGPT App

In your ChatGPT App manifest, add the MCP server endpoint:

```json
{
  "mcp_servers": {
    "beagle": {
      "url": "http://localhost:3000/mcp",
      "description": "BEAGLE exocortex for memory and pipeline control"
    }
  }
}
```

---

## Configuration

### Environment Variables

See `.env.example` for all available options. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `BEAGLE_CORE_URL` | `http://localhost:8080` | BEAGLE Core API base URL |
| `MCP_AUTH_TOKEN` | (empty) | Optional auth token for BEAGLE Core |
| `HTTP_TIMEOUT` | `60000` | Request timeout in milliseconds |
| `HTTP_MAX_RETRIES` | `2` | Max retry attempts for failed requests |
| `MCP_TRANSPORT` | `stdio` | Transport protocol (`stdio` or `http`) |
| `OPENAI_APPS_SDK_ENABLED` | `false` | Enable ChatGPT Apps SDK mode |

### Timeouts by Tool

Default timeout is 60s. For long-running operations (like pipeline runs), timeouts are automatically extended:

- `beagle_llm_complete`: 30s
- `beagle_pipeline_run`: 120s (just starts the pipeline, doesn't wait)
- `beagle_pipeline_status`: 10s
- `beagle_memory_query`: 15s
- `beagle_memory_ingest_chat`: 30s
- `beagle_feedback_tag`: 10s

---

## Development

### Project Structure

```
beagle-mcp-server/
├── src/
│   ├── index.ts              # Main server entry point
│   ├── beagle-client.ts      # HTTP client with retry/timeout
│   ├── compat.ts             # Client type detection
│   ├── logger.ts             # Structured logging
│   ├── security.ts           # Output sanitization
│   ├── auth.ts               # Auth validation (optional)
│   ├── tools/
│   │   ├── index.ts          # Tool registry
│   │   ├── llm.ts            # beagle_llm_complete
│   │   ├── pipeline.ts       # beagle_pipeline_run, beagle_pipeline_status
│   │   ├── memory.ts         # beagle_memory_query, beagle_memory_ingest_chat
│   │   └── feedback.ts       # beagle_feedback_tag
│   └── transports/
│       ├── claude-desktop.ts # STDIO transport config
│       └── openai-apps.ts    # HTTP transport config
├── dist/                     # Compiled JavaScript
├── package.json
├── tsconfig.json
├── .env.example
└── README.md
```

### Scripts

```bash
# Development with auto-reload
npm run dev

# Build for production
npm run build

# Build for specific client
npm run build:claude
npm run build:chatgpt

# Start production server
npm start

# Run integration tests (requires BEAGLE core running)
npm run test:mcp
```

### Adding New Tools

1. Create tool definition in `src/tools/my-tool.ts`:

```typescript
import { z } from 'zod';
import { BeagleClient } from '../beagle-client.js';
import { McpTool } from './index.js';

const MyToolSchema = z.object({
  param: z.string(),
});

export function myTools(client: BeagleClient): McpTool[] {
  return [
    {
      name: 'beagle_my_tool',
      description: 'Description for AI to understand when to use this',
      inputSchema: {
        type: 'object',
        properties: {
          param: { type: 'string', description: 'Parameter description' },
        },
        required: ['param'],
      },
      handler: async (args: unknown) => {
        const { param } = MyToolSchema.parse(args);
        const result = await client.myApiCall(param);
        return { success: true, data: result };
      },
    },
  ];
}
```

2. Add to `src/tools/index.ts`:

```typescript
import { myTools } from './my-tool.js';

export function defineTools(client: BeagleClient): McpTool[] {
  return [
    ...llmTools(client),
    ...pipelineTools(client),
    ...memoryTools(client),
    ...feedbackTools(client),
    ...myTools(client), // ← Add here
  ];
}
```

3. Add corresponding method to `BeagleClient` in `src/beagle-client.ts`.

---

## Integration Tests

Tests assume BEAGLE Core is running at `BEAGLE_CORE_URL`.

### Run Tests

```bash
# Start BEAGLE Core first
cd /path/to/beagle
cargo run --bin beagle-server

# In another terminal, run MCP tests
cd beagle-mcp-server
npm run test:mcp
```

### Test Coverage

Tests cover:
- ✅ `beagle_llm_complete` - LLM proxy with simple prompt
- ✅ `beagle_pipeline_run` + `beagle_pipeline_status` - End-to-end pipeline
- ✅ `beagle_memory_ingest_chat` + `beagle_memory_query` - Memory round-trip
- ✅ `beagle_feedback_tag` - Run tagging

---

## Troubleshooting

### "Connection refused" or "ECONNREFUSED"

**Problem**: MCP server can't reach BEAGLE Core.

**Solution**:
1. Check BEAGLE Core is running: `curl http://localhost:8080/health`
2. Verify `BEAGLE_CORE_URL` in `.env` matches actual URL
3. Check firewall settings

### "Request timeout after 60000ms"

**Problem**: BEAGLE Core is slow or unresponsive.

**Solution**:
1. Increase timeout: `HTTP_TIMEOUT=120000` in `.env`
2. Check BEAGLE Core logs for errors
3. Ensure BEAGLE has access to external services (Qdrant, Neo4j, LLM APIs)

### Tools not appearing in Claude Desktop

**Problem**: MCP server not loading or crashed.

**Solution**:
1. Check Claude Desktop logs (Help → View Logs)
2. Test MCP server manually: `node dist/index.js`
3. Verify `claude_desktop_config.json` has correct path
4. Ensure Node.js >= 18 is installed

### ChatGPT Apps can't connect

**Problem**: HTTP server not reachable.

**Solution**:
1. Verify `MCP_TRANSPORT=http` in `.env`
2. Check server is running: `curl http://localhost:3000/mcp`
3. Ensure `MCP_HTTP_PORT` matches Apps SDK config
4. Check CORS settings if accessing from browser

---

## Architecture

### HTTP Client (beagle-client.ts)

- **Automatic retries**: Exponential backoff for 5xx and network errors
- **Smart timeout**: Configurable per-request
- **Error classification**: Don't retry 4xx client errors
- **Logging**: Structured logs for debugging

### Transport Layer

- **STDIO**: For Claude Desktop local MCP servers
- **HTTP**: For ChatGPT Apps SDK via streamable HTTP transport
- **Auto-detection**: Client type detection via environment or request metadata

### Security

- **Output sanitization**: Prevents injection attacks
- **Rate limiting**: Configurable per-client limits
- **Auth support**: Optional token-based authentication
- **Input validation**: Zod schemas for all tool inputs

---

## API Contract with BEAGLE Core

This MCP server expects the following HTTP endpoints from BEAGLE Core:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/llm/complete` | POST | LLM completion via TieredRouter |
| `/api/pipeline/start` | POST | Start pipeline run |
| `/api/pipeline/status/:run_id` | GET | Get pipeline status |
| `/api/run/:run_id/artifacts` | GET | Get run artifacts |
| `/api/runs/recent` | GET | List recent runs |
| `/api/memory/query` | POST | Memory RAG search |
| `/api/memory/ingest_chat` | POST | Ingest conversation turn |
| `/api/feedback/tag_run` | POST | Tag run with feedback |

If any endpoint is missing, the corresponding tool will fail gracefully with a descriptive error.

---

## License

MIT

---

## Contributing

1. Follow existing code style (TypeScript + Prettier)
2. Add tests for new tools
3. Update this README if adding features
4. Ensure `npm run build` passes without errors

---

## Links

- **MCP Specification**: https://modelcontextprotocol.io/
- **Anthropic MCP Docs**: https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-mcp
- **OpenAI Apps SDK**: https://developers.openai.com/apps-sdk
- **BEAGLE Project**: (add link to main BEAGLE docs)

---

**Version**: 0.3.0  
**Last Updated**: 2025-11-22
