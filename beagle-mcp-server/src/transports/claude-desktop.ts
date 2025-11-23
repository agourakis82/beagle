/**
 * Claude Desktop MCP Transport
 * 
 * Claude Desktop uses native MCP via STDIO transport.
 * This module provides Claude-specific configuration and optimizations.
 */

import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { logger } from '../logger.js';
import { isClaudeDesktopEnabled } from '../compat.js';

/**
 * Create STDIO transport for Claude Desktop
 */
export function createClaudeDesktopTransport(): StdioServerTransport {
  if (!isClaudeDesktopEnabled()) {
    throw new Error('Claude Desktop transport is disabled');
  }

  logger.info('Creating Claude Desktop STDIO transport');
  return new StdioServerTransport();
}

/**
 * Configure server for Claude Desktop
 */
export function configureForClaudeDesktop(server: Server): void {
  logger.info('Configuring MCP server for Claude Desktop');
  
  // Claude Desktop specific optimizations can be added here
  // For now, the standard MCP server configuration works
}

