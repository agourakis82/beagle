/**
 * Standard connector tools.
 *
 * Hosted clients such as ChatGPT and Claude tend to understand a small
 * search/fetch surface best. These tools map that public pattern onto the
 * canonical Beagle memory, Chronoself, projects, and Home APIs.
 */

import { z } from "zod";
import { BeagleClient } from "../beagle-client.js";
import { sanitizeOutput } from "../security.js";
import { McpTool } from "./index.js";

const SearchSchema = z.object({
    query: z.string().min(1),
    max_results: z.number().int().min(1).max(20).optional().default(8),
});

const FetchSchema = z.object({
    id: z.string().min(1),
});

const DIRECT_RESOURCE_IDS = new Set([
    "beagle://home",
    "beagle://chronoself/current",
    "beagle://chronoself/commits",
    "beagle://memory/recent",
    "beagle://projects/active",
    "beagle://cluster/truth",
    "beagle://trust/current",
]);

export function standardTools(client: BeagleClient): McpTool[] {
    return [
        {
            name: "search",
            description:
                "Search Beagle Exocortex memory, Chronoself, active projects, and recent context. Returns stable IDs that can be passed to fetch.",
            inputSchema: {
                type: "object",
                properties: {
                    query: {
                        type: "string",
                        description: "Search query for Beagle memory and exocortex context.",
                    },
                    max_results: {
                        type: "number",
                        minimum: 1,
                        maximum: 20,
                        default: 8,
                        description: "Maximum results to return.",
                    },
                },
                required: ["query"],
            },
            handler: async (args: unknown) => {
                const { query, max_results } = SearchSchema.parse(args ?? {});
                const memory = await hotPathMemoryQuery(client, query, max_results);
                const results = memory.highlights.map((highlight, index) => ({
                    id: searchResultId(query, index),
                    title: resultTitle(highlight.source, highlight.date, index),
                    text: highlight.snippet,
                    url: highlight.run_id ? `beagle://run/${highlight.run_id}` : undefined,
                    metadata: {
                        source: highlight.source,
                        date: highlight.date,
                        session_id: highlight.session_id,
                        run_id: highlight.run_id,
                        relevance: highlight.relevance,
                    },
                }));

                return sanitizeOutput(
                    {
                        query,
                        summary: memory.summary,
                        results,
                        fetchable_resources: [
                            "beagle://home",
                            "beagle://chronoself/current",
                            "beagle://chronoself/commits",
                            "beagle://memory/recent",
                            "beagle://projects/active",
                            "beagle://trust/current",
                        ],
                    },
                    { isMemoryQuery: true },
                );
            },
        },
        {
            name: "fetch",
            description:
                "Fetch a Beagle search result or canonical exocortex resource by ID, such as beagle://home or an ID returned by search.",
            inputSchema: {
                type: "object",
                properties: {
                    id: {
                        type: "string",
                        description:
                            "ID returned by search or a canonical Beagle resource URI.",
                    },
                },
                required: ["id"],
            },
            handler: async (args: unknown) => {
                const { id } = FetchSchema.parse(args ?? {});
                if (DIRECT_RESOURCE_IDS.has(id)) {
                    return sanitizeOutput(await readDirectResource(client, id));
                }

                const memoryRef = parseSearchResultId(id);
                if (memoryRef) {
                    const memory = await hotPathMemoryQuery(client, memoryRef.query, memoryRef.index + 1);
                    const highlight = memory.highlights[memoryRef.index];
                    if (!highlight) {
                        return {
                            id,
                            found: false,
                            message: "Search result is no longer available at that index.",
                        };
                    }
                    return sanitizeOutput(
                        {
                            id,
                            found: true,
                            summary: memory.summary,
                            result: highlight,
                        },
                        { isMemoryQuery: true },
                    );
                }

                return {
                    id,
                    found: false,
                    message:
                        "Unknown Beagle fetch ID. Use search first or pass a supported beagle:// resource URI.",
                };
            },
        },
    ];
}

async function hotPathMemoryQuery(
    client: BeagleClient,
    query: string,
    maxItems: number,
): Promise<{
    summary: string;
    highlights: Array<{
        source: string;
        date?: string;
        snippet: string;
        run_id?: string;
        session_id?: string;
        relevance: number;
    }>;
    links: unknown[];
}> {
    try {
        const mesh = await client.retrievalAgentQuery({
            query,
            max_items: maxItems,
            mode: "hypermemory_multivector",
            planner_mode: "hybrid",
            surface: "hosted-search",
        }) as Record<string, unknown>;
        const core = (mesh.core_response ?? {}) as Record<string, unknown>;
        const evidence = Array.isArray(core.evidence) ? core.evidence as Array<Record<string, unknown>> : [];
        const episodes = Array.isArray(core.episodes) ? core.episodes as Array<Record<string, unknown>> : [];
        const highlights = evidence.slice(0, maxItems).map((item) => {
            const episodeId = String(item.episode_id ?? "");
            const episode = episodes.find((candidate) => candidate.id === episodeId);
            return {
                source: String(episode?.source ?? "hypermemory_multivector"),
                date: typeof episode?.occurred_at === "string" ? episode.occurred_at : undefined,
                snippet: String(item.text ?? ""),
                session_id: typeof episode?.session_id === "string" ? episode.session_id : undefined,
                relevance: typeof item.score === "number" ? item.score : 0,
            };
        });
        if (highlights.length > 0) {
            return {
                summary: String(core.summary ?? mesh.summary ?? `HyperMemory search completed for ${query}.`),
                highlights,
                links: [
                    {
                        runtime_used: mesh.runtime_used,
                        retrieval_agent: mesh.retrieval_agent,
                        strategy_used: mesh.strategy_used,
                        retrieval_plan_id: mesh.retrieval_plan_id,
                        fallback_chain: mesh.fallback_chain,
                        runtime_trace: mesh.runtime_trace,
                        semantic_trace: mesh.semantic_trace,
                        truthset_gate_status: mesh.truthset_gate_status,
                    },
                ],
            };
        }
    } catch {
        // Hosted connectors should degrade to the canonical memory API rather than failing search.
    }
    return client.memoryQuery(query, maxItems);
}

async function readDirectResource(client: BeagleClient, id: string): Promise<unknown> {
    switch (id) {
        case "beagle://home":
            return client.exocortexHome(undefined, "mcp-fetch");
        case "beagle://chronoself/current":
            return client.chronoselfCurrent();
        case "beagle://chronoself/commits":
            return client.chronoselfCommits(25);
        case "beagle://memory/recent":
            return client.memoryQuery("recent Beagle Exocortex memory signals", 10);
        case "beagle://projects/active":
            return client.activeProjects();
        case "beagle://cluster/truth":
            return {
                core_url: client.baseUrl,
                core_health: await client.health(),
            };
        case "beagle://trust/current":
            return {
                core_url: client.baseUrl,
                core_health: await client.health(),
                destructive_locked: true,
            };
        default:
            return { id, found: false };
    }
}

function searchResultId(query: string, index: number): string {
    return `beagle-memory://search/${base64UrlEncode(query)}/${index}`;
}

function parseSearchResultId(id: string): { query: string; index: number } | undefined {
    const match = /^beagle-memory:\/\/search\/([^/]+)\/(\d+)$/.exec(id);
    if (!match) {
        return undefined;
    }
    return {
        query: base64UrlDecode(match[1]),
        index: Number.parseInt(match[2], 10),
    };
}

function base64UrlEncode(value: string): string {
    return Buffer.from(value, "utf8").toString("base64url");
}

function base64UrlDecode(value: string): string {
    return Buffer.from(value, "base64url").toString("utf8");
}

function resultTitle(source: string, date: string | undefined, index: number): string {
    const suffix = date ? ` (${date})` : "";
    return `${source || "Beagle memory"} result ${index + 1}${suffix}`;
}
