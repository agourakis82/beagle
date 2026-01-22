# MCP Endpoints Analysis (BEAGLE v0.27.x)

This document captures the current MCP transport implementation and externally visible HTTP endpoints for the BEAGLE MCP server.

## Entry point

- Server entry point: `beagle-mcp-server/src/index.ts`
- MCP SDK: `@modelcontextprotocol/sdk`
  - `Server` API: `@modelcontextprotocol/sdk/server/index.js`
  - Transports in use:
    - `StdioServerTransport` (`@modelcontextprotocol/sdk/server/stdio.js`)
    - `StreamableHTTPServerTransport` (`@modelcontextprotocol/sdk/server/streamableHttp.js`)

## Transport selection

Transport is selected in `beagle-mcp-server/src/index.ts` via:

- `MCP_TRANSPORT=http|stdio` (explicit override)
- Client detection heuristics (`beagle-mcp-server/src/compat.ts`)
  - ChatGPT/OpenAI Apps defaults to `http` if `OPENAI_APPS_SDK_ENABLED=true`
  - Otherwise defaults to `stdio`

## HTTP server endpoints (transport = http)

The HTTP server is implemented using Node’s built-in `http` module (`createServer`), not Express/Fastify.

Default bind configuration (env-controlled):

- `MCP_HTTP_HOST` (default: `0.0.0.0`)
- `MCP_HTTP_PORT` (default: `3000`)
- `MCP_HTTP_PATH` (default: `/mcp`)

Endpoints currently exposed:

- `GET /health`
  - Returns `{ "status": "ok" }`
  - Used for liveness checks and tunnel verification.
- `POST|GET /mcp` (via `StreamableHTTPServerTransport`)
  - MCP “Streamable HTTP” transport endpoint.
  - Session IDs are enabled via `sessionIdGenerator: () => randomUUID()`.
  - Optional DNS rebinding protection:
    - `MCP_HTTP_DNS_REBINDING_PROTECTION=true`
    - `MCP_HTTP_ALLOWED_HOSTS=...`
    - `MCP_HTTP_ALLOWED_ORIGINS=...`
- Legacy SSE transport (for older clients):
  - `GET /sse` (env: `MCP_SSE_PATH`, default: `/sse`)
  - `POST /message?sessionId=...` (env: `MCP_SSE_MESSAGE_PATH`, default: `/message`)
  - Note: this transport is deprecated in the MCP SDK, but remains useful for compatibility.
- Optional GitHub webhook proxy:
  - Enabled by: `MCP_GITHUB_WEBHOOK_PROXY_ENABLED=true`
  - Path: `MCP_GITHUB_WEBHOOK_PATH` (default: `/webhooks/github/push`)
  - Forwards to BEAGLE Core: `POST {BEAGLE_CORE_URL}/webhooks/github/push`

Notes:
- There is no standalone `/tools` HTTP endpoint; tool listing is served through the MCP protocol (`ListToolsRequestSchema`).

## Auth / rate limiting

Tool-call auth is implemented in `beagle-mcp-server/src/auth.ts`:

- `MCP_ENABLE_AUTH=true` enables bearer-token auth.
- `MCP_AUTH_TOKEN=<token>` is the shared secret.
- Rate limiting: simple in-memory token bucket (per client identifier), applied on tool calls.

Implementation detail:
- Auth is currently enforced in the MCP request handler for tool calls (`CallToolRequestSchema`) via `Authorization` header (or `meta.authorization` when present).
- In HTTP mode, the server can also enforce auth at the endpoint layer for `/mcp`, `/sse`, and `/message` (recommended when exposing publicly).

## Tool registry

Tools are registered by composing multiple tool groups:

- Registry: `beagle-mcp-server/src/tools/index.ts`
  - `llmTools`, `pipelineTools`, `memoryTools`, `feedbackTools`
  - `scienceJobTools`, `darwinTools`, `exocortexTools`, `observerTools`, `voiceTools`, `experimentalTools`

The Darwin “ResearchOps” tool surface (nightly workflows, indexer/harvest/brief/eval, etc.) is primarily defined in:

- `beagle-mcp-server/src/tools/darwin.ts`
