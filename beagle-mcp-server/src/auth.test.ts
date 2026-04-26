import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";
import {
    exportJWK,
    generateKeyPair,
    SignJWT,
    type JWK,
    type KeyLike,
} from "jose";

type AuthModule = typeof import("./auth.js");

const AUTH_ENV_KEYS = [
    "MCP_ENABLE_AUTH",
    "MCP_REQUIRE_AUTH",
    "MCP_AUTH_TOKEN",
    "BEAGLE_CORE_API_TOKEN",
    "MCP_ALLOW_LEGACY_BEARER",
    "MCP_OAUTH_ISSUER",
    "MCP_AUTHORIZATION_SERVER_URL",
    "MCP_OAUTH_JWKS_URI",
    "MCP_OAUTH_AUDIENCE",
    "MCP_RESOURCE_IDENTIFIER",
    "MCP_DEFAULT_SCOPES",
    "MCP_TOKEN_SCOPE_MAP",
    "MCP_PUBLIC_BASE_URL",
    "MCP_RESOURCE_METADATA_URL",
];

test("Auth0-style JWT validation accepts scoped OAuth access tokens", async () => {
    await withJwksFixture(async (fixture) => {
        const auth = await loadAuth({
            MCP_REQUIRE_AUTH: "true",
            MCP_ALLOW_LEGACY_BEARER: "false",
            MCP_OAUTH_ISSUER: fixture.issuer,
            MCP_OAUTH_JWKS_URI: fixture.jwksUri,
            MCP_OAUTH_AUDIENCE: fixture.audience,
            MCP_RESOURCE_IDENTIFIER: fixture.audience,
        });
        const token = await fixture.sign({
            scope: "exocortex:read memory:write",
            client_id: "claude-mcp-test",
        });

        const result = await auth.validateAuth(token);

        assert.equal(result.valid, true);
        assert.equal(result.authType, "oauth");
        assert.equal(result.clientId, "claude-mcp-test");
        assert.deepEqual(result.scopes, ["exocortex:read", "memory:write"]);
    });
});

test("Auth0-style JWT validation accepts permissions array scopes", async () => {
    await withJwksFixture(async (fixture) => {
        const auth = await loadAuth({
            MCP_REQUIRE_AUTH: "true",
            MCP_ALLOW_LEGACY_BEARER: "false",
            MCP_OAUTH_ISSUER: fixture.issuer,
            MCP_OAUTH_JWKS_URI: fixture.jwksUri,
            MCP_OAUTH_AUDIENCE: fixture.audience,
        });
        const token = await fixture.sign({
            permissions: ["exocortex:read", "research:run"],
            azp: "auth0-claude-app",
        });

        const result = await auth.validateAuth(token);

        assert.equal(result.valid, true);
        assert.equal(result.clientId, "auth0-claude-app");
        assert.deepEqual(result.scopes, ["exocortex:read", "research:run"]);
    });
});

test("Auth0-style JWT validation rejects expired, wrong-audience, and wrong-issuer tokens", async () => {
    await withJwksFixture(async (fixture) => {
        const auth = await loadAuth({
            MCP_REQUIRE_AUTH: "true",
            MCP_ALLOW_LEGACY_BEARER: "false",
            MCP_OAUTH_ISSUER: fixture.issuer,
            MCP_OAUTH_JWKS_URI: fixture.jwksUri,
            MCP_OAUTH_AUDIENCE: fixture.audience,
        });

        const expired = await fixture.sign(
            { scope: "exocortex:read" },
            { expiresAt: Math.floor(Date.now() / 1000) - 60 },
        );
        const wrongAudience = await fixture.sign(
            { scope: "exocortex:read" },
            { audience: "https://wrong.example.com/mcp" },
        );
        const wrongIssuer = await fixture.sign(
            { scope: "exocortex:read" },
            { issuer: `${fixture.issuer}wrong/` },
        );

        for (const token of [expired, wrongAudience, wrongIssuer]) {
            const result = await auth.validateAuth(token);
            assert.equal(result.valid, false);
            assert.equal(result.statusCode, 401);
            assert.equal(result.errorCode, "invalid_token");
        }
    });
});

test("OAuth production mode rejects legacy bearer tokens when disabled", async () => {
    await withJwksFixture(async (fixture) => {
        const auth = await loadAuth({
            MCP_REQUIRE_AUTH: "true",
            MCP_AUTH_TOKEN: "legacy-secret",
            MCP_ALLOW_LEGACY_BEARER: "false",
            MCP_OAUTH_ISSUER: fixture.issuer,
            MCP_OAUTH_JWKS_URI: fixture.jwksUri,
            MCP_OAUTH_AUDIENCE: fixture.audience,
        });

        const result = await auth.validateAuth("legacy-secret");

        assert.equal(result.valid, false);
        assert.equal(result.statusCode, 401);
        assert.equal(result.errorCode, "invalid_token");
    });
});

test("missing OAuth scope produces insufficient-scope challenge metadata", async () => {
    await withJwksFixture(async (fixture) => {
        const auth = await loadAuth({
            MCP_REQUIRE_AUTH: "true",
            MCP_ALLOW_LEGACY_BEARER: "false",
            MCP_OAUTH_ISSUER: fixture.issuer,
            MCP_OAUTH_JWKS_URI: fixture.jwksUri,
            MCP_OAUTH_AUDIENCE: fixture.audience,
            MCP_PUBLIC_BASE_URL: "https://mcp.agourakis.com",
        });
        const token = await fixture.sign({ scope: "exocortex:read" });
        const result = await auth.validateAuth(token);

        assert.equal(result.valid, true);
        const scopeCheck = auth.assertRequiredScopes(result.scopes, [
            "exocortex:read",
            "research:run",
        ]);
        assert.equal(scopeCheck.allowed, false);
        assert.deepEqual(scopeCheck.missing, ["research:run"]);
        assert.match(
            auth.wwwAuthenticateHeader({
                error: "insufficient_scope",
                description: "Missing scopes: research:run",
                scopes: ["exocortex:read", "research:run"],
            }),
            /error="insufficient_scope".*scope="exocortex:read research:run"/,
        );
    });
});

test("public scope policy reserves destructive scope without exposing it", async () => {
    const auth = await loadAuth({
        MCP_REQUIRE_AUTH: "true",
        MCP_ALLOW_LEGACY_BEARER: "false",
        MCP_OAUTH_ISSUER: "https://auth.example.com/",
        MCP_OAUTH_JWKS_URI: "https://auth.example.com/.well-known/jwks.json",
        MCP_OAUTH_AUDIENCE: "https://mcp.agourakis.com/mcp",
        MCP_TOOL_SURFACE: "trusted_full",
    });

    const policy = auth.scopePolicy();

    assert.equal(policy.auth_mode, "oauth_jwt_resource_server");
    assert.equal(policy.tool_surface, "trusted_full");
    assert.equal(policy.destructive_scope, null);
    assert.equal(policy.destructive_scope_reserved, "admin:destructive");
    assert.ok(!policy.default_scopes.includes("admin:destructive"));
});

async function loadAuth(env: Record<string, string>): Promise<AuthModule> {
    for (const key of AUTH_ENV_KEYS) {
        delete process.env[key];
    }
    Object.assign(process.env, env);
    return import(`./auth.js?case=${Date.now()}-${Math.random()}`);
}

async function withJwksFixture(
    fn: (fixture: {
        issuer: string;
        jwksUri: string;
        audience: string;
        sign: (
            payload: Record<string, unknown>,
            options?: { audience?: string; issuer?: string; expiresAt?: number | string },
        ) => Promise<string>;
    }) => Promise<void>,
): Promise<void> {
    const { publicKey, privateKey } = await generateKeyPair("RS256", { extractable: true });
    const kid = "beagle-auth0-test-key";
    const publicJwk = {
        ...(await exportJWK(publicKey)),
        kid,
        alg: "RS256",
        use: "sig",
    } as JWK;

    const server = http.createServer((req, res) => {
        if (req.url === "/.well-known/jwks.json") {
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ keys: [publicJwk] }));
            return;
        }
        res.writeHead(404, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "not_found" }));
    });

    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    assert.ok(address && typeof address === "object");
    const issuer = `http://127.0.0.1:${address.port}/`;
    const audience = "https://mcp.agourakis.com/mcp";

    try {
        await fn({
            issuer,
            jwksUri: `${issuer}.well-known/jwks.json`,
            audience,
            sign: (payload, options = {}) =>
                signToken(privateKey, kid, {
                    issuer: options.issuer ?? issuer,
                    audience: options.audience ?? audience,
                    expiresAt: options.expiresAt ?? "5m",
                    payload,
                }),
        });
    } finally {
        await new Promise<void>((resolve, reject) =>
            server.close((error) => (error ? reject(error) : resolve())),
        );
    }
}

async function signToken(
    privateKey: KeyLike,
    kid: string,
    options: {
        issuer: string;
        audience: string;
        expiresAt: number | string;
        payload: Record<string, unknown>;
    },
): Promise<string> {
    return new SignJWT(options.payload)
        .setProtectedHeader({ alg: "RS256", kid })
        .setIssuer(options.issuer)
        .setAudience(options.audience)
        .setSubject("auth0|beagle-test")
        .setIssuedAt()
        .setExpirationTime(options.expiresAt)
        .sign(privateKey);
}
