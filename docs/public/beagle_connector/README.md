# Beagle Exocortex Connector

Beagle Exocortex is a private MCP connector for a cluster-canonical personal exocortex: memory, Chronoself, active projects, research threads, audit trail, and trust context.

Public connector name: Beagle Exocortex

Tagline: Your audited exocortex memory and research nervous system.

Connector endpoint: `https://mcp.agourakis.com/mcp`

Discovery:

- `https://mcp.agourakis.com/.well-known/mcp`
- `https://mcp.agourakis.com/.well-known/oauth-protected-resource`
- `https://mcp.agourakis.com/health`
- `https://mcp.agourakis.com/ready`

## What It Does

- Searches Beagle OmniMemory and recent exocortex context through `search`.
- Fetches canonical Beagle resources through `fetch`, including Home, current Chronoself, recent memory, active projects, and trust context.
- Exposes a trusted-full non-destructive surface for hosted Claude first: memory writes, Chronoself commits, research runs, Round Table, and agent sessions are controlled by OAuth scopes.
- Keeps irreversible destructive actions locked out of v1.2; `admin:destructive` is reserved for a future explicit flow.
- Writes append-only audit events for tool calls when the cluster is reachable.
- Publishes a capability ledger with `manifest_version`, `toolset_id`, `security_profile`, client surfaces, and manifest history resources.

## Public Trusted-Full Mode

The first public Claude deployment should run with:

```bash
MCP_TOOL_SURFACE=trusted_full
MCP_PUBLIC_BASE_URL=https://mcp.agourakis.com
MCP_PUBLIC_DISCOVERY=true
MCP_ALLOW_LEGACY_BEARER=false
```

`trusted_full` still exposes no destructive tools. Read/write/run capabilities require OAuth scopes such as `exocortex:read`, `memory:write`, `chronoself:write`, `research:run`, and `agent:start`.

## Capability Ledger

Beagle MCP v1.2 exposes:

- `beagle://mcp/manifest/current`
- `beagle://mcp/manifest/history`
- `beagle://agents/current`
- `beagle://agents/recent`
- `beagle://capabilities/current`
- `beagle://trust/current`

These resources let hosted agents see the current toolset, security profile, client surface, destructive-action lock, and recent audited MCP activity.

## Health and Body Context

Beagle may store and summarize personal context such as energy, sleep, activity, and other HealthKit-derived signals when the user explicitly syncs them from Apple devices. These signals are used as personal productivity and cognitive context only. Beagle is not a medical device and does not provide diagnosis, treatment, or emergency guidance.

## Test Account

Directory reviewers should use a sanitized test account configured by the operator. The test account should contain realistic but non-sensitive memory, project, Chronoself, and audit data.

## Platform Readiness

Claude remote connectors are expected to work across Claude web, Desktop, and mobile after the connector is added and authenticated from the supported setup surfaces. ChatGPT MCP apps/connectors should be tested on ChatGPT web first; mobile support is not treated as an acceptance requirement until OpenAI marks MCP apps/connectors as available on mobile.

## Related Documents

- [Privacy Policy](privacy_policy.md)
- [Data Retention and Deletion](data_retention_deletion.md)
- [Security Notes](security_notes.md)
- [Setup and Test Instructions](setup_test_instructions.md)
- [Auth0 and Claude Setup](auth0_claude_setup.md)
