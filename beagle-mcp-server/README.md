# BEAGLE MCP Server

**Memory & Control Plane (MCP) server** exposing BEAGLE functionality to ChatGPT (custom connector) and Claude (MCP client).

## Overview

This MCP server acts as a "façade" over the BEAGLE core HTTP API, exposing it as a standardized MCP protocol server that can be registered with:

- **ChatGPT** (Pro/Business/Enterprise) via custom connector
- **Claude** (Code/Desktop/API) via MCP client

The server implements the [MCP specification](https://platform.openai.com/docs/mcp) and provides tools for:

- **Pipeline & Triad**: Run scientific paper generation pipelines
- **Science Jobs**: Execute PBPK, Heliobiology, Scaffold, PCS, KEC computations
- **Memory**: Query persistent memory and ingest conversations
- **Feedback**: Tag runs with human feedback and experimental conditions
- **Experimental**: Serendipity Engine and Void (optional, dev/lab only)

## Installation

```bash
cd beagle-mcp-server
npm install
npm run build
```

## Configuration

Copy `.env.example` to `.env` and configure:

```bash
# BEAGLE Core HTTP endpoint
BEAGLE_CORE_URL=http://localhost:8080

# MCP Server Auth (optional but recommended)
MCP_AUTH_TOKEN=your-secret-token-here
MCP_ENABLE_AUTH=true

# Experimental features (off by default)
MCP_ENABLE_SERENDIPITY=false
MCP_ENABLE_VOID=false
```

## Running

### Development

```bash
npm run dev
```

### Production

```bash
npm run build
npm start
```

## MCP Tools

### Pipeline & Triad

- `beagle_run_pipeline`: Start a pipeline to generate a scientific draft
- `beagle_get_run_summary`: Get summary and artifacts for a pipeline run
- `beagle_list_recent_runs`: List recent pipeline runs

### Science Jobs

- `beagle_start_science_job`: Start a scientific computation job (PBPK, Helio, Scaffold, PCS, KEC)
- `beagle_get_science_job_status`: Get status of a scientific job
- `beagle_get_science_job_artifacts`: Get artifacts from a completed job

### Memory

- `beagle_query_memory`: Query BEAGLE's persistent memory (GraphRAG + embeddings)
- `beagle_ingest_chat`: Ingest a conversation into BEAGLE's memory

### Feedback

- `beagle_tag_run`: Tag a pipeline run with human feedback
- `beagle_tag_experiment_run`: Tag a run with an experimental condition

### Experimental (dev/lab only)

- `beagle_serendipity_toggle`: Toggle Serendipity Engine
- `beagle_serendipity_perturb_prompt`: Perturb a prompt using Serendipity Engine
- `beagle_void_break_loop`: Apply Void behavior to break a cognitive loop

## ChatGPT Integration

### Custom Connector Setup

1. Enable Developer Mode in ChatGPT (Pro/Business/Enterprise)
2. Create a custom connector
3. Configure:

```json
{
  "name": "BEAGLE Exocortex",
  "url": "https://your-mcp-server.com",
  "auth": {
    "type": "bearer",
    "token": "your-secret-token"
  },
  "tools": [
    "beagle_query_memory",
    "beagle_run_pipeline",
    "beagle_get_run_summary",
    "beagle_list_recent_runs",
    "beagle_tag_run"
  ]
}
```

4. Test with: "Use beagle_query_memory to find recent work on PBPK modeling"

## Claude Integration

### MCP Server Registration

1. Open Claude Code/Desktop settings
2. Add MCP server:

```json
{
  "mcpServers": {
    "beagle": {
      "url": "https://your-mcp-server.com",
      "auth": {
        "type": "bearer",
        "token": "your-secret-token"
      }
    }
  }
}
```

3. Restart Claude
4. Test: "Use MCP server: BEAGLE. Query memory for recent experiments."

## Security

### MCP-UPD Protection

The server implements protections against Unintended Privacy Disclosure:

- **Output sanitization**: Removes potential prompt injection markers
- **Memory query delimiters**: Explicitly marks memory data as DATA, not commands
- **Input validation**: Validates inputs for dangerous patterns

### Authentication

- **Bearer token**: Recommended for production
- **OAuth**: Can be added for multi-user scenarios

### TLS

For production, run behind a reverse proxy (nginx, Caddy) with TLS:

```nginx
server {
    listen 443 ssl;
    server_name your-mcp-server.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Development

### Testing

Use MCP Inspector or a test client:

```bash
# Install MCP Inspector
npm install -g @modelcontextprotocol/inspector

# Test server
mcp-inspector --server beagle-mcp-server
```

### Logging

Logs are written to stdout. Set `MCP_LOG_LEVEL` to control verbosity:

- `debug`: All logs
- `info`: Info and above (default)
- `warn`: Warnings and errors
- `error`: Errors only

## Architecture

```
ChatGPT/Claude
    ↓ (MCP Protocol)
BEAGLE MCP Server (TypeScript/Node.js)
    ↓ (HTTP)
BEAGLE Core (Rust/Axum)
    ↓
Pipeline, Triad, Memory, Jobs, etc.
```

The MCP server is a **thin adapter layer** that:
- Implements MCP protocol
- Validates inputs
- Sanitizes outputs
- Calls BEAGLE HTTP API
- Handles errors gracefully

## License

MIT

