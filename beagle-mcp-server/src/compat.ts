/**
 * MCP Client Compatibility Detection
 * 
 * Detects and adapts to different MCP client types:
 * - Claude Desktop (native MCP via STDIO)
 * - ChatGPT (Apps SDK via HTTP or STDIO)
 */

import { logger } from './logger.js';

export type McpClientType = 'claude' | 'chatgpt' | 'unknown';

export interface ClientInfo {
  type: McpClientType;
  transport: 'stdio' | 'http';
  version?: string;
}

/**
 * Detect MCP client type from environment or request metadata
 */
export function detectClientType(meta?: Record<string, unknown>): McpClientType {
  // Check environment variables first
  const envClientType = process.env.MCP_CLIENT_TYPE;
  if (envClientType === 'claude' || envClientType === 'chatgpt') {
    return envClientType;
  }

  // Try to detect from request metadata
  if (meta) {
    const userAgent = meta.userAgent as string | undefined;
    if (userAgent?.includes('Claude')) {
      return 'claude';
    }
    if (userAgent?.includes('ChatGPT') || userAgent?.includes('OpenAI')) {
      return 'chatgpt';
    }
  }

  // Default: unknown (will use stdio transport)
  return 'unknown';
}

/**
 * Get client information
 */
export function getClientInfo(meta?: Record<string, unknown>): ClientInfo {
  const clientType = detectClientType(meta);
  const transport = process.env.MCP_TRANSPORT === 'http' ? 'http' : 'stdio';

  const info: ClientInfo = {
    type: clientType,
    transport,
  };

  if (meta?.version) {
    info.version = String(meta.version);
  }

  logger.debug('Client detected', info);
  return info;
}

/**
 * Check if OpenAI Apps SDK is enabled
 */
export function isOpenAiAppsSdkEnabled(): boolean {
  return process.env.OPENAI_APPS_SDK_ENABLED === 'true';
}

/**
 * Check if Claude Desktop is enabled
 */
export function isClaudeDesktopEnabled(): boolean {
  return process.env.CLAUDE_DESKTOP_ENABLED !== 'false'; // Default: true
}

/**
 * Get appropriate transport type based on client
 */
export function getTransportType(clientType: McpClientType): 'stdio' | 'http' {
  const envTransport = process.env.MCP_TRANSPORT;
  if (envTransport === 'http' || envTransport === 'stdio') {
    return envTransport;
  }

  // Default: stdio for Claude, can be http for ChatGPT
  if (clientType === 'chatgpt' && isOpenAiAppsSdkEnabled()) {
    return 'http';
  }

  return 'stdio';
}

