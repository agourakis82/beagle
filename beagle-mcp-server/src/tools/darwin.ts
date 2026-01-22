/**
 * Darwin Jobs Tools (Continuous RAG + ResearchOps)
 *
 * These tools trigger server-side Darwin jobs:
 * - incremental repo indexing
 * - research/web harvesting (via darwin-* binaries)
 * - brief generation
 * - eval runs
 */

import { z } from "zod";
import { BeagleClient } from "../beagle-client.js";
import { McpTool } from "./index.js";
import { sanitizeOutput } from "../security.js";

const StartDarwinJobSchema = z.object({
    kind: z
        .enum([
            "indexer",
            "research_harvester",
            "web_harvester",
            "knowledge_manager",
            "brief",
            "eval",
            "nightly",
        ])
        .describe("Darwin job kind"),
    config: z
        .record(z.unknown())
        .default({})
        .describe(
            "Job-specific configuration. For non-indexer jobs, pass { argv: string[], env?: object, timeout_secs?: number }.",
        ),
});

const GetDarwinJobStatusSchema = z.object({
    job_id: z.string().describe("Job ID from beagle_start_darwin_job"),
});

const GetDarwinJobArtifactsSchema = z.object({
    job_id: z.string().describe("Job ID from beagle_start_darwin_job"),
});

const ListRecentDarwinJobsSchema = z.object({
    limit: z
        .number()
        .int()
        .min(1)
        .max(50)
        .optional()
        .default(10)
        .describe("Maximum number of jobs to return"),
});

const DarwinIndexerSchema = z.object({
    force: z.boolean().optional().describe("Re-index everything (ignore git diff state)"),
    sync: z.boolean().optional().describe("Run `git pull --ff-only` before indexing"),
    repo_path: z
        .array(z.string())
        .optional()
        .default([])
        .describe("One or more local repo paths to index"),
    repo_url: z
        .array(z.string())
        .optional()
        .default([])
        .describe("One or more git clone URLs to index (cloned into repos_dir)"),
    repos_file: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Repo targets file(s) on the core server host (YAML/TOML/JSON)"),
    github_user: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Discover public repos from GitHub user(s)"),
    github_org: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Discover public repos from GitHub org(s)"),
    github_me: z
        .boolean()
        .optional()
        .describe(
            "Discover repos for the authenticated GitHub user (may include private; requires token on core host)",
        ),
    github_api_base: z
        .string()
        .optional()
        .describe("GitHub API base (for GitHub Enterprise)"),
    github_include_forks: z
        .boolean()
        .optional()
        .describe("Include fork repos when listing via GitHub API"),
    github_clone_ssh: z
        .boolean()
        .optional()
        .describe("Prefer SSH clone URLs for GitHub-discovered repos"),
    repos_dir: z.string().optional().describe("Directory containing cloned repos"),
    state_file: z.string().optional().describe("State file path on core server host"),
    qdrant_url: z.string().optional().describe("Override QDRANT_URL for this job"),
    embedding_url: z.string().optional().describe("Override EMBEDDING_URL for this job"),
    embedding_model: z.string().optional().describe("Override EMBEDDING_MODEL for this job"),
    collection: z.string().optional().describe("Override DARWIN_QDRANT_COLLECTION for this job"),
    error_webhook_url: z
        .string()
        .optional()
        .describe("Optional error webhook URL (overrides DARWIN_INDEX_ERROR_WEBHOOK_URL)"),
    success_webhook_url: z
        .string()
        .optional()
        .describe("Optional success webhook URL (overrides DARWIN_INDEX_SUCCESS_WEBHOOK_URL)"),
});

const DarwinBriefZaiSchema = z.object({
    topics_file: z
        .string()
        .optional()
        .default("scripts/darwin-research-topics.yaml")
        .describe("Topics registry file path on the BEAGLE core server host"),
    topic: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Only run specific topic(s) from the topics file"),
    out_dir: z
        .string()
        .optional()
        .describe("Output directory for briefs (overrides DARWIN_BRIEF_DIR)"),
    state_file: z
        .string()
        .optional()
        .describe("Brief state file path (overrides DARWIN_BRIEF_STATE_FILE)"),
    collections: z
        .string()
        .optional()
        .describe("Comma-separated Qdrant collections list (optional)"),
    k: z
        .number()
        .int()
        .min(1)
        .max(50)
        .optional()
        .describe("Top-k per query per collection (default: 10)"),
    max_docs: z
        .number()
        .int()
        .min(1)
        .max(50)
        .optional()
        .describe("Max docs to include in the brief (default: 12)"),
    max_snippet_chars: z
        .number()
        .int()
        .min(100)
        .max(5000)
        .optional()
        .describe("Max chars per snippet sent to the LLM (default: 900)"),
    no_llm: z
        .boolean()
        .optional()
        .describe("Skip LLM synthesis and emit retrieval report only"),
    delta_days: z
        .number()
        .int()
        .min(0)
        .max(365)
        .optional()
        .describe("Compute changes since N days ago (default: 7; 0 disables)"),
    strict_citations: z
        .boolean()
        .optional()
        .describe("Fail if out-of-range bracket citations are emitted"),
    min_citations: z
        .number()
        .int()
        .min(0)
        .max(200)
        .optional()
        .describe("Minimum number of citations required when LLM is enabled"),
    timeout_secs: z
        .number()
        .int()
        .min(10)
        .max(3600)
        .optional()
        .describe("Optional job timeout in seconds"),
    env: z
        .record(z.string())
        .optional()
        .default({})
        .describe("Optional environment overrides for the spawned darwin-brief process"),
    extra_argv: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Extra raw argv segments (advanced; appended as-is)"),
});

const DarwinWebHarvesterSchema = z.object({
    sources_file: z
        .string()
        .optional()
        .describe("Optional sources file path on the BEAGLE core server host"),
    source: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Only run specific source(s) from the sources file"),
    url: z.array(z.string()).optional().default([]).describe("One or more URLs to fetch"),
    rss: z.array(z.string()).optional().default([]).describe("RSS/Atom feed URLs"),
    sitemap: z.array(z.string()).optional().default([]).describe("Sitemap URLs"),
    allow_host: z.array(z.string()).optional().default([]).describe("Allow-list hosts"),
    deny_host: z.array(z.string()).optional().default([]).describe("Deny-list hosts"),
    allow_path_regex: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Allow-list path regexes (repeatable)"),
    deny_path_regex: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Deny-list path regexes (repeatable)"),
    allow_cross_host: z
        .boolean()
        .optional()
        .describe("Allow crawling outside the seed host"),
    crawl_depth: z
        .number()
        .int()
        .min(0)
        .max(5)
        .optional()
        .describe("Crawl depth (0 = only provided URLs)"),
    max_urls: z
        .number()
        .int()
        .min(1)
        .max(5000)
        .optional()
        .describe("Max URLs to fetch across all sources"),
    max_bytes: z
        .number()
        .int()
        .min(1)
        .max(50_000_000)
        .optional()
        .describe("Max bytes to download per URL"),
    concurrency: z
        .number()
        .int()
        .min(1)
        .max(64)
        .optional()
        .describe("Global concurrency"),
    per_host_concurrency: z
        .number()
        .int()
        .min(1)
        .max(32)
        .optional()
        .describe("Max concurrent requests per host"),
    host_delay_ms: z
        .number()
        .int()
        .min(0)
        .max(60_000)
        .optional()
        .describe("Politeness delay (ms) between requests to the same host"),
    max_links: z
        .number()
        .int()
        .min(0)
        .max(50_000)
        .optional()
        .describe("Max discovered links to enqueue per page"),
    ignore_robots: z
        .boolean()
        .optional()
        .describe("Ignore robots.txt"),
    robots_fail_closed: z
        .boolean()
        .optional()
        .describe("If robots.txt cannot be fetched, skip the host (fail closed)"),
    robots_user_agent: z
        .string()
        .optional()
        .describe("User-agent used for robots.txt rules"),
    eval_after: z
        .boolean()
        .optional()
        .describe("Run eval gates after harvesting (fail on regression)"),
    eval_file: z
        .string()
        .optional()
        .describe("Eval file path (passed as --eval-file)"),
    eval_k: z
        .number()
        .int()
        .min(1)
        .max(200)
        .optional()
        .describe("Eval top-k (passed as --eval-k)"),
    eval_history_file: z
        .string()
        .optional()
        .describe("Eval history JSONL file path (passed as --eval-history-file)"),
    eval_min_mrr: z
        .number()
        .min(0)
        .max(1)
        .optional()
        .describe("Fail if MRR is below this value (passed as --eval-min-mrr)"),
    eval_max_mrr_drop: z
        .number()
        .min(0)
        .max(1)
        .optional()
        .describe("Fail if MRR dropped more than this value (passed as --eval-max-mrr-drop)"),
    eval_min_recall: z
        .number()
        .min(0)
        .max(1)
        .optional()
        .describe("Fail if recall@k is below this value (passed as --eval-min-recall)"),
    eval_max_recall_drop: z
        .number()
        .min(0)
        .max(1)
        .optional()
        .describe("Fail if recall@k dropped more than this value (passed as --eval-max-recall-drop)"),
    tag: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Extra tags to attach to all ingested docs"),
    license: z
        .string()
        .optional()
        .describe("Optional license string to attach to ingested docs"),
    out_dir: z
        .string()
        .optional()
        .describe("Output directory for harvested markdown stubs"),
    ledger_db_url: z
        .string()
        .optional()
        .describe("Optional Postgres URL to enable the ingestion ledger"),
    force: z
        .boolean()
        .optional()
        .describe("Force re-index even if ledger indicates content is unchanged"),
    timeout_secs: z
        .number()
        .int()
        .min(10)
        .max(7200)
        .optional()
        .describe("Optional job timeout in seconds"),
    env: z
        .record(z.string())
        .optional()
        .default({})
        .describe("Optional environment overrides for the spawned darwin-web-harvester process"),
    extra_argv: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Extra raw argv segments (advanced; appended as-is)"),
});

const DarwinResearchHarvesterSchema = z.object({
    query: z.array(z.string()).optional().default([]).describe("One or more search queries"),
    backend: z
        .enum(["pubmed", "arxiv", "openalex", "crossref", "europepmc", "all"])
        .optional()
        .describe("Which backend(s) to query (default: all)"),
    max_results: z
        .number()
        .int()
        .min(1)
        .max(100)
        .optional()
        .describe("Max results per query per backend (default: 10)"),
    topics_file: z
        .string()
        .optional()
        .describe("Optional topics file path on the BEAGLE core server host"),
    topic: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Only run specific topic(s) from the topics file (repeatable)"),
    tag: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Extra tags to attach to all ingested papers"),
    rss: z
        .array(z.string())
        .optional()
        .default([])
        .describe("RSS/Atom feed URLs (repeatable)"),
    arxiv_category: z
        .array(z.string())
        .optional()
        .default([])
        .describe("arXiv categories to harvest (repeatable), e.g. cs.AI"),
    max_bytes: z
        .number()
        .int()
        .min(1)
        .max(50_000_000)
        .optional()
        .describe("Max bytes to download per RSS feed (default: 2_000_000)"),
    out_dir: z
        .string()
        .optional()
        .describe("Output directory for harvested markdown stubs"),
    ledger_db_url: z
        .string()
        .optional()
        .describe("Optional Postgres URL to enable the ingestion ledger"),
    force: z
        .boolean()
        .optional()
        .describe("Force re-index even if ledger indicates content is unchanged"),
    timeout_secs: z
        .number()
        .int()
        .min(10)
        .max(7200)
        .optional()
        .describe("Optional job timeout in seconds"),
    env: z
        .record(z.string())
        .optional()
        .default({})
        .describe("Optional environment overrides for the spawned darwin-research-harvester process"),
    extra_argv: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Extra raw argv segments (advanced; appended as-is)"),
});

const DarwinEvalSchema = z.object({
    eval_file: z
        .string()
        .optional()
        .default("scripts/darwin-eval.yaml")
        .describe("Eval file path on the BEAGLE core server host"),
    k: z
        .number()
        .int()
        .min(1)
        .max(100)
        .optional()
        .describe("Default top-k per query (default: 10)"),
    history_file: z
        .string()
        .optional()
        .describe("Append eval runs to this JSONL file for trend tracking"),
    min_mrr: z
        .number()
        .min(0)
        .max(1)
        .optional()
        .describe("Fail if MRR is below this value"),
    max_mrr_drop: z
        .number()
        .min(0)
        .max(1)
        .optional()
        .describe("Fail if MRR dropped by more than this value vs previous run"),
    min_recall: z
        .number()
        .min(0)
        .max(1)
        .optional()
        .describe("Fail if recall@k is below this value"),
    max_recall_drop: z
        .number()
        .min(0)
        .max(1)
        .optional()
        .describe("Fail if recall@k dropped by more than this value vs previous run"),
    timeout_secs: z
        .number()
        .int()
        .min(10)
        .max(7200)
        .optional()
        .describe("Optional job timeout in seconds"),
    env: z
        .record(z.string())
        .optional()
        .default({})
        .describe("Optional environment overrides for the spawned darwin-eval process"),
    extra_argv: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Extra raw argv segments (advanced; appended as-is)"),
});

const DarwinNightlyWorkflowSchema = z.object({
    run_indexer: z
        .boolean()
        .optional()
        .default(false)
        .describe("Whether to run the incremental indexer step"),
    run_research: z
        .boolean()
        .optional()
        .default(true)
        .describe("Whether to run the research harvester step"),
    run_web: z
        .boolean()
        .optional()
        .default(true)
        .describe("Whether to run the web harvester step"),
    run_brief: z
        .boolean()
        .optional()
        .default(true)
        .describe("Whether to run the brief generation step"),
    run_eval: z
        .boolean()
        .optional()
        .default(true)
        .describe("Whether to run the eval step"),
    index_args: z
        .string()
        .optional()
        .describe("Raw args string for the indexer step (DARWIN_INDEX_ARGS)"),
    harvest_args: z
        .string()
        .optional()
        .describe("Raw args string for darwin-research-harvester (DARWIN_HARVEST_ARGS)"),
    web_harvest_args: z
        .string()
        .optional()
        .describe("Raw args string for darwin-web-harvester (DARWIN_WEB_HARVEST_ARGS)"),
    brief_args: z
        .string()
        .optional()
        .describe("Raw args string for darwin-brief (DARWIN_BRIEF_ARGS)"),
    eval_args: z
        .string()
        .optional()
        .describe("Raw args string for darwin-eval (DARWIN_EVAL_ARGS)"),
    error_webhook_url: z
        .string()
        .optional()
        .describe("Optional error webhook URL (DARWIN_NIGHTLY_ERROR_WEBHOOK_URL)"),
    success_webhook_url: z
        .string()
        .optional()
        .describe("Optional success webhook URL (DARWIN_NIGHTLY_SUCCESS_WEBHOOK_URL)"),
    timeout_secs: z
        .number()
        .int()
        .min(10)
        .max(86_400)
        .optional()
        .describe("Optional job timeout in seconds (default: none)"),
    env: z
        .record(z.string())
        .optional()
        .default({})
        .describe("Optional environment overrides for the spawned nightly process"),
    extra_argv: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Extra argv segments for the nightly script (advanced; appended as-is)"),
});

const DarwinKnowledgeManagerSchema = z.object({
    command: z
        .enum(["list", "scan", "add-paper", "add-docs", "add-book"])
        .describe("darwin-knowledge-manager subcommand"),
    dir: z
        .string()
        .optional()
        .describe("Base directory for scan (expects papers/, docs/, books/)"),
    path: z
        .string()
        .optional()
        .describe("File path for add-paper/add-docs/add-book"),
    title: z.string().optional().describe("Document title (required for add-*)"),
    author: z.string().optional().describe("Optional author (papers/books)"),
    year: z.number().int().optional().describe("Optional year (papers/books)"),
    doi: z.string().optional().describe("Optional DOI (papers)"),
    source: z
        .string()
        .optional()
        .describe("Optional source label (e.g., journal/site/library)"),
    tags: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Optional tags to attach"),
    chunk_size: z.number().int().min(100).max(10_000).optional(),
    chunk_overlap: z.number().int().min(0).max(5_000).optional(),
    papers_collection: z.string().optional(),
    docs_collection: z.string().optional(),
    books_collection: z.string().optional(),
    max_file_size: z.number().int().min(1).max(100_000_000).optional(),
    ledger_db_url: z.string().optional().describe("Optional Postgres URL for ledger"),
    force: z.boolean().optional().describe("Force re-index even if unchanged"),
    enrich_metadata: z
        .boolean()
        .optional()
        .describe("Enable metadata enrichment (DOI/arXiv extraction + Crossref/OpenAlex lookups)"),
    timeout_secs: z.number().int().min(10).max(86_400).optional(),
    env: z
        .record(z.string())
        .optional()
        .default({})
        .describe("Optional env overrides for the spawned darwin-knowledge-manager process"),
    extra_argv: z
        .array(z.string())
        .optional()
        .default([])
        .describe("Extra argv segments (advanced; appended as-is)"),
});

export function darwinTools(client: BeagleClient): McpTool[] {
    return [
        {
            name: "beagle_start_darwin_job",
            description: `Start a Darwin job (continuous RAG + ResearchOps).

Supported kinds:
- indexer: Incremental git-based repo indexing (server runs Rust indexer directly)
- research_harvester: Runs darwin-research-harvester (requires binary available on core server host)
- web_harvester: Runs darwin-web-harvester (requires binary available on core server host)
- knowledge_manager: Runs darwin-knowledge-manager (index local PDFs/docs/books into separate collections)
- brief: Runs darwin-brief (requires binary available on core server host)
- eval: Runs darwin-eval (requires binary available on core server host)
- nightly: Runs scripts/systemd/darwin-nightly.sh on the core server host (requires bash + darwin-* bins)

For non-indexer jobs, pass:
- config.argv: string[] (CLI args, excluding binary name)
- config.env: object (optional env var overrides)
- config.timeout_secs: number (optional)

Example (brief):
{ "kind": "brief", "config": { "argv": ["--topics-file", "scripts/darwin-research-topics.yaml", "--delta-days", "7"], "env": { "BEAGLE_QDRANT_COLLECTIONS": "darwin-papers,darwin-docs,darwin-books,darwin-repos" } } }

Example (indexer):
{ "kind": "indexer", "config": { "repo_path": ["/home/demetrios/beagle"], "sync": true } }`,
            inputSchema: {
                type: "object",
                properties: {
                    kind: {
                        type: "string",
                        enum: [
                            "indexer",
                            "research_harvester",
                            "web_harvester",
                            "knowledge_manager",
                            "brief",
                            "eval",
                            "nightly",
                        ],
                        description: "Darwin job kind",
                    },
                    config: {
                        type: "object",
                        description:
                            "Job configuration. For non-indexer jobs: { argv: string[], env?: object, timeout_secs?: number }",
                    },
                },
                required: ["kind"],
            },
            handler: async (args: unknown) => {
                const { kind, config } = StartDarwinJobSchema.parse(args);
                const result = await client.startDarwinJob(
                    kind,
                    config as Record<string, unknown>,
                );
                return sanitizeOutput({
                    job_id: result.job_id,
                    status: result.status,
                    kind,
                    message: `Darwin job started: ${kind} (job_id: ${result.job_id})`,
                });
            },
        },
        {
            name: "beagle_darwin_indexer",
            description: `Start Darwin incremental indexer (git-based) on the BEAGLE core server.

This calls BEAGLE Core: POST /api/jobs/darwin/start (kind="indexer"), which runs the Rust indexer in-process.

Notes:
- Prefer configuring secrets via the Core host env (systemd env files), not tool args.
- For GitHub discovery, set DARWIN_GITHUB_TOKEN/GITHUB_TOKEN/GH_TOKEN on the core server host if needed.

Examples:
- Index a local repo:
  { "repo_path": ["/root/beagle"], "sync": true }
- Index all public repos from a GitHub user:
  { "github_user": ["agourakis82"], "sync": true }
- Index repos for the authenticated GitHub user (may include private; requires token on host):
  { "github_me": true, "github_clone_ssh": true, "sync": true }
- Use a repo registry file:
  { "repos_file": ["scripts/darwin-repos.example.yaml"], "sync": true }`,
            inputSchema: {
                type: "object",
                properties: {
                    force: { type: "boolean" },
                    sync: { type: "boolean" },
                    repo_path: { type: "array", items: { type: "string" } },
                    repo_url: { type: "array", items: { type: "string" } },
                    repos_file: { type: "array", items: { type: "string" } },
                    github_user: { type: "array", items: { type: "string" } },
                    github_org: { type: "array", items: { type: "string" } },
                    github_me: { type: "boolean" },
                    github_api_base: { type: "string" },
                    github_include_forks: { type: "boolean" },
                    github_clone_ssh: { type: "boolean" },
                    repos_dir: { type: "string" },
                    state_file: { type: "string" },
                    qdrant_url: { type: "string" },
                    embedding_url: { type: "string" },
                    embedding_model: { type: "string" },
                    collection: { type: "string" },
                    error_webhook_url: { type: "string" },
                    success_webhook_url: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = DarwinIndexerSchema.parse(args);
                const result = await client.startDarwinJob("indexer", parsed);
                return sanitizeOutput({
                    job_id: result.job_id,
                    status: result.status,
                    message: `Darwin indexer job started (job_id: ${result.job_id})`,
                });
            },
        },
        {
            name: "beagle_darwin_brief_zai",
            description: `Start darwin-brief with BEAGLE_ROUTING_POLICY=zai-grok-deepseek (Z.ai → Grok → DeepSeek).

This is a convenience wrapper over beagle_start_darwin_job(kind="brief") that:
- Builds argv for darwin-brief
- Injects env:
  - BEAGLE_ROUTING_POLICY=zai-grok-deepseek
  - BEAGLE_ZAI_ENABLE=true

Prereqs on the BEAGLE core server host:
- darwin-brief binary available (PATH or DARWIN_BIN_DIR)
- Z.ai key present in the environment (ZAI_API_KEY) if you want Z.ai to be used

Use beagle_get_darwin_job_status / beagle_get_darwin_job_artifacts to follow up.`,
            inputSchema: {
                type: "object",
                properties: {
                    topics_file: {
                        type: "string",
                        description:
                            "Topics registry file path on the BEAGLE core server host (default: scripts/darwin-research-topics.yaml)",
                    },
                    topic: {
                        type: "array",
                        description:
                            "Only run specific topic(s) from the topics file (repeatable)",
                        items: { type: "string" },
                    },
                    out_dir: {
                        type: "string",
                        description:
                            "Output directory for briefs (overrides DARWIN_BRIEF_DIR)",
                    },
                    state_file: {
                        type: "string",
                        description:
                            "Brief state file path (overrides DARWIN_BRIEF_STATE_FILE)",
                    },
                    collections: {
                        type: "string",
                        description:
                            "Comma-separated Qdrant collections list (optional)",
                    },
                    k: {
                        type: "number",
                        description: "Top-k per query per collection (1-50)",
                        minimum: 1,
                        maximum: 50,
                    },
                    max_docs: {
                        type: "number",
                        description: "Max docs in brief (1-50)",
                        minimum: 1,
                        maximum: 50,
                    },
                    max_snippet_chars: {
                        type: "number",
                        description: "Max chars per snippet (100-5000)",
                        minimum: 100,
                        maximum: 5000,
                    },
                    no_llm: {
                        type: "boolean",
                        description:
                            "Skip LLM synthesis and emit retrieval report only",
                    },
                    delta_days: {
                        type: "number",
                        description:
                            "Compute changes since N days ago (0-365; 0 disables)",
                        minimum: 0,
                        maximum: 365,
                    },
                    strict_citations: {
                        type: "boolean",
                        description:
                            "Fail if out-of-range bracket citations are emitted",
                    },
                    min_citations: {
                        type: "number",
                        description:
                            "Minimum number of citations required when LLM is enabled",
                        minimum: 0,
                        maximum: 200,
                    },
                    timeout_secs: {
                        type: "number",
                        description: "Optional job timeout in seconds (10-3600)",
                        minimum: 10,
                        maximum: 3600,
                    },
                    env: {
                        type: "object",
                        description:
                            "Optional env overrides for the spawned darwin-brief process (string values only)",
                    },
                    extra_argv: {
                        type: "array",
                        description:
                            "Extra raw argv segments (advanced; appended as-is)",
                        items: { type: "string" },
                    },
                },
            },
            handler: async (args: unknown) => {
                const {
                    topics_file,
                    topic,
                    out_dir,
                    state_file,
                    collections,
                    k,
                    max_docs,
                    max_snippet_chars,
                    no_llm,
                    delta_days,
                    strict_citations,
                    min_citations,
                    timeout_secs,
                    env,
                    extra_argv,
                } = DarwinBriefZaiSchema.parse(args);

                const argv: string[] = ["--topics-file", topics_file];
                for (const t of topic) argv.push("--topic", t);
                if (out_dir) argv.push("--out-dir", out_dir);
                if (state_file) argv.push("--state-file", state_file);
                if (collections) argv.push("--collections", collections);
                if (typeof k === "number") argv.push("--k", String(k));
                if (typeof max_docs === "number")
                    argv.push("--max-docs", String(max_docs));
                if (typeof max_snippet_chars === "number")
                    argv.push("--max-snippet-chars", String(max_snippet_chars));
                if (no_llm) argv.push("--no-llm");
                if (typeof delta_days === "number")
                    argv.push("--delta-days", String(delta_days));
                if (strict_citations) argv.push("--strict-citations");
                if (typeof min_citations === "number")
                    argv.push("--min-citations", String(min_citations));
                argv.push(...extra_argv);

                const env_overrides: Record<string, string> = {
                    ...env,
                    BEAGLE_ROUTING_POLICY: "zai-grok-deepseek",
                    BEAGLE_ZAI_ENABLE: "true",
                };

                const result = await client.startDarwinJob("brief", {
                    argv,
                    env: env_overrides,
                    timeout_secs,
                });

                return sanitizeOutput({
                    job_id: result.job_id,
                    status: result.status,
                    kind: "brief",
                    routing_policy: "zai-grok-deepseek",
                    message: `Darwin job started: brief (zai policy) (job_id: ${result.job_id})`,
                });
            },
        },
        {
            name: "beagle_darwin_web_harvester",
            description: `Start darwin-web-harvester (URLs/RSS/sitemaps → darwin-docs).

This is a convenience wrapper over beagle_start_darwin_job(kind="web_harvester") that builds argv.

Note: This job does not use LLM routing, but the wrapper still injects:
- BEAGLE_ROUTING_POLICY=zai-grok-deepseek
- BEAGLE_ZAI_ENABLE=true

Prereqs on the BEAGLE core server host:
- darwin-web-harvester binary available (PATH or DARWIN_BIN_DIR)

Use beagle_get_darwin_job_status / beagle_get_darwin_job_artifacts to follow up.`,
            inputSchema: {
                type: "object",
                properties: {
                    sources_file: {
                        type: "string",
                        description: "Optional sources file path on the BEAGLE core server host",
                    },
                    source: {
                        type: "array",
                        description: "Only run specific source(s) from the sources file",
                        items: { type: "string" },
                    },
                    url: {
                        type: "array",
                        description: "One or more URLs to fetch",
                        items: { type: "string" },
                    },
                    rss: {
                        type: "array",
                        description: "RSS/Atom feed URLs",
                        items: { type: "string" },
                    },
                    sitemap: {
                        type: "array",
                        description: "Sitemap URLs",
                        items: { type: "string" },
                    },
                    allow_host: {
                        type: "array",
                        description: "Allow-list hosts",
                        items: { type: "string" },
                    },
                    deny_host: {
                        type: "array",
                        description: "Deny-list hosts",
                        items: { type: "string" },
                    },
                    allow_path_regex: {
                        type: "array",
                        description: "Allow-list path regexes (repeatable)",
                        items: { type: "string" },
                    },
                    deny_path_regex: {
                        type: "array",
                        description: "Deny-list path regexes (repeatable)",
                        items: { type: "string" },
                    },
                    allow_cross_host: {
                        type: "boolean",
                        description: "Allow crawling outside the seed host",
                    },
                    crawl_depth: {
                        type: "number",
                        description: "Crawl depth (0-5)",
                        minimum: 0,
                        maximum: 5,
                    },
                    max_urls: {
                        type: "number",
                        description: "Max URLs to fetch (1-5000)",
                        minimum: 1,
                        maximum: 5000,
                    },
                    max_bytes: {
                        type: "number",
                        description: "Max bytes per URL (1-50000000)",
                        minimum: 1,
                        maximum: 50000000,
                    },
                    concurrency: {
                        type: "number",
                        description: "Global concurrency (1-64)",
                        minimum: 1,
                        maximum: 64,
                    },
                    per_host_concurrency: {
                        type: "number",
                        description: "Per-host concurrency (1-32)",
                        minimum: 1,
                        maximum: 32,
                    },
                    host_delay_ms: {
                        type: "number",
                        description: "Host delay ms (0-60000)",
                        minimum: 0,
                        maximum: 60000,
                    },
                    max_links: {
                        type: "number",
                        description: "Max discovered links (0-50000)",
                        minimum: 0,
                        maximum: 50000,
                    },
                    ignore_robots: {
                        type: "boolean",
                        description: "Ignore robots.txt",
                    },
                    robots_fail_closed: {
                        type: "boolean",
                        description:
                            "If robots.txt cannot be fetched, skip the host (fail closed)",
                    },
                    robots_user_agent: {
                        type: "string",
                        description: "User-agent used for robots.txt rules",
                    },
                    eval_after: {
                        type: "boolean",
                        description:
                            "Run eval gates after harvesting (fail on regression)",
                    },
                    eval_file: {
                        type: "string",
                        description: "Eval file path (passed as --eval-file)",
                    },
                    eval_k: {
                        type: "number",
                        description: "Eval top-k (passed as --eval-k)",
                        minimum: 1,
                        maximum: 200,
                    },
                    eval_history_file: {
                        type: "string",
                        description:
                            "Eval history JSONL file path (passed as --eval-history-file)",
                    },
                    eval_min_mrr: {
                        type: "number",
                        description:
                            "Fail if MRR is below this value (passed as --eval-min-mrr)",
                        minimum: 0,
                        maximum: 1,
                    },
                    eval_max_mrr_drop: {
                        type: "number",
                        description:
                            "Fail if MRR dropped more than this value (passed as --eval-max-mrr-drop)",
                        minimum: 0,
                        maximum: 1,
                    },
                    eval_min_recall: {
                        type: "number",
                        description:
                            "Fail if recall@k is below this value (passed as --eval-min-recall)",
                        minimum: 0,
                        maximum: 1,
                    },
                    eval_max_recall_drop: {
                        type: "number",
                        description:
                            "Fail if recall@k dropped more than this value (passed as --eval-max-recall-drop)",
                        minimum: 0,
                        maximum: 1,
                    },
                    tag: {
                        type: "array",
                        description: "Extra tags to attach to all ingested docs",
                        items: { type: "string" },
                    },
                    license: {
                        type: "string",
                        description: "Optional license string to attach to ingested docs",
                    },
                    out_dir: {
                        type: "string",
                        description:
                            "Output directory for harvested markdown stubs",
                    },
                    ledger_db_url: {
                        type: "string",
                        description:
                            "Optional Postgres URL to enable the ingestion ledger",
                    },
                    force: {
                        type: "boolean",
                        description:
                            "Force re-index even if ledger indicates unchanged",
                    },
                    timeout_secs: {
                        type: "number",
                        description: "Optional job timeout in seconds (10-7200)",
                        minimum: 10,
                        maximum: 7200,
                    },
                    env: {
                        type: "object",
                        description:
                            "Optional env overrides for the spawned darwin-web-harvester process (string values only)",
                    },
                    extra_argv: {
                        type: "array",
                        description:
                            "Extra raw argv segments (advanced; appended as-is)",
                        items: { type: "string" },
                    },
                },
            },
            handler: async (args: unknown) => {
                const {
                    sources_file,
                    source,
                    url,
                    rss,
                    sitemap,
                    allow_host,
                    deny_host,
                    allow_path_regex,
                    deny_path_regex,
                    allow_cross_host,
                    crawl_depth,
                    max_urls,
                    max_bytes,
                    concurrency,
                    per_host_concurrency,
                    host_delay_ms,
                    max_links,
                    ignore_robots,
                    robots_fail_closed,
                    robots_user_agent,
                    eval_after,
                    eval_file,
                    eval_k,
                    eval_history_file,
                    eval_min_mrr,
                    eval_max_mrr_drop,
                    eval_min_recall,
                    eval_max_recall_drop,
                    tag,
                    license,
                    out_dir,
                    ledger_db_url,
                    force,
                    timeout_secs,
                    env,
                    extra_argv,
                } = DarwinWebHarvesterSchema.parse(args);

                const has_seed =
                    url.length > 0 ||
                    rss.length > 0 ||
                    sitemap.length > 0 ||
                    Boolean(sources_file) ||
                    extra_argv.some((a) => {
                        const lower = a.toLowerCase();
                        return (
                            lower === "--url" ||
                            lower.startsWith("--url=") ||
                            lower === "--rss" ||
                            lower.startsWith("--rss=") ||
                            lower === "--sitemap" ||
                            lower.startsWith("--sitemap=") ||
                            lower === "--sources-file" ||
                            lower.startsWith("--sources-file=")
                        );
                    });
                if (!has_seed) {
                    throw new Error(
                        "Provide at least one seed via url/rss/sitemap/sources_file (or pass --url/--rss/--sitemap/--sources-file in extra_argv).",
                    );
                }

                const argv: string[] = [];
                if (sources_file) argv.push("--sources-file", sources_file);
                for (const s of source) argv.push("--source", s);
                for (const u of url) argv.push("--url", u);
                for (const r of rss) argv.push("--rss", r);
                for (const s of sitemap) argv.push("--sitemap", s);
                for (const h of allow_host) argv.push("--allow-host", h);
                for (const h of deny_host) argv.push("--deny-host", h);
                for (const r of allow_path_regex) argv.push("--allow-path-regex", r);
                for (const r of deny_path_regex) argv.push("--deny-path-regex", r);
                if (typeof max_bytes === "number") argv.push("--max-bytes", String(max_bytes));
                if (typeof concurrency === "number") argv.push("--concurrency", String(concurrency));
                if (typeof per_host_concurrency === "number")
                    argv.push("--per-host-concurrency", String(per_host_concurrency));
                if (typeof host_delay_ms === "number")
                    argv.push("--host-delay-ms", String(host_delay_ms));
                if (typeof max_links === "number") argv.push("--max-links", String(max_links));
                if (typeof crawl_depth === "number")
                    argv.push("--crawl-depth", String(crawl_depth));
                if (typeof max_urls === "number") argv.push("--max-urls", String(max_urls));
                if (allow_cross_host) argv.push("--allow-cross-host");
                if (ignore_robots) argv.push("--ignore-robots");
                if (robots_user_agent)
                    argv.push("--robots-user-agent", robots_user_agent);
                if (robots_fail_closed) argv.push("--robots-fail-closed");
                if (eval_after) argv.push("--eval-after");
                if (eval_file) argv.push("--eval-file", eval_file);
                if (typeof eval_k === "number") argv.push("--eval-k", String(eval_k));
                if (eval_history_file)
                    argv.push("--eval-history-file", eval_history_file);
                if (typeof eval_min_mrr === "number")
                    argv.push("--eval-min-mrr", String(eval_min_mrr));
                if (typeof eval_max_mrr_drop === "number")
                    argv.push("--eval-max-mrr-drop", String(eval_max_mrr_drop));
                if (typeof eval_min_recall === "number")
                    argv.push("--eval-min-recall", String(eval_min_recall));
                if (typeof eval_max_recall_drop === "number")
                    argv.push("--eval-max-recall-drop", String(eval_max_recall_drop));
                for (const t of tag) argv.push("--tag", t);
                if (license) argv.push("--license", license);
                if (out_dir) argv.push("--out-dir", out_dir);
                if (ledger_db_url) argv.push("--ledger-db-url", ledger_db_url);
                if (force) argv.push("--force");
                argv.push(...extra_argv);

                const env_overrides: Record<string, string> = {
                    ...env,
                    BEAGLE_ROUTING_POLICY: "zai-grok-deepseek",
                    BEAGLE_ZAI_ENABLE: "true",
                };

                const result = await client.startDarwinJob("web_harvester", {
                    argv,
                    env: env_overrides,
                    timeout_secs,
                });

                return sanitizeOutput({
                    job_id: result.job_id,
                    status: result.status,
                    kind: "web_harvester",
                    message: `Darwin job started: web_harvester (job_id: ${result.job_id})`,
                });
            },
        },
        {
            name: "beagle_darwin_research_harvester",
            description: `Start darwin-research-harvester (PubMed/arXiv/OpenAlex/Crossref/EuropePMC → darwin-papers).

This is a convenience wrapper over beagle_start_darwin_job(kind="research_harvester") that builds argv.

Prereqs on the BEAGLE core server host:
- darwin-research-harvester binary available (PATH or DARWIN_BIN_DIR)`,
            inputSchema: {
                type: "object",
                properties: {
                    query: { type: "array", items: { type: "string" } },
                    backend: {
                        type: "string",
                        enum: ["pubmed", "arxiv", "openalex", "crossref", "europepmc", "all"],
                        description: "Which backend(s) to query (default: all)",
                    },
                    max_results: {
                        type: "number",
                        minimum: 1,
                        maximum: 100,
                        description: "Max results per query per backend (default: 10)",
                    },
                    topics_file: {
                        type: "string",
                        description: "Optional topics file path on the BEAGLE core server host",
                    },
                    topic: { type: "array", items: { type: "string" } },
                    tag: { type: "array", items: { type: "string" } },
                    rss: { type: "array", items: { type: "string" } },
                    arxiv_category: { type: "array", items: { type: "string" } },
                    max_bytes: {
                        type: "number",
                        minimum: 1,
                        maximum: 50000000,
                        description: "Max bytes to download per RSS feed (default: 2_000_000)",
                    },
                    out_dir: { type: "string" },
                    ledger_db_url: { type: "string" },
                    force: { type: "boolean" },
                    timeout_secs: {
                        type: "number",
                        minimum: 10,
                        maximum: 7200,
                        description: "Optional job timeout in seconds",
                    },
                    env: {
                        type: "object",
                        description: "Optional env overrides (string values only)",
                    },
                    extra_argv: { type: "array", items: { type: "string" } },
                },
            },
            handler: async (args: unknown) => {
                const {
                    query,
                    backend,
                    max_results,
                    topics_file,
                    topic,
                    tag,
                    rss,
                    arxiv_category,
                    max_bytes,
                    out_dir,
                    ledger_db_url,
                    force,
                    timeout_secs,
                    env,
                    extra_argv,
                } = DarwinResearchHarvesterSchema.parse(args);

                const has_seed =
                    query.length > 0 ||
                    rss.length > 0 ||
                    arxiv_category.length > 0 ||
                    Boolean(topics_file) ||
                    extra_argv.some((a) => {
                        const lower = a.toLowerCase();
                        return (
                            lower === "--query" ||
                            lower.startsWith("--query=") ||
                            lower === "--topics-file" ||
                            lower.startsWith("--topics-file=") ||
                            lower === "--rss" ||
                            lower.startsWith("--rss=") ||
                            lower === "--arxiv-category" ||
                            lower.startsWith("--arxiv-category=")
                        );
                    });
                if (!has_seed) {
                    throw new Error(
                        "Provide at least one seed via query/topics_file/rss/arxiv_category (or pass --query/--topics-file/--rss/--arxiv-category in extra_argv).",
                    );
                }

                const argv: string[] = [];
                for (const q of query) argv.push("--query", q);
                if (backend) argv.push("--backend", backend);
                if (typeof max_results === "number")
                    argv.push("--max-results", String(max_results));
                if (topics_file) argv.push("--topics-file", topics_file);
                for (const t of topic) argv.push("--topic", t);
                for (const t of tag) argv.push("--tag", t);
                for (const r of rss) argv.push("--rss", r);
                for (const c of arxiv_category) argv.push("--arxiv-category", c);
                if (typeof max_bytes === "number")
                    argv.push("--max-bytes", String(max_bytes));
                if (out_dir) argv.push("--out-dir", out_dir);
                if (ledger_db_url) argv.push("--ledger-db-url", ledger_db_url);
                if (force) argv.push("--force");
                argv.push(...extra_argv);

                const result = await client.startDarwinJob("research_harvester", {
                    argv,
                    env,
                    timeout_secs,
                });

                return sanitizeOutput({
                    job_id: result.job_id,
                    status: result.status,
                    kind: "research_harvester",
                    message: `Darwin job started: research_harvester (job_id: ${result.job_id})`,
                });
            },
        },
        {
            name: "beagle_darwin_eval",
            description: `Start darwin-eval (retrieval quality gates against golden queries).

This is a convenience wrapper over beagle_start_darwin_job(kind="eval") that builds argv.

Prereqs on the BEAGLE core server host:
- darwin-eval binary available (PATH or DARWIN_BIN_DIR)`,
            inputSchema: {
                type: "object",
                properties: {
                    eval_file: { type: "string" },
                    k: { type: "number", minimum: 1, maximum: 100 },
                    history_file: { type: "string" },
                    min_mrr: { type: "number", minimum: 0, maximum: 1 },
                    max_mrr_drop: { type: "number", minimum: 0, maximum: 1 },
                    min_recall: { type: "number", minimum: 0, maximum: 1 },
                    max_recall_drop: { type: "number", minimum: 0, maximum: 1 },
                    timeout_secs: { type: "number", minimum: 10, maximum: 7200 },
                    env: {
                        type: "object",
                        description: "Optional env overrides (string values only)",
                    },
                    extra_argv: { type: "array", items: { type: "string" } },
                },
            },
            handler: async (args: unknown) => {
                const {
                    eval_file,
                    k,
                    history_file,
                    min_mrr,
                    max_mrr_drop,
                    min_recall,
                    max_recall_drop,
                    timeout_secs,
                    env,
                    extra_argv,
                } = DarwinEvalSchema.parse(args);

                const argv: string[] = ["--eval-file", eval_file];
                if (typeof k === "number") argv.push("--k", String(k));
                if (history_file) argv.push("--history-file", history_file);
                if (typeof min_mrr === "number") argv.push("--min-mrr", String(min_mrr));
                if (typeof max_mrr_drop === "number")
                    argv.push("--max-mrr-drop", String(max_mrr_drop));
                if (typeof min_recall === "number")
                    argv.push("--min-recall", String(min_recall));
                if (typeof max_recall_drop === "number")
                    argv.push("--max-recall-drop", String(max_recall_drop));
                argv.push(...extra_argv);

                const result = await client.startDarwinJob("eval", {
                    argv,
                    env,
                    timeout_secs,
                });

                return sanitizeOutput({
                    job_id: result.job_id,
                    status: result.status,
                    kind: "eval",
                    message: `Darwin job started: eval (job_id: ${result.job_id})`,
                });
            },
        },
        {
            name: "beagle_darwin_knowledge_manager",
            description: `Start darwin-knowledge-manager to index local papers/docs/books into separate Qdrant collections.

This is a convenience wrapper over beagle_start_darwin_job(kind="knowledge_manager") that builds argv.

Prereqs on the BEAGLE core server host:
- darwin-knowledge-manager binary available (PATH or DARWIN_BIN_DIR)
- for PDFs: pdftotext installed (poppler-utils)

Example (scan):
{ "command": "scan", "dir": "/home/demetrios/knowledge" }

Example (add-paper):
{ "command": "add-paper", "path": "/home/demetrios/knowledge/papers/paper.pdf", "title": "My Paper", "doi": "10.xxxx/yyy", "tags": ["hrv","sota"] }`,
            inputSchema: {
                type: "object",
                properties: {
                    command: {
                        type: "string",
                        enum: ["list", "scan", "add-paper", "add-docs", "add-book"],
                    },
                    dir: { type: "string" },
                    path: { type: "string" },
                    title: { type: "string" },
                    author: { type: "string" },
                    year: { type: "number" },
                    doi: { type: "string" },
                    source: { type: "string" },
                    tags: { type: "array", items: { type: "string" } },
                    chunk_size: { type: "number" },
                    chunk_overlap: { type: "number" },
                    papers_collection: { type: "string" },
                    docs_collection: { type: "string" },
                    books_collection: { type: "string" },
                    max_file_size: { type: "number" },
                    ledger_db_url: { type: "string" },
                    force: { type: "boolean" },
                    enrich_metadata: {
                        type: "boolean",
                        description:
                            "Enable metadata enrichment (DOI/arXiv extraction + Crossref/OpenAlex lookups)",
                    },
                    timeout_secs: { type: "number", minimum: 10, maximum: 86400 },
                    env: {
                        type: "object",
                        description: "Optional env overrides (string values only)",
                    },
                    extra_argv: { type: "array", items: { type: "string" } },
                },
                required: ["command"],
            },
            handler: async (args: unknown) => {
                const {
                    command,
                    dir,
                    path,
                    title,
                    author,
                    year,
                    doi,
                    source,
                    tags,
                    chunk_size,
                    chunk_overlap,
                    papers_collection,
                    docs_collection,
                    books_collection,
                    max_file_size,
                    ledger_db_url,
                    force,
                    enrich_metadata,
                    timeout_secs,
                    env,
                    extra_argv,
                } = DarwinKnowledgeManagerSchema.parse(args);

                const argv: string[] = [];
                if (typeof chunk_size === "number")
                    argv.push("--chunk-size", String(chunk_size));
                if (typeof chunk_overlap === "number")
                    argv.push("--chunk-overlap", String(chunk_overlap));
                if (papers_collection)
                    argv.push("--papers-collection", papers_collection);
                if (docs_collection) argv.push("--docs-collection", docs_collection);
                if (books_collection) argv.push("--books-collection", books_collection);
                if (typeof max_file_size === "number")
                    argv.push("--max-file-size", String(max_file_size));
                if (ledger_db_url) argv.push("--ledger-db-url", ledger_db_url);
                if (force) argv.push("--force");
                if (typeof enrich_metadata === "boolean")
                    argv.push("--enrich-metadata", String(enrich_metadata));

                argv.push(command);

                if (command === "scan") {
                    if (!dir) throw new Error('command="scan" requires "dir"');
                    argv.push(dir);
                } else if (command === "add-paper") {
                    if (!path || !title)
                        throw new Error('command="add-paper" requires "path" and "title"');
                    argv.push(path, "--title", title);
                    if (author) argv.push("--author", author);
                    if (typeof year === "number") argv.push("--year", String(year));
                    if (doi) argv.push("--doi", doi);
                    if (source) argv.push("--source", source);
                    if (tags.length > 0) argv.push("--tags", ...tags);
                } else if (command === "add-docs") {
                    if (!path || !title)
                        throw new Error('command="add-docs" requires "path" and "title"');
                    argv.push(path, "--title", title);
                    if (source) argv.push("--source", source);
                    if (tags.length > 0) argv.push("--tags", ...tags);
                } else if (command === "add-book") {
                    if (!path || !title)
                        throw new Error('command="add-book" requires "path" and "title"');
                    argv.push(path, "--title", title);
                    if (author) argv.push("--author", author);
                    if (typeof year === "number") argv.push("--year", String(year));
                    if (source) argv.push("--source", source);
                    if (tags.length > 0) argv.push("--tags", ...tags);
                } else if (command === "list") {
                    // no extra args
                } else {
                    throw new Error(`Unsupported command: ${command}`);
                }

                argv.push(...extra_argv);

                const result = await client.startDarwinJob("knowledge_manager", {
                    argv,
                    env,
                    timeout_secs,
                });

                return sanitizeOutput({
                    job_id: result.job_id,
                    status: result.status,
                    kind: "knowledge_manager",
                    command,
                    message: `Darwin job started: knowledge_manager (${command}) (job_id: ${result.job_id})`,
                });
            },
        },
        {
            name: "beagle_darwin_nightly_workflow_zai",
            description: `Start the full nightly ResearchOps workflow (research → web → brief → eval) with Z.ai routing policy.

This triggers BEAGLE Core: POST /api/jobs/darwin/start (kind="nightly"), which runs:
- scripts/systemd/darwin-nightly.sh

Env injected by this tool:
- BEAGLE_ROUTING_POLICY=zai-grok-deepseek
- BEAGLE_ZAI_ENABLE=true

Prereqs on the BEAGLE core server host:
- scripts/systemd/darwin-nightly.sh present under BEAGLE_WORKSPACE_ROOT
- /usr/local/bin/darwin-* binaries installed (or available in PATH)
- ZAI_API_KEY set if you want Z.ai to be used for darwin-brief

Use beagle_get_darwin_job_status / beagle_get_darwin_job_artifacts to follow up.`,
            inputSchema: {
                type: "object",
                properties: {
                    run_indexer: { type: "boolean" },
                    run_research: { type: "boolean" },
                    run_web: { type: "boolean" },
                    run_brief: { type: "boolean" },
                    run_eval: { type: "boolean" },
                    index_args: { type: "string" },
                    harvest_args: { type: "string" },
                    web_harvest_args: { type: "string" },
                    brief_args: { type: "string" },
                    eval_args: { type: "string" },
                    error_webhook_url: { type: "string" },
                    success_webhook_url: { type: "string" },
                    timeout_secs: { type: "number", minimum: 10, maximum: 86400 },
                    env: {
                        type: "object",
                        description:
                            "Optional env overrides for the spawned nightly process (string values only)",
                    },
                    extra_argv: { type: "array", items: { type: "string" } },
                },
            },
            handler: async (args: unknown) => {
                const {
                    run_indexer,
                    run_research,
                    run_web,
                    run_brief,
                    run_eval,
                    index_args,
                    harvest_args,
                    web_harvest_args,
                    brief_args,
                    eval_args,
                    error_webhook_url,
                    success_webhook_url,
                    timeout_secs,
                    env,
                    extra_argv,
                } = DarwinNightlyWorkflowSchema.parse(args);

                if (!run_indexer && !run_research && !run_web && !run_brief && !run_eval) {
                    throw new Error("At least one step must be enabled.");
                }

                const env_overrides: Record<string, string> = {
                    ...env,
                    BEAGLE_ROUTING_POLICY: "zai-grok-deepseek",
                    BEAGLE_ZAI_ENABLE: "true",
                    DARWIN_NIGHTLY_RUN_INDEXER: run_indexer ? "1" : "0",
                    DARWIN_NIGHTLY_RUN_RESEARCH: run_research ? "1" : "0",
                    DARWIN_NIGHTLY_RUN_WEB: run_web ? "1" : "0",
                    DARWIN_NIGHTLY_RUN_BRIEF: run_brief ? "1" : "0",
                    DARWIN_NIGHTLY_RUN_EVAL: run_eval ? "1" : "0",
                };

                if (index_args) env_overrides.DARWIN_INDEX_ARGS = index_args;
                if (harvest_args) env_overrides.DARWIN_HARVEST_ARGS = harvest_args;
                if (web_harvest_args)
                    env_overrides.DARWIN_WEB_HARVEST_ARGS = web_harvest_args;
                if (brief_args) env_overrides.DARWIN_BRIEF_ARGS = brief_args;
                if (eval_args) env_overrides.DARWIN_EVAL_ARGS = eval_args;
                if (error_webhook_url)
                    env_overrides.DARWIN_NIGHTLY_ERROR_WEBHOOK_URL = error_webhook_url;
                if (success_webhook_url)
                    env_overrides.DARWIN_NIGHTLY_SUCCESS_WEBHOOK_URL = success_webhook_url;

                const result = await client.startDarwinJob("nightly", {
                    argv: extra_argv,
                    env: env_overrides,
                    timeout_secs,
                });

                return sanitizeOutput({
                    job_id: result.job_id,
                    status: result.status,
                    kind: "nightly",
                    routing_policy: "zai-grok-deepseek",
                    steps: {
                        indexer: run_indexer,
                        research: run_research,
                        web: run_web,
                        brief: run_brief,
                        eval: run_eval,
                    },
                    message: `Darwin job started: nightly workflow (zai policy) (job_id: ${result.job_id})`,
                });
            },
        },
        {
            name: "beagle_darwin_nightly_workflow_minimax",
            description: `Start the full nightly ResearchOps workflow (research → web → brief → eval) with MiniMax routing policy.

This triggers BEAGLE Core: POST /api/jobs/darwin/start (kind="nightly"), which runs:
- scripts/systemd/darwin-nightly.sh

Env injected by this tool:
- BEAGLE_ROUTING_POLICY=minimax-grok-deepseek
- BEAGLE_MINIMAX_ENABLE=true

Prereqs on the BEAGLE core server host:
- scripts/systemd/darwin-nightly.sh present under BEAGLE_WORKSPACE_ROOT
- /usr/local/bin/darwin-* binaries installed (or available in PATH)
- MINIMAX_API_KEY set if you want MiniMax to be used for darwin-brief

Use beagle_get_darwin_job_status / beagle_get_darwin_job_artifacts to follow up.`,
            inputSchema: {
                type: "object",
                properties: {
                    run_indexer: { type: "boolean" },
                    run_research: { type: "boolean" },
                    run_web: { type: "boolean" },
                    run_brief: { type: "boolean" },
                    run_eval: { type: "boolean" },
                    index_args: { type: "string" },
                    harvest_args: { type: "string" },
                    web_harvest_args: { type: "string" },
                    brief_args: { type: "string" },
                    eval_args: { type: "string" },
                    error_webhook_url: { type: "string" },
                    success_webhook_url: { type: "string" },
                    timeout_secs: { type: "number", minimum: 10, maximum: 86400 },
                    env: {
                        type: "object",
                        description:
                            "Optional env overrides for the spawned nightly process (string values only)",
                    },
                    extra_argv: { type: "array", items: { type: "string" } },
                },
            },
            handler: async (args: unknown) => {
                const {
                    run_indexer,
                    run_research,
                    run_web,
                    run_brief,
                    run_eval,
                    index_args,
                    harvest_args,
                    web_harvest_args,
                    brief_args,
                    eval_args,
                    error_webhook_url,
                    success_webhook_url,
                    timeout_secs,
                    env,
                    extra_argv,
                } = DarwinNightlyWorkflowSchema.parse(args);

                if (!run_indexer && !run_research && !run_web && !run_brief && !run_eval) {
                    throw new Error("At least one step must be enabled.");
                }

                const env_overrides: Record<string, string> = {
                    ...env,
                    BEAGLE_ROUTING_POLICY: "minimax-grok-deepseek",
                    BEAGLE_MINIMAX_ENABLE: "true",
                    DARWIN_NIGHTLY_RUN_INDEXER: run_indexer ? "1" : "0",
                    DARWIN_NIGHTLY_RUN_RESEARCH: run_research ? "1" : "0",
                    DARWIN_NIGHTLY_RUN_WEB: run_web ? "1" : "0",
                    DARWIN_NIGHTLY_RUN_BRIEF: run_brief ? "1" : "0",
                    DARWIN_NIGHTLY_RUN_EVAL: run_eval ? "1" : "0",
                };

                if (index_args) env_overrides.DARWIN_INDEX_ARGS = index_args;
                if (harvest_args) env_overrides.DARWIN_HARVEST_ARGS = harvest_args;
                if (web_harvest_args)
                    env_overrides.DARWIN_WEB_HARVEST_ARGS = web_harvest_args;
                if (brief_args) env_overrides.DARWIN_BRIEF_ARGS = brief_args;
                if (eval_args) env_overrides.DARWIN_EVAL_ARGS = eval_args;
                if (error_webhook_url)
                    env_overrides.DARWIN_NIGHTLY_ERROR_WEBHOOK_URL = error_webhook_url;
                if (success_webhook_url)
                    env_overrides.DARWIN_NIGHTLY_SUCCESS_WEBHOOK_URL = success_webhook_url;

                const result = await client.startDarwinJob("nightly", {
                    argv: extra_argv,
                    env: env_overrides,
                    timeout_secs,
                });

                return sanitizeOutput({
                    job_id: result.job_id,
                    status: result.status,
                    kind: "nightly",
                    routing_policy: "minimax-grok-deepseek",
                    steps: {
                        indexer: run_indexer,
                        research: run_research,
                        web: run_web,
                        brief: run_brief,
                        eval: run_eval,
                    },
                    message: `Darwin job started: nightly workflow (minimax policy) (job_id: ${result.job_id})`,
                });
            },
        },
        {
            name: "beagle_get_darwin_job_status",
            description: `Get status of a Darwin job.

Returns:
- status: created | running | done | error
- timestamps
- error (if any)`,
            inputSchema: {
                type: "object",
                properties: {
                    job_id: {
                        type: "string",
                        description: "Job ID from beagle_start_darwin_job",
                    },
                },
                required: ["job_id"],
            },
            handler: async (args: unknown) => {
                const { job_id } = GetDarwinJobStatusSchema.parse(args);
                const result = await client.getDarwinJobStatus(job_id);
                return sanitizeOutput({
                    job_id: result.job_id,
                    kind: result.kind,
                    status: result.status,
                    created_at: result.created_at,
                    updated_at: result.updated_at,
                    error: result.error || null,
                });
            },
        },
        {
            name: "beagle_get_darwin_job_artifacts",
            description: `Get artifacts (paths/logs) from a Darwin job.

Returns:
- output_paths: array of job files (job_config.json, job_summary.json, job.log)
- result_json: optional structured summary`,
            inputSchema: {
                type: "object",
                properties: {
                    job_id: {
                        type: "string",
                        description: "Job ID from beagle_start_darwin_job",
                    },
                },
                required: ["job_id"],
            },
            handler: async (args: unknown) => {
                const { job_id } = GetDarwinJobArtifactsSchema.parse(args);
                const result = await client.getDarwinJobArtifacts(job_id);
                return sanitizeOutput({
                    job_id: result.job_id,
                    kind: result.kind,
                    status: result.status,
                    output_paths: result.output_paths,
                    result_json: result.result_json ?? null,
                });
            },
        },
        {
            name: "beagle_list_recent_darwin_jobs",
            description: `List recent Darwin jobs with status metadata.

Useful for:
- finding job_ids to fetch status/artifacts
- tracking indexing/harvesting/brief/eval activity`,
            inputSchema: {
                type: "object",
                properties: {
                    limit: {
                        type: "number",
                        description: "Maximum number of jobs to return (1-50)",
                        minimum: 1,
                        maximum: 50,
                        default: 10,
                    },
                },
            },
            handler: async (args: unknown) => {
                const { limit } = ListRecentDarwinJobsSchema.parse(args);
                const result = await client.listRecentDarwinJobs(limit);
                return sanitizeOutput({
                    jobs: result.jobs.map((j) => ({
                        job_id: j.job_id,
                        kind: j.kind,
                        status: j.status,
                        created_at: j.created_at,
                        updated_at: j.updated_at,
                        error: j.error || null,
                    })),
                });
            },
        },
    ];
}
