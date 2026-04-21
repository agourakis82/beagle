/**
 * BEAGLE HTTP Client
 *
 * Thin wrapper around BEAGLE core HTTP API.
 */

import { logger } from "./logger.js";
import { triggerEvent, WebhookEventType } from "./webhooks.js";

export interface BeagleConfig {
    baseUrl: string;
    authToken?: string;
    consumerId?: string;
}

export class BeagleClient {
    private timeout: number;
    private maxRetries: number;

    constructor(
        public baseUrl: string,
        private authToken?: string,
        timeout = 60000, // 60s default
        maxRetries = 2,
        private consumerId = process.env.BEAGLE_CONSUMER || "beagle-operator",
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
        if (this.consumerId) {
            headers["X-Beagle-Consumer"] = this.consumerId;
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
        error?: string;
    }> {
        const result = await this.request<{
            run_id: string;
            status: string;
            question?: string;
            error?: string;
        }>("GET", `/api/pipeline/status/${runId}`);

        // Trigger webhook if pipeline completed or failed
        if (result.status === "completed") {
            await triggerEvent("pipeline.complete", {
                run_id: result.run_id,
                question: result.question,
                timestamp: new Date().toISOString(),
            });
        } else if (result.status === "failed") {
            await triggerEvent("pipeline.failed", {
                run_id: result.run_id,
                question: result.question,
                error: result.error,
                timestamp: new Date().toISOString(),
            });
        }

        return result;
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
        kind?: string;
        started_at?: string;
        completed_at?: string;
        error?: string;
    }> {
        const result = await this.request<{
            job_id: string;
            status: string;
            kind?: string;
            started_at?: string;
            completed_at?: string;
            error?: string;
        }>("GET", `/api/jobs/science/status/${jobId}`);

        // Trigger webhook if job completed or failed
        if (result.status === "completed") {
            await triggerEvent("science_job.complete", {
                job_id: result.job_id,
                kind: result.kind,
                started_at: result.started_at,
                completed_at: result.completed_at,
                timestamp: new Date().toISOString(),
            }, { jobType: result.kind });
        } else if (result.status === "failed") {
            await triggerEvent("science_job.failed", {
                job_id: result.job_id,
                kind: result.kind,
                error: result.error,
                started_at: result.started_at,
                timestamp: new Date().toISOString(),
            }, { jobType: result.kind });
        }

        return result;
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
        limit = 5,
        domain?: string,
        tags?: string[],
        includeRecentPhysio = false,
    ): Promise<{
        summary: string;
        results: Array<{
            memory_id: string;
            source: string;
            conversation_id: string;
            turn_index: number;
            role: string;
            text: string;
            tags: string[];
            domain?: string;
            timestamp: string;
            physio_snapshot?: Record<string, unknown>;
            experiment_flags?: Record<string, unknown>;
            score?: number;
        }>;
        recent_physio?: Record<string, unknown>;
    }> {
        return this.request("POST", "/api/memory/query", {
            query,
            limit,
            domain,
            tags,
            include_recent_physio: includeRecentPhysio,
        });
    }

    async memoryIngestChat(
        source: string,
        conversationId: string,
        turnIndex: number,
        role: "user" | "assistant" | "system" | "tool",
        text: string,
        domain?: string,
        tags?: string[],
        provider?: string,
        model?: string,
    ): Promise<{
        status: string;
        memory_id?: string;
        searchable: boolean;
        physio_attached: boolean;
        experiment_flags_attached: boolean;
    }> {
        const result = await this.request<{
            status: string;
            memory_id?: string;
            searchable: boolean;
            physio_attached: boolean;
            experiment_flags_attached: boolean;
        }>("POST", "/api/memory/ingest_chat", {
            source,
            conversation_id: conversationId,
            turn_index: turnIndex,
            role,
            text,
            domain,
            tags,
            provider,
            model,
        });

        // Trigger webhook if ingestion completed successfully
        if (result.status === "ok" || result.status === "success") {
            await triggerEvent("memory.ingest_complete", {
                memory_id: result.memory_id,
                source,
                conversation_id: conversationId,
                turn_index: turnIndex,
                role,
                domain,
                tags,
                timestamp: new Date().toISOString(),
            });
        }

        return result;
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

    /**
     * Stream LLM completion via Server-Sent Events (SSE)
     * Returns an async generator that yields chunks as they arrive from the LLM
     */
    async *llmCompleteStream(
        prompt: string,
        options?: {
            requires_math?: boolean;
            requires_high_quality?: boolean;
            offline_required?: boolean;
            max_tokens?: number;
            temperature?: number;
        },
    ): AsyncGenerator<
        | { type: "chunk"; content: string; index: number }
        | { type: "complete"; metadata: Record<string, unknown> }
        | { type: "error"; error: string },
        void,
        unknown
    > {
        const url = new URL(`${this.baseUrl}/api/llm/complete/stream`);
        url.searchParams.append("prompt", prompt);
        if (options?.requires_math) url.searchParams.append("requires_math", "true");
        if (options?.requires_high_quality)
            url.searchParams.append("requires_high_quality", "true");
        if (options?.offline_required) url.searchParams.append("offline_required", "true");
        if (options?.max_tokens) url.searchParams.append("max_tokens", options.max_tokens.toString());
        if (options?.temperature !== undefined)
            url.searchParams.append("temperature", options.temperature.toString());

        const headers: Record<string, string> = {
            Accept: "text/event-stream",
        };

        if (this.authToken) {
            headers["Authorization"] = `Bearer ${this.authToken}`;
        }
        if (this.consumerId) {
            headers["X-Beagle-Consumer"] = this.consumerId;
        }

        const response = await fetch(url.toString(), {
            method: "GET",
            headers,
        });

        if (!response.ok) {
            throw new Error(`SSE request failed: ${response.status} ${response.statusText}`);
        }

        if (!response.body) {
            throw new Error("Response body is null");
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        try {
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                buffer += decoder.decode(value, { stream: true });

                // Process SSE events in buffer
                const lines = buffer.split("\n");
                buffer = lines.pop() || ""; // Keep incomplete line in buffer

                let currentEvent: string | null = null;

                for (const line of lines) {
                    if (line.startsWith("event: ")) {
                        currentEvent = line.slice(7).trim();
                    } else if (line.startsWith("data: ")) {
                        const data = line.slice(6);
                        if (currentEvent === "chunk") {
                            try {
                                const parsed = JSON.parse(data);
                                yield { type: "chunk", content: parsed.content, index: parsed.index };
                            } catch (e) {
                                logger.warn("Failed to parse chunk data:", { data, error: e });
                            }
                        } else if (currentEvent === "complete") {
                            try {
                                const parsed = JSON.parse(data);
                                yield { type: "complete", metadata: parsed };
                                return;
                            } catch (e) {
                                logger.warn("Failed to parse complete data:", { data, error: e });
                                yield {
                                    type: "complete",
                                    metadata: { raw: data },
                                };
                                return;
                            }
                        } else if (currentEvent === "error") {
                            yield { type: "error", error: data };
                        }
                    } else if (line.trim() === "" && currentEvent) {
                        // Event separator, reset event type
                        currentEvent = null;
                    }
                }
            }

            // Process any remaining data in buffer
            if (buffer.trim()) {
                const lines = buffer.split("\n");
                let currentEvent: string | null = null;
                for (const line of lines) {
                    if (line.startsWith("event: ")) {
                        currentEvent = line.slice(7).trim();
                    } else if (line.startsWith("data: ")) {
                        const data = line.slice(6);
                        if (currentEvent === "chunk") {
                            try {
                                const parsed = JSON.parse(data);
                                yield { type: "chunk", content: parsed.content, index: parsed.index };
                            } catch {
                                // Ignore parse errors for incomplete data
                            }
                        } else if (currentEvent === "complete") {
                            try {
                                const parsed = JSON.parse(data);
                                yield { type: "complete", metadata: parsed };
                            } catch {
                                yield { type: "complete", metadata: { raw: data } };
                            }
                        }
                    }
                }
            }
        } finally {
            reader.releaseLock();
        }
    }
}
