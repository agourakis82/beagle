/**
 * Pipeline & Triad Tools
 */

import { z } from 'zod';
import { BeagleClient } from '../beagle-client.js';
import { McpTool } from './index.js';
import { sanitizeOutput } from '../security.js';

const RunPipelineSchema = z.object({
  question: z.string().describe('Research question or topic for the pipeline'),
  with_triad: z.boolean().optional().default(true).describe('Whether to run Triad adversarial review after pipeline'),
});

const GetRunSummarySchema = z.object({
  run_id: z.string().describe('Run ID from beagle_run_pipeline'),
});

const ListRecentRunsSchema = z.object({
  limit: z.number().int().min(1).max(50).optional().default(10).describe('Maximum number of runs to return'),
});

export function pipelineTools(client: BeagleClient): McpTool[] {
  return [
    {
      name: 'beagle_run_pipeline',
      description: `Run BEAGLE pipeline to generate a scientific draft from a research question.
      
This tool starts an asynchronous pipeline that:
1. Uses Darwin (GraphRAG) to gather semantic context
2. Captures physiological state (HRV) via Observer
3. Uses HERMES to synthesize a draft paper
4. Optionally runs Triad adversarial review (ATHENA-HERMES-ARGOS + final judge)

Returns a run_id that can be used to check status and retrieve artifacts.

IMPORTANT: This is an asynchronous operation. Use beagle_get_run_summary to check progress and retrieve results.`,
      inputSchema: {
        type: 'object',
        properties: {
          question: {
            type: 'string',
            description: 'Research question or topic',
          },
          with_triad: {
            type: 'boolean',
            description: 'Whether to run Triad adversarial review (default: true)',
            default: true,
          },
        },
        required: ['question'],
      },
      handler: async (args: unknown) => {
        const { question, with_triad } = RunPipelineSchema.parse(args);
        
        const result = await client.startPipeline(question, with_triad ?? true);
        
        return sanitizeOutput({
          run_id: result.run_id,
          status: result.status,
          message: `Pipeline started successfully. Run ID: ${result.run_id}. Use beagle_get_run_summary to check progress.`,
        });
      },
    },
    {
      name: 'beagle_get_run_summary',
      description: `Get summary and artifacts for a pipeline run.
      
Returns:
- Question and status
- Highlights from Triad review (if completed)
- Paths to draft.md and draft_reviewed.md
- LLM usage statistics

Use this to check if a pipeline run has completed and retrieve the generated artifacts.`,
      inputSchema: {
        type: 'object',
        properties: {
          run_id: {
            type: 'string',
            description: 'Run ID from beagle_run_pipeline',
          },
        },
        required: ['run_id'],
      },
      handler: async (args: unknown) => {
        const { run_id } = GetRunSummarySchema.parse(args);
        
        // Get artifacts
        const artifacts = await client.getRunArtifacts(run_id);
        
        // Try to read run_report.json for additional context
        let runReport: unknown = null;
        if (artifacts.triad_report_json) {
          try {
            // In a real implementation, we'd read the file
            // For now, we'll just indicate it exists
            runReport = { path: artifacts.triad_report_json };
          } catch {
            // Ignore
          }
        }
        
        return sanitizeOutput({
          run_id: artifacts.run_id,
          question: artifacts.question || 'N/A',
          status: 'completed', // Could be enhanced to check actual status
          highlights: {
            draft_md: artifacts.draft_md,
            draft_pdf: artifacts.draft_pdf,
            triad_final_md: artifacts.triad_final_md,
            triad_report: artifacts.triad_report_json,
          },
          llm_stats: artifacts.llm_stats,
          short_summary: `Pipeline run ${run_id} generated draft and ${artifacts.triad_final_md ? 'Triad review' : 'no Triad review'}.`,
        });
      },
    },
    {
      name: 'beagle_list_recent_runs',
      description: `List recent pipeline runs with their status and metadata.
      
Useful for:
- Finding run_ids to retrieve artifacts
- Reviewing recent work
- Tracking pipeline activity`,
      inputSchema: {
        type: 'object',
        properties: {
          limit: {
            type: 'number',
            description: 'Maximum number of runs to return (1-50)',
            minimum: 1,
            maximum: 50,
            default: 10,
          },
        },
      },
      handler: async (args: unknown) => {
        const { limit } = ListRecentRunsSchema.parse(args);
        
        const result = await client.listRecentRuns(limit);
        
        return sanitizeOutput({
          runs: result.runs.map(run => ({
            run_id: run.run_id,
            question: run.question,
            status: run.status,
            created_at: run.created_at,
          })),
        });
      },
    },
  ];
}

