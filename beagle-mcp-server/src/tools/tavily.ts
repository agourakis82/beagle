/**
 * Tavily MCP Tool
 *
 * Web search via Tavily API optimized for LLM consumption.
 * Provides search results with snippets and sources.
 *
 * Requires TAVILY_API_KEY environment variable.
 */

import { z } from "zod";
import { BeagleClient } from "../beagle-client.js";
import { McpTool } from "./index.js";
import { sanitizeOutput } from "../security.js";

const TavilySearchSchema = z.object({
    query: z
        .string()
        .describe("Search query for web search"),
    max_results: z
        .number()
        .int()
        .min(1)
        .max(20)
        .optional()
        .default(5)
        .describe("Maximum number of search results to return"),
    search_depth: z
        .enum(["basic", "advanced"])
        .optional()
        .default("basic")
        .describe("Search depth - basic (fast) or advanced (comprehensive)"),
    include_domains: z
        .array(z.string())
        .optional()
        .describe("List of domains to include in search (e.g., ['arxiv.org', 'pubmed.ncbi.nlm.nih.gov'])"),
    exclude_domains: z
        .array(z.string())
        .optional()
        .describe("List of domains to exclude from search"),
    include_answer: z
        .boolean()
        .optional()
        .default(false)
        .describe("Include AI-generated answer based on search results"),
    include_raw_content: z
        .boolean()
        .optional()
        .default(false)
        .describe("Include full raw content of search results (increases token usage)"),
    days: z
        .number()
        .int()
        .min(1)
        .max(365)
        .optional()
        .describe("Filter results by time range in days (e.g., 7 for past week)"),
});

interface TavilySearchResult {
    query: string;
    answer?: string;
    results: Array<{
        title: string;
        url: string;
        content: string;
        raw_content?: string;
        score: number;
    }>;
    images?: Array<{
        url: string;
        description?: string;
    }>;
    response_time: string;
}

async function callTavilyAPI(
    apiKey: string,
    params: z.infer<typeof TavilySearchSchema>
): Promise<TavilySearchResult> {
    const response = await fetch("https://api.tavily.com/search", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            api_key: apiKey,
            query: params.query,
            max_results: params.max_results,
            search_depth: params.search_depth,
            include_domains: params.include_domains,
            exclude_domains: params.exclude_domains,
            include_answer: params.include_answer,
            include_raw_content: params.include_raw_content,
            days: params.days,
        }),
    });

    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Tavily API error: ${response.status} ${errorText}`);
    }

    return await response.json() as TavilySearchResult;
}

export function tavilyTools(_client: BeagleClient): McpTool[] {
    const apiKey = process.env.TAVILY_API_KEY;

    return [
        {
            name: "tavily_search",
            description: [
                "Web search via Tavily API optimized for LLM consumption.",
                "Returns search results with relevant snippets and source URLs.",
                "Supports advanced search depth for comprehensive results.",
                "Can include AI-generated summaries of search results.",
                "",
                "Requires TAVILY_API_KEY environment variable.",
                "Free tier: 1,000 API calls/month.",
                "",
                "Use cases:",
                "- Current events and news",
                "- Scientific literature search",
                "- Fact verification",
                "- Context gathering for research",
            ].join("\n"),
            inputSchema: {
                type: "object",
                properties: {
                    query: {
                        type: "string",
                        description: "Search query for web search",
                    },
                    max_results: {
                        type: "number",
                        description: "Maximum number of results (1-20, default: 5)",
                    },
                    search_depth: {
                        type: "string",
                        enum: ["basic", "advanced"],
                        description: "basic (fast) or advanced (comprehensive)",
                    },
                    include_domains: {
                        type: "array",
                        items: { type: "string" },
                        description: "Domains to include (e.g., ['arxiv.org'])",
                    },
                    exclude_domains: {
                        type: "array",
                        items: { type: "string" },
                        description: "Domains to exclude",
                    },
                    include_answer: {
                        type: "boolean",
                        description: "Include AI-generated answer (default: false)",
                    },
                    include_raw_content: {
                        type: "boolean",
                        description: "Include full page content (default: false)",
                    },
                    days: {
                        type: "number",
                        description: "Time filter in days (1-365)",
                    },
                },
                required: ["query"],
            },
            handler: async (args: unknown) => {
                if (!apiKey) {
                    return {
                        error: "TAVILY_API_KEY environment variable not set",
                        setup_instructions: [
                            "1. Get your API key at: https://tavily.com",
                            "2. Set TAVILY_API_KEY environment variable",
                            "3. Restart the MCP server",
                        ].join("\n"),
                    };
                }

                const params = TavilySearchSchema.parse(args);

                try {
                    const result = await callTavilyAPI(apiKey, params);

                    // Format response for LLM consumption
                    const formattedResults = result.results.map((r, idx) => ({
                        index: idx + 1,
                        title: r.title,
                        url: r.url,
                        snippet: r.content.substring(0, 500),
                        relevance_score: Math.round(r.score * 100) / 100,
                    }));

                    const response: Record<string, unknown> = {
                        query: result.query,
                        results: formattedResults,
                        result_count: result.results.length,
                        response_time: result.response_time,
                    };

                    if (result.answer && params.include_answer) {
                        response.answer = sanitizeOutput(result.answer);
                    }

                    if (result.images && result.images.length > 0) {
                        response.images = result.images.map(img => ({
                            url: img.url,
                            description: img.description,
                        }));
                    }

                    return response;
                } catch (error) {
                    const errorMessage = error instanceof Error ? error.message : String(error);
                    return {
                        error: `Tavily search failed: ${errorMessage}`,
                        query: params.query,
                    };
                }
            },
        },
        {
            name: "tavily_research",
            description: [
                "Comprehensive research query using Tavily advanced search.",
                "Automatically enables AI answer and deeper search.",
                "Optimized for scientific and academic research.",
                "",
                "This is a convenience wrapper that sets:",
                "- search_depth: advanced",
                "- include_answer: true",
                "- max_results: 10",
            ].join("\n"),
            inputSchema: {
                type: "object",
                properties: {
                    query: {
                        type: "string",
                        description: "Research query",
                    },
                    focus_area: {
                        type: "string",
                        enum: ["general", "scientific", "medical", "technical", "news"],
                        description: "Type of research focus",
                    },
                    time_range_days: {
                        type: "number",
                        description: "Filter results by time (days)",
                    },
                },
                required: ["query"],
            },
            handler: async (args: unknown) => {
                if (!apiKey) {
                    return {
                        error: "TAVILY_API_KEY environment variable not set",
                    };
                }

                const schema = z.object({
                    query: z.string(),
                    focus_area: z.enum(["general", "scientific", "medical", "technical", "news"]).optional().default("general"),
                    time_range_days: z.number().int().min(1).max(365).optional(),
                });

                const params = schema.parse(args);

                // Configure domains based on focus area
                const domainMap: Record<string, string[]> = {
                    scientific: ["arxiv.org", "pubmed.ncbi.nlm.nih.gov", "scholar.google.com", "researchgate.net"],
                    medical: ["pubmed.ncbi.nlm.nih.gov", "ncbi.nlm.nih.gov", "who.int", "cdc.gov", "fda.gov"],
                    technical: ["github.com", "stackoverflow.com", "docs.python.org", "docs.rs", "developer.mozilla.org"],
                    news: ["reuters.com", "apnews.com", "bbc.com", "cnn.com"],
                    general: [],
                };

                const searchParams = {
                    query: params.query,
                    max_results: 10,
                    search_depth: "advanced" as const,
                    include_answer: true,
                    include_raw_content: false,
                    include_domains: domainMap[params.focus_area] || [],
                    days: params.time_range_days,
                };

                try {
                    const result = await callTavilyAPI(apiKey, searchParams);

                    return {
                        query: result.query,
                        answer: result.answer ? sanitizeOutput(result.answer) : undefined,
                        results: result.results.map((r, idx) => ({
                            index: idx + 1,
                            title: r.title,
                            url: r.url,
                            snippet: r.content.substring(0, 800),
                            relevance_score: Math.round(r.score * 100) / 100,
                        })),
                        focus_area: params.focus_area,
                        result_count: result.results.length,
                        response_time: result.response_time,
                    };
                } catch (error) {
                    const errorMessage = error instanceof Error ? error.message : String(error);
                    return {
                        error: `Tavily research failed: ${errorMessage}`,
                        query: params.query,
                    };
                }
            },
        },
    ];
}
