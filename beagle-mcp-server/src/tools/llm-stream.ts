/**
 * LLM Streaming Tools
 *
 * Provides streaming completions with chunked responses for better UX
 * with long-running LLM operations.
 */

import { z } from 'zod';
import { BeagleClient } from '../beagle-client.js';
import { McpTool } from './index.js';
import { sanitizeOutput } from '../security.js';
import { logger } from '../logger.js';

const LlmStreamSchema = z.object({
  prompt: z.string().describe('Prompt for LLM completion'),
  requires_math: z.boolean().optional().describe('Whether the task requires mathematical reasoning'),
  requires_high_quality: z.boolean().optional().describe('Whether to prefer high-quality models'),
  offline_required: z.boolean().optional().describe('Whether to require offline/local models only'),
  max_tokens: z.number().int().min(1).max(32000).optional().describe('Maximum tokens to generate'),
  temperature: z.number().min(0).max(2).optional().describe('Temperature for sampling (0-2)'),
  stream_chunk_size: z.number().int().min(1).max(500).optional()
    .describe('Size of text chunks for streaming simulation (1-500 chars). Not used for native streaming.'),
  use_native_streaming: z.boolean().optional()
    .describe('Use native SSE streaming from LLM provider (true) or simulated chunking (false). Default: true'),
});

export function llmStreamTools(client: BeagleClient): McpTool[] {
  return [
    {
      name: 'beagle_llm_complete_stream',
      description: `Streaming LLM completion through BEAGLE's TieredRouter.

Uses Server-Sent Events (SSE) for real-time streaming from supported LLM providers.
Falls back to chunked simulation for providers without native streaming.

Parameters:
- prompt: The prompt text
- use_native_streaming: Whether to use native SSE streaming (default: true)
- All other params same as beagle_llm_complete

Returns stream of chunks with format:
- type: "chunk" - A piece of the response
  data: { content: string, index: number }
- type: "complete" - Final metadata
  data: { provider, tier, duration_ms, model, total_chunks }
- type: "error" - Error information

Use this for:
- Long-form content generation (lower time-to-first-byte)
- Real-time progress visibility
- Better perceived performance with large outputs

Note: Native streaming reduces latency. For short completions (<500 chars), use beagle_llm_complete.`,
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
          use_native_streaming: {
            type: 'boolean',
            description: 'Use native SSE streaming (true) or chunked simulation (false)',
            default: true,
          },
        },
        required: ['prompt'],
      },
      handler: async (args: unknown) => {
        const params = LlmStreamSchema.parse(args);
        const useNativeStreaming = params.use_native_streaming !== false;

        const startTime = Date.now();

        if (useNativeStreaming) {
          logger.info('Using native SSE streaming from BEAGLE Core');

          const chunks: Array<{ content: string; index: number }> = [];
          let completeMetadata: Record<string, unknown> | null = null;

          try {
            for await (const event of client.llmCompleteStream(params.prompt, {
              requires_math: params.requires_math,
              requires_high_quality: params.requires_high_quality,
              offline_required: params.offline_required,
              max_tokens: params.max_tokens,
              temperature: params.temperature,
            })) {
              if (event.type === 'chunk') {
                chunks.push({ content: event.content, index: event.index });
              } else if (event.type === 'complete') {
                completeMetadata = event.metadata;
              } else if (event.type === 'error') {
                logger.error('Streaming error from BEAGLE Core:', { error: event.error });
                return sanitizeOutput({
                  error: event.error,
                  stream_info: { failed: true },
                });
              }
            }

            const fullText = chunks.map(c => c.content).join('');

            return sanitizeOutput({
              stream_info: {
                total_chunks: chunks.length,
                total_length: fullText.length,
                duration_ms: Date.now() - startTime,
                native_streaming: true,
                ...completeMetadata,
              },
              chunks: chunks.map((c, i) => ({
                index: c.index,
                content: c.content,
                done: i === chunks.length - 1,
              })),
              complete_text: fullText,
            });
          } catch (error) {
            logger.error('Native streaming failed, falling back to simulation:', { error });
            // Fall through to simulated chunking below
          }
        }

        // Fallback: simulated chunking (original behavior)
        const chunkSize = params.stream_chunk_size || 100;
        logger.info(`Using simulated streaming (chunk size: ${chunkSize})`);

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

        const text = result.text;
        const chunks: string[] = [];

        // Split text into chunks
        for (let i = 0; i < text.length; i += chunkSize) {
          chunks.push(text.slice(i, i + chunkSize));
        }

        return sanitizeOutput({
          stream_info: {
            total_chunks: chunks.length,
            total_length: text.length,
            provider: result.provider,
            llm_stats: result.llm_stats,
            duration_ms: Date.now() - startTime,
            native_streaming: false,
            note: 'chunked-simulation',
          },
          chunks: chunks.map((content, index) => ({
            index,
            content,
            done: index === chunks.length - 1,
          })),
          complete_text: text,
        });
      },
    },
  ];
}
