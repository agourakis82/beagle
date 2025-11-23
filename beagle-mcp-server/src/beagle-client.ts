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

    constructor(
        public baseUrl: string,
        private authToken?: string,
        timeout = 60000, // 60s default
        maxRetries = 2,
    ) {
        // Remove trailing slash
        this.baseUrl = baseUrl.replace(/\/$/, "");
        this.timeout = timeout;
        this.maxRetries = maxRetries;
    }

    private async request<T>(
        method: string,
        path: string,
        body?: unknown,
        customTimeout?: number,
    ): Promise<T> {
        const url = `${this.baseUrl}${path}`;
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
        topK = 5,
    ): Promise<{
        results: Array<{
            id: string;
            source: string;
            snippet: string;
            score?: number;
            metadata?: Record<string, unknown>;
        }>;
    }> {
        return this.request("POST", "/api/memory/query", {
            query,
            top_k: topK,
        });
    }

    async memoryIngestChat(
        source: string,
        conversationId: string,
        turnIndex: number,
        role: "user" | "assistant" | "system",
        text: string,
        subjectHint?: string,
        tags?: string[],
    ): Promise<{
        stored: boolean;
        memory_id?: string;
    }> {
        return this.request("POST", "/api/memory/ingest_chat", {
            source,
            conversation_id: conversationId,
            turn_index: turnIndex,
            role,
            text,
            subject_hint: subjectHint,
            tags,
        });
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
