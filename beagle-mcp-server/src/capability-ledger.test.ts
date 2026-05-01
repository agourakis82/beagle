import assert from "node:assert/strict";
import test from "node:test";
import { BeagleClient } from "./beagle-client.js";
import {
    capabilityManifest,
    createCapabilityLedgerState,
    MCP_MANIFEST_VERSION,
    MCP_SECURITY_PROFILE,
} from "./capability-ledger.js";
import { defineResources } from "./resources.js";
import { defineTools } from "./tools/index.js";

test("capability ledger exposes MCP v2.5 manifest and client surfaces", () => {
    const previousAllowLegacy = process.env.MCP_ALLOW_LEGACY_BEARER;
    process.env.MCP_ALLOW_LEGACY_BEARER = "false";
    try {
        const tools = defineTools({} as BeagleClient);
        const ledger = createCapabilityLedgerState(tools);
        const manifest = capabilityManifest(tools, ledger);

        assert.equal(manifest.manifest_version, MCP_MANIFEST_VERSION);
        assert.equal(manifest.security_profile, MCP_SECURITY_PROFILE);
        assert.equal(manifest.toolset_id, manifest.tool_manifest_hash);
        assert.equal(manifest.active_client_surface, "claude_trusted_full");
        assert.ok(manifest.client_surfaces.some((surface) => surface.id === "chatgpt_review_safe"));
        assert.equal(manifest.destructive_actions, "locked");
    } finally {
        if (previousAllowLegacy === undefined) {
            delete process.env.MCP_ALLOW_LEGACY_BEARER;
        } else {
            process.env.MCP_ALLOW_LEGACY_BEARER = previousAllowLegacy;
        }
    }
});

test("MCP resources include manifest, agent, capability, and trust surfaces", () => {
    const tools = defineTools({} as BeagleClient);
    const ledger = createCapabilityLedgerState(tools);
    const resources = defineResources({} as BeagleClient, tools, ledger);
    const uris = new Set(resources.map((resource) => resource.uri));

    assert.ok(uris.has("beagle://mcp/manifest/current"));
    assert.ok(uris.has("beagle://mcp/manifest/history"));
    assert.ok(uris.has("beagle://memory/graph/status"));
    assert.ok(uris.has("beagle://memory/governance/status"));
    assert.ok(uris.has("beagle://memory/bench/status"));
    assert.ok(uris.has("beagle://memory/bench/latest"));
    assert.ok(uris.has("beagle://memory/retrieval/status"));
    assert.ok(uris.has("beagle://memory/memoryarena/status"));
    assert.ok(uris.has("beagle://context/compiler/status"));
    assert.ok(uris.has("beagle://memory/policy/status"));
    assert.ok(uris.has("beagle://memory/dreamcycle/status"));
    assert.ok(uris.has("beagle://sounio/paperrun/current"));
    assert.ok(uris.has("beagle://agent/observer/status"));
    assert.ok(uris.has("beagle://memory/contradictions/recent"));
    assert.ok(uris.has("beagle://work/current"));
    assert.ok(uris.has("beagle://agents/current"));
    assert.ok(uris.has("beagle://agents/recent"));
    assert.ok(uris.has("beagle://capabilities/current"));
    assert.ok(uris.has("beagle://trust/current"));
});
