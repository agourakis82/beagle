/**
 * Authentication middleware for MCP server
 * 
 * Implements bearer token validation and rate limiting
 */

import { logger } from './logger.js';

const AUTH_TOKEN = process.env.MCP_AUTH_TOKEN;
const ENABLE_AUTH = process.env.MCP_ENABLE_AUTH === 'true';

/**
 * Validates bearer token from request
 */
export function validateAuth(token?: string): { valid: boolean; error?: string } {
  if (!ENABLE_AUTH) {
    return { valid: true };
  }

  if (!AUTH_TOKEN) {
    logger.warn('MCP_ENABLE_AUTH=true but MCP_AUTH_TOKEN not set');
    return { valid: false, error: 'Authentication required but not configured' };
  }

  if (!token) {
    return { valid: false, error: 'Missing authorization token' };
  }

  // Remove "Bearer " prefix if present
  const cleanToken = token.startsWith('Bearer ') ? token.slice(7) : token;

  if (cleanToken !== AUTH_TOKEN) {
    logger.warn('Invalid auth token attempt');
    return { valid: false, error: 'Invalid authorization token' };
  }

  return { valid: true };
}

/**
 * Extracts token from Authorization header
 */
export function extractToken(authHeader?: string): string | undefined {
  if (!authHeader) {
    return undefined;
  }

  if (authHeader.startsWith('Bearer ')) {
    return authHeader.slice(7);
  }

  return authHeader;
}

/**
 * Rate limiting (simple in-memory, can be enhanced with Redis)
 */
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();

const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX_REQUESTS = 100; // per minute

export function checkRateLimit(identifier: string): { allowed: boolean; remaining?: number } {
  const now = Date.now();
  const record = rateLimitMap.get(identifier);

  if (!record || now > record.resetAt) {
    // Reset or create new record
    rateLimitMap.set(identifier, {
      count: 1,
      resetAt: now + RATE_LIMIT_WINDOW_MS,
    });
    return { allowed: true, remaining: RATE_LIMIT_MAX_REQUESTS - 1 };
  }

  if (record.count >= RATE_LIMIT_MAX_REQUESTS) {
    return { allowed: false };
  }

  record.count += 1;
  return { allowed: true, remaining: RATE_LIMIT_MAX_REQUESTS - record.count };
}

/**
 * Cleanup old rate limit records (call periodically)
 */
export function cleanupRateLimit(): void {
  const now = Date.now();
  for (const [key, record] of rateLimitMap.entries()) {
    if (now > record.resetAt) {
      rateLimitMap.delete(key);
    }
  }
}

// Cleanup every 5 minutes
setInterval(cleanupRateLimit, 5 * 60 * 1000);

