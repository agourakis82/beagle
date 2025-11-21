/**
 * BEAGLE HTTP Client
 * 
 * Thin wrapper around BEAGLE core HTTP API.
 */

import { logger } from './logger.js';

export interface BeagleConfig {
  baseUrl: string;
  authToken?: string;
}

export class BeagleClient {
  constructor(
    public baseUrl: string,
    private authToken?: string
  ) {
    // Remove trailing slash
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown
  ): Promise<T> {
    const url = `${this.baseUrl}${path}`;
    
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    
    if (this.authToken) {
      headers['Authorization'] = `Bearer ${this.authToken}`;
    }

    const options: RequestInit = {
      method,
      headers,
    };

    if (body) {
      options.body = JSON.stringify(body);
    }

    try {
      const response = await fetch(url, options);
      
      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(
          `BEAGLE API error (${response.status}): ${errorText}`
        );
      }

      // Handle empty responses
      const contentType = response.headers.get('content-type');
      if (contentType?.includes('application/json')) {
        return (await response.json()) as T;
      }
      
      return {} as T;
    } catch (error) {
      logger.error(`BEAGLE API request failed: ${method} ${path}`, { error });
      throw error;
    }
  }

  async health(): Promise<{ status: string; profile?: string; safe_mode?: boolean }> {
    return this.request('GET', '/health');
  }

  async startPipeline(question: string, withTriad = true): Promise<{
    run_id: string;
    status: string;
  }> {
    return this.request('POST', '/api/pipeline/start', {
      question,
      with_triad: withTriad,
    });
  }

  async getRunStatus(runId: string): Promise<{
    run_id: string;
    status: string;
    question?: string;
  }> {
    return this.request('GET', `/api/pipeline/status/${runId}`);
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
    return this.request('GET', `/api/run/${runId}/artifacts`);
  }

  async listRecentRuns(limit = 10): Promise<{
    runs: Array<{
      run_id: string;
      question: string;
      status: string;
      created_at?: string;
    }>;
  }> {
    return this.request('GET', `/api/runs/recent?limit=${limit}`);
  }

  async startScienceJob(kind: string, config: Record<string, unknown>): Promise<{
    job_id: string;
    status: string;
  }> {
    return this.request('POST', '/api/jobs/science/start', {
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
    return this.request('GET', `/api/jobs/science/status/${jobId}`);
  }

  async getScienceJobArtifacts(jobId: string): Promise<{
    job_id: string;
    artifacts: Array<{
      path: string;
      type: string;
    }>;
  }> {
    return this.request('GET', `/api/jobs/science/${jobId}/artifacts`);
  }

  async queryMemory(query: string, scope?: string, maxItems = 5): Promise<{
    summary: string;
    highlights: Array<{
      text: string;
      source: string;
      relevance: number;
    }>;
    links: Array<{
      type: string;
      id: string;
      label: string;
    }>;
  }> {
    return this.request('POST', '/api/memory/query', {
      query,
      scope,
      max_items: maxItems,
    });
  }

  async ingestChat(
    source: string,
    sessionId: string,
    turns: Array<{
      role: 'user' | 'assistant';
      content: string;
      timestamp?: string;
      model?: string;
    }>,
    tags?: string[],
    metadata?: Record<string, unknown>
  ): Promise<{
    status: string;
    num_turns: number;
    num_chunks: number;
    session_id: string;
  }> {
    const result = await this.request<{
      status: string;
      session_id: string;
      num_turns: number;
      num_chunks: number;
    }>('POST', '/api/memory/ingest_chat', {
      source,
      session_id: sessionId,
      turns,
      tags,
      metadata,
    });
    
    return {
      status: result.status,
      num_turns: result.num_turns,
      num_chunks: result.num_chunks,
      session_id: result.session_id,
    };
  }

  async tagRun(
    runId: string,
    accepted: boolean,
    rating?: number,
    notes?: string
  ): Promise<{
    status: string;
    run_id: string;
  }> {
    return this.request('POST', '/api/feedback/tag_run', {
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
    notes?: string
  ): Promise<{
    status: string;
  }> {
    return this.request('POST', '/api/experiments/tag_run', {
      experiment_id: experimentId,
      run_id: runId,
      condition,
      notes,
    });
  }

  async updatePhysio(hrvMs: number, heartRateBpm?: number, source = 'mcp'): Promise<{
    status: string;
    hrv_level: string;
  }> {
    return this.request('POST', '/api/observer/physio', {
      source,
      hrv_ms: hrvMs,
      heart_rate_bpm: heartRateBpm,
    });
  }
}

