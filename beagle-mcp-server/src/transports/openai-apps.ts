/**
 * OpenAI Apps SDK MCP Transport
 * 
 * OpenAI Apps SDK can use both STDIO and HTTP transports.
 * This module provides OpenAI-specific configuration and optimizations.
 */

import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { logger } from '../logger.js';
import { isOpenAiAppsSdkEnabled } from '../compat.js';

/**
 * Create STDIO transport for OpenAI Apps SDK
 */
export function createOpenAiStdioTransport(): StdioServerTransport {
  if (!isOpenAiAppsSdkEnabled()) {
    throw new Error('OpenAI Apps SDK transport is disabled');
  }

  logger.info('Creating OpenAI Apps SDK STDIO transport');
  return new StdioServerTransport();
}

/**
 * Configure server for OpenAI Apps SDK
 */
export function configureForOpenAiApps(server: Server): void {
  logger.info('Configuring MCP server for OpenAI Apps SDK');
  
  // OpenAI Apps SDK specific optimizations can be added here
  // The Apps SDK extends MCP with additional metadata support
}

/**
 * Add OpenAI-specific metadata to tools
 * 
 * OpenAI Apps SDK supports additional metadata for UI rendering and tool invocation
 */
export function addOpenAiMetadata(tool: {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
}): Record<string, unknown> {
  return {
    ...tool,
    inputSchema: {
      ...tool.inputSchema,
      _meta: {
        'openai/toolInvocation/invoking': `Calling ${tool.name}...`,
        'openai/toolInvocation/invoked': `${tool.name} completed`,
      },
    },
  };
}

