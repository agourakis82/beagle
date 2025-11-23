/**
 * LLM Completion Tools
 *
 * Proxy LLM completions through BEAGLE's TieredRouter
 */

import { z } from 'zod';
import { BeagleClient } from '../beagle-client.js';
import { McpTool } from './index.js';
import { sanitizeOutput } from '../security.js';

const LlmCompleteSchema = z.object({
  prompt: z.string().describe('Prompt for LLM completion'),
  requires_math: z.boolean().optional().describe('Whether the task requires mathematical reasoning'),
  requires_high_quality: z.boolean().optional().describe('Whether to prefer high-quality models (e.g., o1, Claude Opus)'),
  offline_required: z.boolean().optional().describe('Whether to require offline/local models only'),
  max_tokens: z.number().int().min(1).max(32000).optional().describe('Maximum tokens to generate'),
  temperature: z.number().min(0).max(2).optional().describe('Temperature for sampling (0-2)'),
});

export function llmTools(client: BeagleClient): McpTool[] {
  return [
    {
      name: 'beagle_llm_complete',
      description: `Proxy LLM completion through BEAGLE's TieredRouter.

BEAGLE automatically selects the best available LLM based on:
- Task requirements (math, high quality, offline)
- Current HRV state (may downgrade to local models under stress)
- Cost optimization
- Availability

Supported tiers:
- Tier 0: Fast local models (Qwen, Llama)
- Tier 1: Cloud efficient (DeepSeek, Grok, Gemini Flash)
- Tier 2: High quality (Claude Opus, GPT-4, o1)
- Tier 3: Specialized (o1 for math/reasoning)

Returns:
- text: Generated completion
- provider: Which model was used (e.g., "grok3", "deepseek", "qwen2.5-local")
- llm_stats: Token usage and cost information

IMPORTANT: This is for auxiliary tasks only. Don't use this to replace the main conversation.`,
      inputSchema: {
        type: 'object',
        properties: {
          prompt: {
            type: 'string',
            description: 'Prompt for LLM completion',
          },
          requires_math: {
            type: 'boolean',
            description: 'Whether the task requires mathematical reasoning',
            default: false,
          },
          requires_high_quality: {
            type: 'boolean',
            description: 'Whether to prefer high-quality models',
            default: false,
          },
          offline_required: {
            type: 'boolean',
            description: 'Whether to require offline/local models only',
            default: false,
          },
          max_tokens: {
            type: 'number',
            description: 'Maximum tokens to generate (1-32000)',
            minimum: 1,
            maximum: 32000,
          },
          temperature: {
            type: 'number',
            description: 'Temperature for sampling (0-2)',
            minimum: 0,
            maximum: 2,
          },
        },
        required: ['prompt'],
      },
      handler: async (args: unknown) => {
        const params = LlmCompleteSchema.parse(args);

        const result = await client.llmComplete(
          params.prompt,
          {
            requires_math: params.requires_math,
            requires_high_quality: params.requires_high_quality,
            offline_required: params.offline_required,
            max_tokens: params.max_tokens,
            temperature: params.temperature,
          }
        );

        return sanitizeOutput({
          text: result.text,
          provider: result.provider,
          llm_stats: result.llm_stats,
        });
      },
    },
  ];
}
