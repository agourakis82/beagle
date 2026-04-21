/**
 * OAuth 2.0 Authorization Code flow with PKCE implementation
 *
 * BEAGLE's own OAuth server supporting:
 * - Authorization Code flow with PKCE (for public clients)
 * - Client Credentials flow (for server-to-server)
 * - JWT access tokens with configurable expiration
 * - Token refresh
 * - Multi-tenant user context
 */

import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { logger } from './logger.js';
import { userStore, type TokenData, type UserProfile, type AuthorizationCode, type OAuthClient } from './user-store.js';

// ========================================
// Configuration
// ========================================

const JWT_SECRET = process.env.OAUTH_JWT_SECRET || process.env.MCP_AUTH_TOKEN || 'default-secret-change-in-production';
const ACCESS_TOKEN_EXPIRY_MS = parseInt(process.env.OAUTH_ACCESS_TOKEN_EXPIRY_MS || '3600000', 10); // 1 hour default
const REFRESH_TOKEN_EXPIRY_MS = parseInt(process.env.OAUTH_REFRESH_TOKEN_EXPIRY_MS || '604800000', 10); // 7 days default
const AUTH_CODE_EXPIRY_MS = 10 * 60 * 1000; // 10 minutes
const OAUTH_ENABLED = process.env.OAUTH_ENABLED === 'true';
const ISSUER = process.env.OAUTH_ISSUER || 'beagle-mcp-server';

// PKCE Code Challenge Methods
export type CodeChallengeMethod = 'S256' | 'plain';

// ========================================
// Types
// ========================================

export interface TokenResponse {
  access_token: string;
  token_type: 'Bearer';
  expires_in: number;
  refresh_token?: string;
  scope?: string;
}

export interface TokenIntrospection {
  active: boolean;
  sub?: string; // userId
  tenant_id?: string;
  scope?: string;
  client_id?: string;
  exp?: number;
  iat?: number;
  iss?: string;
  jti?: string;
}

export interface UserContext {
  userId: string;
  tenantId: string;
  scopes: string[];
  roles: string[];
  clientId?: string;
  email?: string;
}

export interface AuthorizationRequest {
  response_type: 'code';
  client_id: string;
  redirect_uri: string;
  scope?: string;
  state?: string;
  code_challenge?: string;
  code_challenge_method?: CodeChallengeMethod;
  tenant_id?: string;
}

export interface TokenRequest {
  grant_type: 'authorization_code' | 'refresh_token' | 'client_credentials';
  code?: string;
  redirect_uri?: string;
  client_id?: string;
  client_secret?: string;
  code_verifier?: string;
  refresh_token?: string;
  scope?: string;
}

export interface JWTClaims {
  sub: string; // subject (userId)
  tenant_id: string;
  scope: string;
  client_id?: string;
  email?: string;
  roles: string[];
  iat: number;
  exp: number;
  iss: string;
  jti: string; // JWT ID for revocation
}

// ========================================
// PKCE Utilities
// ========================================

/**
 * Generate PKCE code verifier (43-128 chars)
 */
export function generateCodeVerifier(): string {
  // Generate 32 bytes (256 bits) of random data, base64url encode
  return crypto.randomBytes(32)
    .toString('base64url')
    .replace(/=/g, '');
}

/**
 * Generate PKCE code challenge from verifier using S256 method
 */
export function generateCodeChallenge(verifier: string, method: CodeChallengeMethod = 'S256'): string {
  if (method === 'plain') {
    return verifier;
  }
  // S256: SHA256 hash then base64url encode
  return crypto.createHash('sha256')
    .update(verifier)
    .digest('base64url')
    .replace(/=/g, '');
}

/**
 * Verify code challenge against stored challenge
 */
export function verifyCodeChallenge(verifier: string, challenge: string, method: CodeChallengeMethod): boolean {
  if (method === 'plain') {
    return verifier === challenge;
  }
  const computed = generateCodeChallenge(verifier, 'S256');
  return computed === challenge;
}

// ========================================
// Token Generation
// ========================================

/**
 * Generate secure random token
 */
function generateRandomToken(length: number = 32): string {
  return crypto.randomBytes(length).toString('base64url').slice(0, length);
}

/**
 * Generate JWT access token
 */
export function generateAccessToken(user: UserProfile, clientId: string, scopes: string[]): string {
  const now = Math.floor(Date.now() / 1000);
  const claims: JWTClaims = {
    sub: user.userId,
    tenant_id: user.tenantId,
    scope: scopes.join(' '),
    client_id: clientId,
    email: user.email,
    roles: user.roles,
    iat: now,
    exp: now + Math.floor(ACCESS_TOKEN_EXPIRY_MS / 1000),
    iss: ISSUER,
    jti: generateRandomToken(16),
  };

  return jwt.sign(claims, JWT_SECRET, { algorithm: 'HS256' });
}

/**
 * Generate refresh token
 */
function generateRefreshToken(): string {
  return generateRandomToken(64);
}

/**
 * Generate authorization code
 */
function generateAuthorizationCode(): string {
  return generateRandomToken(32);
}

// ========================================
// Token Validation
// ========================================

/**
 * Validate and decode JWT access token
 */
export function validateAccessToken(token: string): { valid: boolean; context?: UserContext; error?: string } {
  try {
    const decoded = jwt.verify(token, JWT_SECRET, {
      algorithms: ['HS256'],
      issuer: ISSUER,
    }) as JWTClaims;

    // Check if token is revoked in store
    const storedToken = userStore.getToken(token);
    if (!storedToken) {
      return { valid: false, error: 'Token has been revoked' };
    }

    // Check expiration
    if (decoded.exp * 1000 < Date.now()) {
      return { valid: false, error: 'Token has expired' };
    }

    const context: UserContext = {
      userId: decoded.sub,
      tenantId: decoded.tenant_id,
      scopes: decoded.scope.split(' ').filter(s => s),
      roles: decoded.roles || [],
      clientId: decoded.client_id,
      email: decoded.email,
    };

    return { valid: true, context };
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      return { valid: false, error: 'Token has expired' };
    }
    if (error instanceof jwt.JsonWebTokenError) {
      return { valid: false, error: 'Invalid token' };
    }
    logger.error('Token validation error', { error });
    return { valid: false, error: 'Token validation failed' };
  }
}

/**
 * Introspect token (OAuth 2.0 Token Introspection RFC 7662)
 */
export function introspectToken(token: string): TokenIntrospection {
  const validation = validateAccessToken(token);

  if (!validation.valid || !validation.context) {
    return { active: false };
  }

  const storedToken = userStore.getToken(token);
  if (!storedToken) {
    return { active: false };
  }

  const ctx = validation.context;
  const decoded = jwt.decode(token) as JWTClaims;

  return {
    active: true,
    sub: ctx.userId,
    tenant_id: ctx.tenantId,
    scope: ctx.scopes.join(' '),
    client_id: ctx.clientId,
    exp: decoded.exp,
    iat: decoded.iat,
    iss: decoded.iss,
    jti: decoded.jti,
  };
}

// ========================================
// OAuth Flow Handlers
// ========================================

/**
 * Handle authorization request (PKCE flow step 1)
 * In a real OAuth server, this would show a login/consent page
 * For MCP server, we auto-approve if client is registered
 */
export function handleAuthorizationRequest(
  request: AuthorizationRequest,
  userId: string,
): { success: true; code: string; state?: string } | { success: false; error: string; error_description?: string } {
  // Validate client
  const client = userStore.getClient(request.client_id);
  if (!client) {
    return { success: false, error: 'invalid_client', error_description: 'Client not registered' };
  }

  // Validate redirect URI
  if (!client.redirectUris.includes(request.redirect_uri)) {
    return { success: false, error: 'invalid_redirect_uri', error_description: 'Redirect URI not registered' };
  }

  // Validate response type
  if (request.response_type !== 'code') {
    return { success: false, error: 'unsupported_response_type' };
  }

  // Validate scope
  const requestedScopes = request.scope?.split(' ').filter(s => s) || ['default'];
  const invalidScopes = requestedScopes.filter(s => !client.allowedScopes.includes(s) && s !== 'default');
  if (invalidScopes.length > 0) {
    return { success: false, error: 'invalid_scope', error_description: `Invalid scopes: ${invalidScopes.join(', ')}` };
  }

  // PKCE is required for public clients
  if (!client.isConfidential && !request.code_challenge) {
    return { success: false, error: 'invalid_request', error_description: 'PKCE code_challenge required for public clients' };
  }

  // Get or create user profile
  const tenantId = request.tenant_id || 'default';
  let user = userStore.getUser(userId);

  if (!user) {
    user = {
      userId,
      tenantId,
      roles: ['user'],
      metadata: {},
      createdAt: Date.now(),
      lastAccessAt: Date.now(),
    };
    userStore.setUser(user);
  } else {
    user.lastAccessAt = Date.now();
    userStore.setUser(user);
  }

  // Generate authorization code
  const code = generateAuthorizationCode();
  const codeData: AuthorizationCode = {
    code,
    clientId: request.client_id,
    userId,
    tenantId,
    codeChallenge: request.code_challenge || '',
    codeChallengeMethod: (request.code_challenge_method as 'S256') || 'S256',
    scope: requestedScopes,
    expiresAt: Date.now() + AUTH_CODE_EXPIRY_MS,
    used: false,
  };

  userStore.setAuthorizationCode(codeData);

  logger.info('Authorization code issued', {
    clientId: request.client_id,
    userId,
    tenantId,
    scope: requestedScopes.join(' '),
  });

  return { success: true, code, state: request.state };
}

/**
 * Handle token request (exchange code for tokens or refresh)
 */
export function handleTokenRequest(
  request: TokenRequest,
): { success: true; response: TokenResponse } | { success: false; error: string; error_description?: string } {
  // Validate client credentials for confidential clients
  if (request.client_id && request.client_secret) {
    const isValid = userStore.validateClientCredentials(request.client_id, request.client_secret);
    if (!isValid) {
      return { success: false, error: 'invalid_client', error_description: 'Invalid client credentials' };
    }
  }

  switch (request.grant_type) {
    case 'authorization_code':
      return handleAuthorizationCodeGrant(request);
    case 'refresh_token':
      return handleRefreshTokenGrant(request);
    case 'client_credentials':
      return handleClientCredentialsGrant(request);
    default:
      return { success: false, error: 'unsupported_grant_type' };
  }
}

/**
 * Handle authorization code grant (exchange code for tokens)
 */
function handleAuthorizationCodeGrant(
  request: TokenRequest,
): { success: true; response: TokenResponse } | { success: false; error: string; error_description?: string } {
  if (!request.code) {
    return { success: false, error: 'invalid_request', error_description: 'Missing authorization code' };
  }

  // Consume the code (marks as used and removes)
  const codeData = userStore.consumeAuthorizationCode(request.code);
  if (!codeData) {
    return { success: false, error: 'invalid_grant', error_description: 'Invalid or expired authorization code' };
  }

  // Validate client
  const client = userStore.getClient(codeData.clientId);
  if (!client) {
    return { success: false, error: 'invalid_client' };
  }

  // Verify PKCE code verifier if PKCE was used
  if (codeData.codeChallenge && request.code_verifier) {
    const valid = verifyCodeChallenge(
      request.code_verifier,
      codeData.codeChallenge,
      codeData.codeChallengeMethod,
    );
    if (!valid) {
      return { success: false, error: 'invalid_grant', error_description: 'Invalid code_verifier' };
    }
  } else if (codeData.codeChallenge && !request.code_verifier) {
    return { success: false, error: 'invalid_request', error_description: 'Missing code_verifier' };
  }

  // Get user
  let user = userStore.getUser(codeData.userId);
  if (!user) {
    return { success: false, error: 'invalid_grant', error_description: 'User not found' };
  }

  // Update last access
  user.lastAccessAt = Date.now();
  userStore.setUser(user);

  // Generate tokens
  const accessToken = generateAccessToken(user, codeData.clientId, codeData.scope);
  const refreshToken = generateRefreshToken();

  // Store token data
  const tokenData: TokenData = {
    accessToken,
    refreshToken,
    expiresAt: Date.now() + ACCESS_TOKEN_EXPIRY_MS,
    scope: codeData.scope,
    tokenType: 'Bearer',
  };
  userStore.setToken(accessToken, tokenData, user.userId);

  logger.info('Token issued (authorization_code)', {
    clientId: codeData.clientId,
    userId: user.userId,
    tenantId: user.tenantId,
  });

  return {
    success: true,
    response: {
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: Math.floor(ACCESS_TOKEN_EXPIRY_MS / 1000),
      refresh_token: refreshToken,
      scope: codeData.scope.join(' '),
    },
  };
}

/**
 * Handle refresh token grant
 */
function handleRefreshTokenGrant(
  request: TokenRequest,
): { success: true; response: TokenResponse } | { success: false; error: string; error_description?: string } {
  if (!request.refresh_token) {
    return { success: false, error: 'invalid_request', error_description: 'Missing refresh_token' };
  }

  // Get user from refresh token
  const userId = userStore.getUserByRefreshToken(request.refresh_token);
  if (!userId) {
    return { success: false, error: 'invalid_grant', error_description: 'Invalid refresh token' };
  }

  const user = userStore.getUser(userId);
  if (!user) {
    return { success: false, error: 'invalid_grant', error_description: 'User not found' };
  }

  // Determine scopes (can be subset of original, or maintain same)
  const scopes = request.scope?.split(' ').filter(s => s) || ['default'];

  // Generate new tokens
  const accessToken = generateAccessToken(user, request.client_id || 'unknown', scopes);
  const newRefreshToken = generateRefreshToken();

  // Store new token data
  const tokenData: TokenData = {
    accessToken,
    refreshToken: newRefreshToken,
    expiresAt: Date.now() + ACCESS_TOKEN_EXPIRY_MS,
    scope: scopes,
    tokenType: 'Bearer',
  };
  userStore.setToken(accessToken, tokenData, userId);

  logger.info('Token refreshed', {
    clientId: request.client_id,
    userId: user.userId,
    tenantId: user.tenantId,
  });

  return {
    success: true,
    response: {
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: Math.floor(ACCESS_TOKEN_EXPIRY_MS / 1000),
      refresh_token: newRefreshToken,
      scope: scopes.join(' '),
    },
  };
}

/**
 * Handle client credentials grant (server-to-server)
 */
function handleClientCredentialsGrant(
  request: TokenRequest,
): { success: true; response: TokenResponse } | { success: false; error: string; error_description?: string } {
  if (!request.client_id) {
    return { success: false, error: 'invalid_request', error_description: 'Missing client_id' };
  }

  // Client must be confidential and authenticated
  const client = userStore.getClient(request.client_id);
  if (!client || !client.isConfidential) {
    return { success: false, error: 'unauthorized_client', error_description: 'Client not authorized for client_credentials' };
  }

  // Create service user for this client
  const userId = `service:${request.client_id}`;
  const tenantId = 'system';

  let user = userStore.getUser(userId);
  if (!user) {
    user = {
      userId,
      tenantId,
      roles: ['service'],
      metadata: { clientId: request.client_id },
      createdAt: Date.now(),
      lastAccessAt: Date.now(),
    };
    userStore.setUser(user);
  }

  // Determine scopes
  const requestedScopes = request.scope?.split(' ').filter(s => s) || ['default'];
  const allowedScopes = requestedScopes.filter(s => client.allowedScopes.includes(s));

  // Generate tokens
  const accessToken = generateAccessToken(user, request.client_id, allowedScopes);
  const refreshToken = generateRefreshToken();

  // Store token data
  const tokenData: TokenData = {
    accessToken,
    refreshToken,
    expiresAt: Date.now() + ACCESS_TOKEN_EXPIRY_MS,
    scope: allowedScopes,
    tokenType: 'Bearer',
  };
  userStore.setToken(accessToken, tokenData, userId);

  logger.info('Token issued (client_credentials)', {
    clientId: request.client_id,
    scope: allowedScopes.join(' '),
  });

  return {
    success: true,
    response: {
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: Math.floor(ACCESS_TOKEN_EXPIRY_MS / 1000),
      refresh_token: refreshToken,
      scope: allowedScopes.join(' '),
    },
  };
}

// ========================================
// Client Registration
// ========================================

/**
 * Register a new OAuth client
 */
export function registerOAuthClient(
  clientName: string,
  redirectUris: string[],
  allowedScopes: string[] = ['default', 'read', 'write'],
  isConfidential: boolean = false,
  clientSecret?: string,
): OAuthClient {
  const clientId = generateRandomToken(16);
  const secret = isConfidential ? (clientSecret || generateRandomToken(32)) : undefined;

  const client: OAuthClient = {
    clientId,
    clientSecret: secret,
    clientName,
    redirectUris,
    allowedScopes,
    isConfidential,
    createdAt: Date.now(),
  };

  userStore.registerClient(client);

  logger.info('OAuth client registered via API', {
    clientId,
    clientName,
    isConfidential,
  });

  return client;
}

// ========================================
// Revocation
// ========================================

/**
 * Revoke a token (OAuth 2.0 Token Revocation RFC 7009)
 */
export function revokeToken(token: string, tokenTypeHint?: 'access_token' | 'refresh_token'): boolean {
  // Try as access token first
  if (!tokenTypeHint || tokenTypeHint === 'access_token') {
    const revoked = userStore.revokeToken(token);
    if (revoked) return true;
  }

  // If not found as access token or hint was refresh_token, nothing more to do
  // (we already delete both together in userStore.revokeToken)
  return false;
}

// ========================================
// Middleware Helpers
// ========================================

/**
 * Extract bearer token from authorization header
 */
export function extractBearerToken(authHeader?: string): string | undefined {
  if (!authHeader) return undefined;

  const parts = authHeader.split(' ');
  if (parts.length === 2 && parts[0] === 'Bearer') {
    return parts[1];
  }

  return undefined;
}

/**
 * Check if OAuth is enabled
 */
export function isOAuthEnabled(): boolean {
  return OAUTH_ENABLED;
}

/**
 * Validate JWT secret is configured
 */
export function validateOAuthConfig(): { valid: boolean; error?: string } {
  if (!OAUTH_ENABLED) {
    return { valid: true };
  }

  if (JWT_SECRET === 'default-secret-change-in-production') {
    logger.warn('OAuth enabled with default JWT secret - this is insecure for production');
  }

  return { valid: true };
}
