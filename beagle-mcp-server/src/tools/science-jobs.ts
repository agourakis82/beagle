/**
 * Science Jobs Tools (PBPK, Helio, Scaffold, PCS, KEC)
 */

import { z } from 'zod';
import { BeagleClient } from '../beagle-client.js';
import { McpTool } from './index.js';
import { sanitizeOutput } from '../security.js';

const StartScienceJobSchema = z.object({
  kind: z.enum(['pbpk', 'helio', 'scaffold', 'pcs', 'kec']).describe('Type of scientific job'),
  config: z.record(z.unknown()).describe('Job-specific configuration parameters'),
});

const GetScienceJobStatusSchema = z.object({
  job_id: z.string().describe('Job ID from beagle_start_science_job'),
});

const GetScienceJobArtifactsSchema = z.object({
  job_id: z.string().describe('Job ID from beagle_start_science_job'),
});

export function scienceJobTools(client: BeagleClient): McpTool[] {
  return [
    {
      name: 'beagle_start_science_job',
      description: `Start a scientific computation job (PBPK, Heliobiology, Scaffold analysis, PCS, or KEC).
      
Job types:
- pbpk: Physiological-based pharmacokinetic modeling
- helio: Heliobiology analysis (solar/geomagnetic data)
- scaffold: MicroCT scaffold analysis
- pcs: Symbolic computational psychiatry
- kec: KEC 3.0 GPU-accelerated computations

Returns a job_id that can be used to check status and retrieve results.

IMPORTANT: These are HPC jobs that run asynchronously. Use beagle_get_science_job_status to check progress.`,
      inputSchema: {
        type: 'object',
        properties: {
          kind: {
            type: 'string',
            enum: ['pbpk', 'helio', 'scaffold', 'pcs', 'kec'],
            description: 'Type of scientific job',
          },
          config: {
            type: 'object',
            description: 'Job-specific configuration (see BEAGLE docs for each job type)',
          },
        },
        required: ['kind', 'config'],
      },
      handler: async (args: unknown) => {
        const { kind, config } = StartScienceJobSchema.parse(args);
        
        const result = await client.startScienceJob(kind, config as Record<string, unknown>);
        
        return sanitizeOutput({
          job_id: result.job_id,
          status: result.status,
          kind,
          message: `Science job started: ${kind} (job_id: ${result.job_id})`,
        });
      },
    },
    {
      name: 'beagle_get_science_job_status',
      description: `Get status of a scientific computation job.
      
Returns:
- Current status (running, completed, failed)
- Timestamps (started_at, completed_at)
- Error message (if failed)`,
      inputSchema: {
        type: 'object',
        properties: {
          job_id: {
            type: 'string',
            description: 'Job ID from beagle_start_science_job',
          },
        },
        required: ['job_id'],
      },
      handler: async (args: unknown) => {
        const { job_id } = GetScienceJobStatusSchema.parse(args);
        
        const result = await client.getScienceJobStatus(job_id);
        
        return sanitizeOutput({
          job_id: result.job_id,
          status: result.status,
          started_at: result.started_at,
          completed_at: result.completed_at,
          error: result.error || null,
        });
      },
    },
    {
      name: 'beagle_get_science_job_artifacts',
      description: `Get artifacts (results) from a completed scientific job.
      
Returns paths/URLs to:
- CSV files (data tables)
- JSON files (structured results)
- Images (plots, visualizations)
- Other job-specific outputs`,
      inputSchema: {
        type: 'object',
        properties: {
          job_id: {
            type: 'string',
            description: 'Job ID from beagle_start_science_job',
          },
        },
        required: ['job_id'],
      },
      handler: async (args: unknown) => {
        const { job_id } = GetScienceJobArtifactsSchema.parse(args);
        
        const result = await client.getScienceJobArtifacts(job_id);
        
        return sanitizeOutput({
          job_id: result.job_id,
          artifacts: result.artifacts.map(a => ({
            path: a.path,
            type: a.type,
          })),
        });
      },
    },
  ];
}

