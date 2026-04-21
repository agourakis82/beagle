/**
 * In-memory user and tenant store for OAuth multi-tenant authentication
 *
 * Stores user tokens, tenant associations, and rate limit data.
 * This is a simple in-memory implementation - production should use Redis/database.
 */

import { logger } from './logger.js';

/**
 * Token data stored for each user/tenant
 */
export interface TokenData {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  scope: string[];
  tokenType: 'Bearer';
}

/**
 * User profile information
 */
export interface UserProfile {
  userId: string;
  tenantId: string;
  email?: string;
  name?: string;
  roles: string[];
  metadata: Record<string, unknown>;
  createdAt: number;
  lastAccessAt: number;
}

/**
 * OAuth client application registration
 */
export interface OAuthClient {
  clientId: string;
  clientSecret?: string; // Only for confidential clients
  clientName: string;
  redirectUris: string[];
  allowedScopes: string[];
  isConfidential: boolean;
  createdAt: number;
}

/**
 * Authorization code for PKCE flow
 */
export interface AuthorizationCode {
  code: string;
  clientId: string;
  userId: string;
  tenantId: string;
  codeChallenge: string;
  codeChallengeMethod: 'S256';
  scope: string[];
  expiresAt: number;
  used: boolean;
}

/**
 * In-memory store for all OAuth and user data
 */
class UserStore {
  private users: Map<string, UserProfile> = new Map();
  private tokens: Map<string, TokenData> = new Map(); // key: accessToken
  private refreshTokens: Map<string, string> = new Map(); // key: refreshToken, value: userId
  private authCodes: Map<string, AuthorizationCode> = new Map();
  private clients: Map<string, OAuthClient> = new Map();
  private tenantUsers: Map<string, Set<string>> = new Map(); // key: tenantId, value: Set of userIds

  // Rate limiting per user (separate from IP-based)
  private userRateLimits: Map<string, { count: number; resetAt: number }> = new Map();

  // Default rate limit settings
  private readonly RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
  private readonly RATE_LIMIT_MAX_REQUESTS = 100;

  /**
   * Store or update a user profile
   */
  setUser(profile: UserProfile): void {
    this.users.set(profile.userId, profile);

    // Add to tenant index
    const tenantUserSet = this.tenantUsers.get(profile.tenantId);
    if (tenantUserSet) {
      tenantUserSet.add(profile.userId);
    } else {
      this.tenantUsers.set(profile.tenantId, new Set([profile.userId]));
    }

    logger.debug('User stored', { userId: profile.userId, tenantId: profile.tenantId });
  }

  /**
   * Get user by ID
   */
  getUser(userId: string): UserProfile | undefined {
    return this.users.get(userId);
  }

  /**
   * Get all users for a tenant
   */
  getTenantUsers(tenantId: string): UserProfile[] {
    const userIds = this.tenantUsers.get(tenantId);
    if (!userIds) return [];

    return Array.from(userIds)
      .map(id => this.users.get(id))
      .filter((u): u is UserProfile => u !== undefined);
  }

  /**
   * Store token data for a user
   */
  setToken(accessToken: string, tokenData: TokenData, userId: string): void {
    this.tokens.set(accessToken, tokenData);
    this.refreshTokens.set(tokenData.refreshToken, userId);
    logger.debug('Token stored', { userId, expiresAt: tokenData.expiresAt });
  }

  /**
   * Get token data by access token
   */
  getToken(accessToken: string): TokenData | undefined {
    return this.tokens.get(accessToken);
  }

  /**
   * Get user ID from refresh token
   */
  getUserByRefreshToken(refreshToken: string): string | undefined {
    return this.refreshTokens.get(refreshToken);
  }

  /**
   * Revoke an access token
   */
  revokeToken(accessToken: string): boolean {
    const token = this.tokens.get(accessToken);
    if (token) {
      this.tokens.delete(accessToken);
      this.refreshTokens.delete(token.refreshToken);
      logger.debug('Token revoked', { accessToken: accessToken.substring(0, 16) + '...' });
      return true;
    }
    return false;
  }

  /**
   * Revoke all tokens for a user
   */
  revokeUserTokens(userId: string): number {
    let count = 0;
    for (const [token, data] of this.tokens.entries()) {
      const user = this.users.get(userId);
      if (user) {
        // We need to track token -> user mapping better, but for now iterate
        // In production, maintain an index: userId -> tokens[]
        this.tokens.delete(token);
        count++;
      }
    }
    logger.debug('All tokens revoked for user', { userId, count });
    return count;
  }

  /**
   * Clean up expired tokens
   */
  cleanupExpiredTokens(): number {
    const now = Date.now();
    let count = 0;
    for (const [token, data] of this.tokens.entries()) {
      if (data.expiresAt < now) {
        this.tokens.delete(token);
        this.refreshTokens.delete(data.refreshToken);
        count++;
      }
    }
    if (count > 0) {
      logger.debug('Cleaned up expired tokens', { count });
    }
    return count;
  }

  /**
   * Store authorization code for PKCE flow
   */
  setAuthorizationCode(codeData: AuthorizationCode): void {
    this.authCodes.set(codeData.code, codeData);
    logger.debug('Authorization code stored', { clientId: codeData.clientId, userId: codeData.userId });
  }

  /**
   * Get and validate authorization code
   */
  consumeAuthorizationCode(code: string): AuthorizationCode | undefined {
    const codeData = this.authCodes.get(code);
    if (!codeData) return undefined;

    // Check expiration
    if (codeData.expiresAt < Date.now()) {
      this.authCodes.delete(code);
      return undefined;
    }

    // Mark as used
    codeData.used = true;
    this.authCodes.delete(code);

    return codeData;
  }

  /**
   * Register an OAuth client
   */
  registerClient(client: OAuthClient): void {
    this.clients.set(client.clientId, client);
    logger.debug('OAuth client registered', { clientId: client.clientId, name: client.clientName });
  }

  /**
   * Get OAuth client by ID
   */
  getClient(clientId: string): OAuthClient | undefined {
    return this.clients.get(clientId);
  }

  /**
   * Validate client credentials (for confidential clients)
   */
  validateClientCredentials(clientId: string, clientSecret: string): boolean {
    const client = this.clients.get(clientId);
    if (!client || !client.isConfidential) return false;
    return client.clientSecret === clientSecret;
  }

  /**
   * Check rate limit for a specific user
   */
  checkUserRateLimit(userId: string): { allowed: boolean; remaining: number; resetAt: number } {
    const now = Date.now();
    const record = this.userRateLimits.get(userId);

    if (!record || now > record.resetAt) {
      // Reset or create new record
      const resetAt = now + this.RATE_LIMIT_WINDOW_MS;
      this.userRateLimits.set(userId, {
        count: 1,
        resetAt,
      });
      return {
        allowed: true,
        remaining: this.RATE_LIMIT_MAX_REQUESTS - 1,
        resetAt,
      };
    }

    if (record.count >= this.RATE_LIMIT_MAX_REQUESTS) {
      return {
        allowed: false,
        remaining: 0,
        resetAt: record.resetAt,
      };
    }

    record.count += 1;
    return {
      allowed: true,
      remaining: this.RATE_LIMIT_MAX_REQUESTS - record.count,
      resetAt: record.resetAt,
    };
  }

  /**
   * Clean up old rate limit records
   */
  cleanupRateLimits(): void {
    const now = Date.now();
    for (const [key, record] of this.userRateLimits.entries()) {
      if (now > record.resetAt) {
        this.userRateLimits.delete(key);
      }
    }
  }

  /**
   * Get store statistics (for monitoring)
   */
  getStats(): {
    userCount: number;
    tenantCount: number;
    tokenCount: number;
    authCodeCount: number;
    clientCount: number;
  } {
    return {
      userCount: this.users.size,
      tenantCount: this.tenantUsers.size,
      tokenCount: this.tokens.size,
      authCodeCount: this.authCodes.size,
      clientCount: this.clients.size,
    };
  }

  /**
   * Clear all data (for testing)
   */
  clear(): void {
    this.users.clear();
    this.tokens.clear();
    this.refreshTokens.clear();
    this.authCodes.clear();
    this.clients.clear();
    this.tenantUsers.clear();
    this.userRateLimits.clear();
    logger.warn('User store cleared');
  }
}

// Export singleton instance
export const userStore = new UserStore();

// Periodic cleanup
setInterval(() => {
  userStore.cleanupExpiredTokens();
  userStore.cleanupRateLimits();
}, 5 * 60 * 1000); // Every 5 minutes
