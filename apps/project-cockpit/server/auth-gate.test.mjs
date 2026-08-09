import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyAuth } from "./auth-gate.mjs";

const TOKENS = new Set(["real-token", "internal-token"]);

test("a real token passes, on reads and on writes", () => {
  for (const method of ["GET", "POST", "DELETE"]) {
    assert.equal(classifyAuth({ method, tokens: TOKENS, headerToken: "real-token" }).allow, true);
    assert.equal(classifyAuth({ method, tokens: TOKENS, bearer: "internal-token" }).allow, true);
  }
});

test("no credential at all is refused", () => {
  const v = classifyAuth({ method: "GET", tokens: TOKENS });
  assert.equal(v.allow, false);
  assert.match(v.reason, /unauthorized/);
});

test("a wrong token does not slip through as an empty match", () => {
  assert.equal(classifyAuth({ method: "GET", tokens: TOKENS, headerToken: "nope" }).allow, false);
  // An empty string must never be treated as "present and matching".
  assert.equal(classifyAuth({ method: "GET", tokens: new Set([""]), headerToken: "" }).allow, false);
  assert.equal(classifyAuth({ method: "GET", tokens: new Set([""]), bearer: "" }).allow, false);
});

test("FAIL CLOSED when no token is configured — a missing secret is not an open door", () => {
  const v = classifyAuth({ method: "GET", tokens: new Set() });
  assert.equal(v.allow, false, "an unmounted secret must not open the control plane");
  assert.match(v.reason, /no token configured/);
  // …unless the operator explicitly asks for open mode.
  assert.equal(classifyAuth({ method: "GET", tokens: new Set(), allowOpen: true }).allow, true);
  assert.equal(classifyAuth({ method: "POST", tokens: new Set(), allowOpen: true }).via, "open-mode");
});

test("the forgeable tailnet header is a READ convenience — never a write credential", () => {
  // PROVEN live 2026-08-08: a curl from the workspace pod with a made-up header got 200 on a
  // read AND successfully POSTed a claim. Reads stay open (the operator browses over tailnet);
  // writes now require a token.
  const ts = { tokens: TOKENS, tsUser: "qualquer-um@exemplo.com" };
  assert.equal(classifyAuth({ ...ts, method: "GET" }).via, "tailnet-read");
  assert.equal(classifyAuth({ ...ts, method: "HEAD" }).allow, true);
  for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
    const v = classifyAuth({ ...ts, method });
    assert.equal(v.allow, false, `${method} must not pass on a forgeable header`);
    assert.match(v.reason, /not sufficient for a write/);
  }
});

test("a tailnet user WITH a token may write (the operator is not locked out)", () => {
  const v = classifyAuth({ method: "POST", tokens: TOKENS, tsUser: "dev@me.com", headerToken: "real-token" });
  assert.equal(v.allow, true);
  assert.equal(v.via, "token");
});

test("health probes and CORS preflight always pass, even with no credential", () => {
  assert.equal(classifyAuth({ method: "GET", path: "/livez", tokens: TOKENS }).via, "probe");
  assert.equal(classifyAuth({ method: "GET", path: "/healthz", tokens: TOKENS }).via, "probe");
  assert.equal(classifyAuth({ method: "OPTIONS", path: "/api/mobile/v1/coord", tokens: TOKENS }).via, "probe");
  // But a probe path must not become a wildcard for writes.
  assert.equal(classifyAuth({ method: "POST", path: "/api/mobile/v1/coord/claim", tokens: TOKENS }).allow, false);
});

test("method casing cannot be used to smuggle a write past the read rule", () => {
  for (const method of ["post", "Post", "pOsT", "delete"]) {
    assert.equal(
      classifyAuth({ method, tokens: TOKENS, tsUser: "x@y.com" }).allow, false,
      `${method} must be treated as a write`,
    );
  }
});

// ─── WebSocket upgrades ──────────────────────────────────────────────────────────────────
// index.mjs classifies every upgrade as a WRITE (method "POST"), because a terminal socket
// carries keystrokes into a live session. These pin the posture the upgrade gate now inherits.

test("a WS upgrade is a WRITE: tailnet identity alone never opens a terminal", () => {
  const asUpgrade = (over) => classifyAuth({ method: "POST", path: "/ws/loom", tokens: TOKENS, ...over });
  assert.equal(asUpgrade({ tsUser: "demetrios@me.com" }).allow, false, "a forgeable header must not type into a lane");
  assert.equal(asUpgrade({ headerToken: [...TOKENS][0] }).allow, true, "x-cockpit-token is the real credential");
  assert.equal(asUpgrade({ bearer: [...TOKENS][0] }).allow, true, "?token= stays supported");
  assert.equal(asUpgrade({}).allow, false);
});

test("a WS upgrade with NO secret mounted fails CLOSED", () => {
  // The bug this replaces: `if (COCKPIT_AUTH_TOKEN) { …check… }` — an empty secret skipped the
  // whole check, leaving /ws/loom (which can type into any lane) open to anything in the cluster.
  const noSecret = classifyAuth({ method: "POST", path: "/ws/loom", tokens: new Set() });
  assert.equal(noSecret.allow, false);
  assert.match(noSecret.reason, /no token configured/);
  assert.equal(classifyAuth({ method: "POST", path: "/ws/loom", tokens: new Set(), allowOpen: true }).allow, true,
    "opening it stays possible, but only as an explicit operator choice");
});

test("the internal token works on a socket too — the WS gate no longer checks a narrower set", () => {
  // Measured drift: the old gate compared against PROJECT_COCKPIT_AUTH_TOKEN only, so
  // PROJECT_COCKPIT_INTERNAL_AUTH_TOKEN authenticated on HTTP and was rejected on WS.
  const both = new Set(["public-token", "internal-token"]);
  assert.equal(classifyAuth({ method: "POST", path: "/ws/loom", tokens: both, headerToken: "internal-token" }).allow, true);
});
