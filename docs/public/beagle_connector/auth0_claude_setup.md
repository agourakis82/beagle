# Auth0 and Claude Setup for Beagle MCP

Last updated: 2026-04-26

## Auth0 API

Create an Auth0 API for Beagle MCP:

- Name: `Beagle Exocortex MCP`
- Identifier: `https://mcp.agourakis.com/mcp`
- Signing algorithm: `RS256`
- Access token format: JWT

Scopes:

- `exocortex:read`
- `memory:write`
- `chronoself:write`
- `research:run`
- `agent:start`

Do not add `admin:destructive` for v1.1.

## Auth0 Application for Claude

Create a regular web application or native/SPA-style OAuth client according to the Auth0 dashboard flow that supports Authorization Code with PKCE.

Allowed callback URL:

```text
https://claude.ai/api/mcp/auth_callback
```

Recommended settings:

- Authorization Code with PKCE enabled.
- Refresh tokens enabled if Auth0 policy allows it.
- Audience/resource set to `https://mcp.agourakis.com/mcp`.
- Access token includes either `scope` or `permissions` claims.

## Beagle Kubernetes Secret

Create the runtime secret in namespace `beagle`:

```bash
kubectl -n beagle create secret generic beagle-mcp-oauth \
  --from-literal=authorization_server_url='https://YOUR_AUTH0_DOMAIN/' \
  --from-literal=issuer='https://YOUR_AUTH0_DOMAIN/' \
  --from-literal=jwks_uri='https://YOUR_AUTH0_DOMAIN/.well-known/jwks.json' \
  --from-literal=audience='https://mcp.agourakis.com/mcp'
```

Use the exact issuer string from Auth0 metadata, including the trailing slash.

After creating or updating this secret, restart the MCP deployment so protected-resource metadata and JWT validation are active:

```bash
kubectl -n beagle rollout restart deploy/beagle-mcp-server
kubectl -n beagle rollout status deploy/beagle-mcp-server
```

## Beagle MCP Runtime

The public deployment should run with:

```bash
MCP_PUBLIC_BASE_URL=https://mcp.agourakis.com
MCP_RESOURCE_IDENTIFIER=https://mcp.agourakis.com/mcp
MCP_RESOURCE_DOCUMENTATION_URL=https://mcp.agourakis.com/connector
MCP_PUBLIC_DISCOVERY=true
MCP_TOOL_SURFACE=trusted_full
MCP_ALLOW_LEGACY_BEARER=false
```

The private/local launcher can still use a trusted bearer token through stdio or tailnet-only paths.

The public `mcp.agourakis.com` endpoint should not allow the legacy bearer path.

## Claude Acceptance

In Claude web/Desktop, add the remote MCP connector:

```text
https://mcp.agourakis.com/mcp
```

Then validate:

- OAuth login opens Auth0.
- Consent grants the expected Beagle scopes.
- `search` and `fetch` work.
- `beagle_exocortex_home` works.
- `beagle_memory_ingest_chat` works with sanitized test content.
- `beagle_round_table` works with a short prompt.

After connection succeeds on web/Desktop, verify the connector from Claude iOS.
