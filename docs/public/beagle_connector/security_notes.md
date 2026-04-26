# Beagle Exocortex Connector Security Notes

Last updated: 2026-04-26

## Trust Boundary

Beagle MCP is a resource server. The cluster remains the source of truth; Claude, ChatGPT, Codex, Cursor, Apple devices, and local agents are clients.

## Authentication and Authorization

The public endpoint should require OAuth 2.1 access tokens validated by issuer, audience/resource, expiration, not-before, JWKS signature, and scopes.

Minimum scopes:

- `exocortex:read`
- `memory:write`
- `chronoself:write`
- `research:run`
- `agent:start`

Irreversible destructive actions are locked out of v1.1 unless a future `admin:destructive` scope and explicit audit policy are added.

## Public Trusted-Full Surface

The first Claude deployment uses `MCP_TOOL_SURFACE=trusted_full` with Auth0 scopes. This exposes non-destructive read, write, research, Round Table, and agent-session tools to authorized clients while keeping irreversible destructive actions unavailable.

## Tool Poisoning Controls

Tool descriptions are static source-controlled strings. The server validates that exposed tools have annotations, required scopes, risk levels, and no obvious hidden control text or tool-poisoning phrases. The manifest hash is exposed in `/.well-known/mcp` and `beagle://mcp/tool_manifest`.

## Audit

Tool calls are written to the Beagle append-only audit event API when the core is reachable. Audit records include client ID, tool name, required scopes, granted scopes, risk level, status, argument keys, annotations, and tool manifest hash.

## Network Exposure

`mcp.agourakis.com` is the public connector URL. Tailnet URLs are operational/admin paths and should not be submitted as public connector endpoints.
