// platform-bridge.mjs — the leash. Maps allowlisted Command Deck session kinds to EXACT
// kubectl-exec targets: t560 tmux (via the t560 platform-bridge pod) and the sounio workspace
// zellij (via the workspace pod, as the non-root workspace user). No free-form command ever
// reaches a shell — every argv is fixed here. Pure + unit-tested.

const SOCK = (s) => `/tmp/tmux-1000/${s}`;
const TMUX_LIST_FORMAT = "#{session_name}|#{session_attached}|#{session_activity}|#{window_name}";

// pod "@bridge" = resolve the t560 platform-bridge pod at call time; a literal name = that pod.
export const SESSION_ALLOWLIST = {
  "t560-beagle":     { type: "tmux", pod: "@bridge", socket: "default", target: "beagle" },
  "t560-darwin-ops": { type: "tmux", pod: "@bridge", socket: "default", target: "darwin-ops" },
  "t560-clops":      { type: "tmux", pod: "@bridge", socket: "clops",   target: "clops" },
  "sounio-dev":      { type: "zellij", pod: "sounio-workspace-control-0", container: "workspace-ssh",
                       user: "openvscode-server", home: "/home/openvscode-server", session: "sounio-dev" },
};

// Any allowlisted deck session (name kept isT560Kind for the existing import sites).
export function isT560Kind(kind) {
  return Object.prototype.hasOwnProperty.call(SESSION_ALLOWLIST, kind);
}
export const isDeckKind = isT560Kind;

// zellij runs as a non-root workspace user; wrap in `su` with a clean env. The body is fixed
// (user/home/session come only from the allowlist above — never from request input).
function zellijSu(s, inner) {
  const body = `cd ${s.home}; unset ZELLIJ ZELLIJ_SESSION_NAME; export HOME=${s.home}; exec ${inner}`;
  return ["su", "-s", "/bin/bash", s.user, "-c", body];
}

// Returns { pod, container, argv } — the part AFTER `kubectl -n <ns> exec -i[t] <pod> [-c <c>] --`
// — or null if kind/action is not allowlisted. pod may be "@bridge".
// Tab names are injection-safe only if they match this charset (no shell metacharacters);
// the goto-tab param is shell-interpolated inside zellijSu, so anything else is refused.
const SAFE_TAB = /^[A-Za-z0-9._-]{1,64}$/;

export function deckExec(kind, action, param) {
  const s = SESSION_ALLOWLIST[kind];
  if (!s) return null;
  if (s.type === "tmux") {
    let cmd;
    if (action === "attach") cmd = ["tmux", "-S", SOCK(s.socket), "attach", "-t", s.target];
    else if (action === "list") cmd = ["tmux", "-S", SOCK(s.socket), "list-sessions", "-F", TMUX_LIST_FORMAT];
    else if (action === "kill") cmd = ["tmux", "-S", SOCK(s.socket), "kill-session", "-t", s.target];
    else return null;
    return { pod: s.pod, container: null, argv: cmd };
  }
  if (s.type === "zellij") {
    let inner;
    if (action === "attach") inner = `zellij attach ${s.session}`;
    else if (action === "list") inner = "zellij list-sessions";
    else if (action === "kill") inner = `zellij kill-session ${s.session}`;
    else if (action === "tab-next") inner = `zellij -s ${s.session} action go-to-next-tab`;
    else if (action === "tab-prev") inner = `zellij -s ${s.session} action go-to-previous-tab`;
    else if (action === "tabs") inner = `zellij -s ${s.session} action dump-layout`;
    else if (action === "goto-tab") {
      if (!SAFE_TAB.test(String(param || ""))) return null;
      inner = `zellij -s ${s.session} action go-to-tab-name ${param}`;
    }
    else return null;
    return { pod: s.pod, container: s.container || null, argv: zellijSu(s, inner) };
  }
  return null;
}

// Full kubectl argv given a resolved pod name (caller resolves "@bridge" → real pod).
export function kubectlArgv(ns, pod, spec, interactive) {
  const c = spec.container ? ["-c", spec.container] : [];
  return ["-n", ns, "exec", interactive ? "-it" : "-i", pod, ...c, "--", ...spec.argv];
}

// Parse a kind's "list" stdout into one metadata-only session entry (or null if absent).
export function parseDeckSession(kind, stdout, now) {
  const s = SESSION_ALLOWLIST[kind];
  if (!s) return null;
  if (s.type === "tmux") {
    const line = String(stdout || "").split("\n").find((l) => l.startsWith(s.target + "|"));
    if (!line) return null;
    const [name, attached, activity, window] = line.trim().split("|");
    return {
      kind, name,
      attached: attached === "1",
      idleSeconds: Math.max(0, Math.round((Number(now) || 0) - (Number(activity) || 0))),
      window: window || "",
    };
  }
  if (s.type === "zellij") {
    // Output carries ANSI + e.g. "sounio-dev [Created 4days ...] (current)".
    const plain = String(stdout || "").replace(/\[[0-9;?]*[A-Za-z]/g, "");
    const line = plain.split("\n").find((l) => l.includes(s.session));
    if (!line) return null;
    return { kind, name: s.session, attached: /current/i.test(line), idleSeconds: 0, window: "zellij" };
  }
  return null;
}
