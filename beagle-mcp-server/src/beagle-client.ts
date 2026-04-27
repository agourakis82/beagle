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
        return this.request("POST", "/api/memory/query", {
            query,
            scope,
            max_items: maxItems,
        });
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

    private memoryEngineUrl(): string {
        return (process.env.BEAGLE_MEMORY_ENGINE_URL || "http://beagle-memory-engine.beagle-memory-lab.svc.cluster.local:8090").replace(/\/$/, "");
    }

    async memoryEngineStatus(): Promise<unknown> {
        return this.request("GET", "/v1/runtimes/status", undefined, 30000, this.memoryEngineUrl());
    }

    async memoryMeshQuery(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/query", body, 120000, this.memoryEngineUrl());
    }

    async memoryEngineBakeoffRun(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/bakeoff/runs", body, 300000, this.memoryEngineUrl());
    }

    async memoryEngineEvalRun(body: unknown): Promise<unknown> {
        return this.request("POST", "/v1/evals/runs", body, 300000, this.memoryEngineUrl());
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
