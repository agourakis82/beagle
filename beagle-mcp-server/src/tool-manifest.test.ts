import assert from "node:assert/strict";
import test from "node:test";
import { BeagleClient } from "./beagle-client.js";
import { defineTools } from "./tools/index.js";
import {
    computeToolManifestHash,
    toolManifest,
    validateToolDefinitions,
} from "./tool-manifest.js";

const TRUSTED_FULL_TOOL_COUNT = 23;
const TRUSTED_FULL_TOOL_MANIFEST_HASH =
    "sha256:0777b33845fff733281aec11aeacd875ea32db3ce62b3245a14c957f8dbbdd1c";

test("all MCP tools expose annotations, scopes, and risk levels", () => {
    const tools = defineTools({} as BeagleClient);
    validateToolDefinitions(tools);

    for (const tool of tools) {
        assert.ok(tool.annotations, `${tool.name} annotations`);
        assert.equal(typeof tool.annotations?.readOnlyHint, "boolean");
        assert.equal(typeof tool.annotations?.destructiveHint, "boolean");
        assert.equal(typeof tool.annotations?.idempotentHint, "boolean");
        assert.equal(typeof tool.annotations?.openWorldHint, "boolean");
        assert.ok(tool.requiredScopes?.length, `${tool.name} requiredScopes`);
        assert.ok(tool.riskLevel, `${tool.name} riskLevel`);
        assert.equal(tool.annotations?.destructiveHint, false, `${tool.name} destructive locked`);
    }
});

test("tool manifest hash is stable and covers annotations", () => {
    const previousSurface = process.env.MCP_TOOL_SURFACE;
    process.env.MCP_TOOL_SURFACE = "trusted_full";
    try {
        const tools = defineTools({} as BeagleClient);
        const hashA = computeToolManifestHash(tools);
        const hashB = computeToolManifestHash([...tools].reverse());

        assert.match(hashA, /^sha256:[a-f0-9]{64}$/);
        assert.equal(hashA, hashB);
        assert.equal(tools.length, TRUSTED_FULL_TOOL_COUNT);
        assert.equal(hashA, TRUSTED_FULL_TOOL_MANIFEST_HASH);

        const manifest = toolManifest(tools);
        assert.equal(manifest.length, tools.length);
        assert.ok(manifest.every((entry) => entry.annotations.title.length > 0));
    } finally {
        if (previousSurface === undefined) {
            delete process.env.MCP_TOOL_SURFACE;
        } else {
            process.env.MCP_TOOL_SURFACE = previousSurface;
        }
    }
});

test("standard search and fetch tools are exposed for hosted connectors", () => {
    const previousSurface = process.env.MCP_TOOL_SURFACE;
    process.env.MCP_TOOL_SURFACE = "trusted_full";
    try {
        const tools = defineTools({} as BeagleClient);
        const names = new Set(tools.map((tool) => tool.name));
        assert.ok(names.has("search"));
        assert.ok(names.has("fetch"));
    } finally {
        if (previousSurface === undefined) {
            delete process.env.MCP_TOOL_SURFACE;
        } else {
            process.env.MCP_TOOL_SURFACE = previousSurface;
        }
    }
});

test("review_safe surface excludes write and run tools", () => {
    const previousSurface = process.env.MCP_TOOL_SURFACE;
    process.env.MCP_TOOL_SURFACE = "review_safe";
    try {
        const tools = defineTools({} as BeagleClient);
        const names = new Set(tools.map((tool) => tool.name));
        assert.ok(names.has("search"));
        assert.ok(names.has("fetch"));
        assert.ok(names.has("beagle_exocortex_home"));
        assert.ok(!names.has("beagle_memory_ingest_chat"));
        assert.ok(!names.has("beagle_chronoself_create_commit"));
        assert.ok(tools.every((tool) => tool.riskLevel === "read"));
    } finally {
        if (previousSurface === undefined) {
            delete process.env.MCP_TOOL_SURFACE;
        } else {
            process.env.MCP_TOOL_SURFACE = previousSurface;
        }
    }
});
