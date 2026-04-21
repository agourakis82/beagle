/**
 * Authentication middleware for MCP server
 *
 * Implements bearer token validation, OAuth 2.0 JWT validation, and rate limiting
 * Supports both simple bearer tokens and multi-tenant OAuth authentication
 */

import { logger } from './logger.js';
import {
  validateAccessToken,
  extractBearerToken,
  isOAuthEnabled,
  type UserContext,
} from './oauth.js';
import { userStore } from './user-store.js';

const AUTH_TOKEN = process.env.MCP_AUTH_TOKEN;
const ENABLE_AUTH = process.env.MCP_ENABLE_AUTH === 'true';
const OAUTH_ENABLED = isOAuthEnabled();

/**
 * Authentication result with optional user context for multi-tenant scenarios
 */
export interface AuthResult {
  valid: boolean;
  error?: string;
  userContext?: UserContext;
  authType?: 'bearer' | 'oauth';
}

/**
 * Validates bearer token from request
 * Supports both simple static bearer tokens and OAuth JWT tokens
 */
export function validateAuth(token?: string): AuthResult {
  if (!ENABLE_AUTH) {
    return { valid: true };
  }

  if (!token) {
    return { valid: false, error: 'Missing authorization token' };
  }

  // Extract clean token from Bearer format
  const cleanToken = extractBearerToken(`Bearer ${token}`) || token;

  // If OAuth is enabled, try OAuth validation first
  if (OAUTH_ENABLED) {
    const oauthResult = validateAccessToken(cleanToken);
    if (oauthResult.valid && oauthResult.context) {
      logger.debug('OAuth token validated', {
        userId: oauthResult.context.userId,
        tenantId: oauthResult.context.tenantId,
      });
      return {
        valid: true,
        userContext: oauthResult.context,
        authType: 'oauth',
      };
    }

    // OAuth validation failed, but we should still check simple bearer token
    // to maintain backward compatibility during transition
  }

  // Fall back to simple bearer token validation
  if (!AUTH_TOKEN) {
    logger.warn('MCP_ENABLE_AUTH=true but MCP_AUTH_TOKEN not set');
    return { valid: false, error: 'Authentication required but not configured' };
  }

  if (cleanToken !== AUTH_TOKEN) {
    logger.warn('Invalid auth token attempt');
    return { valid: false, error: 'Invalid authorization token' };
  }

  return { valid: true, authType: 'bearer' };
}

/**
 * Validates OAuth token specifically (for endpoints that require OAuth)
 */
export function validateOAuth(token?: string): AuthResult {
  if (!token) {
    return { valid: false, error: 'Missing authorization token' };
  }

  const cleanToken = extractBearerToken(`Bearer ${token}`) || token;
  const result = validateAccessToken(cleanToken);

  if (result.valid && result.context) {
    return {
      valid: true,
      userContext: result.context,
      authType: 'oauth',
    };
  }

  return {
    valid: false,
    error: result.error || 'Invalid OAuth token',
  };
}

/**
 * Extracts token from Authorization header
 */
export function extractToken(authHeader?: string): string | undefined {
  return extractBearerToken(authHeader);
}

/**
 * Get user context from validated token
 * Returns null context if OAuth is not enabled or token is simple bearer
 */
export function getUserContextFromToken(authHeader?: string): UserContext | undefined {
  const token = extractBearerToken(authHeader);
  if (!token) return undefined;

  const result = validateAccessToken(token);
  if (result.valid && result.context) {
    return result.context;
  }

  return undefined;
}

/**
 * Rate limiting (simple in-memory, can be enhanced with Redis)
 */
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();

const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX_REQUESTS = 100; // per minute per IP
const RATE_LIMIT_MAX_USER_REQUESTS = 200; // per minute per user (higher for authenticated users)

/**
 * Check rate limit by identifier (IP-based)
 */
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
 * Check rate limit for a specific user (separate from IP-based)
 * OAuth users get higher limits since they're authenticated
 */
export function checkUserRateLimit(userId: string): { allowed: boolean; remaining?: number; resetAt?: number } {
  const result = userStore.checkUserRateLimit(userId);
  return {
    allowed: result.allowed,
    remaining: result.remaining,
    resetAt: result.resetAt,
  };
}

/**
 * Combined rate limiting that checks both IP and user limits
 */
export function checkCombinedRateLimit(
  identifier: string,
  userId?: string,
): { allowed: boolean; remaining?: number; reason?: string } {
  // Check IP-based limit first
  const ipResult = checkRateLimit(identifier);
  if (!ipResult.allowed) {
    return { allowed: false, reason: 'IP rate limit exceeded' };
  }

  // If user is authenticated, also check user-specific limit
  if (userId) {
    const userResult = checkUserRateLimit(userId);
    if (!userResult.allowed) {
      return { allowed: false, reason: 'User rate limit exceeded' };
    }
    // Return the lower remaining count
    return {
      allowed: true,
      remaining: Math.min(ipResult.remaining || 0, userResult.remaining || 0),
    };
  }

  return { allowed: true, remaining: ipResult.remaining };
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

  // Also cleanup user rate limits
  userStore.cleanupRateLimits();
}

// Cleanup every 5 minutes
setInterval(cleanupRateLimit, 5 * 60 * 1000);

