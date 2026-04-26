/**
 * Authentication middleware for MCP server.
 *
 * Supports the v1 local/trusted bearer model and the public remote-connector
 * model where Beagle acts as an OAuth 2.1 protected resource server.
 */

import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";
import { logger } from "./logger.js";
import { BASIC_SCOPES } from "./tool-manifest.js";
import { activeClientSurface } from "./client-profile.js";

const AUTH_TOKEN = process.env.MCP_AUTH_TOKEN || process.env.BEAGLE_CORE_API_TOKEN;
const ENABLE_AUTH =
    process.env.MCP_ENABLE_AUTH === "true" ||
    process.env.MCP_REQUIRE_AUTH === "true";
const ALLOW_LEGACY_BEARER = process.env.MCP_ALLOW_LEGACY_BEARER !== "false";

const RATE_LIMIT_MAX_REQUESTS = Number.parseInt(
    process.env.RATE_LIMIT_PER_MINUTE || process.env.MCP_RATE_LIMIT_PER_MINUTE || "100",
    10,
);

export interface AuthValidationResult {
    valid: boolean;
    error?: string;
    errorCode?: string;
    statusCode?: number;
    clientId?: string;
    scopes: string[];
    authType?: "none" | "bearer" | "oauth";
    principal?: McpPrincipal;
}

export interface McpPrincipal {
    id: string;
    auth_type: "none" | "bearer" | "oauth";
    client_surface: string;
    scopes: string[];
    client_id?: string;
    subject?: string;
    issuer?: string;
    audience?: string | string[];
}

/**
 * Validates a bearer token from request metadata/headers.
 */
export async function validateAuth(token?: string): Promise<AuthValidationResult> {
    if (!isAuthEnabled()) {
        const scopes = [...BASIC_SCOPES];
        return {
            valid: true,
            clientId: "stdio",
            scopes,
            authType: "none",
            principal: {
                id: "stdio",
                auth_type: "none",
                client_surface: activeClientSurface(),
                scopes,
            },
        };
    }

    if (!token) {
        return authFailure("Missing authorization token", "invalid_request", 401);
    }

    const cleanToken = token.startsWith("Bearer ") ? token.slice(7) : token;
    const oauthConfigured = isOAuthEnabled();

    if (oauthConfigured) {
        const oauthResult = await validateOAuthJwt(cleanToken);
        if (oauthResult.valid) {
            return oauthResult;
        }

        if (!ALLOW_LEGACY_BEARER) {
            logger.warn("Invalid OAuth token attempt", {
                error: oauthResult.error,
                errorCode: oauthResult.errorCode,
            });
            return oauthResult;
        }
    }

    const legacyResult = validateLegacyBearer(cleanToken);
    if (legacyResult.valid) {
        return legacyResult;
    }

    if (oauthConfigured) {
        logger.warn("Invalid MCP token attempt", { oauth: true, legacy: false });
        return authFailure("Invalid authorization token", "invalid_token", 401);
    }

    if (!AUTH_TOKEN && !process.env.MCP_TOKEN_SCOPE_MAP) {
        logger.warn("MCP auth enabled but neither MCP_AUTH_TOKEN nor MCP_TOKEN_SCOPE_MAP is set");
        return authFailure("Authentication required but not configured", "server_error", 500);
    }

    logger.warn("Invalid auth token attempt");
    return legacyResult;
}

export function isAuthEnabled(): boolean {
    return ENABLE_AUTH || isOAuthEnabled();
}

export function isOAuthEnabled(): boolean {
    return Boolean(oauthIssuer() && oauthAudiences().length > 0);
}

/**
 * Extracts token from Authorization header
 */
export function extractToken(authHeader?: string): string | undefined {
    if (!authHeader) {
        return undefined;
    }

    if (authHeader.startsWith("Bearer ")) {
        return authHeader.slice(7);
    }

    return authHeader;
}

export function assertRequiredScopes(
    grantedScopes: string[],
    requiredScopes: string[],
): { allowed: boolean; missing: string[] } {
    const granted = new Set(grantedScopes);
    const missing = requiredScopes.filter((scope) => !granted.has(scope));
    return { allowed: missing.length === 0, missing };
}

export function scopePolicy() {
    return {
        default_scopes: BASIC_SCOPES,
        destructive_scope: null,
        destructive_scope_reserved: "admin:destructive",
        destructive_actions: "locked in v1.1; no exposed tool has destructiveHint=true",
        client_surface: activeClientSurface(),
        auth_mode: isOAuthEnabled()
            ? "oauth_jwt_resource_server"
            : isAuthEnabled()
              ? "scoped_bearer"
              : "disabled",
        oauth_issuer: oauthIssuer(),
        oauth_audiences: oauthAudiences(),
        tool_surface: process.env.MCP_TOOL_SURFACE || "trusted_full",
        scope_mapping: process.env.MCP_TOKEN_SCOPE_MAP
            ? "MCP_TOKEN_SCOPE_MAP configured"
            : "single trusted token receives default scopes",
    };
}

export function wwwAuthenticateHeader(options: {
    error?: string;
    description?: string;
    scopes?: string[];
} = {}): string {
    const params = [
        `realm="beagle-mcp"`,
        `resource_metadata="${escapeHeaderValue(resourceMetadataUrl())}"`,
    ];
    if (options.error) {
        params.push(`error="${escapeHeaderValue(options.error)}"`);
    }
    if (options.description) {
        params.push(`error_description="${escapeHeaderValue(options.description)}"`);
    }
    if (options.scopes && options.scopes.length > 0) {
        params.push(`scope="${escapeHeaderValue(options.scopes.join(" "))}"`);
    }
    return `Bearer ${params.join(", ")}`;
}

function validateLegacyBearer(cleanToken: string): AuthValidationResult {
    if (AUTH_TOKEN && cleanToken === AUTH_TOKEN) {
        const scopes = parseScopeList(process.env.MCP_DEFAULT_SCOPES) ?? [...BASIC_SCOPES];
        const clientId = process.env.MCP_DEFAULT_CLIENT_ID || "trusted-agent";
        return {
            valid: true,
            clientId,
            scopes,
            authType: "bearer",
            principal: {
                id: clientId,
                client_id: clientId,
                auth_type: "bearer",
                client_surface: activeClientSurface(),
                scopes,
            },
        };
    }
    return mappedTokenAuth(cleanToken);
}

async function validateOAuthJwt(cleanToken: string): Promise<AuthValidationResult> {
    const issuer = oauthIssuer();
    const audiences = oauthAudiences();
    const jwksUri = oauthJwksUri();
    if (!issuer || audiences.length === 0 || !jwksUri) {
        return authFailure("OAuth validation is not fully configured", "server_error", 500);
    }

    try {
        const jwks = remoteJwks(jwksUri);
        const { payload } = await jwtVerify(cleanToken, jwks, {
            issuer,
            audience: audiences.length === 1 ? audiences[0] : audiences,
        });
        const scopes = scopesFromPayload(payload);
        return {
            valid: true,
            clientId: clientIdFromPayload(payload),
            scopes,
            authType: "oauth",
            principal: principalFromPayload(payload, scopes),
        };
    } catch (error) {
        return authFailure(
            `Invalid OAuth access token: ${error instanceof Error ? error.message : String(error)}`,
            "invalid_token",
            401,
        );
    }
}

let cachedJwksUri: string | undefined;
let cachedJwks: ReturnType<typeof createRemoteJWKSet> | undefined;

function remoteJwks(jwksUri: string): ReturnType<typeof createRemoteJWKSet> {
    if (!cachedJwks || cachedJwksUri !== jwksUri) {
        cachedJwksUri = jwksUri;
        cachedJwks = createRemoteJWKSet(new URL(jwksUri));
    }
    return cachedJwks;
}

function mappedTokenAuth(cleanToken: string): AuthValidationResult {
    const rawMap = process.env.MCP_TOKEN_SCOPE_MAP;
    if (!rawMap) {
        return authFailure("Invalid authorization token", "invalid_token", 401);
    }

    try {
        const parsed = JSON.parse(rawMap) as Record<
            string,
            string[] | { client_id?: string; clientId?: string; scopes?: string[] }
        >;
        const entry = parsed[cleanToken];
        if (!entry) {
            return authFailure("Invalid authorization token", "invalid_token", 401);
        }
        if (Array.isArray(entry)) {
            return {
                valid: true,
                clientId: "mapped-agent",
                scopes: entry,
                authType: "bearer",
                principal: {
                    id: "mapped-agent",
                    client_id: "mapped-agent",
                    auth_type: "bearer",
                    client_surface: activeClientSurface(),
                    scopes: entry,
                },
            };
        }
        const clientId = entry.client_id ?? entry.clientId ?? "mapped-agent";
        const scopes = entry.scopes ?? [];
        return {
            valid: true,
            clientId,
            scopes,
            authType: "bearer",
            principal: {
                id: clientId,
                client_id: clientId,
                auth_type: "bearer",
                client_surface: activeClientSurface(),
                scopes,
            },
        };
    } catch (error) {
        logger.warn("MCP_TOKEN_SCOPE_MAP is not valid JSON", { error });
        return authFailure("Authorization token scope map is invalid", "server_error", 500);
    }
}

function parseScopeList(value?: string): string[] | undefined {
    if (!value) return undefined;
    const scopes = value
        .split(/[,\s]+/)
        .map((scope) => scope.trim())
        .filter(Boolean);
    return scopes.length > 0 ? scopes : undefined;
}

function oauthIssuer(): string | undefined {
    return process.env.MCP_OAUTH_ISSUER || process.env.MCP_AUTHORIZATION_SERVER_URL;
}

function oauthAudiences(): string[] {
    return parseScopeList(process.env.MCP_OAUTH_AUDIENCE || process.env.MCP_RESOURCE_IDENTIFIER) ?? [];
}

function oauthJwksUri(): string | undefined {
    if (process.env.MCP_OAUTH_JWKS_URI) {
        return process.env.MCP_OAUTH_JWKS_URI;
    }
    const issuer = oauthIssuer();
    return issuer ? `${trimTrailingSlash(issuer)}/.well-known/jwks.json` : undefined;
}

function publicBaseUrl(): string {
    if (process.env.MCP_PUBLIC_BASE_URL) {
        return trimTrailingSlash(process.env.MCP_PUBLIC_BASE_URL) ?? process.env.MCP_PUBLIC_BASE_URL;
    }
    if (process.env.MCP_RESOURCE_IDENTIFIER) {
        return trimTrailingSlash(process.env.MCP_RESOURCE_IDENTIFIER.replace(/\/mcp$/, "")) ??
            process.env.MCP_RESOURCE_IDENTIFIER;
    }
    return `http://localhost:${process.env.MCP_HTTP_PORT || "3000"}`;
}

function resourceMetadataUrl(): string {
    return (
        process.env.MCP_RESOURCE_METADATA_URL ||
        `${publicBaseUrl()}/.well-known/oauth-protected-resource`
    );
}

function trimTrailingSlash(value?: string): string | undefined {
    return value?.replace(/\/+$/, "");
}

function scopesFromPayload(payload: JWTPayload): string[] {
    return uniqueScopes([
        ...stringOrArray(payload.scope),
        ...stringOrArray(payload.scp),
        ...stringOrArray(payload.permissions),
    ]);
}

function stringOrArray(value: unknown): string[] {
    if (typeof value === "string") {
        return value.split(/[,\s]+/).filter(Boolean);
    }
    if (Array.isArray(value)) {
        return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
    }
    return [];
}

function uniqueScopes(values: string[]): string[] {
    return Array.from(new Set(values.map((scope) => scope.trim()).filter(Boolean)));
}

function clientIdFromPayload(payload: JWTPayload): string {
    const claimName = process.env.MCP_OAUTH_CLIENT_ID_CLAIM;
    const explicit = claimName ? payload[claimName] : undefined;
    return (
        stringClaim(explicit) ??
        stringClaim(payload.client_id) ??
        stringClaim(payload.azp) ??
        stringClaim(payload.sub) ??
        "oauth-agent"
    );
}

function principalFromPayload(payload: JWTPayload, scopes: string[]): McpPrincipal {
    const clientId = clientIdFromPayload(payload);
    return {
        id: clientId,
        client_id:
            stringClaim(payload.client_id) ??
            stringClaim(payload.azp) ??
            clientId,
        subject: stringClaim(payload.sub),
        issuer: stringClaim(payload.iss),
        audience: payload.aud,
        auth_type: "oauth",
        client_surface: activeClientSurface(),
        scopes,
    };
}

function stringClaim(value: unknown): string | undefined {
    return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}

function authFailure(error: string, errorCode: string, statusCode: number): AuthValidationResult {
    return { valid: false, error, errorCode, statusCode, scopes: [] };
}

function escapeHeaderValue(value: string): string {
    return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

/**
 * Rate limiting (simple in-memory, can be enhanced with Redis)
 */
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();

const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
export function checkRateLimit(identifier: string): { allowed: boolean; remaining?: number } {
    const now = Date.now();
    const record = rateLimitMap.get(identifier);

    if (!record || now > record.resetAt) {
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
const cleanupInterval = setInterval(cleanupRateLimit, 5 * 60 * 1000);
cleanupInterval.unref?.();
