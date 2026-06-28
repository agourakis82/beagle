/**
 * BEAGLE HTTP Client
 *
 * Thin wrapper around BEAGLE core HTTP API.
 */

import { logger } from "./logger.js";

export interface BeagleConfig {
    baseUrl: string;
    authToken?: string;
}

export class BeagleClient {
    private timeout: number;
    private maxRetries: number;
    private cockpitBaseUrl?: string;

    constructor(
        public baseUrl: string,
        private authToken?: string,
        timeout = 60000, // 60s default
        maxRetries = 2,
        cockpitBaseUrl?: string,
    ) {
        // Remove trailing slash
        this.baseUrl = baseUrl.replace(/\/$/, "");
        this.cockpitBaseUrl = cockpitBaseUrl?.replace(/\/$/, "");
        this.timeout = timeout;
        this.maxRetries = maxRetries;
    }

    async request<T>(
        method: string,
        path: string,
        body?: unknown,
        customTimeout?: number,
        baseUrl = this.baseUrl,
    ): Promise<T> {
        const url = `${baseUrl}${path}`;
        const timeoutMs = customTimeout || this.timeout;

        const headers: Record<string, string> = {
            "Content-Type": "application/json",
            // Consumer identity for beagle-core's consumer-policy gate. Without this the
            // server returns 401 when BEAGLE_CONSUMER_POLICY_ENABLED=true (the k8s/prod
            // path), which silently blocked the canonical index population (plan #1).
            "X-Beagle-Consumer": process.env.BEAGLE_CONSUMER || "beagle-operator",
        };

        if (this.authToken) {
            headers["Authorization"] = `Bearer ${this.authToken}`;
        }

        const options: RequestInit = {
            method,
            headers,
            signal: AbortSignal.timeout(timeoutMs),
        };

        if (body) {
            options.body = JSON.stringify(body);
        }

        let lastError: Error | null = null;

        for (let attempt = 0; attempt <= this.maxRetries; attempt++) {
            try {
                const response = await fetch(url, options);

                if (!response.ok) {
                    const errorText = await response.text();
                    const error = new Error(
                        `BEAGLE API error (${response.status}): ${errorText}`,
                    );

                    // Don't retry client errors (4xx)
                    if (response.status >= 400 && response.status < 500) {
                        throw error;
                    }

                    // Retry server errors (5xx) and network errors
                    if (attempt < this.maxRetries) {
                        logger.warn(
                            `Retrying ${method} ${path} (attempt ${attempt + 1}/${this.maxRetries})`,
                        );
                        await this.sleep(1000 * Math.pow(2, attempt)); // Exponential backoff
                        continue;
                    }

                    throw error;
                }

                // Handle empty responses
                const contentType = response.headers.get("content-type");
                if (contentType?.includes("application/json")) {
                    return (await response.json()) as T;
                }

                return {} as T;
            } catch (error) {
                lastError = error as Error;

                // Don't retry on abort/timeout or non-retryable errors
                if (
                    error instanceof Error &&
                    (error.name === "AbortError" ||
                        error.name === "TimeoutError")
                ) {
                    logger.error(
                        `BEAGLE API request timeout: ${method} ${path} (${timeoutMs}ms)`,
                    );
                    throw new Error(
                        `Request timeout after ${timeoutMs}ms: ${method} ${path}`,
                    );
                }

                // Retry network errors
                if (attempt < this.maxRetries) {
                    logger.warn(
                        `Retrying ${method} ${path} after error (attempt ${attempt + 1}/${this.maxRetries}): ${error}`,
                    );
                    await this.sleep(1000 * Math.pow(2, attempt));
                    continue;
                }

                logger.error(`BEAGLE API request failed: ${method} ${path}`, {
                    error,
                });
                throw error;
            }
        }

        throw lastError || new Error("Request failed after retries");
    }

    private sleep(ms: number): Promise<void> {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }

    async health(): Promise<{
        status: string;
        profile?: string;
        safe_mode?: boolean;
    }> {
        return this.request("GET", "/health");
    }

    async startPipeline(
        question: string,
        withTriad?: boolean,
        hrvAware?: boolean,
        experimentId?: string,
    ): Promise<{
        run_id: string;
        status: string;
    }> {
        return this.request("POST", "/api/pipeline/start", {
            question,
            with_triad: withTriad,
            hrv_aware: hrvAware,
            experiment_id: experimentId,
            source: "mcp",
        });
    }

    async getRunStatus(runId: string): Promise<{
        run_id: string;
        status: string;
        question?: string;
    }> {
        return this.request("GET", `/api/pipeline/status/${runId}`);
    }

    async getRunArtifacts(runId: string): Promise<{
        run_id: string;
        question?: string;
        draft_md?: string;
        draft_pdf?: string;
        triad_final_md?: string;
        triad_report_json?: string;
        llm_stats?: unknown;
    }> {
        return this.request("GET", `/api/run/${runId}/artifacts`);
    }

    async listRecentRuns(limit = 10): Promise<{
        runs: Array<{
            run_id: string;
            question: string;
            status: string;
            created_at?: string;
        }>;
    }> {
        return this.request("GET", `/api/runs/recent?limit=${limit}`);
    }

    async startScienceJob(
        kind: string,
        config: Record<string, unknown>,
    ): Promise<{
        job_id: string;
        status: string;
    }> {
        return this.request("POST", "/api/jobs/science/start", {
            kind,
            params: config,
        });
    }

    async getScienceJobStatus(jobId: string): Promise<{
        job_id: string;
        status: string;
        started_at?: string;
        completed_at?: string;
        error?: string;
    }> {
        return this.request("GET", `/api/jobs/science/status/${jobId}`);
    }

    async getScienceJobArtifacts(jobId: string): Promise<{
        job_id: string;
        artifacts: Array<{
            path: string;
            type: string;
        }>;
    }> {
        return this.request("GET", `/api/jobs/science/${jobId}/artifacts`);
    }

    async memoryQuery(
        query: string,
        maxItems = 5,
        scope?: string,
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
        // Trust-aware recall (provenance design §4): when MEMORY_PG_QUERY_URL is set, recall
        // from the canonical, tier-bearing memory-pg store and EXCLUDE `unverified` hits, so
        // a fabricated/orphaned memory is never surfaced to Claude Desktop as the user's truth.
        // Falls back to beagle-core when unset (e.g. the local stdio runtime that cannot reach
        // the in-cluster memory-pg service).
        const pgUrl = (process.env.MEMORY_PG_QUERY_URL || "").replace(/\/$/, "");
        if (pgUrl) {
            return this.memoryQueryPg(pgUrl, query, maxItems);
        }
        return this.request("POST", "/api/memory/query", {
            query,
            scope,
            max_items: maxItems,
        });
    }

    /**
     * Recall from memory-pg /query and drop `unverified` hits, adapting the canonical
     * store's result shape to the highlights shape callers expect. Best-effort.
     */
    private async memoryQueryPg(
        pgUrl: string,
        query: string,
        k: number,
    ): Promise<{
        summary: string;
        highlights: Array<{ source: string; date?: string; snippet: string; relevance: number }>;
        links: unknown[];
    }> {
        const token = process.env.MEMORY_PG_QUERY_TOKEN || "";
        const headers: Record<string, string> = { "Content-Type": "application/json" };
        if (token) headers["Authorization"] = `Bearer ${token}`;
        let results: Array<Record<string, unknown>> = [];
        try {
            const res = await fetch(`${pgUrl}/query`, {
                method: "POST",
                headers,
                body: JSON.stringify({ query, k }),
            });
            if (res.ok) {
                const j = (await res.json()) as { results?: Array<Record<string, unknown>> };
                results = Array.isArray(j?.results) ? j.results : [];
            }
        } catch {
            /* best-effort: fall through to an empty result */
        }
        const trusted = results.filter((r) => r?.["trust_tier"] !== "unverified");
        const excluded = results.length - trusted.length;
        return {
            summary:
                `Found ${trusted.length} trusted memor${trusted.length === 1 ? "y" : "ies"}` +
                (excluded ? ` (excluded ${excluded} unverified)` : "") +
                ".",
            highlights: trusted.map((r) => ({
                source: typeof r["source"] === "string" ? (r["source"] as string) : "memory-pg",
                date: typeof r["occurred_at"] === "string" ? (r["occurred_at"] as string) : undefined,
                snippet: typeof r["text"] === "string" ? (r["text"] as string) : "",
                relevance: typeof r["rerank_score"] === "number" ? (r["rerank_score"] as number) : 0,
            })),
            links: [],
        };
    }

    async memoryIngestChat(
        source: string,
        sessionId: string,
        turns: Array<{
            role: "user" | "assistant" | "system";
            content: string;
            timestamp?: string;
            model?: string;
        }>,
        tags: string[] = [],
        metadata: Record<string, unknown> = {},
    ): Promise<{
        status: string;
        session_id: string;
        num_turns: number;
        num_chunks: number;
    }> {
        return this.request("POST", "/api/memory/ingest_chat", {
            source,
            session_id: sessionId,
            turns,
            tags,
            metadata,
        });
    }

    async exocortexHome(activeProjectSlug?: string, platform?: string): Promise<unknown> {
        const params = new URLSearchParams();
        if (activeProjectSlug) params.set("active_project_slug", activeProjectSlug);
        if (platform) params.set("platform", platform);
        const suffix = params.toString() ? `?${params}` : "";
        return this.request("GET", `/api/exocortex/v1/home${suffix}`);
    }

    async chronoselfCurrent(): Promise<unknown> {
        return this.request("GET", "/api/exocortex/v1/chronoself/current");
    }

    async chronoselfCommits(limit = 20): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/chronoself/commits?limit=${encodeURIComponent(String(limit))}`,
        );
    }

    async chronoselfCreateCommit(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/chronoself/commits", body);
    }

    async omnimemoryImport(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/omnimemory/imports", body, 120000);
    }

    async assistedImportBatch(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/assisted-import", body, 120000);
    }

    async writeProbe(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/write/probe", body, 30000);
    }

    async failedWriteInbox(limit = 25): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/failed-writes?limit=${encodeURIComponent(String(limit))}`,
            undefined,
            30000,
        );
    }

    async failedWriteRescue(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/failed-writes/rescue", body, 120000);
    }

    async captureSessionStart(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/capture/sessions", body, 30000);
    }

    async captureSessionStatus(sessionId: string): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/capture/sessions/${encodeURIComponent(sessionId)}`,
            undefined,
            30000,
        );
    }

    async visualEvidenceAnalyze(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/capture/visual/analyze", body, 90000);
    }

    async captureReviewPromote(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/capture/review", body, 60000);
    }

    async memoryExport(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/export", body, 120000);
    }

    async memoryCandidates(limit = 20): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/memory/candidates?limit=${encodeURIComponent(String(limit))}`,
            undefined,
            30000,
        );
    }

    async memoryCandidateCreate(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/candidates", body, 30000);
    }

    async memoryCandidateQuorum(candidateId: string, body: unknown): Promise<unknown> {
        return this.request(
            "POST",
            `/api/exocortex/v1/memory/candidates/${encodeURIComponent(candidateId)}/quorum`,
            body,
            30000,
        );
    }

    async memoryGovernanceRun(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/governance/run", body, 120000);
    }

    async memoryGovernanceStatus(): Promise<unknown> {
        return this.request("GET", "/api/exocortex/v1/memory/governance/status", undefined, 30000);
    }

    async memoryContradictions(limit = 20): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/memory/contradictions?limit=${encodeURIComponent(String(limit))}`,
            undefined,
            30000,
        );
    }

    async projectMemory(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/project", body, 120000);
    }

    async memoryProjectionStatus(): Promise<unknown> {
        return this.request("GET", "/api/exocortex/v1/memory/projection/status", undefined, 30000);
    }

    async memoryGraphStatus(): Promise<unknown> {
        return this.request("GET", "/api/exocortex/v1/memory/graph/status", undefined, 30000);
    }

    async memoryGraphBakeoff(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/graph/bakeoff", body, 120000);
    }

    async memoryGraphBakeoffStatus(): Promise<unknown> {
        return this.request("GET", "/api/exocortex/v1/memory/graph/bakeoff/status", undefined, 30000);
    }

    async indexGraph(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/index-graph", body, 120000);
    }

    async memoryWorldsRecent(limit = 12): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/memory/worlds/recent?limit=${encodeURIComponent(String(limit))}`,
            undefined,
            30000,
        );
    }

    async graphRagQuery(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/graphrag/query", body, 60000);
    }

    async recallAnswer(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/recall/answer", body, 60000);
    }

    async contextCompile(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/context/compile", body, 120000);
    }

    async contextPackGet(packId: string): Promise<unknown> {
        return this.request("GET", `/api/exocortex/v1/context/packs/${encodeURIComponent(packId)}`, undefined, 30000);
    }

    async memoryEffectivenessRecord(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/effectiveness/events", body, 30000);
    }

    async coreMemoryPolicyStatus(): Promise<unknown> {
        return this.request("GET", "/api/exocortex/v1/memory/policy/status", undefined, 30000);
    }

    async coreDreamCycleRun(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/dreamcycle/run", body, 120000);
    }

    async coreDreamCycleStatus(): Promise<unknown> {
        return this.request("GET", "/api/exocortex/v1/memory/dreamcycle/status", undefined, 30000);
    }

    async sounioProgramCheck(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/sounio/programs/check", body, 30000);
    }

    async sounioClaimCheck(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/sounio/claims/check", body, 30000);
    }

    async sounioMomentType(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/sounio/moments/type", body, 30000);
    }

    async sounioMomentsRecent(limit = 25, projectSlug = "sounio"): Promise<unknown> {
        const params = new URLSearchParams({ limit: String(limit), project_slug: projectSlug });
        return this.request("GET", `/api/exocortex/v1/sounio/moments/recent?${params.toString()}`, undefined, 30000);
    }

    async sounioMomentReview(momentId: string, body: unknown): Promise<unknown> {
        return this.request(
            "POST",
            `/api/exocortex/v1/sounio/moments/${encodeURIComponent(momentId)}/review`,
            body,
            30000,
        );
    }

    async sounioWorkdayStatus(projectSlug = "sounio", limit = 20): Promise<unknown> {
        const params = new URLSearchParams({ project_slug: projectSlug, limit: String(limit) });
        return this.request("GET", `/api/exocortex/v1/sounio/workday/status?${params.toString()}`, undefined, 30000);
    }

    async sounioPaperRunStart(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/sounio/paperruns", body, 120000);
    }

    async sounioPaperRunStatus(paperRunId: string): Promise<unknown> {
        return this.request("GET", `/api/exocortex/v1/sounio/paperruns/${encodeURIComponent(paperRunId)}`, undefined, 30000);
    }

    async sounioPaperRunApproveStep(paperRunId: string, body: unknown): Promise<unknown> {
        return this.request(
            "POST",
            `/api/exocortex/v1/sounio/paperruns/${encodeURIComponent(paperRunId)}/approve-step`,
            body,
            30000,
        );
    }

    async sounioPaperRunAddClaim(paperRunId: string, body: unknown): Promise<unknown> {
        return this.request(
            "POST",
            `/api/exocortex/v1/sounio/paperruns/${encodeURIComponent(paperRunId)}/claims`,
            body,
            30000,
        );
    }

    async sounioClaimReview(paperRunId: string, claimId: string, body: unknown): Promise<unknown> {
        return this.request(
            "POST",
            `/api/exocortex/v1/sounio/paperruns/${encodeURIComponent(paperRunId)}/claims/${encodeURIComponent(claimId)}/review`,
            body,
            30000,
        );
    }

    async sounioPaperRunTheatre(paperRunId: string): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/sounio/paperruns/${encodeURIComponent(paperRunId)}/theatre`,
            undefined,
            30000,
        );
    }

    async sounioPaperRunPublicDigest(paperRunId: string): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/sounio/paperruns/${encodeURIComponent(paperRunId)}/public-digest`,
            undefined,
            30000,
        );
    }

    async sounioPaperRunArtifacts(paperRunId: string): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/sounio/paperruns/${encodeURIComponent(paperRunId)}/artifacts`,
            undefined,
            30000,
        );
    }

    async sounioTraceQuery(paperRunId?: string, limit = 50): Promise<unknown> {
        const params = new URLSearchParams({ limit: String(limit) });
        if (paperRunId) params.set("paper_run_id", paperRunId);
        return this.request("GET", `/api/exocortex/v1/sounio/trace?${params.toString()}`, undefined, 30000);
    }

    private memoryEngineUrl(): string {
        return (process.env.BEAGLE_MEMORY_ENGINE_URL || "http://beagle-memory-engine.beagle-memory-lab.svc.cluster.local:8090").replace(/\/$/, "");
    }

    async memoryEngineStatus(): Promise<unknown> {
        return this.request("GET", "/v1/runtimes/status", undefined, 30000, this.memoryEngineUrl());
    }

    async memoryMeshQuery(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/query", body, 120000, this.memoryEngineUrl());
    }

    async retrievalAgentPlan(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/retrieval/plan", body, 60000, this.memoryEngineUrl());
    }

    async retrievalAgentQuery(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/retrieval/query", body, 120000, this.memoryEngineUrl());
    }

    async retrievalRun(runId: string): Promise<unknown> {
        return this.request("GET", `/v1/retrieval/runs/${encodeURIComponent(runId)}`, undefined, 30000, this.memoryEngineUrl());
    }

    async semanticIndexStatus(): Promise<unknown> {
        return this.request("GET", "/v1/index/semantic/status", undefined, 30000, this.memoryEngineUrl());
    }

    async semanticIndexRebuild(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/index/semantic/rebuild", body, 300000, this.memoryEngineUrl());
    }

    async memoryEngineBakeoffRun(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/bakeoff/runs", body, 300000, this.memoryEngineUrl());
    }

    async memoryEngineEvalRun(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/evals/runs", body, 300000, this.memoryEngineUrl());
    }

    async memoryBenchmarkRun(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/bench/runs", body, 300000, this.memoryEngineUrl());
    }

    async memoryBenchmarkStatus(): Promise<unknown> {
        return this.request("GET", "/v1/bench/status", undefined, 30000, this.memoryEngineUrl());
    }

    async memoryArenaRun(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/bench/memoryarena/runs", body, 300000, this.memoryEngineUrl());
    }

    async memoryArenaStatus(): Promise<unknown> {
        return this.request("GET", "/v1/bench/memoryarena/status", undefined, 30000, this.memoryEngineUrl());
    }

    async engineContextCompile(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/context/compile", body, 120000, this.memoryEngineUrl());
    }

    async memoryPolicyEvaluate(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/policy/evaluate", body, 120000, this.memoryEngineUrl());
    }

    async memoryPolicyUpdate(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/policy/update", body, 120000, this.memoryEngineUrl());
    }

    async memoryPolicyStatus(): Promise<unknown> {
        return this.request("GET", "/v1/policy/status", undefined, 30000, this.memoryEngineUrl());
    }

    async dreamCycleRun(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/dreamcycle/runs", body, 300000, this.memoryEngineUrl());
    }

    async dreamCycleStatus(): Promise<unknown> {
        return this.request("GET", "/v1/dreamcycle/status", undefined, 30000, this.memoryEngineUrl());
    }

    async coreMemoryBenchmarkStatus(): Promise<unknown> {
        return this.request("GET", "/api/exocortex/v1/memory/bench/status", undefined, 30000);
    }

    async memoryTruthsetDraft(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/truthsets/draft", body, 300000, this.memoryEngineUrl());
    }

    async memoryTruthsetReview(truthsetId: string, body: unknown): Promise<unknown> {
        return this.request(
            "POST",
            `/api/exocortex/v1/memory/truthsets/${encodeURIComponent(truthsetId)}/review`,
            body,
            30000,
        );
    }

    async memoryTruthsetGet(truthsetId: string): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/memory/truthsets/${encodeURIComponent(truthsetId)}`,
            undefined,
            30000,
        );
    }

    async memoryEngineGovernanceEvaluate(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/governance/evaluate", body, 120000, this.memoryEngineUrl());
    }

    async temporalAnalyze(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/temporal/analyze", body, 120000);
    }

    async auditEvent(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/audit/events", body, 30000);
    }

    async recentAuditEvents(limit = 25): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/audit/events?limit=${encodeURIComponent(String(limit))}`,
            undefined,
            30000,
        );
    }

    async memoryEvent(body: unknown): Promise<unknown> {
        return this.request("POST", "/api/exocortex/v1/memory/events", body, 30000);
    }

    async recentMemoryEvents(limit = 25): Promise<unknown> {
        return this.request(
            "GET",
            `/api/exocortex/v1/memory/events?limit=${encodeURIComponent(String(limit))}`,
            undefined,
            30000,
        );
    }

    async activeProjects(): Promise<unknown> {
        return this.request("GET", "/api/exocortex/v1/projects/active", undefined, 30000);
    }

    async goDeeper(modality: string, query: string): Promise<unknown> {
        const pathByModality: Record<string, string> = {
            deep_research: "/dev/deep-research",
            swarm: "/dev/swarm",
            temporal: "/dev/temporal",
            neurosymbolic: "/dev/neurosymbolic",
            causal: "/dev/causal",
        };
        const path = pathByModality[modality] || "/dev/deep-research";
        return this.request("POST", path, { query, research_question: query }, 180000);
    }

    async roundTable(prompt: string, voices: string[] = []): Promise<unknown> {
        return this.request("POST", "/api/v1/round-table", { prompt, voices }, 180000);
    }

    async agentSessions(projectSlug: string): Promise<unknown> {
        const baseUrl = this.cockpitBaseUrl || this.baseUrl;
        return this.request(
            "GET",
            `/api/mobile/v1/projects/${encodeURIComponent(projectSlug)}/agent-sessions`,
            undefined,
            30000,
            baseUrl,
        );
    }

    async agentRegistry(projectSlug: string): Promise<unknown> {
        const baseUrl = this.cockpitBaseUrl || this.baseUrl;
        return this.request(
            "GET",
            `/api/workspaces/${encodeURIComponent(projectSlug)}/agents/registry`,
            undefined,
            30000,
            baseUrl,
        );
    }

    async agentRoute(projectSlug: string, body: unknown): Promise<unknown> {
        const baseUrl = this.cockpitBaseUrl || this.baseUrl;
        return this.request(
            "POST",
            `/api/workspaces/${encodeURIComponent(projectSlug)}/agents/route`,
            body,
            30000,
            baseUrl,
        );
    }

    async startAgentSession(
        projectSlug: string,
        kind: string,
        objective?: string,
    ): Promise<unknown> {
        const baseUrl = this.cockpitBaseUrl || this.baseUrl;
        return this.request(
            "POST",
            `/api/mobile/v1/projects/${encodeURIComponent(projectSlug)}/agent-sessions`,
            { agentKind: kind, kind, objective },
            60000,
            baseUrl,
        );
    }

    async tagRun(
        runId: string,
        accepted: boolean,
        rating?: number,
        notes?: string,
    ): Promise<{
        status: string;
        run_id: string;
    }> {
        return this.request("POST", "/api/feedback/tag_run", {
            run_id: runId,
            accepted,
            rating_0_10: rating,
            notes,
        });
    }

    async tagExperimentRun(
        experimentId: string,
        runId: string,
        condition: string,
        notes?: string,
    ): Promise<{
        status: string;
    }> {
        return this.request("POST", "/api/experiments/tag_run", {
            experiment_id: experimentId,
            run_id: runId,
            condition,
            notes,
        });
    }

    async updatePhysio(
        hrvMs: number,
        heartRateBpm?: number,
        source = "mcp",
    ): Promise<{
        status: string;
        hrv_level: string;
    }> {
        return this.request("POST", "/api/observer/physio", {
            source,
            hrv_ms: hrvMs,
            heart_rate_bpm: heartRateBpm,
        });
    }

    async llmComplete(
        prompt: string,
        options?: {
            requires_math?: boolean;
            requires_high_quality?: boolean;
            offline_required?: boolean;
            max_tokens?: number;
            temperature?: number;
        },
    ): Promise<{
        text: string;
        provider: string;
        llm_stats?: {
            tokens_in: number;
            tokens_out: number;
            cost_usd?: number;
            model: string;
        };
    }> {
        return this.request("POST", "/api/llm/complete", {
            prompt,
            requires_math: options?.requires_math,
            requires_high_quality: options?.requires_high_quality,
            offline_required: options?.offline_required,
            max_tokens: options?.max_tokens,
            temperature: options?.temperature,
        });
    }
}
