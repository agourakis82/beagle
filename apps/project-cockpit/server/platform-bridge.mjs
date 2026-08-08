// platform-bridge.mjs — the leash. Maps allowlisted Command Deck session kinds to EXACT
// kubectl-exec targets: t560 tmux (via the t560 platform-bridge pod) and the sounio workspace
// zellij (via the workspace pod, as the non-root workspace user). No free-form command ever
// reaches a shell — every argv is fixed here. Pure + unit-tested.

const SOCK = (s) => `/tmp/tmux-1000/${s}`;
const TMUX_LIST_FORMAT = "#{session_name}|#{session_attached}|#{session_activity}|#{window_name}";
/// How many rows of scrollback a "peek" reads. Enough for a state verdict + a quoted question.
export const PEEK_LINES = 25;
/// Record separator for the batched fleet peek. Chosen to not occur in terminal output.
export const PEEK_DELIM = "@@LANE:";

// pod "@bridge" = resolve the t560 platform-bridge pod at call time; a literal name = that pod.
// The 11 workspace agent lanes are tmux sessions on the workspace pod's OWN uid-owned socket:
// the herd runs them under TMUX_TMPDIR=<home>/.tmux (NOT /tmp/tmux-1000), so they resolve the
// socket via TMUX_TMPDIR and run as the non-root workspace user (`su`-wrapped, like sounio-dev).
export const WORKSPACE_LANES = [
  "claude-1", "claude-2", "claude-3", "codex-1", "codex-2", "codex-3",
  "kimi-cli1", "kimi-cli2", "grok-cli1", "grok-cli2", "repo",
];
const WORKSPACE_LANE = (target) => ({
  type: "tmux", pod: "sounio-workspace-control-0", container: "workspace-ssh",
  user: "openvscode-server", home: "/workspace/.home/openvscode-server",
  tmuxTmpdir: "/workspace/.home/openvscode-server/.tmux", target,
});

export const SESSION_ALLOWLIST = {
  "t560-beagle":     { type: "tmux", pod: "@bridge", socket: "default", target: "beagle" },
  "t560-darwin-ops": { type: "tmux", pod: "@bridge", socket: "default", target: "darwin-ops" },
  "t560-clops":      { type: "tmux", pod: "@bridge", socket: "clops",   target: "clops" },
  "sounio-dev":      { type: "zellij", pod: "sounio-workspace-control-0", container: "workspace-ssh",
                       user: "openvscode-server", home: "/home/openvscode-server", session: "sounio-dev" },
  ...Object.fromEntries(WORKSPACE_LANES.map((l) => [l, WORKSPACE_LANE(l)])),
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

// Workspace tmux lanes run as the non-root user under their own TMUX_TMPDIR (NOT /tmp/tmux-1000).
// Same `su`-wrap discipline as zellij; the socket is resolved by TMUX_TMPDIR so no `-S` is needed.
// user/home/tmuxTmpdir/target come ONLY from the allowlist — never from request input.
function tmuxSu(s, inner) {
  const body = `export HOME=${s.home}; export TMUX_TMPDIR=${s.tmuxTmpdir}; exec ${inner}`;
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
    // Workspace lanes (s.user set): non-root, own TMUX_TMPDIR, `su`-wrapped, socket via env.
    if (s.user) {
      let inner;
      if (action === "attach") inner = `tmux attach -t ${s.target}`;
      else if (action === "list") inner = `tmux list-sessions -F '${TMUX_LIST_FORMAT}'`;
      else if (action === "kill") inner = `tmux kill-session -t ${s.target}`;
      // Read-only screen read: no attach, no client, so it cannot resize or disturb his lane.
      else if (action === "peek") inner = `tmux capture-pane -p -t ${s.target} -S -${PEEK_LINES}`;
      else return null;
      return { pod: s.pod, container: s.container || null, argv: tmuxSu(s, inner) };
    }
    // @bridge sessions: root on the platform-bridge pod, explicit -S socket, no user wrap.
    let cmd;
    if (action === "attach") cmd = ["tmux", "-S", SOCK(s.socket), "attach", "-t", s.target];
    else if (action === "list") cmd = ["tmux", "-S", SOCK(s.socket), "list-sessions", "-F", TMUX_LIST_FORMAT];
    else if (action === "kill") cmd = ["tmux", "-S", SOCK(s.socket), "kill-session", "-t", s.target];
    else if (action === "peek") cmd = ["tmux", "-S", SOCK(s.socket), "capture-pane", "-p", "-t", s.target, "-S", `-${PEEK_LINES}`];
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

// Kill leaked broker-owned zellij attach clients for a session, WITHOUT touching his real
// clients (e.g. the Mac via Termius). Discriminator: broker attaches are children of a
// `su -s /bin/bash <user>` process; his direct clients are children of sshd. Killing the
// cockpit-side kubectl-exec does NOT reliably kill the remote attach (it orphans), so this
// parent-based cleanup is the reliable detach. Session/user come only from the allowlist.
export function zellijCleanupArgv(kind, ns) {
  const s = SESSION_ALLOWLIST[kind];
  if (!s || s.type !== "zellij") return null;
  const script =
    `for z in $(pgrep -x -f "zellij attach ${s.session}" 2>/dev/null); do ` +
    `pp=$(ps -o ppid= -p "$z" 2>/dev/null | tr -d " "); ` +
    `pc=$(ps -o args= -p "$pp" 2>/dev/null); ` +
    `case "$pc" in *"su -s /bin/bash ${s.user}"*) kill -9 "$z" "$pp" 2>/dev/null;; esac; done`;
  return ["-n", ns, "exec", s.pod, "-c", s.container, "--", "sh", "-c", script];
}

// ONE kubectl exec that read-only-peeks EVERY workspace lane, delimited per lane. This is what
// lets the Frota show a TRUE state for all 11 lanes without attaching to any of them (attaching
// 11 clients would resize his real panes). The lane list is the allowlist constant — never
// request input — so the interpolated loop carries no injection surface. Read-only by
// construction: capture-pane cannot write to a pane.
export function lanesPeekArgv(ns) {
  const lane0 = SESSION_ALLOWLIST[WORKSPACE_LANES[0]];
  const script = WORKSPACE_LANES
    .map((l) => `echo "${PEEK_DELIM}${l}"; tmux capture-pane -p -t ${l} -S -${PEEK_LINES} 2>/dev/null`)
    .join("; ");
  const inner = `sh -c '${script}'`;
  return ["-n", ns, "exec", "-i", lane0.pod, "-c", lane0.container, "--", ...tmuxSu(lane0, inner)];
}

// Split the batched peek stdout into { lane: screenText }. Unknown labels are dropped.
export function parseLanesPeek(stdout) {
  const out = {};
  let cur = null, buf = [];
  for (const line of String(stdout || "").split("\n")) {
    if (line.startsWith(PEEK_DELIM)) {
      if (cur) out[cur] = buf.join("\n");
      const name = line.slice(PEEK_DELIM.length).trim();
      cur = WORKSPACE_LANES.includes(name) ? name : null;
      buf = [];
    } else if (cur) {
      buf.push(line);
    }
  }
  if (cur) out[cur] = buf.join("\n");
  return out;
}

// ─── OFICINA: read-only dev-status queries on the workspace repo ─────────────────────────
// Fixed, named, read-only queries — the ONLY dev commands the cockpit may run. No build, no
// test, no gate: those cost ~61GiB of RAM and minutes, so the Oficina READS receipts and CI
// verdicts instead of producing them. Each entry is a literal command string; nothing is ever
// interpolated from a request.
export const WORKSPACE_QUERIES = {
  // "Is it green?" — open PRs with their full check rollup.
  "pr-list": `gh pr list --state open --limit 20 --json number,title,headRefName,isDraft,updatedAt,url,statusCheckRollup`,
  // "Is main green?" — the latest CI run on the default branch.
  "main-ci": `gh run list --branch main --limit 8 --json databaseId,name,status,conclusion,createdAt,url,headSha`,
  // "Where am I?" — the repo's own head, branch and dirty count.
  "git-head": `printf '%s\\n' "$(git rev-parse --abbrev-ref HEAD)" "$(git log -1 --format=%H%x09%ct%x09%s)" "$(git status --porcelain | wc -l)"`,
};

export function workspaceQueryArgv(ns, name) {
  const cmd = Object.prototype.hasOwnProperty.call(WORKSPACE_QUERIES, name) ? WORKSPACE_QUERIES[name] : null;
  if (!cmd) return null;
  const lane0 = SESSION_ALLOWLIST[WORKSPACE_LANES[0]];
  const inner = `sh -c 'cd /workspace/sounio && ${cmd}'`;
  return ["-n", ns, "exec", "-i", lane0.pod, "-c", lane0.container, "--", ...tmuxSu(lane0, inner)];
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
