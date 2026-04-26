# Beagle Exocortex Connector Setup and Test Instructions

Last updated: 2026-04-26

## Public Endpoint Checklist

1. Point `mcp.agourakis.com` to the Beagle MCP service over HTTPS.
2. Verify DNS and TLS:

```bash
dig +short mcp.agourakis.com
curl -fsS https://mcp.agourakis.com/health
curl -fsS https://mcp.agourakis.com/ready
curl -fsS https://mcp.agourakis.com/.well-known/mcp
```

3. Configure Beagle MCP:

```bash
MCP_TRANSPORT=http
MCP_HTTP_PORT=3000
MCP_PUBLIC_BASE_URL=https://mcp.agourakis.com
MCP_RESOURCE_IDENTIFIER=https://mcp.agourakis.com/mcp
MCP_PUBLIC_DISCOVERY=true
MCP_TOOL_SURFACE=trusted_full
MCP_ALLOW_LEGACY_BEARER=false
MCP_RESOURCE_DOCUMENTATION_URL=https://mcp.agourakis.com/connector
```

## OAuth Checklist

Use Auth0, Stytch, or another OAuth 2.1 authorization server.

Required Beagle MCP environment:

```bash
MCP_AUTHORIZATION_SERVER_URL=https://AUTH_DOMAIN
MCP_OAUTH_ISSUER=https://AUTH_DOMAIN
MCP_OAUTH_JWKS_URI=https://AUTH_DOMAIN/.well-known/jwks.json
MCP_OAUTH_AUDIENCE=https://mcp.agourakis.com/mcp
MCP_RESOURCE_IDENTIFIER=https://mcp.agourakis.com/mcp
```

Use the exact issuer string from the OAuth provider metadata. Some providers include a trailing slash in `issuer`; Beagle validates against that exact value.

Claude hosted redirect:

```text
https://claude.ai/api/mcp/auth_callback
```

ChatGPT redirect should be copied from the ChatGPT app/connector creation page.

See [Auth0 and Claude Setup](auth0_claude_setup.md) for exact Auth0 API, scopes, Claude callback, and Kubernetes secret values.

## Protocol Smoke

Use MCP Inspector or a compatible client against:

```text
https://mcp.agourakis.com/mcp
```

Validate:

- `initialize`
- `tools/list`
- `resources/list`
- `prompts/list`
- `tools/call` for `search`
- `tools/call` for `fetch`
- `tools/call` for `beagle_exocortex_home`

## Platform Notes

Claude remote connectors are added on Claude web/Desktop and become usable on Claude mobile after connection. ChatGPT MCP apps/connectors should be tested on ChatGPT web first; current OpenAI help documentation states MCP apps are web-only, so ChatGPT iOS is not an acceptance gate for this connector yet.

## Security Smoke

```bash
curl -i https://mcp.agourakis.com/mcp
```

Expected: protected tool calls without a token return `401` with `WWW-Authenticate`.

With a token missing required scopes, protected tool calls should return `403 insufficient_scope`.

## Cluster Smoke

```bash
kubectl -n beagle rollout status deploy/beagle-mcp-server
kubectl -n beagle exec deploy/beagle-mcp-server -- wget -qO- http://localhost:3000/ready
kubectl -n beagle exec deploy/beagle-mcp-server -- wget -qO- http://localhost:3000/.well-known/mcp
```

Then restart the pod and verify that canonical JSONL state remains on the Beagle core PVC, not on the MCP pod filesystem.
