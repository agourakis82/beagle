// auth-gate.mjs — who may touch the cockpit. Pure so the rules can be tested without a server.
//
// Two holes were found and closed here on 2026-08-08, both PROVEN live with a curl from another
// pod in the cluster — exactly the position the worm held during the incident:
//
//   1. FAIL-OPEN on a missing secret. `tokens.size === 0 → allow` meant an empty or unmounted
//      PROJECT_COCKPIT_AUTH_TOKEN silently opened the ENTIRE control plane. Now it fails CLOSED
//      unless the operator opts in explicitly (PROJECT_COCKPIT_ALLOW_OPEN=1).
//
//   2. FORGEABLE IDENTITY HEADER. `tailscale-user-login` is injected by the tailnet proxy, but
//      nothing stopped an in-cluster caller from just sending it. Measured: a made-up header got
//      200 on reads AND successfully POSTed a write. It cannot be authenticated at this layer —
//      the tailnet arrives via a LoadBalancer, not a loopback sidecar — so it is now treated as
//      what it actually is: a CONVENIENCE FOR READS. Anything that changes state needs a real
//      token. Tailnet reading keeps working, so the operator is not locked out of his own cockpit.

/// Methods that cannot change state.
export const READ_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

/// Paths that must stay reachable for liveness/readiness probes.
export const PROBE_PATHS = new Set(["/livez", "/healthz"]);

/// De onde um UPGRADE de WebSocket tira as credenciais. Vive aqui, puro, porque a versão anterior
/// morava dentro do `server.on("upgrade")` — e uma decisão que só se alcança abrindo um socket não
/// é uma decisão testável. Foi assim que a divergência passou: o gate HTTP lia
/// `Authorization: Bearer` e este lia só `?token=`, então o MESMO segredo abria `/api` e era
/// recusado em `/ws/loom`. Medido antes do conserto: 404 no HTTP (passou pela auth), 401 no WS.
///
/// A ordem é deliberada — cabeçalho primeiro, query depois — para não premiar o cliente que põe
/// segredo na URL, onde ele vaza em log de proxy e em histórico.
export function wsAuthInputs({ url = "/", headers = {} } = {}) {
  let query = "";
  try {
    query = new URL(url, `http://${headers.host || "localhost"}`).searchParams.get("token") || "";
  } catch {
    query = "";
  }
  return {
    // Um upgrade carrega teclas para DENTRO de uma sessão viva: é sempre caminho de escrita.
    method: "POST",
    path: String(url).split("?")[0],
    bearer: String(headers.authorization || "").replace(/^Bearer\s+/i, "") || query,
    headerToken: headers["x-cockpit-token"] || "",
    tsUser: headers["tailscale-user-login"] || "",
  };
}

/// Decide one request. Returns { allow, via } or { allow: false, reason }.
export function classifyAuth({
  method = "GET",
  path = "/",
  bearer = "",
  headerToken = "",
  tsUser = "",
  tokens = new Set(),
  allowOpen = false,
} = {}) {
  const m = String(method).toUpperCase();
  if (PROBE_PATHS.has(path) || m === "OPTIONS") return { allow: true, via: "probe" };

  if (tokens.size === 0) {
    return allowOpen
      ? { allow: true, via: "open-mode" }
      : { allow: false, reason: "no token configured (set PROJECT_COCKPIT_ALLOW_OPEN=1 to run open)" };
  }

  if ((bearer && tokens.has(bearer)) || (headerToken && tokens.has(headerToken))) {
    return { allow: true, via: "token" };
  }

  if (tsUser) {
    if (READ_METHODS.has(m)) return { allow: true, via: "tailnet-read" };
    return { allow: false, reason: "tailnet identity is not sufficient for a write — send a token" };
  }

  return { allow: false, reason: "unauthorized" };
}
