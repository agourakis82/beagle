/**
 * Experimental Tools (Serendipity & Void)
 * 
 * These tools are OFF by default and should only be enabled
 * in dev/lab profiles with clear risk labeling.
 */

import { z } from 'zod';
import { BeagleClient } from '../beagle-client.js';
import { McpTool } from './index.js';
import { sanitizeOutput } from '../security.js';
import { logger } from '../logger.js';

const SerendipityToggleSchema = z.object({
  enabled: z.boolean().describe('Whether to enable Serendipity Engine'),
});

const SerendipityPerturbPromptSchema = z.object({
  prompt: z.string().describe('Prompt to perturb/mutate'),
});

const VoidBreakLoopSchema = z.object({
  run_id: z.string().describe('Run ID to apply Void behavior'),
  reason: z.string().describe('Reason for applying Void'),
});

export function experimentalTools(client: BeagleClient): McpTool[] {
  const enableSerendipity = process.env.MCP_ENABLE_SERENDIPITY === 'true';
  const enableVoid = process.env.MCP_ENABLE_VOID === 'true';

  const tools: McpTool[] = [];

  if (enableSerendipity) {
    tools.push(
      {
        name: 'beagle_serendipity_toggle',
        description: `⚠️ EXPERIMENTAL: Toggle Serendipity Engine on/off.
        
WARNING: This is an experimental feature. Use with caution.
The Serendipity Engine injects creative perturbations into cognitive cycles.

Only available when MCP_ENABLE_SERENDIPITY=true.`,
        inputSchema: {
          type: 'object',
          properties: {
            enabled: {
              type: 'boolean',
              description: 'Whether to enable Serendipity Engine',
            },
          },
          required: ['enabled'],
        },
        handler: async (args: unknown) => {
          const { enabled } = SerendipityToggleSchema.parse(args);
          
          logger.warn('Serendipity toggle called', { enabled });
          
          // TODO: Implement actual toggle endpoint in BEAGLE core
          // For now, return mock response
          return sanitizeOutput({
            status: 'ok',
            enabled,
            message: `Serendipity Engine ${enabled ? 'enabled' : 'disabled'}`,
          });
        },
      },
      {
        name: 'beagle_serendipity_perturb_prompt',
        description: `⚠️ EXPERIMENTAL: Perturb/mutate a prompt using Serendipity Engine.
        
WARNING: This is an experimental feature. The Serendipity Engine may produce unexpected results.

Use this to inject creative "glitches" into prompts for exploration.

Only available when MCP_ENABLE_SERENDIPITY=true.`,
        inputSchema: {
          type: 'object',
          properties: {
            prompt: {
              type: 'string',
              description: 'Prompt to perturb/mutate',
            },
          },
          required: ['prompt'],
        },
        handler: async (args: unknown) => {
          const { prompt } = SerendipityPerturbPromptSchema.parse(args);
          
          logger.warn('Serendipity perturb called', { promptLength: prompt.length });
          
          // TODO: Implement actual perturb endpoint in BEAGLE core
          // For now, return mock response
          return sanitizeOutput({
            mutated_prompt: `[SERENDIPITY_MUTATED] ${prompt} [CREATIVE_GLITCH]`,
            delta_description: 'Mock mutation applied (real implementation pending)',
            message: 'Serendipity perturbation applied (experimental)',
          });
        },
      }
    );
  }

  if (enableVoid) {
    tools.push({
      name: 'beagle_void_break_loop',
      description: `⚠️ EXPERIMENTAL: Apply Void behavior to break a cognitive loop.
        
WARNING: This is an experimental feature. Void behavior may reset context or apply alternative strategies.

Use this when a run seems stuck in a loop or needs a radical reset.

Only available when MCP_ENABLE_VOID=true.`,
      inputSchema: {
        type: 'object',
        properties: {
          run_id: {
            type: 'string',
            description: 'Run ID to apply Void behavior',
          },
          reason: {
            type: 'string',
            description: 'Reason for applying Void',
          },
        },
        required: ['run_id', 'reason'],
      },
      handler: async (args: unknown) => {
        const { run_id, reason } = VoidBreakLoopSchema.parse(args);
        
        logger.warn('Void break loop called', { run_id, reason });
        
        // TODO: Implement actual Void endpoint in BEAGLE core
        // For now, return mock response
        return sanitizeOutput({
          status: 'ok',
          run_id,
          action: 'void_break_applied',
          description: `Void behavior applied to run ${run_id}: ${reason}`,
          message: 'Void break applied (experimental)',
        });
      },
    });
  }

  return tools;
}

